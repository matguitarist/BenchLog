import Foundation
import Testing
@testable import BenchLogKit

/// S-035 Internal jobs, S-036 Sell or keep a shop device.
@Suite struct ShopTests {
    let library: Library
    let shop: Customer
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        shop = try library.shop(named: "Atelier Électro Bench")
        var made = Device(customerId: shop.id, category: .console, brand: "Sony", model: "PS4", revision: "Slim")
        made.purchaseCents = 6_000
        device = try library.save(made)
        repair = try library.createRepair(deviceID: device.id, complaint: "Refurbish: new fan, clean")
        let fan = try library.save(Part(name: "PS4 fan", costCents: 1_250, priceCents: 2_500, quantity: 3), fits: [])
        _ = try library.usePart(fan.id, on: repair.id, quantity: 2)
        _ = try library.save(LabourLine(repairId: repair.id, description: "Clean and repaste", kind: .hourly, hundredthHours: 150, unitCents: 6500))
    }

    @Test func thereIsOneShopNamedAfterTheBusiness() throws {
        let again = try library.shop(named: "Atelier Électro Bench")
        #expect(again.id == shop.id && again.isShop)
        #expect(try library.shop(named: "Électro Bench").name == "Électro Bench")
        #expect(try library.customers().isEmpty)
        #expect(try !library.search("atelier").contains { $0.kind == .customer })
    }

    @Test func anInternalJobCostsPartsAtCostAndHours() throws {
        #expect(try library.isInternal(repair.id))
        let cost = try library.internalCost(of: repair.id)
        #expect(cost.partsCents == 2_500)
        #expect(cost.hundredthHours == 150)
    }

    @Test func anInternalJobHasNoDocumentsAndNeverNeedsCollecting() throws {
        #expect(throws: ShopError.self) { try library.issue(.invoice, for: repair.id) }
        #expect(throws: ShopError.self) { try library.issue(.estimate, for: repair.id) }
        _ = try library.setStatus(.ready, of: repair.id)
        #expect(try !library.toCollectRepairIDs().contains(repair.id))
    }

    @Test func costAndProfitOfASale() throws {
        var row = try #require(try library.shopDevices().first)
        #expect(row.costCents == 8_500)   // 60 $ + 2 fans at 12,50 $
        #expect(row.profitCents == nil)
        try library.setDisposition(.forSale, priceCents: 20_000, of: device.id)
        #expect(try library.shopDevices().first?.profitCents == nil)
        let buyer = try library.save(Customer(name: "Samir Haddad"))
        try library.setDisposition(.sold, priceCents: 15_000, buyer: buyer.id, of: device.id)
        row = try #require(try library.shopDevices().first)
        #expect(row.profitCents == 6_500)
        #expect(row.buyer?.id == buyer.id)
        #expect(try library.device(device.id)?.customerId == buyer.id)
        // The buyer's later repairs are not internal and do not change the shop's cost.
        let later = try library.createRepair(deviceID: device.id, complaint: "Warranty check")
        #expect(try !library.isInternal(later.id))
        #expect(try library.shopDevices().first?.costCents == 8_500)
    }

    @Test func keepingOrUnsellingReturnsItToTheShop() throws {
        let buyer = try library.save(Customer(name: "Emma Wilson"))
        try library.setDisposition(.sold, priceCents: 10_000, buyer: buyer.id, of: device.id)
        try library.setDisposition(.kept, of: device.id)
        let kept = try #require(try library.device(device.id))
        #expect(kept.customerId == shop.id && kept.soldAt == nil && kept.salePriceCents == nil)
    }
}
