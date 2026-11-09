import Foundation
import Testing
@testable import BenchLogKit

@Suite struct BillingTests {
    let library: Library
    let customer: Customer
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "Julie Gagnon", phone: "438 555-0199"))
        device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13",
                                         serial: "356789", condition: "Cracked", passcode: "482913"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran fissuré")
    }

    // S-021
    @Test func totalsRoundHalfUpPerTax() {
        let lines = [BillLine(kind: .labour, description: "Pose", hundredths: 150, unitCents: 6500, amountCents: 9750, isHourly: true),
                     BillLine(kind: .part, description: "Écran", hundredths: 100, unitCents: 28999, amountCents: 28999)]
        let totals = Billing.totals(lines, discountCents: 1000, tpsRate: 50_000, tvqRate: 99_750)
        #expect(totals.subtotalCents == 37749)
        #expect(totals.tpsCents == 1887)        // 1887.45
        #expect(totals.tvqCents == 3765)        // 3765.46…
        #expect(totals.totalCents == 37749 + 1887 + 3765)
        // Half a cent rounds up: 10 $ × 5 % of 0.10 $ … 1 cent × 50 % = 0.5 → 1.
        #expect(Billing.roundHalfUp(5, 10) == 1)
        #expect(Billing.totals([BillLine(kind: .part, description: "", hundredths: 100, unitCents: 10, amountCents: 10)],
                               discountCents: 0, tpsRate: 50_000, tvqRate: 0).tpsCents == 1) // 0.5 ¢ → 1 ¢
    }

    @Test func hourlyLabourIsHoursTimesRate() {
        let line = LabourLine(repairId: repair.id, description: "Diagnostic", hundredthHours: 125, unitCents: 6500)
        #expect(line.amountCents == 8125)
        #expect(LabourLine(repairId: repair.id, description: "Forfait", kind: .flat, unitCents: 4000).amountCents == 4000)
    }

    @Test func aBillHasLabourAndPricedParts() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose de l’écran", hundredthHours: 100, unitCents: 6500))
        try library.useFreePart("Écran", on: repair.id, priceCents: 28999)
        try library.useFreePart("Colle", on: repair.id)
        try library.setDiscount(500, of: repair.id)
        let bill = try library.bill(for: repair.id)
        #expect(bill.lines.map(\.description) == ["Pose de l’écran", "Écran"])
        #expect(bill.unpricedParts == ["Colle"])
        #expect(bill.totals.subtotalCents == 6500 + 28999 - 500)
    }

    @Test func invoicesKeepTheRatesTheyUsed() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        let first = try library.issue(.invoice, for: repair.id)
        var profile = try library.businessProfile()
        profile.tpsRate = 70_000
        try library.save(profile)
        let reread = try #require(try library.invoice(first.id)?.document)
        #expect(reread.totals.tpsRate == 50_000)
        #expect(reread.totals.tpsCents == 500)
        #expect(try library.bill(for: repair.id).totals.tpsCents == 700)
    }

    // S-022
    @Test func invoiceNumbersHaveTheirOwnSequence() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        let estimate = try library.issue(.estimate, for: repair.id)
        let first = try library.issue(.invoice, for: repair.id)
        let second = try library.issue(.invoice, for: repair.id)
        #expect(estimate.number == nil)
        #expect(estimate.validUntil != nil)
        #expect(first.numberText == "F-0001")
        #expect(second.numberText == "F-0002")
        #expect(repair.ticketNumber == 1)
        #expect(try library.metaValue("nextTicketNumber") == "2")
    }

    @Test func aBusinessProfileRoundTrips() throws {
        var profile = BusinessProfile()
        profile.name = "Atelier Mathieu"
        profile.tvqNumber = "1234567890 TQ0001"
        try library.save(profile)
        #expect(try library.businessProfile() == profile)
    }

    // S-024
    @Test func anIssuedInvoiceIsFrozen() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        let invoice = try library.issue(.invoice, for: repair.id)
        try library.save(LabourLine(repairId: repair.id, description: "Extra", kind: .flat, unitCents: 5000))
        var changed = try #require(try library.repair(repair.id))
        changed.diagnosis = "Changed later"
        try library.update(changed)
        let document = try #require(try library.invoice(invoice.id)?.document)
        #expect(document.lines.map(\.description) == ["Pose"])
        #expect(document.diagnosis == "")
        #expect(try library.invoice(invoice.id)?.totalCents == invoice.totalCents)
    }

    @Test func nothingToBillIsAnError() {
        #expect(throws: BillingError.self) { try library.issue(.invoice, for: repair.id) }
    }

    // S-025
    @Test func approvingAnEstimateMovesTheRepairOn() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        try library.setStatus(.awaitingApproval, of: repair.id)
        let estimate = try library.issue(.estimate, for: repair.id)
        let moved = try library.decide(estimate.id, approved: true)
        #expect(moved?.status == .inProgress)
        #expect(try library.notes(for: .repair, id: repair.id).contains { $0.kind == .estimate && $0.text == "approved" })

        let other = try library.createRepair(deviceID: device.id, complaint: "Batterie")
        try library.save(LabourLine(repairId: other.id, description: "Pose", kind: .flat, unitCents: 10000))
        try library.useFreePart("Batterie", on: other.id, priceCents: 4000)
        let second = try library.issue(.estimate, for: other.id)
        #expect(try library.decide(second.id, approved: true)?.status == .waitingOnParts)
    }

    // S-026
    @Test func paidInvoicesLeaveToCollect() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        try library.setStatus(.ready, of: repair.id)
        #expect(try library.toCollectRepairIDs() == [repair.id])
        let invoice = try library.issue(.invoice, for: repair.id)
        try library.setPaid(invoice.id, method: .debit)
        #expect(try library.toCollectRepairIDs().isEmpty)
        #expect(try library.invoice(invoice.id)?.paymentMethod == .debit)
    }
}

