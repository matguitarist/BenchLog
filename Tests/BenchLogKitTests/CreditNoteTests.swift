import Foundation
import Testing
@testable import BenchLogKit

/// S-040 Credit note for an invoice, S-041 Record a refund.
@Suite struct CreditNoteTests {
    let library: Library
    let repair: Repair

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "Léa Tremblay"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran")
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10_000))
        try library.setDiscount(1_000, of: repair.id)
    }

    @Test func aCreditNoteReversesTheInvoiceWithItsOwnNumber() throws {
        let invoice = try library.issue(.invoice, for: repair.id)
        let credit = try library.issueCreditNote(for: invoice.id, reason: "Mauvais prix")
        #expect(credit.numberText == "NC-0001")
        #expect(credit.creditsInvoiceId == invoice.id)
        #expect(credit.totalCents == -invoice.totalCents)
        let content = try #require(credit.document)
        #expect(content.credits == "F-0001" && content.reason == "Mauvais prix")
        #expect(content.totals.taxes.map(\.cents) == [-450, -898])
        #expect(content.lines.first?.amountCents == -10_000)
        // The invoice keeps its number, and the next invoice takes the next one.
        #expect(try library.invoice(invoice.id)?.numberText == "F-0001")
        #expect(try library.issue(.invoice, for: repair.id).numberText == "F-0002")
        #expect(try library.creditNote(of: invoice.id)?.id == credit.id)
    }

    @Test func anInvoiceIsCreditedOnceAndOnlyInvoicesAre() throws {
        let invoice = try library.issue(.invoice, for: repair.id)
        let credit = try library.issueCreditNote(for: invoice.id)
        #expect(throws: BillingError.alreadyCredited("NC-0001")) { try library.issueCreditNote(for: invoice.id) }
        #expect(throws: BillingError.notAnInvoice) { try library.issueCreditNote(for: credit.id) }
        let estimate = try library.issue(.estimate, for: repair.id)
        #expect(throws: BillingError.notAnInvoice) { try library.issueCreditNote(for: estimate.id) }
    }

    @Test func aCreditedInvoiceNoLongerCountsAsPaid() throws {
        _ = try library.setStatus(.ready, of: repair.id)
        let invoice = try library.issue(.invoice, for: repair.id)
        try library.setPaid(invoice.id, method: .debit)
        #expect(try !library.toCollectRepairIDs().contains(repair.id))
        try library.issueCreditNote(for: invoice.id)
        #expect(try library.toCollectRepairIDs().contains(repair.id))
    }

    @Test func theCreditNotePrintsWhatItCredits() throws {
        let invoice = try library.issue(.invoice, for: repair.id)
        let credit = try library.issueCreditNote(for: invoice.id, reason: "Erreur de facturation")
        let french = DocumentHTML(language: .french).document(credit)
        for words in ["Note de crédit", "NC-0001", "Crédite la facture", "F-0001", "Motif", "Erreur de facturation", "-100,00"] {
            #expect(french.contains(words), "missing \(words)")
        }
        #expect(!french.contains("Garantie"))
        try library.setPaid(credit.id, method: .eTransfer)
        let refunded = DocumentHTML(language: .english).document(try #require(try library.invoice(credit.id)))
        #expect(refunded.contains("REFUNDED") && refunded.contains("Refunded on"))
    }
}
