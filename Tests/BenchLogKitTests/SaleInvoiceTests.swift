import Foundation
import GRDB
import Testing
@testable import BenchLogKit

/// S-043 Sales invoice for a shop device.
@Suite struct SaleInvoiceTests {
    let library: Library
    let device: Device
    let buyer: Customer

    init() throws {
        library = try Library()
        let shop = try library.shop(named: "Atelier")
        var made = Device(customerId: shop.id, category: .console, brand: "Sony", model: "PS4", revision: "Slim", serial: "MB123")
        made.purchaseCents = 6_000
        device = try library.save(made)
        buyer = try library.save(Customer(name: "Samir Haddad"))
    }

    @Test func aSaleIsInvoicedToTheBuyerWithTheRegionsTaxes() throws {
        #expect(throws: BillingError.saleNotReady) { try library.issueSaleInvoice(for: device.id) }
        try library.setDisposition(.sold, priceCents: 18_000, buyer: buyer.id, of: device.id)
        let invoice = try library.issueSaleInvoice(for: device.id)
        #expect(invoice.numberText == "F-0001" && invoice.deviceId == device.id && invoice.repairId == nil)
        let content = try #require(invoice.document)
        #expect(content.customer.name == "Samir Haddad")
        #expect(content.lines.map(\.kind) == [.item])
        #expect(content.totals.taxes.map(\.cents) == [900, 1_796])   // 5 % and 9.975 % of 180 $
        #expect(invoice.totalCents == 20_696)
        let html = DocumentHTML(language: .french).document(invoice)
        #expect(html.contains("Articles") && html.contains("Sony PS4 Slim") && !html.contains("N°\u{00A0}de dossier"))
        #expect(!html.contains("Garantie"))
    }

    @Test func aSaleIsInvoicedOnceUnlessCredited() throws {
        try library.setDisposition(.sold, priceCents: 18_000, buyer: buyer.id, of: device.id)
        let first = try library.issueSaleInvoice(for: device.id)
        #expect(throws: BillingError.alreadyInvoiced("F-0001")) { try library.issueSaleInvoice(for: device.id) }
        let credit = try library.issueCreditNote(for: first.id)
        #expect(credit.deviceId == device.id)
        #expect(try library.issueSaleInvoice(for: device.id).numberText == "F-0002")
        #expect(try library.saleInvoices(of: device.id).count == 3)
    }

    @Test func aSoldDeviceWithAnInvoiceStaysOutOfTheTrash() throws {
        try library.setDisposition(.sold, priceCents: 18_000, buyer: buyer.id, of: device.id)
        try library.issueSaleInvoice(for: device.id)
        #expect(throws: TrashError.hasInvoices(["F-0001"])) { try library.moveToTrash(.customer(buyer.id)) }
    }

    @Test func invoicesFromBeforeSalesSurviveTheTableRebuild() throws {
        let queue = try DatabaseQueue()
        try Library.migrator.migrate(queue, upTo: "v10-credit-notes")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO customer (id, name, phone, phoneDigits, email, address, documentsLanguage, createdAt, updatedAt)
                    VALUES ('c', 'Léa', '', '', '', '', 'fr', '2026-01-01', '2026-01-01');
                INSERT INTO device (id, customerId, category, brand, model, revision, serial, colour, condition, passcode, passcodeIsPattern, createdAt, updatedAt)
                    VALUES ('d', 'c', 'phone', 'Apple', 'iPhone', '', '', '', '', '', 0, '2026-01-01', '2026-01-01');
                INSERT INTO repair (id, deviceId, ticketNumber, status, complaint, diagnosis, receivedAt, discountCents, createdAt, updatedAt)
                    VALUES ('r', 'd', 1, 'ready', 'Écran', '', '2026-01-01', 0, '2026-01-01', '2026-01-01');
                INSERT INTO invoice (id, repairId, kind, number, issuedAt, language, content, totalCents, createdAt, updatedAt)
                    VALUES ('i', 'r', 'invoice', 1, '2026-01-02', 'fr', '{}', 11498, '2026-01-02', '2026-01-02');
                INSERT INTO invoice (id, repairId, kind, issuedAt, language, content, totalCents, createdAt, updatedAt, creditNumber, creditsInvoiceId)
                    VALUES ('n', 'r', 'creditNote', '2026-01-03', 'fr', '{}', -11498, '2026-01-03', '2026-01-03', 1, 'i');
                """)
        }
        try Library.migrator.migrate(queue)
        let (count, credits, problems) = try queue.read { db in
            (try Int.fetchOne(db, sql: "SELECT count(*) FROM invoice"),
             try String.fetchOne(db, sql: "SELECT creditsInvoiceId FROM invoice WHERE id = 'n'"),
             try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count)
        }
        #expect(count == 2 && credits == "i" && problems == 0)
    }
}
