import Foundation
import Network

/// One HTTP request. A large body is in a temporary file; a small one is in memory.
public struct HTTPRequest: Sendable {
    public var method: String
    /// The path as sent, without the query and without percent-decoding.
    public var path: String
    public var query: [String: String]
    /// Header names in lowercase.
    public var headers: [String: String]
    public var body: Body

    public enum Body: Sendable {
        case data(Data)
        case file(URL, size: Int)
    }

    /// The body as bytes, up to `limit`; larger bodies throw 413.
    public func bodyData(limit: Int) throws -> Data {
        switch body {
        case .data(let data):
            guard data.count <= limit else { throw ServerError("the request is too large", status: 413) }
            return data
        case .file(let url, let size):
            guard size <= limit else { throw ServerError("the request is too large", status: 413) }
            return try Data(contentsOf: url)
        }
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Body

    public enum Body: Sendable {
        case data(Data)
        /// A file's bytes, streamed; `send: false` for HEAD, which only gives the length.
        case file(URL, size: Int, send: Bool)
    }

    public init(status: Int, headers: [String: String] = [:], body: Body = .data(Data())) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: .data(data))
    }
}

/// A small HTTP/1.1 server on Network.framework: one request per connection, bodies by
/// Content-Length, bodies over 4 MB spooled to a temporary file.
public final class HTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) -> HTTPResponse

    public static let maxBody = 1024 * 1024 * 1024
    static let spoolOver = 4 * 1024 * 1024

    private let listener: NWListener
    private let queue = DispatchQueue(label: "benchlog.server.listener")
    private let handler: Handler
    private let spoolDirectory: URL

    /// - Parameters:
    ///   - port: 0 picks a free port; read `port` after `start()`.
    ///   - localOnly: listen on 127.0.0.1 only (tests).
    public init(port: UInt16, localOnly: Bool = false, spoolDirectory: URL, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if localOnly {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
            listener = try NWListener(using: parameters)
        } else {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
        }
        self.handler = handler
        self.spoolDirectory = spoolDirectory
    }

    /// The port it listens on, once started.
    public var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// Starts listening; returns when the port is open, or throws why it could not be.
    public func start() async throws {
        try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            HTTPConnection(connection: connection, spoolDirectory: spoolDirectory, handler: handler).start()
        }
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.first() { continuation.resume() }
                case .failed(let error): if once.first() { continuation.resume(throwing: error) }
                case .cancelled: if once.first() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener.cancel()
    }
}

/// True the first time only.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func first() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}

/// One connection: reads the head, then the body, answers, and closes.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "benchlog.server.connection")
    private let spoolDirectory: URL
    private let handler: HTTPServer.Handler

    private var buffer = Data()
    private var head: (method: String, target: String, headers: [String: String])?
    private var length = 0
    private var received = 0
    private var spool: (url: URL, handle: FileHandle)?

    init(connection: NWConnection, spoolDirectory: URL, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.spoolDirectory = spoolDirectory
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            if case .failed = state { finish() }
            if case .cancelled = state { removeSpool() }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { take(data) }
            if error != nil { finish(); return }
            if isComplete, !answered { finish(); return }
            if !answered { receive() }
        }
    }

    private var answered = false

    private func take(_ data: Data) {
        if head == nil {
            buffer.append(data)
            guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 64 * 1024 { reply(HTTPResponse.json(431, ["error": "the request head is too large"])) }
                return
            }
            guard let parsed = Self.parseHead(buffer[..<end.lowerBound]) else {
                reply(HTTPResponse.json(400, ["error": "malformed request"]))
                return
            }
            head = parsed
            if parsed.headers["transfer-encoding"] != nil {
                reply(HTTPResponse.json(411, ["error": "send a Content-Length"]))
                return
            }
            length = Int(parsed.headers["content-length"] ?? "0") ?? -1
            guard length >= 0 else { reply(HTTPResponse.json(400, ["error": "malformed Content-Length"])); return }
            guard length <= HTTPServer.maxBody else { reply(HTTPResponse.json(413, ["error": "the file is too large"])); return }
            if parsed.headers["expect"]?.lowercased() == "100-continue" {
                connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
            }
            let rest = Data(buffer[end.upperBound...])
            buffer = Data()
            if length > HTTPServer.spoolOver {
                let url = spoolDirectory.appending(path: ".upload-\(UUID().uuidString)")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                guard let handle = try? FileHandle(forWritingTo: url) else {
                    reply(HTTPResponse.json(500, ["error": "server error"]))
                    return
                }
                spool = (url, handle)
            }
            if !rest.isEmpty { body(rest) }
        } else {
            body(data)
        }
        if head != nil, received >= length, !answered { answer() }
    }

    private func body(_ data: Data) {
        let wanted = data.prefix(length - received)
        received += wanted.count
        if let spool { try? spool.handle.write(contentsOf: wanted) } else { buffer.append(wanted) }
    }

    private func answer() {
        guard let head else { return }
        let request: HTTPRequest.Body
        if let spool {
            try? spool.handle.close()
            request = .file(spool.url, size: received)
        } else {
            request = .data(buffer)
        }
        let parts = head.target.split(separator: "?", maxSplits: 1).map(String.init)
        var query: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
                query[kv[0]] = kv.count > 1 ? kv[1] : ""
            }
        }
        let response = handler(HTTPRequest(method: head.method, path: parts.first ?? "/", query: query, headers: head.headers, body: request))
        reply(response)
    }

    private func reply(_ response: HTTPResponse) {
        answered = true
        var headers = response.headers
        let size: Int
        switch response.body {
        case .data(let data): size = data.count
        case .file(_, let fileSize, _): size = fileSize
        }
        headers["Content-Length"] = "\(size)"
        headers["Connection"] = "close"
        var text = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        switch response.body {
        case .data(let data):
            connection.send(content: Data(text.utf8) + data, isComplete: true, completion: .contentProcessed { [self] _ in finish() })
        case .file(_, _, false):
            connection.send(content: Data(text.utf8), isComplete: true, completion: .contentProcessed { [self] _ in finish() })
        case .file(let url, _, true):
            connection.send(content: Data(text.utf8), completion: .idempotent)
            guard let handle = try? FileHandle(forReadingFrom: url) else { finish(); return }
            sendChunks(handle)
        }
    }

    /// Streams a file 1 MB at a time, waiting for each chunk to go before reading the next.
    private func sendChunks(_ handle: FileHandle) {
        let chunk = (try? handle.read(upToCount: 1024 * 1024)) ?? nil
        guard let chunk, !chunk.isEmpty else {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { [self] _ in finish() })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil { try? handle.close(); finish() } else { sendChunks(handle) }
        })
    }

    private func finish() {
        removeSpool()
        connection.cancel()
    }

    private func removeSpool() {
        guard let spool else { return }
        try? spool.handle.close()
        try? FileManager.default.removeItem(at: spool.url)
        self.spool = nil
    }

    private static func parseHead(_ data: Data) -> (method: String, target: String, headers: [String: String])? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count == 3, first[2].hasPrefix("HTTP/1.") else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return (String(first[0]), String(first[1]), headers)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 100: "Continue"
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 409: "Conflict"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 422: "Unprocessable Content"
        case 431: "Request Header Fields Too Large"
        default: status >= 500 ? "Internal Server Error" : "Status"
        }
    }
}
