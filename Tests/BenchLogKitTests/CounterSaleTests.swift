import Foundation
import GRDB
import Testing
@testable import BenchLogKit

/// S-046 Counter sales.
@Suite struct CounterSaleTests {
    let library: Library
    let cable: Part
    let customer: Customer

    init() throws {
        library = try Library()
        cable = try library.save(Part(name: "USB-C cable", costCents: 300, priceCents: 1_500, quantity: 4), fits: [])
        customer = try library.save(Customer(name: "Nadia Roy"))
    }

    private var items: [CounterSaleItem] {
        [CounterSaleItem(partId: cable.id, description: "USB-C cable", quantity: 2, unitCents: 1_500),
         CounterSaleItem(description: "Screen protector", quantity: 1, unitCents: 1_000)]
    }

    @Test func aCounterSaleIsAnInvoiceAndPartsLeaveStockAsSold() throws {
        let invoice = try library.issueCounterSale(to: customer.id, items: items)
        #expect(invoice.numberText == "F-0001" && invoice.customerId == customer.id && invoice.repairId == nil && invoice.deviceId == nil)
        let content = try #require(invoice.document)
        #expect(content.lines.map(\.kind) == [.part, .item])
        #expect(content.totals.subtotalCents == 4_000)
        #expect(content.totals.taxes.map(\.cents) == [200, 399])   // 5 % and 9.975 % of 40 $
        #expect(try library.part(cable.id)?.quantity == 2)
        let move = try #require(try library.stockHistory(of: cable.id).first)
        #expect(move.move.reason == .sold && move.move.delta == -2 && move.source == "F-0001")
        #expect(try library.counterSales(of: customer.id).map(\.id) == [invoice.id])
        #expect(try library.salesReport(ReportPeriod(.month, containing: .now)).rows.count == 1)
    }

    @Test func creditingPutsThePartsBack() throws {
        let invoice = try library.issueCounterSale(to: customer.id, items: items)
        let credit = try library.issueCreditNote(for: invoice.id, reason: "Wrong cable")
        #expect(credit.customerId == customer.id)
        #expect(try library.part(cable.id)?.quantity == 4)
        let move = try #require(try library.stockHistory(of: cable.id).first)
        #expect(move.move.reason == .returned && move.move.delta == 2 && move.source == "NC-0001")
        #expect(try library.counterSales(of: customer.id).count == 2)
    }

    @Test func aWalkInSaleSitsWithTheShopAndPrintsAsWalkIn() throws {
        let invoice = try library.issueCounterSale(to: nil, items: items)
        let shop = try #require(try library.existingShop())
        #expect(invoice.customerId == shop.id)
        let content = try #require(invoice.document)
        #expect(content.customer.name.isEmpty)
        let html = DocumentHTML(language: .english).document(invoice)
        #expect(html.contains("Walk-in customer"))
        #expect(!html.contains("<h2>Device</h2>"))
    }

    @Test func nothingToSellIsAnError() throws {
        #expect(throws: BillingError.nothingToBill) { try library.issueCounterSale(to: customer.id, items: []) }
        #expect(throws: BillingError.nothingToBill) {
            try library.issueCounterSale(to: customer.id, items: [CounterSaleItem(description: " ", unitCents: 100)])
        }
    }

    /// S-069 The Counter Sales page lists every sale, newest first, with its credit note.
    @Test func theCounterSalesListHasEverySaleNewestFirst() throws {
        let first = try library.issueCounterSale(to: customer.id, items: items, now: Date(timeIntervalSinceNow: -3_600))
        let walkIn = try library.issueCounterSale(to: nil, items: [CounterSaleItem(description: "Carrying case", unitCents: 2_000)])
        let credit = try library.issueCreditNote(for: first.id, reason: "Wrong cable")
        let rows = try library.counterSaleRows()
        #expect(rows.map(\.id) == [walkIn.id, first.id])
        #expect(rows[0].customerName.isEmpty && rows[0].customerId == nil && rows[0].creditNote == nil)
        #expect(rows[1].customerName == "Nadia Roy" && rows[1].customerId == customer.id && rows[1].creditNote?.id == credit.id)
        #expect(rows[1].lines.count == 2 && rows[1].totals.subtotalCents == 4_000)
        #expect(try library.counterSaleRows(matching: "nadia").map(\.id) == [first.id])
        #expect(try library.counterSaleRows(matching: "carrying").map(\.id) == [walkIn.id])
        #expect(try library.counterSaleRows(matching: "F-0002").map(\.id) == [walkIn.id])
        #expect(try library.counterSaleRows(matching: "nothing like it").isEmpty)
    }

    @Test func aCustomerWithACounterSaleStaysOutOfTheTrash() throws {
        try library.issueCounterSale(to: customer.id, items: items)
        #expect(throws: TrashError.hasInvoices(["F-0001"])) { try library.moveToTrash(.customer(customer.id)) }
    }

    @Test func invoicesFromBeforeCounterSalesSurviveTheRebuild() throws {
        let invoice = try library.issueCounterSale(to: customer.id, items: items)
        try library.db.read { db in
            let columns = try db.columns(in: "invoice").map(\.name)
            #expect(columns.contains("customerId"))
            #expect(try Invoice.fetchOne(db, key: invoice.id.stored) != nil)
        }
    }
}
