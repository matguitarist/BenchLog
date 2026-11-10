import BenchLogKit
import SwiftUI

/// New Counter Sale: parts from stock and typed items, to a customer or a walk-in, invoiced
/// with the region's taxes.
struct CounterSaleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerID: UUID?
    var start: [CounterSaleItem] = []

    @State private var customer: UUID?
    @State private var items: [CounterSaleItem] = []
    @State private var customers: [Customer] = []
    @State private var parts: [Part] = []
    @State private var confirmDiscard = false

    private var totals: Totals { model.read(Billing.totals([], discountCents: 0, taxes: [])) { try $0.counterSaleTotals(items) } }
    private var canInvoice: Bool {
        items.contains { $0.quantity > 0 && !$0.description.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Counter Sale").font(.headline).padding(.top, Space.lg)
            Form {
                Section {
                    Picker("Customer", selection: $customer) {
                        Text("Walk-in").tag(UUID?.none)
                        Divider()
                        ForEach(customers) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .help("Who is buying; a walk-in sale is invoiced with no name and filed with the shop")
                }
                Section {
                    if items.isEmpty {
                        Text("Add a part from stock or type an item.").foregroundStyle(.secondary)
                    }
                    ForEach($items) { $item in CounterSaleRow(item: $item, stock: stock(of: item)) { remove(item) } }
                    HStack(spacing: Space.sm) {
                        Menu("Add Part") {
                            ForEach(parts) { part in
                                Button("\(part.name) — \(Money.text(part.priceCents ?? 0)) (\(part.quantity) in stock)") { add(part) }
                                    .disabled(part.quantity == 0)
                            }
                        }
                        .fixedSize()
                        .help("Sell a part from stock; it leaves stock as Sold")
                        Button("Add Item") { items.append(CounterSaleItem(description: "", unitCents: 0)) }
                            .help("Sell something not in the inventory")
                        Spacer()
                    }
                } header: {
                    Text("Items")
                }
                Section {
                    TotalsBlock(totals: totals)
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            SheetButtons(confirm: String(localized: "Invoice"), canConfirm: canInvoice, cancel: cancel) {
                Task {
                    await model.issueCounterSale(to: customer, items: items)
                    dismiss()
                }
            }
        }
        .frame(width: 560)
        .confirmationDialog("Discard this sale?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("Nothing is invoiced.")
        }
        .onAppear {
            customer = customerID
            items = start
            customers = model.read([]) { try $0.customers() }
            parts = model.read([]) { try $0.parts(matching: "") }
        }
    }

    private func stock(of item: CounterSaleItem) -> Int? {
        item.partId.flatMap { id in parts.first { $0.id == id }?.quantity }
    }

    private func add(_ part: Part) {
        if let index = items.firstIndex(where: { $0.partId == part.id }) {
            items[index].quantity += 1
        } else {
            items.append(CounterSaleItem(partId: part.id, description: part.name, unitCents: part.priceCents ?? 0))
        }
    }

    private func remove(_ item: CounterSaleItem) { items.removeAll { $0.id == item.id } }

    private func cancel() {
        if items.isEmpty { dismiss() } else { confirmDiscard = true }
    }
}

/// One line: the part's name or a typed item, how many, the price for one, and the amount.
private struct CounterSaleRow: View {
    @Binding var item: CounterSaleItem
    /// Units on the shelf, for a part from stock.
    let stock: Int?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            if let stock {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.description).lineLimit(1).help(item.description)
                    Text("\(stock) in stock").font(.caption).foregroundStyle(item.quantity > stock ? .orange : .secondary)
                }
            } else {
                TextField("Item", text: $item.description, prompt: Text("Description"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
            Spacer(minLength: Space.sm)
            Text(verbatim: "× \(item.quantity)").monospacedDigit()
            Stepper("Quantity", value: $item.quantity, in: 1...999).labelsHidden()
            TextField("Price", value: Binding(get: { Money.decimal(item.unitCents) }, set: { item.unitCents = Money.cents($0) ?? 0 }),
                      format: Money.format)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
                .help("The price for one, before taxes")
            Text(Money.text(item.amountCents)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button("Remove", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Take this line off the sale")
        }
    }
}
