import BenchLogKit
import SwiftUI

/// The parts on a repair: each with its quantity, status, and price; Add Part… to pick from
/// stock (parts that fit the device first) or type a new one; and an offer to set the repair
/// to Waiting on Parts while one is Needed or Ordered.
struct RepairParts: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    let device: Device

    @State private var uses: [PartUse] = []
    @State private var adding = false

    var body: some View {
        Group {
            if uses.isEmpty {
                Text("No parts yet").foregroundStyle(.secondary)
            }
            ForEach(uses) { use in
                HStack(spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(use.name).lineLimit(1).help(use.name)
                        if !use.vendor.isEmpty {
                            Text(use.vendor).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(verbatim: "× \(use.quantity)").monospacedDigit()
                    Stepper("Quantity", value: Binding(get: { use.quantity }, set: { quantity in
                        var changed = use
                        changed.quantity = quantity
                        model.update(changed)
                    }), in: 1...99)
                    .labelsHidden()
                    .help("Change how many this repair needs")
                    Text(Money.text(use.priceCents.map { $0 * use.quantity }))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 72, alignment: .trailing)
                    PartUseStatusMenu(use: use)
                        .frame(minWidth: 112, alignment: .leading)
                }
                .contextMenu {
                    if let partID = use.partId {
                        Button("Show in Parts") {
                            model.partsTab = .inventory
                            model.selectedPart = partID
                            model.sidebar = .parts
                        }
                    }
                    Button("Remove from Repair", role: .destructive) { model.removeUse(use.id) }
                }
            }
            if uses.contains(where: { $0.status.isMissing }), repair.status != .waitingOnParts, !repair.status.isClosed {
                HStack {
                    Label("A part is not here yet.", systemImage: "shippingbox")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Set to Waiting on Parts") { model.setStatus(.waitingOnParts, for: repair.id) }
                        .controlSize(.small)
                }
            }
            Button("Add Part…") { adding = true }
                .controlSize(.small)
                .help("Add a part from stock, or type one to order")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    AddPartPopover(repair: repair, device: device) { adding = false }
                        .environment(model)
                }
        }
        .task(id: model.dataVersion) {
            uses = model.read([]) { try $0.partUses(on: repair.id) }
        }
    }
}

/// Search the inventory; parts that fit the device come first. Return adds the top match,
/// or the typed name as a new part to order.
private struct AddPartPopover: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    let device: Device
    let done: () -> Void

    @State private var search = ""
    @FocusState private var focused: Bool

    var body: some View {
        let found = model.read((fitting: [Part](), others: [Part]())) { try $0.parts(for: device, matching: search) }
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Part", text: $search, prompt: Text("Search parts or type a new one"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    if let top = found.fitting.first ?? found.others.first {
                        add(top)
                    } else {
                        addTyped()
                    }
                }
            List {
                if !found.fitting.isEmpty {
                    Section("Fits \(device.brand) \(device.model)") {
                        ForEach(found.fitting) { row($0) }
                    }
                }
                if !found.others.isEmpty {
                    Section(found.fitting.isEmpty ? "Inventory" : "Other Parts") {
                        ForEach(found.others) { row($0) }
                    }
                }
            }
            .frame(height: 220)
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add “\(search.trimmingCharacters(in: .whitespaces))” to Order") { addTyped() }
                    .help("A part that is not in your inventory; it starts as Needed")
            }
        }
        .padding(Space.md)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func row(_ part: Part) -> some View {
        Button {
            add(part)
        } label: {
            HStack {
                Text(part.name).lineLimit(1)
                Spacer()
                StockCount(part: part)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add(_ part: Part) {
        model.usePart(part.id, on: repair.id)
        done()
    }

    private func addTyped() {
        model.useFreePart(search, on: repair.id)
        done()
    }
}
