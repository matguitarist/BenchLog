import Foundation
import GRDB
import Testing
@testable import BenchLogKit

@Suite struct LibraryDataTests {
    let library: Library

    init() throws { library = try Library() }

    private func makeDevice(_ name: String = "Mario Tremblay") throws -> (Customer, Device) {
        let customer = try library.save(Customer(name: name, phone: "514 555-1234"))
        let device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch", revision: "OLED Model"))
        return (customer, device)
    }

    // S-001
    @Test func everyCoreTableExistsWithSyncColumns() throws {
        try library.db.read { db in
            for table in ["customer", "device", "repair", "note"] {
                let columns = try db.columns(in: table).map(\.name)
                for column in ["id", "createdAt", "updatedAt", "deletedAt"] {
                    #expect(columns.contains(column), "\(table).\(column)")
                }
            }
        }
    }

    @Test func idsAreStoredAsLowercaseText() throws {
        let (customer, _) = try makeDevice()
        let stored = try library.db.read { try String.fetchOne($0, sql: "SELECT id FROM customer") }
        #expect(stored == customer.id.uuidString.lowercased())
    }

    @Test func savingUpdatesUpdatedAt() throws {
        var customer = try library.save(Customer(name: "A", now: Date(timeIntervalSince1970: 0)), now: Date(timeIntervalSince1970: 0))
        customer.email = "a@example.com"
        let later = Date(timeIntervalSince1970: 1000)
        try library.save(customer, now: later)
        #expect(try library.customer(customer.id)?.updatedAt == later)
    }

    @Test func trashIsSoftAndRestorable() throws {
        let (customer, _) = try makeDevice()
        try library.trash(Customer.self, id: customer.id)
        #expect(try library.customers().isEmpty)
        #expect(try library.customer(customer.id)?.deletedAt != nil)
        try library.restore(Customer.self, id: customer.id)
        #expect(try library.customers().map(\.id) == [customer.id])
    }

    // S-002
    @Test func phoneSearchMatchesDigitsOnly() throws {
        _ = try makeDevice()
        #expect(try library.customers(matching: "5145551234").count == 1)
        #expect(try library.customers(matching: "(514) 555").count == 1)
        #expect(try library.customers(matching: "mario").count == 1)
        #expect(try library.customers(matching: "luigi").isEmpty)
    }

    @Test func customersSortByName() throws {
        for name in ["Zoé", "alex", "Émile", "Benoît"] { try library.save(Customer(name: name)) }
        #expect(try library.customers().map(\.name) == ["alex", "Benoît", "Émile", "Zoé"])
    }

    // S-003
    @Test func theCatalogStartsWithTheDraftsConsoles() throws {
        #expect(try library.catalogBrands(.console).contains("Nintendo"))
        #expect(try library.catalogModels(.handheld, brand: "Nintendo").contains("Game Boy"))
        #expect(try library.catalogRevisions(.console, brand: "Nintendo", model: "Switch").contains("OLED Model"))
        #expect(try library.catalogBrands(.phone).contains("Apple"))
    }

    @Test func aNewValueJoinsTheCatalog() throws {
        let customer = try library.save(Customer(name: "A"))
        #expect(try !library.catalogContains(.console, brand: "Analogue", model: "Pocket"))
        try library.save(Device(customerId: customer.id, category: .console, brand: "Analogue", model: "Pocket", revision: "Glow"))
        #expect(try library.catalogModels(.console, brand: "Analogue") == ["Pocket"])
        #expect(try library.catalogRevisions(.console, brand: "analogue", model: "pocket") == ["Glow"])
    }

    @Test func caseOnlyDifferencesDoNotDuplicate() throws {
        let customer = try library.save(Customer(name: "A"))
        try library.save(Device(customerId: customer.id, category: .console, brand: "nintendo", model: "switch"))
        #expect(try library.catalogBrands(.console).filter { $0.lowercased() == "nintendo" } == ["Nintendo"])
    }

    // S-005
    @Test func ticketNumbersGoUpWithoutGaps() throws {
        let (_, device) = try makeDevice()
        let numbers = try (1...3).map { _ in try library.createRepair(deviceID: device.id, complaint: "No power").ticketNumber }
        #expect(numbers == [1, 2, 3])
        #expect(try library.repair(library.repairRows().last!.id)?.ticket.text == "#0003")
    }

