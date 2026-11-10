import CryptoKit
import Foundation

/// The BenchLog server: the same HTTP API as `server/src/server.js`, on a data folder the
/// Node server can open too (library.sqlite, files/, token).
///
///     GET  /v1/health                      {ok, version}
///     GET  /v1/library                     {libraryId, rows, files, cursor, numbers}
///     POST /v1/library    {libraryId}      claims an empty server for a library
///     POST /v1/push       {rows: [...]}    {applied, kept, cursor}
///     GET  /v1/pull?after=N&limit=M        {rows, cursor, more}
///     POST /v1/numbers/:name  {count}      {first, count}         ticket | invoice | credit
///     POST /v1/numbers/:name/start {atLeast}  {next}
///     POST /v1/numbers/:name/return {number}  {returned}
///     PUT  /v1/files/:id   (X-Sha256)      stores an attachment's bytes
///     GET  /v1/files/:id                   the bytes, with X-Sha256
///     HEAD /v1/files/:id                   200 when stored
public final class BenchLogServer: Sendable {
    public static let defaultPort: UInt16 = 8420
    private static let maxJSON = 32 * 1024 * 1024

    public let dataDirectory: URL
    public let version: String
    private let store: ServerStore
    private let expected: Data
    private let filesDirectory: URL
    private let log: @Sendable (String) -> Void
    private nonisolated(unsafe) var http: HTTPServer?

    /// - Parameters:
    ///   - dataDirectory: holds library.sqlite and files/; nil keeps the library in memory (tests).
    public init(dataDirectory: URL, inMemory: Bool = false, token: String, version: String = "dev",
                log: @escaping @Sendable (String) -> Void = { _ in }) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        self.dataDirectory = dataDirectory
        self.version = version
        self.log = log
        filesDirectory = dataDirectory.appending(path: "files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        store = try ServerStore(path: inMemory ? nil : dataDirectory.appending(path: "library.sqlite").path)
        expected = Data(SHA256.hash(data: Data(token.utf8)))
    }

    /// The token in `dataDirectory/token`, made on first use (24 random bytes, base64url, mode 600).
    /// `created` is true when this call made it.
    public static func token(in dataDirectory: URL) throws -> (token: String, created: Bool) {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let file = dataDirectory.appending(path: "token")
        if let text = try? String(contentsOf: file, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ServerError("no random bytes", status: 500) }
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        FileManager.default.createFile(atPath: file.path, contents: Data((token + "\n").utf8), attributes: [.posixPermissions: 0o600])
        return (token, true)
    }

    /// Listens on `port` (0 picks one); returns the port.
    @discardableResult
    public func start(port: UInt16 = defaultPort, localOnly: Bool = false) async throws -> UInt16 {
        let server = try HTTPServer(port: port, localOnly: localOnly, spoolDirectory: filesDirectory) { [self] request in
            handle(request)
        }
        try await server.start()
        http = server
        return server.port
    }

    public func stop() {
        http?.stop()
        http = nil
    }

    // MARK: Routes

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let started = Date()
        let response: HTTPResponse
        do {
            response = try route(request)
        } catch let error as ServerError {
            response = .json(error.status, ["error": error.message])
        } catch {
            log("error \(request.method) \(request.path): \(error)")
            response = .json(500, ["error": "server error"])
        }
        log("\(request.method) \(request.path) \(response.status) \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        return response
    }

    private func route(_ request: HTTPRequest) throws -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1", parts.count >= 2 else { throw ServerError("not found", status: 404) }
        if request.method == "GET", parts[1] == "health", parts.count == 2 {
            return .json(200, ["ok": true, "version": version])
        }
        guard authorized(request) else { throw ServerError("the token is missing or wrong", status: 401) }

        switch (request.method, parts[1]) {
        case ("GET", "library"):
            return .json(200, try store.info())
        case ("POST", "library"):
            return .json(200, ["libraryId": try store.claim(try json(request)["libraryId"])])
        case ("POST", "push"):
            return .json(200, try store.push(try json(request)["rows"]))
        case ("GET", "pull"):
            guard let after = Int(request.query["after"] ?? "0"), after >= 0, let limit = Int(request.query["limit"] ?? "500") else {
                throw ServerError("after and limit must be integers")
            }
            return .json(200, try store.pull(after: after, limit: limit))
        case ("POST", "numbers"):
            guard parts.count >= 3 else { throw ServerError("not found", status: 404) }
            let body = try json(request)
            if parts.count == 4, parts[3] == "start" { return .json(200, ["next": try store.start(parts[2], atLeast: body["atLeast"])]) }
            if parts.count == 4, parts[3] == "return" { return .json(200, ["returned": try store.giveBack(parts[2], number: body["number"])]) }
            guard parts.count == 3 else { throw ServerError("not found", status: 404) }
            return .json(200, try store.take(parts[2], count: body["count"]))
        case ("PUT", "files"):
            return try putFile(request, id: parts.count == 3 ? parts[2] : "")
        case ("GET", "files"), ("HEAD", "files"):
            return try getFile(request, id: parts.count == 3 ? parts[2] : "")
        default:
            throw ServerError("not found", status: 404)
        }
    }

    /// Compares SHA-256 digests in constant time, so the token's length and bytes leak nothing.
    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"], header.hasPrefix("Bearer ") else { return false }
        let given = Data(SHA256.hash(data: Data(header.dropFirst(7).utf8)))
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func json(_ request: HTTPRequest) throws -> [String: Any] {
        let data = try request.bodyData(limit: Self.maxJSON)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw ServerError("the body is not JSON") }
        return object as? [String: Any] ?? [:]
    }

    // MARK: Files

    private func putFile(_ request: HTTPRequest, id: String) throws -> HTTPResponse {
        try ServerStore.checkID(id)
        let sha256 = (request.headers["x-sha256"] ?? "").lowercased()
        guard sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else { throw ServerError("X-Sha256 is missing or malformed") }
        let temp = filesDirectory.appending(path: ".\(id).\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let size: Int
        var hash = SHA256()
        switch request.body {
        case .data(let data):
            size = data.count
            hash.update(data: data)
            try data.write(to: temp)
        case .file(let url, let fileSize):
            size = fileSize
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
            try FileManager.default.moveItem(at: url, to: temp)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw ServerError("the file does not match its SHA-256", status: 422)
        }
        let destination = filesDirectory.appending(path: id)
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        try store.recordFile(id, sha256: sha256, size: size)
        return .json(200, ["id": id, "sha256": sha256, "size": size])
    }

    private func getFile(_ request: HTTPRequest, id: String) throws -> HTTPResponse {
        guard let record = try store.fileRecord(id) else { throw ServerError("no such file", status: 404) }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/octet-stream", "X-Sha256": record.sha256],
                            body: .file(filesDirectory.appending(path: record.id), size: record.size, send: request.method == "GET"))
    }
}
