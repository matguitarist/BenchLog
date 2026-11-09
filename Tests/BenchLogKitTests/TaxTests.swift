import Foundation
import Testing
@testable import BenchLogKit

/// S-037 Taxes by region, S-038 bills and documents, S-039 currency.
@Suite struct TaxTests {
    let lines = [BillLine(kind: .labour, description: "Pose", hundredths: nil, unitCents: 10_000, amountCents: 10_000),
                 BillLine(kind: .part, description: "Écran", hundredths: 100, unitCents: 30_000, amountCents: 30_000)]

    @Test func everyProvinceHasItsTaxes() {
        func taxes(_ code: String) -> [String] {
            TaxRegion.find(.canada, code)!.taxes.map { "\($0.kind.rawValue) \($0.rate)" }
        }
        #expect(taxes("QC") == ["gst 50000", "qst 99750"])
        #expect(taxes("ON") == ["hst 130000"])
        for code in ["NB", "NL", "PE"] { #expect(taxes(code) == ["hst 150000"]) }
        #expect(taxes("NS") == ["hst 140000"])
        #expect(taxes("BC") == ["gst 50000", "pst 70000"])
        #expect(taxes("MB") == ["gst 50000", "rst 70000"])
        #expect(taxes("SK") == ["gst 50000", "pst 60000"])
        for code in ["AB", "NT", "NU", "YT"] { #expect(taxes(code) == ["gst 50000"]) }
        #expect(TaxRegion.provinces.count == 13)
    }

    @Test func statesHaveOneSalesTaxPlusTheLocalRate() {
        #expect(TaxRegion.states.count == 51)
        for code in ["AK", "DE", "MT", "NH", "OR"] { #expect(TaxRegion.find(.unitedStates, code)!.taxes.isEmpty) }
        var profile = BusinessProfile()
        profile.setRegion(.unitedStates, "NY")
        profile.localRate = 48_750
        #expect(profile.chargedTaxes == [TaxRate(.sales, rate: 88_750)])   // New York City: 8.875 %
        let totals = Billing.totals(lines, discountCents: 0, taxes: profile.chargedTaxes)
        #expect(totals.taxes.map(\.cents) == [3_550])
        // A state with no sales tax still charges the local one.
        profile.setRegion(.unitedStates, "AK")
        #expect(profile.localRate == 0 && profile.chargedTaxes.isEmpty)
        profile.localRate = 50_000
        #expect(profile.chargedTaxes == [TaxRate(.sales, rate: 50_000)])
    }

    @Test func movingKeepsTheNumbersOfTaxesThatStay() {
        var profile = BusinessProfile()
        profile.taxes[0].number = "123456789 RT0001"
        profile.setRegion(.canada, "BC")
        #expect(profile.taxes.map(\.number) == ["123456789 RT0001", ""])
    }

    @Test func untaxedLabourLeavesOnlyThePartsTaxable() {
        let totals = Billing.totals(lines, discountCents: 4_000, taxes: [TaxRate(.sales, rate: 72_500)], taxesLabour: false)
        #expect(totals.subtotalCents == 36_000)
        #expect(totals.taxableCents == 27_000)        // parts less their 3/4 of the discount
        #expect(totals.taxes.map(\.cents) == [1_958])  // 1957.5 → 1958
        #expect(totals.totalCents == 37_958)
    }

    @Test func aProfileFromBeforeRegionsIsQuebec() throws {
        let old = #"{"name":"Atelier","tpsNumber":"123456789 RT0001","tvqNumber":"1234567890 TQ0001","tpsRate":50000,"tvqRate":99750}"#
        let profile = try JSONDecoder().decode(BusinessProfile.self, from: Data(old.utf8))
        #expect(profile.country == .canada && profile.region == "QC")
        #expect(profile.taxes == [TaxRate(.gst, rate: 50_000, number: "123456789 RT0001"),
                                  TaxRate(.qst, rate: 99_750, number: "1234567890 TQ0001")])
    }

    @Test func totalsFromBeforeRegionsKeepTheirTPSAndTVQ() throws {
        let old = #"{"labourCents":10000,"partsCents":0,"discountCents":0,"subtotalCents":10000,"tpsRate":50000,"tvqRate":99750,"tpsCents":500,"tvqCents":998,"totalCents":11498}"#
        let totals = try JSONDecoder().decode(Totals.self, from: Data(old.utf8))
        #expect(totals.taxes == [TaxLine(kind: .gst, rate: 50_000, cents: 500), TaxLine(kind: .qst, rate: 99_750, cents: 998)])
        #expect(totals.taxableCents == 10_000)
    }

    @Test func documentsNameTaxesInTheirLanguageAndCurrency() throws {
        let library = try Library()
        var profile = BusinessProfile()
        profile.setRegion(.canada, "ON")
        profile.taxes[0].number = "123456789 RT0001"
        try library.save(profile)
        let customer = try library.save(Customer(name: "Sam"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone"))
        let repair = try library.createRepair(deviceID: device.id, complaint: "Screen")
        try library.save(LabourLine(repairId: repair.id, description: "Screen", kind: .flat, unitCents: 10_000))
        let invoice = try library.issue(.invoice, for: repair.id)
        let english = DocumentHTML(language: .english).document(invoice)
        #expect(english.contains("HST (13%)") && english.contains("HST No.:") && english.contains("$113.00"))
        let french = DocumentHTML(language: .french).document(invoice)
        #expect(french.contains("TVH (13\u{00A0}%)") && french.contains("N°\u{00A0}de TVH\u{00A0}:"))

        profile.setRegion(.unitedStates, "TX")
        try library.save(profile)
        let repair2 = try library.createRepair(deviceID: device.id, complaint: "Battery")
        try library.save(LabourLine(repairId: repair2.id, description: "Battery", kind: .flat, unitCents: 10_000))
        let us = DocumentHTML(language: .english).document(try library.issue(.invoice, for: repair2.id))
        #expect(us.contains("Sales tax (6.25%)") && us.contains("$106.25"))
        #expect(!us.contains("CA$") && !us.contains("US$"))
        // The Ontario invoice keeps its Canadian dollars.
        #expect(DocumentHTML(language: .english).document(invoice).contains("$113.00"))
    }

    @Test func newCustomersSpeakTheRegionsLanguage() {
        var profile = BusinessProfile()
        #expect(profile.defaultDocumentsLanguage == .french)
        profile.setRegion(.canada, "ON")
        #expect(profile.defaultDocumentsLanguage == .english)
    }
}
