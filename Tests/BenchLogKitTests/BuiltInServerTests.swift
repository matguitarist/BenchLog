import CryptoKit
import Foundation
import Testing
@testable import BenchLogServerKit

/// The server built into the app (S-058): the same rules as server/test/*.test.js.
struct ServerStoreTests {
    private func row(_ id: String, _ updatedAt: String, _ data: [String: Any] = [:], table: String = "customer") -> [String: Any] {
        ["table": table, "id": id, "updatedAt": updatedAt, "deletedAt": NSNull(), "data": data.merging(["name": id]) { a, _ in a }]
    }

    private func ids(_ page: [String: Any]) -> [String] {
        (page["rows"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    @Test func theNewerUpdatedAtWins() throws {
        let store = try ServerStore(path: nil)
        #expect(try store.push([row("a", "2026-11-09 10:00:00.000", ["phone": "1"])])["applied"] as? Int == 1)
        let older = try store.push([row("a", "2026-11-09 09:00:00.000", ["phone": "old"])])
        #expect(older["kept"] as? [[String: String]] == [["table": "customer", "id": "a"]])
        #expect(try store.push([row("a", "2026-11-09 10:00:00.000", ["phone": "echo"])])["applied"] as? Int == 0)
        _ = try store.push([row("a", "2026-11-09 11:00:00.000", ["phone": "new"])])
        let rows = try store.pull(after: 0, limit: 500)["rows"] as? [[String: Any]] ?? []
        #expect(rows.count == 1)
        #expect((rows.first?["data"] as? [String: Any])?["phone"] as? String == "new")
    }

    @Test func pullPagesInOrder() throws {
        let store = try ServerStore(path: nil)
        _ = try store.push([row("a", "2026-01-01 00:00:00.000"), row("b", "2026-01-01 00:00:00.000"), row("c", "2026-01-01 00:00:00.000")])
        let first = try store.pull(after: 0, limit: 2)
        #expect(ids(first) == ["a", "b"])
        #expect(first["more"] as? Bool == true)
        let second = try store.pull(after: first["cursor"] as? Int ?? 0, limit: 2)
        #expect(ids(second) == ["c"])
        #expect(second["more"] as? Bool == false)
        _ = try store.push([row("a", "2026-01-02 00:00:00.000")])
        #expect(ids(try store.pull(after: second["cursor"] as? Int ?? 0, limit: 500)) == ["a"])
    }

    @Test func deletionsAndMalformedRows() throws {
        let store = try ServerStore(path: nil)
        _ = try store.push([row("a", "2026-01-01 00:00:00.000")])
        var deleted = row("a", "2026-01-02 00:00:00.000")
        deleted["deletedAt"] = "2026-01-02 00:00:00.000"
        _ = try store.push([deleted])
        #expect((try store.pull(after: 0, limit: 500)["rows"] as? [[String: Any]])?.first?["deletedAt"] as? String == "2026-01-02 00:00:00.000")
        let bad: [String: Any] = ["table": "x; DROP", "id": "b", "updatedAt": "2026", "data": [:] as [String: Any]]
        #expect(throws: ServerError.self) { try store.push([row("z", "2026-01-01 00:00:00.000"), bad]) }
        #expect(try store.info()["rows"] as? Int == 1)
        #expect(!ServerStore.isID("..") && !ServerStore.isID(".hidden") && !ServerStore.isID("a/b") && ServerStore.isID("A1._-"))
    }

    @Test func numbers() throws {
        let store = try ServerStore(path: nil)
        #expect(try store.start("ticket", atLeast: 42) == 42)
        #expect(try store.start("ticket", atLeast: 10) == 42)
        #expect(try store.take("ticket", count: 10) == ["first": 42, "count": 10])
        #expect(try store.take("ticket", count: nil) == ["first": 52, "count": 1])
        _ = try store.start("invoice", atLeast: 7)
        #expect(try store.take("invoice", count: nil) == ["first": 7, "count": 1])
        #expect(throws: ServerError.self) { try store.take("invoice", count: 2) }
        #expect(throws: ServerError.self) { try store.take("nope", count: nil) }
        #expect(throws: ServerError.self) { try store.take("ticket", count: 1.5) }
        #expect(throws: ServerError.self) { try store.take("ticket", count: true) }
        #expect(try store.giveBack("invoice", number: 7) == true)    // the last one handed out
        #expect(try store.giveBack("invoice", number: 5) == false)
        #expect(try store.numbers() == ["ticket": 53, "invoice": 7, "credit": 1])
    }

    @Test func aServerBelongsToTheFirstLibrary() throws {
        let store = try ServerStore(path: nil)
        #expect(try store.info()["libraryId"] is NSNull)
        _ = try store.claim("lib-1")
        _ = try store.claim("lib-1")
        #expect(throws: ServerError("this server holds another library", status: 409)) { try store.claim("lib-2") }
    }
}

/// The HTTP API, over a real socket.
@Suite(.serialized) struct BuiltInServerHTTPTests {
    private func withServer(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "benchlog-swift-server-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = try BenchLogServer(dataDirectory: dir, inMemory: true, token: "test-token")
        let port = try await server.start(port: 0, localOnly: true)
        defer { server.stop() }
        try await body(URL(string: "http://127.0.0.1:\(port)")!)
    }

    private func send(_ base: URL, _ method: String, _ path: String, token: String? = "test-token", json: Any? = nil,
                      data: Data? = nil, headers: [String: String] = [:]) async throws -> (Int, Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: base.absoluteString + path)!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
        if let data { request.httpBody = data }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (body, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        return (http.statusCode, body, http)
    }

    private func code(_ base: URL, _ method: String, _ path: String, token: String? = "test-token", json: Any? = nil,
                        data: Data? = nil, headers: [String: String] = [:]) async throws -> Int {
        try await send(base, method, path, token: token, json: json, data: data, headers: headers).0
    }

    @Test func healthNeedsNoToken() async throws {
        try await withServer { base in
            let r1 = try await code(base, "GET", "/v1/health", token: nil)
            #expect(r1 == 200)
            let r2 = try await code(base, "GET", "/v1/library", token: nil)
            #expect(r2 == 401)
            let r3 = try await code(base, "GET", "/v1/library", token: "wrong")
            #expect(r3 == 401)
            let r4 = try await code(base, "GET", "/v1/library")
            #expect(r4 == 200)
            let r5 = try await code(base, "GET", "/nope")
            #expect(r5 == 404)
        }
    }

    @Test func pushPullAndNumbers() async throws {
        try await withServer { base in
            let rows: [[String: Any]] = [["table": "repair", "id": "r1", "updatedAt": "2026-11-09 12:00:00.000", "data": ["ticketNumber": 1, "note": "Écran"]]]
            let (status, body, _) = try await send(base, "POST", "/v1/push", json: ["rows": rows])
            #expect(status == 200)
            #expect((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["applied"] as? Int == 1)
            let pulled = try JSONSerialization.jsonObject(with: try await send(base, "GET", "/v1/pull?after=0&limit=10").1) as? [String: Any]
            let data = (pulled?["rows"] as? [[String: Any]])?.last?["data"] as? [String: Any]
            #expect(data?["ticketNumber"] as? Int == 1 && data?["note"] as? String == "Écran")
            let r6 = try await code(base, "POST", "/v1/push", json: ["rows": "nope"])
            #expect(r6 == 400)
            let r7 = try await code(base, "GET", "/v1/pull?after=x")
            #expect(r7 == 400)
            _ = try await send(base, "POST", "/v1/numbers/invoice/start", json: ["atLeast": 12])
            let taken = try JSONSerialization.jsonObject(with: try await send(base, "POST", "/v1/numbers/invoice", json: [:] as [String: Any]).1) as? [String: Int]
            #expect(taken == ["first": 12, "count": 1])
            let r8 = try await code(base, "POST", "/v1/numbers/invoice", json: ["count": 3])
            #expect(r8 == 400)
        }
    }

    @Test func filesAreCheckedBySHA256() async throws {
        try await withServer { base in
            let bytes = Data(repeating: 9, count: 6 * 1024 * 1024)   // over the spool size: goes through a temporary file
            let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let r9 = try await code(base, "PUT", "/v1/files/f1", data: bytes, headers: ["X-Sha256": String(repeating: "0", count: 64)])
            #expect(r9 == 422)
            let r10 = try await code(base, "HEAD", "/v1/files/f1")
            #expect(r10 == 404)
            let r11 = try await code(base, "PUT", "/v1/files/f1", data: bytes, headers: ["X-Sha256": sha])
            #expect(r11 == 200)
            let (status, body, response) = try await send(base, "GET", "/v1/files/f1")
            #expect(status == 200 && body == bytes && response.value(forHTTPHeaderField: "X-Sha256") == sha)
            let r12 = try await code(base, "HEAD", "/v1/files/f1")
            #expect(r12 == 200)
            let r13 = try await code(base, "GET", "/v1/files/..%2Fetc")
            #expect(r13 == 400)
            let r14 = try await code(base, "PUT", "/v1/files/..", data: bytes, headers: ["X-Sha256": sha])
            #expect(r14 != 200)
        }
    }

    @Test func theTokenFileIsMadeOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "benchlog-token-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try BenchLogServer.token(in: dir)
        let again = try BenchLogServer.token(in: dir)
        #expect(first.created && !again.created && first.token == again.token && first.token.count == 32)
        let mode = try FileManager.default.attributesOfItem(atPath: dir.appending(path: "token").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}
