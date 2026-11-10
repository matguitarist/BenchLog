import Foundation
import GRDB
import Testing
@testable import BenchLogKit

/// The server's rules (server/src/store.js), in memory, for testing the engine.
final class MemoryServer: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: (row: SyncRow, seq: Int)] = [:]
    private var seq = 0
    private var libraryID: String?
    private var numbers = ["ticket": 1, "invoice": 1, "credit": 1]
    private(set) var files: [String: Data] = [:]
    var offline = false

    private func locked<T>(_ body: () throws -> T) throws -> T {
        if offline { throw SyncError.unreachable("offline") }
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    func library() async throws -> ServerLibrary {
        try locked { ServerLibrary(libraryId: libraryID, rows: rows.count, files: files.count, cursor: seq, numbers: numbers) }
    }
    func claim(_ id: String) async throws {
        try locked {
            if let libraryID, libraryID != id { throw SyncError.server(409, "this server holds another library") }
            libraryID = id
        }
    }
    func push(_ incoming: [SyncRow]) async throws -> PushResult {
        try locked {
            var applied = 0
            for row in incoming {
                let key = "\(row.table)/\(row.id)"
                if let existing = rows[key], existing.row.updatedAt >= row.updatedAt { continue }
                seq += 1
                rows[key] = (row, seq)
                applied += 1
            }
            return PushResult(applied: applied, cursor: seq)
        }
    }
    func pull(after cursor: Int, limit: Int) async throws -> PullPage {
        try locked {
            let all = rows.values.filter { $0.seq > cursor }.sorted { $0.seq < $1.seq }
            let page = Array(all.prefix(limit))
            return PullPage(rows: page.map(\.row), cursor: page.last?.seq ?? cursor, more: all.count > limit)
        }
    }
    func take(_ sequence: String, count: Int) async throws -> Int {
        try locked { let first = numbers[sequence]!; numbers[sequence] = first + count; return first }
    }
    func start(_ sequence: String, atLeast: Int) async throws { try locked { numbers[sequence] = max(numbers[sequence]!, atLeast) } }
    func giveBack(_ sequence: String, number: Int) async throws {
        try locked { if numbers[sequence] == number + 1 { numbers[sequence] = number } }
    }
    func hasFile(_ id: String) async throws -> Bool { try locked { files[id] != nil } }
    func upload(_ id: String, data: Data) async throws { try locked { files[id] = data } }
    func download(_ id: String) async throws -> Data { try locked { files[id]! } }
    func row(_ table: String, _ id: String) -> SyncRow? { lock.lock(); defer { lock.unlock() }; return rows["\(table)/\(id)"]?.row }
    func nextNumber(_ sequence: String) -> Int { lock.lock(); defer { lock.unlock() }; return numbers[sequence]! }
}

/// S-051 and S-052: connecting, and changes in both directions.
@Suite struct SyncTests {
    let server = MemoryServer()
    let mac: Library
    let other: Library

    init() throws {
        mac = try Library()
        other = try Library()
    }

    private func engine(_ library: Library) -> SyncEngine { SyncEngine(library: library, transport: server, pageSize: 3) }

    /// A customer with a device, a repair, a part that fits it, and a photo.
    @discardableResult
    private func fill(_ library: Library) throws -> (Customer, Device, Repair) {
        let customer = try library.save(Customer(name: "Léa Martin", phone: "514 555-0101"))
        let device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch", passcode: "1234"))
        let repair = try library.createRepair(deviceID: device.id, complaint: "Joy-Con drift")
        try library.save(Part(name: "Joy-Con stick", costCents: 300, quantity: 4),
                         fits: [PartFit(category: .console, brand: "Nintendo", model: "Switch")])
        _ = try library.addAttachment(data: Data("photo".utf8), originalName: "intake.jpg", to: .repair, id: repair.id)
        var profile = try library.businessProfile()
        profile.name = "Atelier Test"
        try library.save(profile)
        return (customer, device, repair)
    }

