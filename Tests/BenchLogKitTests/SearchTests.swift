import Foundation
import Testing
@testable import BenchLogKit

/// S-027 Global search.
@Suite struct SearchTests {
    let library: Library
    let customer: Customer
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "Mario Tremblay", phone: "514 555-0142", email: "mario@example.com"))
        device = try library.save(Device(customerId: customer.id, category: .console, brand: "Nintendo", model: "Switch",
                                         revision: "OLED Model", serial: "XTW70012345678", passcode: "8642"))
        var made = try library.createRepair(deviceID: device.id, complaint: "Left Joy-Con drifts")
        // Ticket 12, to check "#12" and "12".
        for _ in 0..<11 { made = try library.createRepair(deviceID: device.id, complaint: "Fan is loud") }
        repair = made
    }

    private func kinds(_ text: String) throws -> [SearchKind] { try library.search(text).map(\.kind) }

    @Test func aTicketNumberFindsItsRepair() throws {
        #expect(repair.ticketNumber == 12)
        for text in ["#12", "12", "0012", "#0012"] {
            let hit = try library.search(text).first { $0.kind == .repair && $0.id == repair.id }
            #expect(hit != nil, "\(text)")
            #expect(hit?.title == "#0012 Mario Tremblay")
        }
    }

    @Test func digitsMatchPhoneNumbers() throws {
        for text in ["5145550142", "514 555-0142", "555-0142", "5550142", "555"] {
            #expect(try library.search(text).contains { $0.kind == .customer && $0.id == customer.id }, "\(text)")
        }
    }

    @Test func serialsNamesAndAccentsMatch() throws {
        #expect(try kinds("XTW700").contains(.device))
        #expect(try kinds("tremb").contains(.customer))
        let accented = try library.save(Customer(name: "Chloé Bouchard"))
        #expect(try library.search("chloe").contains { $0.id == accented.id })
    }

    @Test func thePasscodeIsNeverIndexed() throws {
        #expect(try library.search("8642").isEmpty)
    }

    @Test func notesOpenTheirOwner() throws {
        let note = try #require(try library.addNote("Ordered a fan from AliExpress\nshould arrive Friday", to: .repair, id: repair.id))
        let hit = try #require(try library.search("aliexpress").first)
        #expect(hit.kind == .note && hit.id == note.id)
        #expect(hit.target == .init(kind: .repair, id: repair.id))
        #expect(hit.title == "Ordered a fan from AliExpress")
        #expect(hit.subtitle == "#0012")
    }

    @Test func partsAndGuidesAreFound() throws {
        _ = try library.save(Part(name: "Switch OLED fan", sku: "SW-FAN-01", vendor: "iFixit"), fits: [])
        #expect(try kinds("SW-FAN").contains(.part))
        #expect(try kinds("ifixit").contains(.part))
    }

    @Test func aRenamedCustomerRenamesTheirRepairs() throws {
        var renamed = customer
        renamed.name = "Mario Bros"
        _ = try library.save(renamed)
        #expect(try library.search("bros 12").contains { $0.kind == .repair && $0.title.hasPrefix("#0012 Mario Bros") })
        #expect(try library.search("tremblay").isEmpty)
    }

    @Test func trashedRowsDropOut() throws {
        try library.trash(Customer.self, id: customer.id)
        #expect(try !kinds("tremblay").contains(.customer))
    }

    @Test func resultsAreGroupedByKind() throws {
        let hits = try library.search("mario", limitPerKind: 3)
        // Each kind appears in one run, never interleaved.
        var seen: [SearchKind] = []
        for hit in hits where seen.last != hit.kind {
            #expect(!seen.contains(hit.kind))
            seen.append(hit.kind)
        }
        #expect(hits.filter { $0.kind == .repair }.count == 3)
    }

    @Test func punctuationAloneSearchesNothing() throws {
        #expect(try library.search("  #- ").isEmpty)
        #expect(SearchIndex.query("Joy-Con") == "\"joy\"* \"con\"*")
    }
}
