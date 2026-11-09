import Foundation
import GRDB

/// The length of a report: a month, a calendar quarter, or a year.
public enum ReportLength: String, CaseIterable, Sendable, Identifiable {
    case month, quarter, year
    public var id: String { rawValue }
}

/// One report period, such as November 2026, Q4 2026, or 2026.
public struct ReportPeriod: Hashable, Sendable {
    public var length: ReportLength
    public var start: Date

    /// The period of this length that holds `date`.
    public init(_ length: ReportLength, containing date: Date, calendar: Calendar = .current) {
        self.length = length
        let parts = calendar.dateComponents([.year, .month], from: date)
        var first = DateComponents(year: parts.year, month: 1, day: 1)
        switch length {
        case .month: first.month = parts.month
        case .quarter: first.month = ((parts.month ?? 1) - 1) / 3 * 3 + 1
        case .year: break
        }
        start = calendar.date(from: first) ?? date
    }

    private var months: Int { length == .month ? 1 : length == .quarter ? 3 : 12 }

    public func end(_ calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: start) ?? start
    }

    /// The period before (-1) or after (+1).
    public func moved(by steps: Int, _ calendar: Calendar = .current) -> ReportPeriod {
        var period = self
        period.start = calendar.date(byAdding: .month, value: months * steps, to: start) ?? start
        return period
    }
}

/// One document in a report: an invoice (a repair's or a sale's) or a credit note, whose
/// amounts are negative.
public struct ReportRow: Hashable, Sendable, Identifiable {
    public var invoice: Invoice
    public var customer: String
    public var subtotalCents: Int
    public var taxes: [TaxLine]
    public var totalCents: Int
    /// Paid for an invoice, refunded for a credit note.
    public var isSettled: Bool
    /// An invoice a credit note cancels.
    public var isCredited: Bool
    public var id: UUID { invoice.id }

    public func taxCents(_ kind: TaxKind) -> Int { taxes.filter { $0.kind == kind }.reduce(0) { $0 + $1.cents } }
}

/// What was invoiced in a period and the tax collected, for filing returns. Credit notes
/// count in the period they were issued, as negative amounts.
public struct SalesReport: Hashable, Sendable {
    public var period: ReportPeriod
    public var rows: [ReportRow]

    /// The tax kinds that appear, in the order taxes print.
    public var taxKinds: [TaxKind] { TaxKind.allCases.filter { kind in rows.contains { $0.taxCents(kind) != 0 } } }
    public var salesCents: Int { rows.reduce(0) { $0 + $1.subtotalCents } }
    public func taxCents(_ kind: TaxKind) -> Int { rows.reduce(0) { $0 + $1.taxCents(kind) } }
    public var totalCents: Int { rows.reduce(0) { $0 + $1.totalCents } }
    /// Invoices paid less credit notes refunded.
    public var collectedCents: Int { rows.filter(\.isSettled).reduce(0) { $0 + $1.totalCents } }
    /// Invoices not paid and not credited.
    public var owedCents: Int {
        rows.filter { $0.invoice.kind == .invoice && !$0.isSettled && !$0.isCredited }.reduce(0) { $0 + $1.totalCents }
    }

    /// One line per document; each tax in its own column; amounts like 1234.56.
    public func csv() -> String {
        let kinds = taxKinds
        func amount(_ cents: Int) -> String {
            String(format: "%@%d.%02d", cents < 0 ? "-" : "", abs(cents) / 100, abs(cents) % 100)
        }
        func field(_ text: String) -> String {
            text.contains(where: { ",\"\n".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var lines = [(["Date", "Number", "Kind", "Customer", "Subtotal"] + kinds.map { $0.name(.english) } + ["Total", "Settled"])
            .joined(separator: ",")]
        for row in rows {
            lines.append(([row.invoice.issuedAt.formatted(day), row.invoice.numberText ?? "", row.invoice.kind.rawValue,
                           field(row.customer), amount(row.subtotalCents)]
                          + kinds.map { amount(row.taxCents($0)) }
                          + [amount(row.totalCents), row.isSettled ? "yes" : "no"]).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension Library {
    /// Invoices and credit notes issued in the period, oldest first.
    public func salesReport(_ period: ReportPeriod) throws -> SalesReport {
        let documents = try db.read { db in
            try Invoice.filter(["invoice", "creditNote"].contains(Column("kind")) && Column("deletedAt") == nil)
                .filter(Column("issuedAt") >= period.start && Column("issuedAt") < period.end())
                .order(Column("issuedAt"), Column("rowid"))
                .fetchAll(db)
        }
        let credited = try db.read { db in
            Set(try String.fetchAll(db, sql: "SELECT creditsInvoiceId FROM invoice WHERE creditsInvoiceId IS NOT NULL AND deletedAt IS NULL"))
        }
        let rows = documents.compactMap { invoice -> ReportRow? in
            guard let content = invoice.document else { return nil }
            return ReportRow(invoice: invoice, customer: content.customer.name, subtotalCents: content.totals.subtotalCents,
                             taxes: content.totals.taxes, totalCents: content.totals.totalCents,
                             isSettled: invoice.paidAt != nil, isCredited: credited.contains(invoice.id.stored))
        }
        return SalesReport(period: period, rows: rows)
    }
}
