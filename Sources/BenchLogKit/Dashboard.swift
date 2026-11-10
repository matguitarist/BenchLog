import Foundation
import GRDB

/// Why a repair is on the Dashboard's Needs Attention list. A repair has one reason, the most pressing.
public enum AttentionReason: Hashable, Sendable {
    /// The promised date passed this many days ago and the repair is not Ready.
    case overdue(days: Int)
    /// Promised for today and not Ready.
    case promisedToday
    /// Ready, with no paid invoice.
    case toCollect
    /// The estimate waits on the customer.
    case awaitingApproval
    /// Not Ready after more than `Dashboard.longBenchDays` days.
    case longOnBench(days: Int)

    /// The order of the list: late first.
    var rank: Int {
        switch self {
        case .overdue: 0
        case .promisedToday: 1
        case .toCollect: 2
        case .awaitingApproval: 3
        case .longOnBench: 4
        }
    }

    var days: Int {
        switch self {
        case .overdue(let days), .longOnBench(let days): days
        default: 0
        }
    }
}

/// One open repair that needs something, and why.
public struct AttentionRow: Hashable, Sendable, Identifiable {
    public var row: RepairRow
    public var reason: AttentionReason
    public var id: UUID { row.id }
}

/// What is going on in the shop today: the open repairs by status, the ones that need
/// attention, the parts to deal with, and the month's sales.
public struct Dashboard: Hashable, Sendable {
    /// A repair on the bench longer than this needs attention.
    public static let longBenchDays = 14

    /// Open repairs per status; a status with none is missing.
    public var statusCounts: [RepairStatus: Int]
    /// Late first, then promised today, to collect, awaiting approval, and long on the bench.
    public var attention: [AttentionRow]
    public var lowStock: Int
    /// Parts Needed across open repairs.
    public var toOrder: Int
    /// Parts Ordered across open repairs.
    public var incoming: Int
    /// The current month's invoices and credit notes.
    public var month: SalesReport

    public func count(_ status: RepairStatus) -> Int { statusCounts[status] ?? 0 }
    public var openCount: Int { statusCounts.values.reduce(0, +) }
    public var overdueCount: Int { attention.filter { $0.reason.rank == 0 }.count }
    public var toCollectCount: Int { attention.filter { $0.reason == .toCollect }.count }

    /// Nothing open, nothing to order, and nothing invoiced this month.
    public var isEmpty: Bool {
        openCount == 0 && lowStock == 0 && toOrder == 0 && incoming == 0 && month.rows.isEmpty
    }
}

extension Library {
    public func dashboard(now: Date = .now, calendar: Calendar = .current) throws -> Dashboard {
        let open = try repairRows(statuses: Set(RepairStatus.allCases.filter { !$0.isClosed }))
        let unpaid = try toCollectRepairIDs()
        let today = calendar.startOfDay(for: now)
        var attention: [AttentionRow] = []
        for row in open {
            let repair = row.repair
            let late = repair.promisedAt.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0 }
            let bench = repair.benchDays(now: now, calendar: calendar)
            let reason: AttentionReason? = if repair.status == .ready {
                unpaid.contains(repair.id) ? .toCollect : nil
            } else if let late, late > 0 {
                .overdue(days: late)
            } else if late == 0 {
                .promisedToday
            } else if repair.status == .awaitingApproval {
                .awaitingApproval
            } else if bench > Dashboard.longBenchDays {
                .longOnBench(days: bench)
            } else {
                nil
            }
            if let reason { attention.append(AttentionRow(row: row, reason: reason)) }
        }
        // Stable: within a reason, the most days first, then the oldest repair.
        attention = attention.enumerated().sorted {
            ($0.element.reason.rank, -$0.element.reason.days, $0.offset) < ($1.element.reason.rank, -$1.element.reason.days, $1.offset)
        }.map(\.element)
        return Dashboard(statusCounts: Dictionary(grouping: open, by: \.repair.status).mapValues(\.count),
                         attention: attention,
                         lowStock: try lowStockCount(),
                         toOrder: try partUseRows(.needed).count,
                         incoming: try partUseRows(.ordered).count,
                         month: try salesReport(ReportPeriod(.month, containing: now, calendar: calendar)))
    }
}
