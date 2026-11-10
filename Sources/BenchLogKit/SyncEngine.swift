import CryptoKit
import Foundation

/// What a server holds, before connecting to it.
public struct ServerLibrary: Codable, Hashable, Sendable {
    public var libraryId: String?
    public var rows: Int
    public var files: Int
    public var cursor: Int
    public var numbers: [String: Int]
}

public struct PushResult: Codable, Hashable, Sendable {
    public var applied: Int
    public var cursor: Int
}

public struct PullPage: Codable, Hashable, Sendable {
    public var rows: [SyncRow]
    public var cursor: Int
    public var more: Bool
}

/// The server, as the sync engine sees it. `HTTPSyncTransport` talks to `server/`; tests
/// use an in-memory server with the same rules.
public protocol SyncTransport: Sendable {
    func library() async throws -> ServerLibrary
    func claim(_ libraryID: String) async throws
    func push(_ rows: [SyncRow]) async throws -> PushResult
    func pull(after cursor: Int, limit: Int) async throws -> PullPage
    /// Hands out `count` numbers from a sequence (ticket, invoice, credit); returns the first.
    func take(_ sequence: String, count: Int) async throws -> Int
    func start(_ sequence: String, atLeast: Int) async throws
    func hasFile(_ id: String) async throws -> Bool
    func upload(_ id: String, data: Data) async throws
    func download(_ id: String) async throws -> Data
}

public enum SyncError: LocalizedError, Equatable {
    case unreachable(String)
    case unauthorized
    case server(Int, String)
    /// The server holds a different library: joining replaces this one.
    case otherLibrary(rows: Int)
    case notConnected
    case fileMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let detail): String(localized: "Unable to reach the server: \(detail)")
        case .unauthorized: String(localized: "The server refused the token. Check it in Settings > Sync.")
        case .server(let status, let message): String(localized: "The server answered \(status): \(message)")
        case .otherLibrary: String(localized: "This server already holds another library.")
        case .notConnected: String(localized: "This library is not connected to a server.")
        case .fileMismatch(let id): String(localized: "A file from the server was damaged on the way (\(id)).")
        }
    }
}

/// Talks to the BenchLog server over HTTP with the library token.
public struct HTTPSyncTransport: SyncTransport {
    public let baseURL: URL
    let token: String
    let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                         headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil, headers["Content-Type"] == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.unreachable("no HTTP response") }
        if http.statusCode == 401 { throw SyncError.unauthorized }
        if http.statusCode >= 300, !(method == "HEAD" && http.statusCode == 404) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SyncError.server(http.statusCode, message)
        }
        return (data, http)
    }

    private func json<T: Decodable>(_ method: String, _ path: String, _ body: some Encodable = [String: String](),
                                    query: [URLQueryItem] = []) async throws -> T {
        let data = method == "GET" ? nil : try JSONEncoder().encode(body)
        return try JSONDecoder().decode(T.self, from: try await request(method, path, query: query, body: data).0)
    }

    public func library() async throws -> ServerLibrary { try await json("GET", "v1/library") }

    public func claim(_ libraryID: String) async throws {
        let _: [String: String] = try await json("POST", "v1/library", ["libraryId": libraryID])
    }

    public func push(_ rows: [SyncRow]) async throws -> PushResult {
        struct Body: Encodable { var rows: [SyncRow] }
        return try await json("POST", "v1/push", Body(rows: rows))
    }

    public func pull(after cursor: Int, limit: Int) async throws -> PullPage {
        try await json("GET", "v1/pull", query: [URLQueryItem(name: "after", value: "\(cursor)"), URLQueryItem(name: "limit", value: "\(limit)")])
    }

    public func take(_ sequence: String, count: Int) async throws -> Int {
        let taken: [String: Int] = try await json("POST", "v1/numbers/\(sequence)", ["count": count])
        guard let first = taken["first"] else { throw SyncError.server(500, "no number") }
        return first
    }

    public func start(_ sequence: String, atLeast: Int) async throws {
        let _: [String: Int] = try await json("POST", "v1/numbers/\(sequence)/start", ["atLeast": atLeast])
    }

    public func hasFile(_ id: String) async throws -> Bool {
        try await request("HEAD", "v1/files/\(id)").1.statusCode == 200
    }

    public func upload(_ id: String, data: Data) async throws {
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        _ = try await request("PUT", "v1/files/\(id)", body: data, headers: ["X-Sha256": sha, "Content-Type": "application/octet-stream"])
    }

    public func download(_ id: String) async throws -> Data {
        let (data, response) = try await request("GET", "v1/files/\(id)")
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expected = response.value(forHTTPHeaderField: "X-Sha256"), expected != sha { throw SyncError.fileMismatch(id) }
        return data
    }
}

