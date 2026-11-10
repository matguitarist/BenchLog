import BenchLogKit
import SwiftUI

extension StockReason {
    var title: String {
        switch self {
        case .opening: String(localized: "Opening stock")
        case .installed: String(localized: "Installed")
        case .returned: String(localized: "Returned")
        case .received: String(localized: "Received")
        case .counted: String(localized: "Counted")
        case .damaged: String(localized: "Damaged")
        case .sold: String(localized: "Sold")
        case .adjusted: String(localized: "Adjusted")
        }
    }

    var symbol: String {
        switch self {
        case .opening: "flag"
        case .installed: "wrench.and.screwdriver"
        case .returned: "arrow.uturn.backward"
        case .received: "shippingbox.and.arrow.backward"
        case .counted: "number"
        case .damaged: "xmark.bin"
        case .sold: "cart"
        case .adjusted: "slider.horizontal.3"
        }
    }
}

/// A part's stock: the count with a stepper, the threshold, and Count… and Remove Damaged….
struct StockSection: View {
    @Environment(AppModel.self) private var model
    let part: Part
    @State private var counting = false
    @State private var removing = false

    var body: some View {
        Section("Stock") {
            Stepper(value: Binding(get: { part.quantity }, set: { model.adjustStock(of: part.id, by: $0 - part.quantity) }), in: 0...9999) {
                StockCount(part: part)
            }
            LabeledContent("Low-stock threshold", value: part.lowStockThreshold > 0 ? "\(part.lowStockThreshold)" : String(localized: "None"))
            HStack(spacing: Space.sm) {
                Spacer()
                Button("Remove Damaged…") { removing = true }
                    .disabled(part.quantity == 0)
                    .help("Take broken or lost units out of stock, with a note")
                    .popover(isPresented: $removing, arrowEdge: .bottom) {
                        StockChange(title: String(localized: "Remove Damaged"), label: String(localized: "Units"), start: 1,
                                    action: String(localized: "Remove")) { quantity, note in
                            model.removeDamaged(part.id, quantity: quantity, note: note)
                        }
                    }
                Button("Count…") { counting = true }
                    .help("Set the stock to what is on the shelf; the difference is recorded")
                    .popover(isPresented: $counting, arrowEdge: .bottom) {
                        StockChange(title: String(localized: "Count Stock"), label: String(localized: "On the shelf"), start: part.quantity,
                                    action: String(localized: "Save Count")) { counted, note in
                            model.count(part.id, counted: counted, note: note)
                        }
                    }
            }
        }
    }
}

/// The popover for Count… and Remove Damaged…: a number and an optional note.
private struct StockChange: View {
    let title: String
    let label: String
    let start: Int
    let action: String
    let done: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = 0
    @State private var note = ""

    var body: some View {
        Form {
            Text(title).font(.headline)
            Stepper(value: $number, in: 0...9999) {
                LabeledContent(label) {
                    TextField(label, value: $number, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(width: 64)
                }
            }
            TextField("Note", text: $note, prompt: Text("Optional"))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) {
                    done(number, note)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.lg)
        .frame(width: 300)
        .onAppear { number = start }
    }
}

/// Every change to a part's stock, newest first: why, from which ticket or invoice, and
/// the count after.
struct StockHistorySection: View {
    @Environment(AppModel.self) private var model
    let partID: UUID
    @State private var rows: [StockMoveRow] = []
    @State private var showingAll = false

    var body: some View {
        Section {
            if rows.isEmpty { Text("No stock changes yet").foregroundStyle(.secondary) }
            ForEach(showingAll ? rows : Array(rows.prefix(8))) { row in
                HStack(spacing: Space.sm) {
                    Image(systemName: row.move.reason.symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([row.move.reason.title, row.source].compactMap { $0 }.joined(separator: " · "))
                        Text([row.move.createdAt.formatted(date: .abbreviated, time: .shortened), row.move.note]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(verbatim: row.move.delta > 0 ? "+\(row.move.delta)" : "\(row.move.delta)")
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(row.move.delta > 0 ? .green : .primary)
                    Text(verbatim: "→ \(row.move.quantityAfter)").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if rows.count > 8 {
                Button(showingAll ? "Show Fewer" : "Show All \(rows.count)") { showingAll.toggle() }
                    .buttonStyle(.link)
            }
        } header: {
            Text("Stock History")
        }
        .task(id: model.dataVersion) { rows = model.read([]) { try $0.stockHistory(of: partID) } }
    }
}