    @Test func aTrashedRepairsNumberIsNeverReused() throws {
        let (_, device) = try makeDevice()
        let first = try library.createRepair(deviceID: device.id, complaint: "A")
        try library.trash(Repair.self, id: first.id)
        #expect(try library.createRepair(deviceID: device.id, complaint: "B").ticketNumber == 2)
    }

    // S-006
    @Test func statusChangesSetDatesAndWriteANote() throws {
        let (_, device) = try makeDevice()
        let repair = try library.createRepair(deviceID: device.id, complaint: "Fan noise")
        let done = Date(timeIntervalSince1970: 5000)
        let ready = try #require(try library.setStatus(.ready, of: repair.id, now: done))
        #expect(ready.completedAt == done)
        let picked = try #require(try library.setStatus(.pickedUp, of: repair.id, now: done.addingTimeInterval(60)))
        #expect(picked.pickedUpAt == done.addingTimeInterval(60))
        #expect(picked.completedAt == done)
        let notes = try library.notes(for: .repair, id: repair.id)
        #expect(notes.compactMap(\.status) == [.ready, .pickedUp])
        let back = try #require(try library.setStatus(.inProgress, of: repair.id))
        #expect(back.pickedUpAt == nil && back.completedAt == nil)
    }

    @Test func settingTheSameStatusDoesNothing() throws {
        let (_, device) = try makeDevice()
        let repair = try library.createRepair(deviceID: device.id, complaint: "A")
        #expect(try library.setStatus(.intake, of: repair.id) == nil)
        #expect(try library.notes(for: .repair, id: repair.id).isEmpty)
    }

    // S-007
    @Test func repairRowsComeInWorkflowOrderWithTheirCustomer() throws {
        let (customer, device) = try makeDevice()
        let a = try library.createRepair(deviceID: device.id, complaint: "A", now: Date(timeIntervalSince1970: 100))
        let b = try library.createRepair(deviceID: device.id, complaint: "B", now: Date(timeIntervalSince1970: 200))
        try library.setStatus(.ready, of: a.id)
        let rows = try library.repairRows()
        #expect(rows.map(\.repair.id) == [b.id, a.id])
        #expect(rows.first?.customer.id == customer.id)
        #expect(try library.repairRows(statuses: [.ready]).map(\.repair.id) == [a.id])
        #expect(try library.openRepairCount() == 2)
        try library.setStatus(.pickedUp, of: a.id)
        #expect(try library.openRepairCount() == 1)
    }

    @Test func benchDaysCountCalendarDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        let repair = Repair(id: UUID(), deviceId: UUID(), ticketNumber: 1, status: .intake, complaint: "", diagnosis: "",
                            receivedAt: start, promisedAt: nil, completedAt: nil, pickedUpAt: nil,
                            createdAt: start, updatedAt: start, deletedAt: nil)
        #expect(repair.benchDays(now: now, calendar: calendar) == 3)
    }

    // S-008
    @Test func notesAttachToAnyOwner() throws {
        let (customer, device) = try makeDevice()
        try library.addNote("Prefers texts", to: .customer, id: customer.id)
        try library.addNote("  ", to: .device, id: device.id)
        try library.addNote("Back cover cracked", to: .device, id: device.id)
        #expect(try library.notes(for: .customer, id: customer.id).map(\.text) == ["Prefers texts"])
        #expect(try library.notes(for: .device, id: device.id).map(\.text) == ["Back cover cracked"])
    }

    // S-009
    @Test func deviceRowsShowTheLatestRepairsStatus() throws {
        let (customer, device) = try makeDevice()
        let old = try library.createRepair(deviceID: device.id, complaint: "A", now: Date(timeIntervalSince1970: 100))
        try library.setStatus(.pickedUp, of: old.id)
        _ = try library.createRepair(deviceID: device.id, complaint: "B", now: Date(timeIntervalSince1970: 200))
        let rows = try library.deviceRows()
        #expect(rows.count == 1)
        #expect(rows.first?.customer.id == customer.id)
        #expect(rows.first?.lastStatus == .intake)
        #expect(try library.deviceRows(matching: "OLED").count == 1)
        #expect(try library.deviceRows(matching: "Mario").count == 1)
        #expect(try library.deviceRows(matching: "PS5").isEmpty)
    }
}
