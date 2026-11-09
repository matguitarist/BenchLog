import Foundation
import Testing
@testable import BenchLogKit

// S-016
@Suite struct CatalogTests {
    let library: Library
    let customer: Customer

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "A"))
    }

    @Test func theOutlineGoesCategoryBrandModelRevision() throws {
        _ = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13", revision: "Pro"))
        let apple = try #require(try library.catalogOutline()[.phone]?.first { $0.name == "Apple" })
        let thirteen = try #require(apple.children?.first { $0.name == "iPhone 13" })
        #expect(thirteen.children?.contains { $0.name == "Pro" } == true)
        #expect(apple.deviceCount == 1 && thirteen.deviceCount == 1)
    }

    @Test func mergingModelsMovesDevicesAndPartFits() throws {
        _ = try library.save(Device(customerId: customer.id, category: .console, brand: "Sony", model: "PS5 Digital"))
        _ = try library.save(Device(customerId: customer.id, category: .console, brand: "Sony", model: "PS5"))
        let port = try library.save(Part(name: "HDMI port"), fits: [PartFit(category: .console, brand: "Sony", model: "PS5 Digital"),
                                                                     PartFit(category: .console, brand: "Sony", model: "PS5")])
        try library.renameCatalog(CatalogPath(category: .console, brand: "Sony", model: "PS5 Digital"), to: "PS5")
        #expect(try !library.catalogModels(.console, brand: "Sony").contains("PS5 Digital"))
        #expect(try library.deviceRows(matching: "").filter { $0.device.brand == "Sony" }.allSatisfy { $0.device.model == "PS5" })
        #expect(try library.fits(of: port.id).map(\.model) == ["PS5"])
    }

    @Test func aRenameThatOnlyChangesCaseKeepsTheNewSpelling() throws {
        _ = try library.save(Device(customerId: customer.id, category: .computer, brand: "Lenovo", model: "thinkpad x1"))
        try library.renameCatalog(CatalogPath(category: .computer, brand: "Lenovo", model: "thinkpad x1"), to: "ThinkPad X1")
        #expect(try library.catalogModels(.computer, brand: "Lenovo").contains("ThinkPad X1"))
    }

    @Test func deletingFromTheCatalogKeepsDevices() throws {
        let device = try library.save(Device(customerId: customer.id, category: .handheld, brand: "Analogue", model: "Pocket"))
        try library.deleteFromCatalog(CatalogPath(category: .handheld, brand: "Analogue"))
        #expect(try library.catalogBrands(.handheld).contains("Analogue") == false)
        #expect(try library.device(device.id)?.model == "Pocket")
    }
}
