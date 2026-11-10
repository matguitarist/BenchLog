import Foundation
import Testing
@testable import BenchLogKit

/// S-045 Restock orders.
@Suite struct RestockTests {
    let library: Library
    let screen: Part
    let battery: Part
    let paste: Part

    init() throws {
        library = try Library()
        screen = try library.save(Part(name: "iPhone 13 screen", vendor: "MobileSentrix", costCents: 6_000, quantity: 1, lowStockThreshold: 2), fits: [])
        battery = try library.save(Part(name: "iPhone 13 battery", vendor: "MobileSentrix", costCents: 1_500, quantity: 8, lowStockThreshold: 3), fits: [])
        paste = try library.save(Part(name: "Thermal paste", vendor: "Amazon", costCents: 900, quantity: 0, lowStockThreshold: 1), fits: [])
    }

    @Test func orderMoreAddsToTheVendorsDraft() throws {
        let first = try library.orderMore(screen.id)
        let again = try library.orderMore(battery.id, quantity: 4)
        #expect(first == again)
        try library.orderMore(screen.id, quantity: 2)
        let orders = try library.restockOrders()
        #expect(orders.count == 1)
        #expect(orders[0].restock.vendor == "MobileSentrix")
        #expect(orders[0].lines.map(\.line.quantity) == [3 + 2, 4])   // 2 × 2 − 1 to reach twice the threshold, then 2 more
        #expect(orders[0].totalCents == 5 * 6_000 + 4 * 1_500)
    }

    @Test func addLowPartsFillsDraftsOncePerPart() throws {
        #expect(try library.addLowParts() == 2)   // the screen and the paste; the battery is not low
        #expect(try library.addLowParts() == 0)
        let orders = try library.restockOrders()
        #expect(Set(orders.map(\.restock.vendor)) == ["MobileSentrix", "Amazon"])
        #expect(orders.first { $0.restock.vendor == "Amazon" }?.lines.first?.line.quantity == 2)
    }

    @Test func receivingPutsStockOnTheShelfAndUpdatesTheCost() throws {
        let id = try #require(try library.orderMore(screen.id, quantity: 3))
        let line = try #require(try library.restockOrders().first?.lines.first)
        try library.updateRestockLine(line.id, quantity: 4, costCents: 5_500)
        #expect(throws: RestockError.wrongStatus) { try library.receive(id) }
        try library.markOrdered(id)
        #expect(try library.unitsOnOrder(screen.id) == 4)
        #expect(throws: RestockError.wrongStatus) { try library.updateRestockLine(line.id, quantity: 9, costCents: nil) }
        try library.receive(id)
        let part = try #require(try library.part(screen.id))
        #expect(part.quantity == 5)
        #expect(part.costCents == 5_500)
        #expect(try library.unitsOnOrder(screen.id) == 0)
        let move = try #require(try library.stockHistory(of: screen.id).first?.move)
        #expect(move.reason == .received)
        #expect(move.restockId == id)
        #expect(try library.restockOrders().first?.restock.status == .received)
    }

    @Test func anEmptyDraftCannotBeOrderedAndADraftCanBeDiscarded() throws {
        let id = try #require(try library.orderMore(paste.id))
        let line = try #require(try library.restockOrders().first?.lines.first)
        try library.updateRestockLine(line.id, quantity: 0, costCents: nil)
        #expect(throws: RestockError.empty) { try library.markOrdered(id) }
        try library.discardRestock(id)
        #expect(try library.restockOrders().isEmpty)
    }
}
