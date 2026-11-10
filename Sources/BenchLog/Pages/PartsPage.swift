import BenchLogKit
import SwiftUI

/// Parts: the inventory and what is low, beside the selected part; and, across open
/// repairs, the parts to order and the parts on their way.
struct PartsPage: View {
    @Environment(AppModel.self) private var model
    @State private var parts: [Part] = []
    @State private var uses: [PartUseRow] = []

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.partsTab {
            case .inventory, .low:
                HSplitView {
                    inventory
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520, maxHeight: .infinity)
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
                .searchable(text: $model.partSearch, prompt: Text("Name, SKU, or vendor"))
            case .toOrder, .incoming:
                orders
            }
        }
        .navigationTitle("Parts")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $model.partsTab) {
                    ForEach(PartsTab.allCases) { tab in
                        Text(tab == .low && model.lowStockCount > 0 ? "\(tab.title) (\(model.lowStockCount))" : tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose which parts the page shows")
            }
            ToolbarItem {
                Button("New Part", systemImage: "plus") { model.sheet = .newPart }
                    .help("Add a part to the inventory")
            }
        }
        .task(id: "\(model.dataVersion) \(model.partsTab.rawValue) \(model.partSearch)") {
            switch model.partsTab {
            case .inventory: parts = model.read([]) { try $0.parts(matching: model.partSearch) }
            case .low: parts = model.read([]) { try $0.parts(matching: model.partSearch, lowOnly: true) }
            case .toOrder: uses = model.read([]) { try $0.partUseRows(.needed) }
            case .incoming: uses = model.read([]) { try $0.partUseRows(.ordered) }
            }
        }
    }

    @ViewBuilder
    private var inventory: some View {
        @Bindable var model = model
        if parts.isEmpty {
            if !model.partSearch.isEmpty {
                ContentUnavailableView.search(text: model.partSearch)
            } else if model.partsTab == .low {
                ContentUnavailableView("Nothing Is Low", systemImage: "checkmark.circle",
                                       description: Text("Parts at or below their low-stock threshold show here."))
            } else {
                ContentUnavailableView {
                    Label("No Parts", systemImage: "shippingbox")
                } description: {
                    Text("Add the parts you keep on hand.")
                } actions: {
                    Button("New Part") { model.sheet = .newPart }.buttonStyle(.borderedProminent)
                }
            }
        } else {
            List(parts, selection: $model.selectedPart) { part in
                HStack(spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.name).fontWeight(.medium).lineLimit(1).help(part.name)
                        Text([part.sku, part.vendor].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.sm)
                    StockCount(part: part)
                }
                .padding(.vertical, 2)
                .tag(part.id)
                .contextMenu { Button("Move to Trash", role: .destructive) { model.moveToTrash(.part(part.id)) } }
            }
            .onDeleteCommand { model.trashFocused() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedPart {
            PartDetail(partID: id).id(id)
        } else {
            ContentUnavailableView("No Part Selected", systemImage: "shippingbox",
                                   description: Text("Select a part to see its stock and the models it fits."))
        }
    }

    @ViewBuilder
    private var orders: some View {
        if uses.isEmpty {
            ContentUnavailableView(model.partsTab == .toOrder ? "Nothing to Order" : "Nothing on the Way",
                                   systemImage: "shippingbox",
                                   description: Text(model.partsTab == .toOrder
                                                     ? "Parts marked Needed on open repairs show here."
                                                     : "Parts marked Ordered on open repairs show here."))
        } else {
            List(uses) { row in
                HStack(spacing: Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.sm) {
                            Text(row.use.name).fontWeight(.medium)
                            if row.use.quantity > 1 { Text(verbatim: "× \(row.use.quantity)").foregroundStyle(.secondary) }
                        }
                        Text("\(TicketNumber(row.ticketNumber).text) · \(row.customerName) · \(row.deviceTitle)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !row.use.vendor.isEmpty { Text(row.use.vendor).foregroundStyle(.secondary) }
                    PartUseStatusMenu(use: row.use)
                    Button("Open Repair", systemImage: "arrow.forward.circle") { model.open(.repair(row.use.repairId)) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open repair \(TicketNumber(row.ticketNumber).text)")
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// "4 in stock", orange with a warning when the part is low.
struct StockCount: View {
    let part: Part

    var body: some View {
        Label("\(part.quantity) in stock", systemImage: part.isLow ? "exclamationmark.triangle.fill" : "shippingbox")
            .labelStyle(.titleAndIcon)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(part.isLow ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .help(part.isLow ? String(localized: "At or below the low-stock threshold (\(part.lowStockThreshold))") : "")
    }
}

/// One part: what it is, where it comes from, its stock, and the models it fits.
struct PartDetail: View {
    @Environment(AppModel.self) private var model
    let partID: UUID
    @State private var part: Part?
    @State private var fits: [PartFit] = []

    var body: some View {
        Group {
            if let part {
                Form {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text(part.name).font(.title.weight(.semibold)).textSelection(.enabled)
                            Spacer()
                            Button("Edit…") { model.sheet = .editPart(part.id) }
                                .help("Change this part's details")
                        }
                        if !part.sku.isEmpty { LabeledContent("SKU") { Text(part.sku).monospaced().textSelection(.enabled) } }
                        if !part.vendor.isEmpty { LabeledContent("Vendor", value: part.vendor) }
                        if let url = URL(string: part.url), !part.url.isEmpty {
                            LabeledContent("Link") { Link(url.host() ?? part.url, destination: url) }
                        }
                        LabeledContent("Cost", value: Money.text(part.costCents))
                        LabeledContent("Price", value: Money.text(part.priceCents))
                    }
                    StockSection(part: part)
                    Section("Fits") {
                        if fits.isEmpty { Text("Fits any model").foregroundStyle(.secondary) }
                        ForEach(fits, id: \.self) { fit in
                            Label(fit.title, systemImage: fit.category.symbol)
                        }
                    }
                    StockHistorySection(partID: part.id)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Part Selected", systemImage: "shippingbox")
            }
        }
        .task(id: model.dataVersion) {
            part = model.read(nil) { try $0.part(partID) }
            fits = model.read([]) { try $0.fits(of: partID) }
        }
    }
}

/// A part's status on a repair as a menu.
struct PartUseStatusMenu: View {
    @Environment(AppModel.self) private var model
    let use: PartUse

    var body: some View {
        Menu {
            ForEach(PartUseStatus.allCases) { status in
                Toggle(isOn: Binding(get: { use.status == status }, set: { if $0 { model.setStatus(status, ofUse: use.id) } })) {
                    Label(status.title, systemImage: status.symbol)
                }
            }
        } label: {
            Label(use.status.title, systemImage: use.status.symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(use.status.color)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 2)
                .background(use.status.color.opacity(0.14), in: Capsule())
                .fixedSize()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Change where this part is")
        .accessibilityLabel(Text("Part status: \(use.status.title)"))
    }
}
