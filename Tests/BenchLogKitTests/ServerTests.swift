import Foundation
import Testing
@testable import BenchLogKit
import BenchLogServerKit

/// The engine against both real servers: the Node one in `server/` (when Node is installed,
/// S-049 to S-052) and the one built into the app (S-058).
@Suite(.serialized) struct ServerTests {
    static let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }

    enum Kind: String, CaseIterable { case node, swift }

    /// Starts the server on a free port with a fresh data folder; stops it after `body`.
    private func withServer(_ kind: Kind, _ body: (HTTPSyncTransport) async throws -> Void) async throws {
        if kind == .swift {
            let data = FileManager.default.temporaryDirectory.appending(path: "benchlog-server-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: data) }
            let server = try BenchLogServer(dataDirectory: data, token: "test-token")
            let port = try await server.start(port: 0, localOnly: true)
            defer { server.stop() }
            try await body(HTTPSyncTransport(baseURL: URL(string: "http://127.0.0.1:\(port)")!, token: "test-token"))
            return
        }
        guard let node = Self.node else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = FileManager.default.temporaryDirectory.appending(path: "benchlog-server-\(UUID().uuidString)")
        let port = Int.random(in: 20_000...40_000)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [root.appending(path: "server/src/main.js").path]
        process.environment = ["PORT": "\(port)", "DATA_DIR": data.path, "BENCHLOG_TOKEN": "test-token"]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        defer { process.terminate(); try? FileManager.default.removeItem(at: data) }
        let base = URL(string: "http://127.0.0.1:\(port)")!
        for _ in 0..<50 {
            if (try? await URLSession.shared.data(from: base.appending(path: "v1/health"))) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await body(HTTPSyncTransport(baseURL: base, token: "test-token"))
    }

    @Test(arguments: Kind.allCases) func twoLibrariesShareOneServer(_ kind: Kind) async throws {
        try await withServer(kind) { transport in
            let key = LibraryKey()
            let mac = try Library()
            let customer = try mac.save(Customer(name: "Léa Martin"))
            let device = try mac.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
            let repair = try mac.createRepair(deviceID: device.id, complaint: "Écran fissuré")
            _ = try mac.addAttachment(data: Data(repeating: 7, count: 100_000), originalName: "screen.jpg", to: .repair, id: repair.id)
            try await SyncEngine(library: mac, transport: transport, key: key).connect()

            let other = try Library()
            try await SyncEngine(library: other, transport: transport, key: key).connect(join: true)
            #expect(try other.repairRows().first?.repair.complaint == "Écran fissuré")
            let photo = try #require(try other.attachments(for: .repair, id: repair.id).first)
            #expect(try Data(contentsOf: other.fileURL(for: photo)).count == 100_000)

            try other.setStatus(.diagnosing, of: repair.id)
            try await SyncEngine(library: other, transport: transport, key: key).sync()
            try await SyncEngine(library: mac, transport: transport, key: key).sync()
            #expect(try mac.repairRows().first?.repair.status == .diagnosing)
            #expect(try await transport.take("ticket", count: 1) == 2 + 2 * Library.ticketBlockSize)   // after both blocks
        }
    }

    @Test(arguments: Kind.allCases) func aWrongTokenIsRefused(_ kind: Kind) async throws {
        try await withServer(kind) { transport in
            let wrong = HTTPSyncTransport(baseURL: transport.baseURL, token: "nope")
            await #expect(throws: SyncError.unauthorized) { try await wrong.library() }
        }
    }
}
