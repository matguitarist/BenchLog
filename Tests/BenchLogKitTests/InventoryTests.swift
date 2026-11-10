import Foundation
import Testing
@testable import BenchLogKit

/// S-047 Inventory value.
@Suite struct InventoryTests {
    let library: Library
    let day = 86_400.0
    let start = Date(timeIntervalSince1970: 1_780_000_000)

    init() throws { library = try Library() }

    @Test func partsAtCostAndPriceAndShopDevicesInStock() throws {
        try library.save(Part(name: "Fan", costCents: 1_000, priceCents: 2_500, quantity: 3), fits: [])
        try library.save(Part(name: "Paste", priceCents: 500, quantity: 4), fits: [])
        try library.save(Part(name: "Empty", costCents: 9_999, quantity: 0), fits: [])
        let shop = try library.shop(named: "Atelier")
        var ps4 = Device(customerId: shop.id, category: .console, brand: "Sony", model: "PS4")
        ps4.purchaseCents = 6_000
        ps4 = try library.save(ps4)
        try library.setDisposition(.forSale, priceCents: 15_000, of: ps4.id)
        var kept = Device(customerId: shop.id, category: .computer, brand: "Apple", model: "Bench Mac")
        kept.purchaseCents = 50_000
        kept = try library.save(kept)
        try library.setDisposition(.kept, of: kept.id)

        let value = try library.inventoryValue()
        #expect(value.partsCostCents == 3_000)
        #expect(value.partsPriceCents == 7_500 + 2_000)
        #expect(value.units == 7)
        #expect(value.partsWithoutCost == 1)
        #expect(value.devicesCostCents == 6_000 && value.devices == 1)
        #expect(value.totalCents == 9_000)
    }

    @Test func aPastDateUsesTheStockMoves() throws {
        let part = try library.save(Part(name: "Fan", costCents: 1_000, quantity: 2, now: start), fits: [], now: start)
        try library.count(part.id, counted: 5, now: start.addingTimeInterval(10 * day))
        try library.removeDamaged(part.id, quantity: 4, now: start.addingTimeInterval(20 * day))
        #expect(try library.inventoryValue(at: start.addingTimeInterval(-day)).units == 0)
        #expect(try library.inventoryValue(at: start.addingTimeInterval(day)).partsCostCents == 2_000)
        #expect(try library.inventoryValue(at: start.addingTimeInterval(15 * day)).partsCostCents == 5_000)
        #expect(try library.inventoryValue(at: start.addingTimeInterval(25 * day)).partsCostCents == 1_000)
        #expect(try library.inventoryValue().partsCostCents == 1_000)
    }

    @Test func aDeviceSoldAfterTheDateCountsThen() throws {
        let shop = try library.shop(named: "Atelier")
        let buyer = try library.save(Customer(name: "Samir"))
        var gbc = Device(customerId: shop.id, category: .handheld, brand: "Nintendo", model: "Game Boy Color", now: start)
        gbc.purchaseCents = 2_500
        gbc = try library.save(gbc, now: start)
        try library.setDisposition(.sold, priceCents: 12_000, buyer: buyer.id, of: gbc.id, now: start.addingTimeInterval(10 * day))
        #expect(try library.inventoryValue(at: start.addingTimeInterval(5 * day)).devicesCostCents == 2_500)
        #expect(try library.inventoryValue(at: start.addingTimeInterval(15 * day)).devicesCostCents == 0)
        #expect(try library.inventoryValue().devices == 0)
    }
}
