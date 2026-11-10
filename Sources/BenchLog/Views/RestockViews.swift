import BenchLogKit
import SwiftUI

extension RestockStatus {
    var title: String {
        switch self {
        case .draft: String(localized: "Draft")
        case .ordered: String(localized: "Ordered")
        case .received: String(localized: "Received")
        }
    }
}

/// The Restock tab: one order per vendor for the shelf. Drafts can change; ordered ones
/// wait to be received; the last received ones stay below.
struct RestockList: View {
    @Environment(AppModel.self) private var model
    @State private var orders: [RestockOrder] = []

    var body: some View {
        Group {
            if orders.isEmpty {
                ContentUnavailableView {
                    Label("No Restock Orders", systemImage: "shippingbox.and.arrow.backward")
                } description: {
                    Text("Order stock for the shelf from a part’s page, or add every low part at once.")
                } actions: {
                    Button("Add Low Parts") { model.addLowParts() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.lowStockCount == 0)
                }
            } else {
                Form {
                    ForEach(orders) { RestockSection(order: $0) }
                }
                .formStyle(.grouped)
            }
        }
        .task(id: model.dataVersion) { orders = model.read([]) { try $0.restockOrders() } }
    }
}

private struct RestockSection: View {
    @Environment(AppModel.self) private var model
    let order: RestockOrder

    private var isDraft: Bool { order.restock.status == .draft }

    var body: some View {
        Section {
            ForEach(order.lines) { RestockLineRow(row: $0, editable: isDraft) }
            HStack(spacing: Space.sm) {
                Text("Units: \(order.units)").foregroundStyle(.secondary)
                Spacer()
                Text("Total at cost").foregroundStyle(.secondary)
                Text(Money.text(order.totalCents)).monospacedDigit().fontWeight(.semibold)
            }
            if order.restock.status != .received {
                HStack(spacing: Space.sm) {
                    Button(isDraft ? "Discard" : "Cancel Order", role: .destructive) { model.discardRestock(order.id) }
                        .help(isDraft ? "Throw away this draft" : "Cancel this order; nothing goes into stock")
                    Spacer()
                    if isDraft {
                        Button("Mark Ordered") { model.markOrdered(order.id) }
                            .disabled(order.lines.isEmpty)
                            .help("Record that this order was sent to the vendor")
                    } else {
                        Button("Receive") { model.receive(order.id) }
                            .buttonStyle(.borderedProminent)
                            .help("Put every line into stock and update each part’s cost")
                    }
                }
            }
        } header: {
            HStack {
                Text(order.restock.vendor.isEmpty ? String(localized: "No vendor") : order.restock.vendor)
                Spacer()
                RestockStatusLabel(restock: order.restock)
            }
        }
    }
}

private struct RestockStatusLabel: View {
    let restock: Restock

    var body: some View {
        switch restock.status {
        case .draft:
            Label("Draft", systemImage: "pencil").foregroundStyle(.secondary)
        case .ordered:
            Label("Ordered \(restock.orderedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")", systemImage: "shippingbox")
                .foregroundStyle(.orange)
        case .received:
            Label("Received \(restock.receivedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

/// One part on an order: its quantity and cost, editable while a draft.
private struct RestockLineRow: View {
    @Environment(AppModel.self) private var model
    let row: RestockOrder.Line
    let editable: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.part.name).lineLimit(1).help(row.part.name)
                Text("\(row.part.quantity) in stock").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.sm)
            if editable {
                Text(verbatim: "× \(row.line.quantity)").monospacedDigit()
                Stepper("Quantity", value: Binding(get: { row.line.quantity },
                                                   set: { model.updateRestockLine(row.id, quantity: $0, costCents: row.line.costCents) }),
                        in: 0...9999)
                    .labelsHidden()
                    .help("Change how many to order; zero removes the part")
                TextField("Cost", value: Binding(get: { Money.decimal(row.line.costCents) },
                                                 set: { model.updateRestockLine(row.id, quantity: row.line.quantity, costCents: Money.cents($0)) }),
                          format: Money.format)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                    .help("What the vendor charges for one")
            } else {
                Text(verbatim: "× \(row.line.quantity)").monospacedDigit().foregroundStyle(.secondary)
                Text(Money.text(row.line.costCents ?? 0)).monospacedDigit().foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
            }
            Text(Money.text(row.line.quantity * (row.line.costCents ?? 0)))
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)
        }
    }
}
