import Foundation
import Testing
@testable import BenchLogKit

@Suite struct PartTests {
    let library: Library
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "A"))
        device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Drift")
    }

    // S-013
    @Test func aPartFitsCatalogModels() throws {
        let stick = try library.save(Part(name: "Joy-Con stick", sku: "JC-01", priceCents: 1500, quantity: 4),
                                     fits: [PartFit(category: .console, brand: "Nintendo", model: "Switch")])
        let fan = try library.save(Part(name: "PS5 fan", quantity: 1), fits: [])
        #expect(try library.fits(of: stick.id).map(\.title) == ["Nintendo Switch"])
        let found = try library.parts(for: device)
        #expect(found.fitting.map(\.id) == [stick.id])
        #expect(found.others.map(\.id) == [fan.id])
        #expect(try library.parts(matching: "jc-").map(\.id) == [stick.id])
    }

    // S-014
    @Test func installingTakesFromStockAndUndoingPutsItBack() throws {
        let stick = try library.save(Part(name: "Stick", priceCents: 1500, quantity: 4), fits: [])
        let use = try library.usePart(stick.id, on: repair.id, quantity: 2)
        #expect(use.status == .received)
        #expect(use.priceCents == 1500)
        try library.setStatus(.installed, ofUse: use.id)
        #expect(try library.part(stick.id)?.quantity == 2)
        try library.setStatus(.received, ofUse: use.id)
        #expect(try library.part(stick.id)?.quantity == 4)
        try library.setStatus(.installed, ofUse: use.id)
        try library.removeUse(use.id)
        #expect(try library.part(stick.id)?.quantity == 4)
        #expect(try library.partUses(on: repair.id).isEmpty)
    }

    @Test func aPartNotInStockIsNeededAndTheRepairWaits() throws {
        let screen = try library.save(Part(name: "Screen", quantity: 0), fits: [])
        let use = try library.usePart(screen.id, on: repair.id)
        #expect(use.status == .needed)
        #expect(try library.isWaitingOnParts(repair.id))
        try library.setStatus(.ordered, ofUse: use.id)
        #expect(try library.partUseRows(.ordered).map(\.ticketNumber) == [repair.ticketNumber])
        #expect(try library.partUseRows(.needed).isEmpty)
        try library.setStatus(.received, ofUse: use.id)
        #expect(try !library.isWaitingOnParts(repair.id))
    }

    @Test func freeTextPartsDoNotTouchStock() throws {
        let use = try library.useFreePart("HDMI port", on: repair.id, vendor: "AliExpress")
        #expect(use.partId == nil && use.status == .needed)
        try library.setStatus(.installed, ofUse: use.id)
        #expect(try library.partUseRows(.needed).isEmpty)
    }

    @Test func closedRepairsLeaveToOrder() throws {
        _ = try library.useFreePart("Battery", on: repair.id)
        #expect(try library.partUseRows(.needed).count == 1)
        try library.setStatus(.cancelled, of: repair.id)
        #expect(try library.partUseRows(.needed).isEmpty)
    }

    @Test func changingAnInstalledQuantityKeepsStockRight() throws {
        let screw = try library.save(Part(name: "Screw", quantity: 10), fits: [])
        var use = try library.usePart(screw.id, on: repair.id, quantity: 2)
        try library.setStatus(.installed, ofUse: use.id)
        use = try library.partUses(on: repair.id)[0]
        use.quantity = 5
        try library.update(use)
        #expect(try library.part(screw.id)?.quantity == 5)
    }

    // S-015
    @Test func lowStockIsAtOrBelowTheThreshold() throws {
        try library.save(Part(name: "A", quantity: 2, lowStockThreshold: 2), fits: [])
        try library.save(Part(name: "B", quantity: 3, lowStockThreshold: 2), fits: [])
        try library.save(Part(name: "C", quantity: 0, lowStockThreshold: 0), fits: [])
        #expect(try library.parts(lowOnly: true).map(\.name) == ["A"])
        #expect(try library.lowStockCount() == 1)
    }
}