@Suite struct DocumentTests {
    let library: Library
    let customer: Customer
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "Julie Gagnon", phone: "438 555-0199"))
        device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13",
                                         serial: "356789", condition: "Coin fissuré", passcode: "482913"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran fissuré",
                                          now: Date(timeIntervalSince1970: 1_794_225_600)) // 2026-11-09
    }

    // S-023
    @Test func theIntakeSlipIsInQuebecFrenchWithoutThePasscode() {
        let html = DocumentHTML(language: .french).intakeSlip(business: BusinessProfile(), customer: customer, device: device, repair: repair)
        #expect(html.contains("Bon de dépôt"))
        #expect(html.contains("Description du problème"))
        #expect(html.contains("Signature du client"))
        #expect(html.contains("N°\u{00A0}de dossier\u{00A0}:"))
        #expect(html.contains("9 novembre 2026"))
        #expect(!html.contains("482913"))
        let english = DocumentHTML(language: .english).intakeSlip(business: BusinessProfile(), customer: customer, device: device, repair: repair)
        #expect(english.contains("Intake Slip") && english.contains("November 9, 2026"))
    }

    @Test func frenchMoneyAndRates() {
        let french = DocumentHTML(language: .french)
        #expect(french.money(123456) == "1\u{202F}234,56\u{00A0}$" || french.money(123456) == "1\u{00A0}234,56\u{00A0}$")
        #expect(french.percent(99_750) == "9,975\u{00A0}%")
        #expect(french.percent(50_000) == "5\u{00A0}%")
        #expect(DocumentHTML(language: .english).money(123456) == "$1,234.56")
    }

    // S-024, S-026
    @Test func theInvoiceFollowsQuebecPracticeAndShowsPayment() throws {
        var profile = BusinessProfile()
        profile.tpsNumber = "123456789 RT0001"
        profile.tvqNumber = "1234567890 TQ0001"
        try library.save(profile)
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        let issued = try library.issue(.invoice, for: repair.id)
        let html = DocumentHTML(language: .french).document(issued)
        for words in ["Facture", "N°\u{00A0}de TPS\u{00A0}:", "N°\u{00A0}de TVQ\u{00A0}:", "Sous-total", "Total", "F-0001", "TVQ (9,975\u{00A0}%)"] {
            #expect(html.contains(words), "missing \(words)")
        }
        #expect(!html.contains("PAYÉ"))
        try library.setPaid(issued.id, method: .eTransfer)
        let paid = try #require(try library.invoice(issued.id))
        #expect(DocumentHTML(language: .french).document(paid).contains("PAYÉ"))
        #expect(DocumentHTML(language: .french).document(paid).contains("virement Interac"))
    }

    // S-025
    @Test func theEstimateHasValidUntilAndNoNumber() throws {
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10000))
        let estimate = try library.issue(.estimate, for: repair.id)
        let html = DocumentHTML(language: .french).document(estimate)
        #expect(html.contains("Estimation"))
        #expect(html.contains("Valide jusqu’au"))
        #expect(!html.contains("F-0"))
    }
}