    @Test func everySyncedTableHasQueueTriggers() throws {
        try mac.db.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search%'")
            let triggers = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'"))
            for table in tables where !Library.localTables.contains(table) {
                #expect(Library.syncedTables.contains(table), "\(table) neither syncs nor is listed as local")
                #expect(triggers.contains("sync_\(table)_insert") && triggers.contains("sync_\(table)_update"), "\(table) has no queue triggers")
            }
        }
    }

    @Test func connectingAnEmptyServerUploadsTheLibrary() async throws {
        let (customer, _, _) = try fill(mac)
        try mac.issueCounterSale(to: customer.id, items: [CounterSaleItem(description: "Case", unitCents: 1_000)])
        let report = try await engine(mac).connect()
        #expect(report.pushed > 5 && report.uploaded == 1)
        #expect(try mac.pendingSyncCount() == 0)
        #expect(server.row("customer", customer.id.stored)?.data["name"] == .string("Léa Martin"))
        #expect(server.row("meta", "business") != nil)
        #expect(server.nextNumber("ticket") == 2 + Library.ticketBlockSize && server.nextNumber("invoice") == 2)   // after this Mac's block
    }

    @Test func anotherDeviceJoinsAndGetsEverything() async throws {
        let (customer, device, repair) = try fill(mac)
        try await engine(mac).connect()
        try fill(other)   // its own library, about to be replaced
        let rows = try await server.library().rows
        await #expect(throws: SyncError.otherLibrary(rows: rows)) { try await engine(other).connect() }
        try await engine(other).connect(join: true)
        #expect(try other.libraryID() == mac.libraryID())
        #expect(try other.customers().map(\.id) == [customer.id])
        #expect(try other.device(device.id)?.passcode == "1234")
        #expect(try other.repairRows().map(\.id) == [repair.id])
        #expect(try other.parts(matching: "").first.map { try other.fits(of: $0.id).map(\.model) } == ["Switch"])
        #expect(try other.businessProfile().name == "Atelier Test")
        let photo = try #require(try other.attachments(for: .repair, id: repair.id).first)
        #expect(try Data(contentsOf: other.fileURL(for: photo)) == Data("photo".utf8))
        #expect(try other.search("Léa").contains { $0.id == customer.id })
        #expect(try other.pendingSyncCount() == 0)
    }

    @Test func changesFlowBothWaysAndTheLaterOneWins() async throws {
        let (customer, _, repair) = try fill(mac)
        try await engine(mac).connect()
        try await engine(other).connect(join: true)

        var edited = try #require(try other.customer(customer.id))
        edited.phone = "438 555-0199"
        try other.save(edited, now: .now.addingTimeInterval(1))
        try other.setStatus(.diagnosing, of: repair.id)
        try await engine(other).sync()
        let report = try await engine(mac).sync()
        #expect(report.pulled >= 2)
        #expect(try mac.customer(customer.id)?.phone == "438 555-0199")
        #expect(try mac.repairRows().first?.repair.status == .diagnosing)
        #expect(try mac.pendingSyncCount() == 0)   // pulled rows are not queued again

        // Both change the same customer: the later updatedAt wins on both.
        var onMac = try #require(try mac.customer(customer.id))
        onMac.email = "mac@example.com"
        try mac.save(onMac, now: .now.addingTimeInterval(10))
        var onOther = try #require(try other.customer(customer.id))
        onOther.email = "other@example.com"
        try other.save(onOther, now: .now.addingTimeInterval(20))
        try await engine(mac).sync()
        try await engine(other).sync()
        try await engine(mac).sync()
        #expect(try mac.customer(customer.id)?.email == "other@example.com")
        #expect(try other.customer(customer.id)?.email == "other@example.com")
    }

    @Test func workOfflineThenCatchUp() async throws {
        let (customer, _, _) = try fill(mac)
        try await engine(mac).connect()
        server.offline = true
        var edited = try #require(try mac.customer(customer.id))
        edited.name = "Léa Martin-Roy"
        try mac.save(edited, now: .now.addingTimeInterval(1))
        await #expect(throws: SyncError.unreachable("offline")) { try await engine(mac).sync() }
        #expect(try mac.pendingSyncCount() == 1)
        server.offline = false
        try await engine(mac).sync()
        #expect(try mac.pendingSyncCount() == 0)
        #expect(server.row("customer", customer.id.stored)?.data["name"] == .string("Léa Martin-Roy"))
    }

    @Test func trashedRowsTravelAsDeletions() async throws {
        let (customer, _, _) = try fill(mac)
        let lone = try mac.save(Customer(name: "Gone Soon"))
        try await engine(mac).connect()
        try await engine(other).connect(join: true)
        try mac.moveToTrash(.customer(lone.id))
        try await engine(mac).sync()
        try await engine(other).sync()
        #expect(try other.customers().map(\.id) == [customer.id])
    }
}
