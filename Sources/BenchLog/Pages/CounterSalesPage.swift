import BenchLogKit
import SwiftUI

/// Counter Sales: every sale made without a repair, newest first, beside the selected sale.
struct CounterSalesPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [CounterSaleRow] = []

    var body: some View {
        @Bindable var model = model
        HSplitView {
            list
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Counter Sales")
        .searchable(text: $model.saleSearch, prompt: Text("Customer, item, or invoice number"))
        .toolbar {
            ToolbarItem {
                Button("New Counter Sale", systemImage: "cart.badge.plus") { model.sheet = .newCounterSale(customer: nil) }
                    .help("Sell parts or items without a repair (⌥⌘N)")
            }
        }
        .task(id: "\(model.dataVersion) \(model.saleSearch)") {
            rows = model.read([]) { try $0.counterSaleRows(matching: model.saleSearch) }
        }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var model = model
        if rows.isEmpty {
            if model.saleSearch.isEmpty {
                ContentUnavailableView {
                    Label("No Counter Sales", systemImage: SidebarItem.counterSales.symbol)
                } description: {
                    Text("Sell parts or items without a repair, to a customer or a walk-in.")
                } actions: {
                    Button("New Counter Sale") { model.sheet = .newCounterSale(customer: nil) }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: model.saleSearch)
            }
        } else {
            List(rows, selection: $model.selectedSale) { row in
                CounterSaleListRow(row: row)
                    .tag(row.id)
                    .contextMenu {
                        Button("Open PDF") { model.open(row.invoice) }.disabled(row.invoice.fileId == nil)
                        if let customer = row.customerId { Button("Open Customer") { model.open(.customer(customer)) } }
                    }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let row = rows.first(where: { $0.id == model.selectedSale }) {
            CounterSaleDetail(row: row).id(row.id)
        } else {
            ContentUnavailableView("No Counter Sale Selected", systemImage: SidebarItem.counterSales.symbol,
                                   description: Text("Select a sale to see its items and its invoice."))
        }
    }
}

extension CounterSaleRow {
    /// The customer's name, or "Walk-in".
    var buyer: String { customerName.isEmpty ? String(localized: "Walk-in") : customerName }
}

/// One sale in the list: invoice number, buyer, date, what was sold, the total, and its status.
private struct CounterSaleListRow: View {
    let row: CounterSaleRow

    var body: some View {
        let items = row.lines.map(\.description).joined(separator: ", ")
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(row.invoice.numberText ?? "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(row.buyer)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .help(row.buyer)
                }
                Text(items)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(items)
                Text(row.invoice.issuedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(Money.text(row.totals.totalCents)).monospacedDigit()
                InvoiceStatus(invoice: row.invoice, isCredited: row.creditNote != nil)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One sale: who bought and when, the items, the totals, and the invoice with its payment.
private struct CounterSaleDetail: View {
    @Environment(AppModel.self) private var model
    let row: CounterSaleRow

    var body: some View {
        Form {
            Section {
                Text("Counter Sale \(row.invoice.numberText ?? "")")
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                LabeledContent("Customer") {
                    if let customer = row.customerId {
                        Button(row.buyer) { model.open(.customer(customer)) }
                            .buttonStyle(.link)
                            .help("Open customer \(row.buyer)")
                    } else {
                        Text(row.buyer)
                    }
                }
                LabeledContent("Date", value: row.invoice.issuedAt.formatted(date: .long, time: .shortened))
            }
            Section("Items") {
                ForEach(Array(row.lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: Space.sm) {
                        Text(line.description).lineLimit(2)
                        Spacer(minLength: Space.sm)
                        Text(verbatim: "\((line.hundredths ?? 100) / 100) × \(Money.text(line.unitCents))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Money.text(line.amountCents))
                            .monospacedDigit()
                            .frame(width: 88, alignment: .trailing)
                    }
                }
            }
            Section {
                TotalsBlock(totals: row.totals)
            }
            Section("Documents") {
                DocumentRow(document: row.invoice, creditedBy: row.creditNote)
                if let note = row.creditNote { DocumentRow(document: note) }
            }
        }
        .formStyle(.grouped)
    }
}
