import Foundation
import Testing
@testable import BenchLogKit

/// S-033 Delete and undo.
@Suite struct TrashTests {
    let library: Library
    let customer: Customer
    let device: Device
    let repair: Repair
    let day = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "Léa Tremblay", phone: "514 555-0142"))
        device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran fissuré")
        _ = try library.addNote("Fissure en haut à gauche", to: .repair, id: repair.id)
        _ = try library.addAttachment(data: Data("photo".utf8), originalName: "front.jpg", to: .repair, id: repair.id)
    }

    @Test func aCustomerTakesItsDevicesRepairsAndNotesAlong() throws {
        #expect(try library.openRepairCount(ofCustomer: customer.id) == 1)
        let stamp = try library.moveToTrash(.customer(customer.id), now: day)
        #expect(try library.customers().isEmpty)
        #expect(try library.devices(of: customer.id).isEmpty)
        #expect(try library.repairRows().isEmpty)
        #expect(try library.notes(for: .repair, id: repair.id).isEmpty)
        #expect(try library.search("Tremblay").isEmpty)
        #expect(try library.search("fissure").isEmpty)

        try library.putBack(.customer(customer.id), trashedAt: stamp)
        #expect(try library.customers().count == 1)
        #expect(try library.repairRows().count == 1)
        #expect(try library.notes(for: .repair, id: repair.id).count == 1)
        #expect(try library.attachments(for: .repair, id: repair.id).count == 1)
        #expect(try !library.search("Tremblay").isEmpty)
    }

    @Test func putBackLeavesWhatWasTrashedBefore() throws {
        try library.moveToTrash(.repair(repair.id), now: day)
        let stamp = try library.moveToTrash(.device(device.id), now: day.addingTimeInterval(60))
        try library.putBack(.device(device.id), trashedAt: stamp)
        #expect(try library.devices(of: customer.id).count == 1)
        #expect(try library.repairRows().isEmpty)
    }

    @Test func aRepairWithAnInvoiceStays() throws {
        _ = try library.save(LabourLine(repairId: repair.id, description: "Écran", kind: .flat, unitCents: 12_000))
        _ = try library.issue(.invoice, for: repair.id)
        #expect(throws: TrashError.hasInvoices(["F-0001"])) { try library.moveToTrash(.customer(customer.id)) }
        #expect(try library.customers().count == 1)
    }

    @Test func theShopStays() throws {
        let shop = try library.shop(named: "Atelier")
        #expect(throws: TrashError.isShop) { try library.moveToTrash(.customer(shop.id)) }
    }

    @Test func emptyTrashRemovesOldRowsAndTheirFiles() throws {
        let file = try #require(try library.attachments(for: .repair, id: repair.id).first)
        let url = library.fileURL(for: file)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let part = try library.save(Part(name: "Écran iPhone 13", costCents: 6_000, priceCents: 12_000, quantity: 1), fits: [])
        try library.moveToTrash(.customer(customer.id), now: day)
        try library.moveToTrash(.part(part.id), now: day.addingTimeInterval(29 * 86_400))

        let later = day.addingTimeInterval(31 * 86_400)
        #expect(try library.trashCount(now: later) == 5)   // customer, device, repair, note, photo
        #expect(try library.emptyTrash(now: later) == 5)
        #expect(try library.customer(customer.id) == nil)
        #expect(try library.repair(repair.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // The part went in 2 days ago: it waits its 30 days.
        #expect(try library.trashCount(now: later) == 0)
        #expect(try library.trashCount(now: later.addingTimeInterval(29 * 86_400)) == 1)
    }
}
