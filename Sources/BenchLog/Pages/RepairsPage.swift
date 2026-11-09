import BenchLogKit
import SwiftUI

/// Repairs: the list grouped by status (workflow order, oldest first) beside the selected repair.
struct RepairsPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [RepairRow] = []
    @State private var hasAny = true

    var body: some View {
        @Bindable var model = model
        HSplitView {
            list
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Repairs")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $model.repairFilter) {
                    ForEach(RepairFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Choose which repairs the list shows")
            }
            ToolbarItem {
                Button("New Repair", systemImage: "plus") { model.newRepair() }
                    .help("Open a repair for a device (⌘N)")
            }
        }
        .task(id: [model.dataVersion, model.repairFilter.hashValue]) {
            rows = model.read([]) { try $0.repairRows(statuses: model.repairFilter.statuses) }
            hasAny = !rows.isEmpty || model.read(false) { try !$0.repairRows().isEmpty }
        }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var model = model
        if let error = model.libraryError {
            ContentUnavailableView {
                Label("Unable to Open the Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label(hasAny ? model.repairFilter.emptyTitle : String(localized: "No Repairs"), systemImage: "wrench.and.screwdriver")
            } description: {
                Text(hasAny ? "Choose All to see every repair." : "Open a repair when a customer brings in a device.")
            } actions: {
                if !hasAny { Button("New Repair") { model.newRepair() }.buttonStyle(.borderedProminent) }
            }
        } else {
            List(selection: $model.selectedRepair) {
                ForEach(RepairStatus.allCases) { status in
                    let group = rows.filter { $0.repair.status == status }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { row in
                                RepairListRow(row: row)
                                    .tag(row.id)
                                    .contextMenu {
                                        Menu("Status") { StatusButtons(model: model, repairID: row.id, current: row.repair.status, shortcuts: false) }
                                        Divider()
                                        Button("Open Customer") { model.open(.customer(row.customer.id)) }
                                        Button("Open Device") { model.open(.device(row.device.id)) }
                                    }
                            }
                        } header: {
                            Text("\(status.title) (\(group.count))")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedRepair {
            RepairDetail(repairID: id)
                .id(id)
        } else {
            ContentUnavailableView("No Repair Selected", systemImage: "wrench.and.screwdriver",
                                   description: Text("Select a repair to see its details and timeline."))
        }
    }
}

/// One repair in the list: ticket, customer, device, complaint, days on the bench, and status.
struct RepairListRow: View {
    let row: RepairRow

    var body: some View {
        let days = row.repair.benchDays()
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(row.repair.ticket.text)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(row.customer.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .help(row.customer.name)
                }
                Text(row.device.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.repair.complaint)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(row.repair.complaint)
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: Space.xs) {
                StatusPill(status: row.repair.status)
                if !row.repair.status.isClosed {
                    Text("\(days) d")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(days > 14 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .help("On the bench for \(days) days")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Repair \(row.repair.ticket.text), \(row.customer.name), \(row.device.title), \(row.repair.status.title), \(days) days"))
    }
}