/// What one sync did.
public struct SyncReport: Hashable, Sendable {
    public var pushed = 0
    public var pulled = 0
    public var uploaded = 0
    public var downloaded = 0
}

/// Pushes queued local changes, pulls what changed on the server, and moves the files
/// that go with attachments. One sync at a time.
public actor SyncEngine {
    public let library: Library
    let transport: any SyncTransport
    private let pageSize: Int

    public init(library: Library, transport: any SyncTransport, pageSize: Int = 500) {
        self.library = library
        self.transport = transport
        self.pageSize = pageSize
    }

    /// Connects this library to the server. An empty server takes this library (every row
    /// and file, and number sequences that start after this library's); the same library
    /// just syncs; another library throws `otherLibrary` unless `join` replaces this one.
    @discardableResult
    public func connect(join: Bool = false) async throws -> SyncReport {
        let server = try await transport.library()
        let mine = try library.libraryID()
        if server.libraryId == nil, server.rows == 0 {
            try await transport.claim(mine)
            for (sequence, next) in try library.localNextNumbers() {
                try await transport.start(sequence, atLeast: next)
            }
            try library.queueEverything()
            try library.setLocalMeta("syncCursor", "0")
        } else if server.libraryId != mine {
            guard join, let theirs = server.libraryId else { throw SyncError.otherLibrary(rows: server.rows) }
            try library.clearForJoin(libraryID: theirs)
        }
        return try await sync()
    }

    /// One round: push, pull, then files.
    @discardableResult
    public func sync() async throws -> SyncReport {
        var report = SyncReport()
        // Push, files first so a row never arrives before its file.
        while true {
            let batch = try library.queuedChanges(limit: pageSize)
            guard !batch.isEmpty else { break }
            for case (let change, let row?) in batch where change.table == "attachment" && row.deletedAt == nil {
                if try await upload(attachmentID: change.id) { report.uploaded += 1 }
            }
            let rows = batch.compactMap(\.1)
            if !rows.isEmpty { report.pushed += try await transport.push(rows).applied }
            try library.dequeue(batch.map(\.0))
            if batch.count < pageSize { break }
        }
        // Pull every page, then apply them together so a row can refer to one later in the feed.
        var cursor = try library.syncCursor()
        var rows: [SyncRow] = []
        while true {
            let page = try await transport.pull(after: cursor, limit: pageSize)
            rows += page.rows
            cursor = page.cursor
            if !page.more { break }
        }
        if !rows.isEmpty {
            report.pulled = try library.apply(rows).applied
        }
        try library.setLocalMeta("syncCursor", "\(cursor)")
        // Download files that arrived as attachment rows, or that an earlier sync missed.
        for attachment in try library.attachmentsMissingFiles() {
            if try await transport.hasFile(attachment.id.stored) {
                try library.storeFile(try await transport.download(attachment.id.stored), for: attachment)
                report.downloaded += 1
            }
        }
        return report
    }

    private func upload(attachmentID: String) async throws -> Bool {
        guard let id = UUID(uuidString: attachmentID), let attachment = try library.attachment(id) else { return false }
        let url = library.fileURL(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path), !(try await transport.hasFile(attachmentID)) else { return false }
        try await transport.upload(attachmentID, data: try Data(contentsOf: url))
        return true
    }
}

extension Library {
    /// The next number of each sequence here, so the server starts after them.
    func localNextNumbers() throws -> [(String, Int)] {
        try db.read { db in
            try [("ticket", "nextTicketNumber"), ("invoice", "nextInvoiceNumber"), ("credit", "nextCreditNumber")].map { sequence, key in
                (sequence, Int(try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) ?? "1") ?? 1)
            }
        }
    }

    /// Live attachments whose file is not on this device yet.
    func attachmentsMissingFiles() throws -> [Attachment] {
        try db.read { try Attachment.filter(sql: "deletedAt IS NULL").fetchAll($0) }
            .filter { !FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    /// Writes a downloaded file where its attachment says it lives.
    func storeFile(_ data: Data, for attachment: Attachment) throws {
        let url = fileURL(for: attachment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
