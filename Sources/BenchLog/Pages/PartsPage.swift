import BenchLogKit
import SwiftUI

/// Parts: the inventory and what is low, beside the selected part; and, across open
/// repairs, the parts to order and the parts on their way.
struct PartsPage: View {
    @Environment(AppModel.self) private var model
    @State private var parts: [Part] = []
    @State private var uses: [PartUseRow] = []
    @State private var value = InventoryValue()

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.partsTab {
            case .inventory, .low:
                HSplitView {
                    inventory
                        .frame(minWidth: 300, idealWidth: 400, maxWidth: 520, maxHeight: .infinity)
                        .layoutPriority(1)
                    detail
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .searchable(text: $model.partSearch, prompt: Text("Name, SKU, vendor, or location"))
            case .toOrder, .incoming:
                orders
            case .restock:
                RestockList()
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
            if model.partsTab == .inventory || model.partsTab == .low {
                ToolbarItem {
                    Picker("Kind", systemImage: "line.3.horizontal.decrease", selection: $model.partKind) {
                        Text("All Kinds").tag(PartKind?.none)
                        Divider()
                        ForEach(PartKind.allCases) { Label($0.plural, systemImage: $0.symbol).tag(PartKind?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    .help("Show one kind of part")
                }
            }
            if model.partsTab == .restock {
                ToolbarItem {
                    Button("Add Low Parts", systemImage: "cart.badge.plus") { model.addLowParts() }
                        .disabled(model.lowStockCount == 0)
                        .help("Put every low part on its vendor’s draft, enough to reach twice its threshold")
                }
            }
            ToolbarItem {
                Button("New Part", systemImage: "plus") { model.sheet = .newPart }
                    .help("Add a part to the inventory")
            }
        }
        .task(id: "\(model.dataVersion) \(model.partsTab.rawValue) \(model.partSearch) \(model.partKind?.rawValue ?? "")") {
            switch model.partsTab {
            case .inventory:
                parts = model.read([]) { try $0.parts(matching: model.partSearch, kind: model.partKind) }
                value = model.read(InventoryValue()) { try $0.inventoryValue() }
            case .low: parts = model.read([]) { try $0.parts(matching: model.partSearch, lowOnly: true, kind: model.partKind) }
            case .toOrder: uses = model.read([]) { try $0.partUseRows(.needed) }
            case .incoming: uses = model.read([]) { try $0.partUseRows(.ordered) }
            case .restock: break
            }
        }
    }

    @ViewBuilder
    private var inventory: some View {
        @Bindable var model = model
        if parts.isEmpty {
            if !model.partSearch.isEmpty {
                ContentUnavailableView.search(text: model.partSearch)
            } else if let kind = model.partKind {
                ContentUnavailableView {
                    Label("Nothing of This Kind", systemImage: kind.symbol)
                } actions: {
                    Button("Show All Kinds") { model.partKind = nil }
                }
            } else if model.partsTab == .low {
                ContentUnavailableView("Nothing Is Low", systemImage: "checkmark.circle",
                                       description: Text("Parts at or below their low-stock threshold show here."))
            } else {
                ContentUnavailableView {
                    Label("No Parts", systemImage: "shippingbox")
                } description: {
                    Text("Add the parts you keep on hand, or start from the usual parts of a console.")
                } actions: {
                    HStack(spacing: Space.sm) {
                        Button("New Part") { model.sheet = .newPart }.buttonStyle(.borderedProminent)
                        Menu("Add Starter Parts") { StarterPartsButtons(model: model) }
                            .fixedSize()
                            .help("Add the usual parts, cables, and controllers of a console, at zero stock")
                    }
                }
            }
        } else {
            List(parts, selection: $model.selectedPart) { part in
                HStack(spacing: Space.sm) {
                    Image(systemName: part.kind.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityLabel(Text(part.kind.title))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.name).fontWeight(.medium).lineLimit(1).help(part.name)
                        Text(([part.kind.title, part.sku, part.vendor, part.location].filter { !$0.isEmpty }
                              + [Money.text(part.priceCents)].filter { _ in part.priceCents != nil }).joined(separator: " · "))
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.partsTab == .inventory, model.partSearch.isEmpty { StockValueFooter(value: value) }
            }
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

/// The consoles with starter parts, then all of them: the File menu and the empty Parts page.
struct StarterPartsButtons: View {
    let model: AppModel

    var body: some View {
        ForEach(StarterSet.allCases) { set in
            Button(set.title) { model.addStarterParts([set]) }
        }
        Divider()
        Button("All Consoles") { model.addStarterParts(StarterSet.allCases) }
    }
}

extension PartKind {
    var plural: String {
        switch self {
        case .part: String(localized: "kind.parts", defaultValue: "Parts", comment: "A kind of part, plural: components for repairs")
        case .accessory: String(localized: "Accessories")
        case .cable: String(localized: "Cables")
        case .controller: String(localized: "Controllers")
        case .supply: String(localized: "Supplies")
        }
    }
}

/// One part: what it is, its prices, its stock, and the models it fits; beside them, in a
/// wide window, the repairs it is on, its stock history, and its notes.
struct PartDetail: View {
    @Environment(AppModel.self) private var model
    let partID: UUID
    @State private var part: Part?
    @State private var fits: [PartFit] = []
    @State private var repairs: [PartRepairRow] = []
    @State private var wide = false

    /// From this width the details split into two columns.
    private nonisolated static let wideWidth: CGFloat = 880

    var body: some View {
        Group {
            if let part {
                if wide {
                    HStack(spacing: 0) {
                        Form { main(part, header: Text("Details")) }.formStyle(.grouped)
                        Form { side(part) }.formStyle(.grouped)
                    }
                } else {
                    Form {
                        main(part, header: nil)
                        side(part)
                    }
                    .formStyle(.grouped)
                }
            } else {
                ContentUnavailableView("No Part Selected", systemImage: "shippingbox")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.wideWidth } action: { wide = $0 }
        .task(id: model.dataVersion) {
            part = model.read(nil) { try $0.part(partID) }
            fits = model.read([]) { try $0.fits(of: partID) }
            repairs = model.read([]) { try $0.repairs(usingPart: partID) }
        }
    }

    @ViewBuilder
    private func main(_ part: Part, header: Text?) -> some View {
        // Beside a second column, the first section has a header so both columns start level.
        Section {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: part.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(part.kind.title))
                Text(part.name).font(.title.weight(.semibold)).textSelection(.enabled)
                Spacer()
                Button("Edit…") { model.sheet = .editPart(part.id) }
                    .help("Change this part's details")
            }
            LabeledContent("Kind", value: part.kind.title)
            if let condition = part.condition { LabeledContent("Condition", value: condition.title) }
            if !part.sku.isEmpty { LabeledContent("SKU") { Text(part.sku).monospaced().textSelection(.enabled) } }
            if !part.vendor.isEmpty { LabeledContent("Vendor", value: part.vendor) }
            if let url = URL(string: part.url), !part.url.isEmpty {
                LabeledContent("Link") { Link(url.host() ?? part.url, destination: url) }
            }
            if !part.location.isEmpty { LabeledContent("Location") { Text(part.location).textSelection(.enabled) } }
        } header: {
            if let header { header }
        }
        Section("Prices") {
            LabeledContent("Cost", value: Money.text(part.costCents))
            LabeledContent("Price", value: Money.text(part.priceCents))
            if let margin = part.marginCents {
                LabeledContent("Margin") {
                    if let price = part.priceCents, price > 0 {
                        Text("\(Money.text(margin)) (\(Double(margin) / Double(price), format: .percent.precision(.fractionLength(0))))")
                    } else {
                        Text(Money.text(margin))
                    }
                }
                .monospacedDigit()
            }
            if part.quantity > 0, let cost = part.costCents {
                LabeledContent("Stock value", value: Money.text(cost * part.quantity))
            }
        }
        StockSection(part: part)
        Section("Fits") {
            if fits.isEmpty { Text("Fits any model").foregroundStyle(.secondary) }
            ForEach(fits, id: \.self) { fit in
                Label(fit.title, systemImage: fit.category.symbol)
            }
        }
    }

    @ViewBuilder
    private func side(_ part: Part) -> some View {
        Section("On Repairs") {
            if repairs.isEmpty { Text("Not on a repair yet").foregroundStyle(.secondary) }
            ForEach(repairs.prefix(8)) { row in
                Button {
                    model.open(.repair(row.use.repairId))
                } label: {
                    HStack(spacing: Space.sm) {
                        Text(TicketNumber(row.ticketNumber).text).monospacedDigit()
                        Text(verbatim: "\(row.customerName) · \(row.deviceTitle)").lineLimit(1).foregroundStyle(.secondary)
                        if row.use.quantity > 1 { Text(verbatim: "× \(row.use.quantity)").foregroundStyle(.secondary) }
                        Spacer()
                        Label(row.use.status.title, systemImage: row.use.status.symbol)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        StatusPill(status: row.repairStatus)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open repair \(TicketNumber(row.ticketNumber).text)")
            }
        }
        StockHistorySection(partID: part.id)
        Section("Notes") {
            if part.notes.isEmpty {
                Text("No notes").foregroundStyle(.secondary)
            } else {
                Text(part.notes).textSelection(.enabled)
            }
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

/// Under the inventory: what the parts on the shelf are worth at cost and at price.
private struct StockValueFooter: View {
    let value: InventoryValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Stock value")
                Spacer()
                Text(Money.text(value.partsCostCents)).monospacedDigit().fontWeight(.semibold)
            }
            HStack {
                Text("Units: \(value.units) · at price \(Money.text(value.partsPriceCents))")
                if value.partsWithoutCost > 0 {
                    Spacer()
                    Label("Without cost: \(value.partsWithoutCost)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help("Parts in stock with no cost count as zero; add their cost in Edit Part")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
