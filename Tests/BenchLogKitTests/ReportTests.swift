import Foundation
import Testing
@testable import BenchLogKit

/// S-042 Sales and tax report.
@Suite struct ReportTests {
    let library: Library
    let repair: Repair
    let november = DateComponents(calendar: .current, year: 2026, month: 11, day: 9).date!

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "Tremblay, Léa"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran")
        try library.save(LabourLine(repairId: repair.id, description: "Pose", kind: .flat, unitCents: 10_000))
    }

    @Test func periodsAreCalendarMonthsQuartersAndYears() {
        let calendar = Calendar.current
        let quarter = ReportPeriod(.quarter, containing: november)
        #expect(calendar.dateComponents([.year, .month, .day], from: quarter.start) == DateComponents(year: 2026, month: 10, day: 1))
        #expect(calendar.component(.month, from: quarter.end()) == 1)
        #expect(calendar.component(.month, from: ReportPeriod(.month, containing: november).moved(by: -1).start) == 10)
        #expect(calendar.component(.year, from: ReportPeriod(.year, containing: november).moved(by: 1).start) == 2027)
    }

    @Test func creditNotesSubtractAndOnlyThePeriodCounts() throws {
        let paid = try library.issue(.invoice, for: repair.id, now: november)
        try library.setPaid(paid.id, method: .debit, now: november)
        let wrong = try library.issue(.invoice, for: repair.id, now: november.addingTimeInterval(3_600))
        try library.issueCreditNote(for: wrong.id, now: november.addingTimeInterval(7_200))
        _ = try library.issue(.invoice, for: repair.id, now: november.addingTimeInterval(10_800))   // unpaid
        _ = try library.issue(.invoice, for: repair.id, now: november.addingTimeInterval(40 * 86_400)) // December
        _ = try library.issue(.estimate, for: repair.id, now: november)

        let report = try library.salesReport(ReportPeriod(.month, containing: november))
        #expect(report.rows.map { $0.invoice.numberText } == ["F-0001", "F-0002", "NC-0001", "F-0003"])
        #expect(report.salesCents == 20_000)                       // 3 invoices − 1 credit
        #expect(report.taxKinds == [.gst, .qst])
        #expect(report.taxCents(.gst) == 1_000 && report.taxCents(.qst) == 1_996)
        #expect(report.totalCents == 22_996)
        #expect(report.collectedCents == 11_498)                   // F-0001
        #expect(report.owedCents == 11_498)                        // F-0003; F-0002 is credited

        let csv = report.csv().split(separator: "\n")
        #expect(csv.first == "Date,Number,Kind,Customer,Subtotal,GST,QST,Total,Settled")
        #expect(csv.contains { $0.hasPrefix("2026-11-09,NC-0001,creditNote,\"Tremblay, Léa\",-100.00,-5.00,-9.98,-114.98,no") })
    }
}
