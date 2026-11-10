import BenchLogKit
import SwiftUI

/// Dashboard: what is going on today. The open repairs, the ones that need attention,
/// the parts to deal with, and the month's sales. Everything on it opens the page behind it.
struct DashboardPage: View {
    @Environment(AppModel.self) private var model
    @State private var dashboard: Dashboard?

    /// The Needs Attention list shows this many repairs, then says how many more there are.
    private let attentionLimit = 12

    var body: some View {
        Group {
            if let error = model.libraryError {
                ContentUnavailableView {
                    Label("Unable to Open the Library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if let dashboard {
                if dashboard.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on the Bench", systemImage: SidebarItem.dashboard.symbol)
                    } description: {
                        Text("Open a repair when a customer brings in a device.")
                    } actions: {
                        Button("New Repair") { model.newRepair() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    content(dashboard)
                }
            } else {
                // Not read yet. An empty Group would drop the task that reads it.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Dashboard")
        .navigationSubtitle(Date.now.formatted(date: .complete, time: .omitted))
        .toolbar {
            ToolbarItem {
                Button("New Repair", systemImage: "plus") { model.newRepair() }
                    .help("Open a repair for a device (⌘N)")
            }
        }
        .task(id: model.dataVersion) { dashboard = model.read(nil) { try $0.dashboard() } }
    }

    private func content(_ dashboard: Dashboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.lg) {
                    tile(String(localized: "Open Repairs"), dashboard.openCount, symbol: "wrench.and.screwdriver",
                         help: "Show the open repairs") { model.show(.repairs, repairs: .open) }
                    tile(RepairStatus.ready.title, dashboard.count(.ready), symbol: RepairStatus.ready.symbol,
                         help: "Show the repairs ready for pickup") { model.show(.repairs, repairs: .ready) }
                    tile(String(localized: "To Collect"), dashboard.toCollectCount, symbol: "dollarsign.circle", color: .orange,
                         help: "Show the repairs ready for pickup; To Collect marks the ones with no paid invoice") {
                        model.show(.repairs, repairs: .ready)
                    }
                    tile(String(localized: "Overdue"), dashboard.overdueCount, symbol: "calendar.badge.exclamationmark", color: .red,
                         help: "Open repairs whose promised date has passed. Show the open repairs") {
                        model.show(.repairs, repairs: .open)
                    }
                }
                .gridProbe("tiles", area: "dashboard")
                HStack(alignment: .top, spacing: Space.lg) {
                    attention(dashboard)
                        .gridProbe("attention", area: "dashboard")
                    VStack(spacing: Space.lg) {
                        statuses(dashboard)
                        parts(dashboard)
                        month(dashboard.month)
                    }
                }
            }
            .padding(Space.margin)
            .gridArea("dashboard")
        }
    }

    // MARK: Cards

    /// One big number; a click opens the list behind it.
    private func tile(_ title: String, _ value: Int, symbol: String, color: Color? = nil,
                      help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value, format: .number)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(value > 0 ? color ?? .primary : .primary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value, format: .number))
        .accessibilityAddTraits(.isButton)
    }

    private func attention(_ dashboard: Dashboard) -> some View {
        Card {
            header("Needs Attention")
            if dashboard.attention.isEmpty {
                Label("Nothing needs attention", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(dashboard.attention.prefix(attentionLimit)) { item in
                Divider()
                Button {
                    model.open(.repair(item.id))
                } label: {
                    HStack(spacing: Space.sm) {
                        Text(item.row.repair.ticket.text)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.row.customer.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(item.row.device.title)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: Space.sm)
                        AttentionLabel(reason: item.reason)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open repair \(item.row.repair.ticket.text)")
            }
            if dashboard.attention.count > attentionLimit {
                Divider()
                Button("\(dashboard.attention.count - attentionLimit) more in Repairs") { model.show(.repairs, repairs: .open) }
                    .buttonStyle(.link)
                    .help("Show the open repairs")
            }
        }
    }

    private func statuses(_ dashboard: Dashboard) -> some View {
        Card {
            header("By Status") {
                Button("Show Repairs") { model.show(.repairs, repairs: .open) }
                    .help("Show the open repairs")
            }
            ForEach(RepairStatus.allCases.filter { !$0.isClosed }) { status in
                Divider()
                HStack {
                    StatusPill(status: status)
                    Spacer()
                    count(dashboard.count(status))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func parts(_ dashboard: Dashboard) -> some View {
        Card {
            header("Parts")
            partsRow(.low, symbol: "exclamationmark.triangle", dashboard.lowStock)
            partsRow(.toOrder, symbol: "cart", dashboard.toOrder)
            partsRow(.incoming, symbol: "shippingbox", dashboard.incoming)
        }
    }

    @ViewBuilder
    private func partsRow(_ tab: PartsTab, symbol: String, _ value: Int) -> some View {
        Divider()
        Button {
            model.show(.parts, parts: tab)
        } label: {
            HStack {
                Label(tab.title, systemImage: symbol)
                Spacer()
                count(value, color: .orange)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open \(tab.title) in Parts")
    }

    private func month(_ report: SalesReport) -> some View {
        Card {
            header(report.period.title) {
                Button("Show Reports") { model.show(.reports) }
                    .help("Open this month in Reports")
            }
            Divider()
            amount("Sales before taxes", report.salesCents)
            Divider()
            amount("Collected", report.collectedCents)
            Divider()
            amount("Owed", report.owedCents, color: report.owedCents > 0 ? .orange : nil)
        }
    }

    // MARK: Pieces

    private func header(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func header(_ title: String, @ViewBuilder link: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            link().buttonStyle(.link)
        }
    }

    private func amount(_ title: LocalizedStringKey, _ cents: Int, color: Color? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.text(cents))
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// A count at the end of a row: faded at zero, colored when it asks for something.
    private func count(_ value: Int, color: Color? = nil) -> some View {
        Text(value, format: .number)
            .monospacedDigit()
            .fontWeight(value > 0 ? .medium : .regular)
            .foregroundStyle(value == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color ?? .primary))
    }
}

/// Why a repair needs attention: a symbol, words, and a color, never color alone.
private struct AttentionLabel: View {
    let reason: AttentionReason

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch reason {
        case .overdue(let days): (String(localized: "Overdue \(days) d"), "calendar.badge.exclamationmark", .red)
        case .promisedToday: (String(localized: "Promised Today"), "calendar", .orange)
        case .toCollect: (String(localized: "To Collect"), "dollarsign.circle", .orange)
        case .awaitingApproval: (RepairStatus.awaitingApproval.title, RepairStatus.awaitingApproval.symbol, .orange)
        case .longOnBench(let days): (String(localized: "\(days) d on the bench"), "clock", .secondary)
        }
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}
