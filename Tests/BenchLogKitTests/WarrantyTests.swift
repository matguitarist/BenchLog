import Foundation
import Testing
@testable import BenchLogKit

/// S-085 Warranty tracking.
@Suite struct WarrantyTests {
    let library: Library
    let device: Device
    let first: Repair
    let day = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "Léa Tremblay", phone: "514 555-0142"))
        device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch"))
        first = try library.createRepair(deviceID: device.id, complaint: "Port USB-C", now: day)
    }

    @Test func onlyFinishedRepairsOfTheDeviceCanBeWarrantied() throws {
        #expect(try library.warrantyCandidates(deviceID: device.id).isEmpty)
        _ = try library.setStatus(.pickedUp, of: first.id, now: day.addingTimeInterval(86_400))
        #expect(try library.warrantyCandidates(deviceID: device.id).map(\.id) == [first.id])
    }

    @Test func aWarrantyRepairPointsAtTheFirst() throws {
        _ = try library.setStatus(.pickedUp, of: first.id, now: day.addingTimeInterval(86_400))
        let again = try library.createRepair(deviceID: device.id, complaint: "Le port lâche encore", warrantyOf: first.id,
                                             now: day.addingTimeInterval(20 * 86_400))
        #expect(again.warrantyOfId == first.id)
        #expect(try library.repair(again.id)?.warrantyOfId == first.id)
        #expect(try library.warrantyRepairs(of: first.id).map(\.id) == [again.id])
        let picked = try #require(try library.repair(first.id))
        #expect(Library.daysSinceDone(picked, now: day.addingTimeInterval(20 * 86_400)) == 19)
        #expect(try library.warrantyCandidates(deviceID: device.id, excluding: first.id).isEmpty)
    }

    @Test func anotherDevicesRepairIsRefused() throws {
        let other = try library.save(Device(customerId: device.customerId, category: .phone, brand: "Apple", model: "iPhone 13"))
        #expect(throws: RepairError.warrantyOfAnotherDevice) {
            try library.createRepair(deviceID: other.id, complaint: "Écran", warrantyOf: first.id)
        }
    }

    @Test func emptyingTheFirstFromTheTrashKeepsTheWarrantyRepair() throws {
        let again = try library.createRepair(deviceID: device.id, complaint: "Encore", warrantyOf: first.id, now: day)
        try library.moveToTrash(.repair(first.id), now: day)
        try library.emptyTrash(now: day.addingTimeInterval(40 * 86_400))
        #expect(try library.repair(first.id) == nil)
        #expect(try library.repair(again.id)?.warrantyOfId == nil)
    }
}
