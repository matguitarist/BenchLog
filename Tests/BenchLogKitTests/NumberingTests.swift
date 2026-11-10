import Foundation
import Testing
@testable import BenchLogKit

/// S-053 Invoices and tickets use the server's numbers.
@Suite struct NumberingTests {
    let server = MemoryServer()
    let key = LibraryKey()
    let mac: Library
    let other: Library

    init() throws {
        mac = try Library()
        other = try Library()
    }

    private func connect(_ library: Library, join: Bool = false) async throws -> SyncEngine {
        let engine = SyncEngine(library: library, transport: server, key: key)
        try await engine.connect(join: join)
        try library.setSyncServer(URL(string: "http://bench.local:8420"))
        return engine
    }

    private func billableRepair(_ library: Library) throws -> Repair {
        let customer = try library.save(Customer(name: "Léa"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        let repair = try library.createRepair(deviceID: device.id, complaint: "Écran")
        try library.save(LabourLine(repairId: repair.id, description: "Écran", kind: .flat, unitCents: 10_000))
        return repair
    }

    @Test func twoDevicesNeverShareATicketNumber() async throws {
        _ = try billableRepair(mac)   // #0001 before connecting
        let macEngine = try await connect(mac)
        _ = try await connect(other, join: true)
        #expect(try mac.reservedTickets() == Library.ticketBlockSize)
        let device = try #require(try mac.repairRows().first?.device)
        let onMac = try mac.createRepair(deviceID: device.id, complaint: "A")
        try await macEngine.sync()
        try await SyncEngine(library: other, transport: server, key: key).sync()
        let onOther = try other.createRepair(deviceID: device.id, complaint: "B")
        #expect(onMac.ticketNumber == 2)
        #expect(onOther.ticketNumber == 2 + Library.ticketBlockSize)
    }

    @Test func offlineCheckInUsesTheReserveUntilItRunsOut() async throws {
        _ = try billableRepair(mac)
        _ = try await connect(mac)
        server.offline = true
        let device = try #require(try mac.repairRows().first?.device)
        for _ in 0..<Library.ticketBlockSize { _ = try mac.createRepair(deviceID: device.id, complaint: "Offline") }
        #expect(throws: NumberingError.noTicketNumbers) { try mac.createRepair(deviceID: device.id, complaint: "One too many") }
    }

    @Test func aConnectedLibraryTakesInvoiceNumbersFromTheServer() async throws {
        let repair = try billableRepair(mac)
        try mac.issue(.invoice, for: repair.id)   // F-0001, before connecting
        let engine = try await connect(mac)
        #expect(throws: NumberingError.needsServer) { try mac.issue(.invoice, for: repair.id) }
        #expect(try mac.issue(.estimate, for: repair.id).number == nil)   // estimates have no number
        let invoice = try mac.issue(.invoice, for: repair.id, number: try await engine.number("invoice"))
        #expect(invoice.numberText == "F-0002")
        let credit = try mac.issueCreditNote(for: invoice.id, number: try await engine.number("credit"))
        #expect(credit.numberText == "NC-0001")
        #expect(server.nextNumber("invoice") == 3)
    }
}
