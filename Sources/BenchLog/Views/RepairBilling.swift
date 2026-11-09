import BenchLogKit
import SwiftUI

/// Billing on a repair: labour lines, the priced parts, a discount, and the totals with
/// TPS and TVQ.
struct RepairBilling: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    @State private var labour: [LabourLine] = []
    @State private var bill: Bill?
    @State private var discount: Decimal?

    var body: some View {
        Group {
            ForEach(labour) { line in
                LabourRow(line: line).id(line.id)
            }
            Button("Add Labour") { model.addLabour(to: repair.id) }
                .controlSize(.small)
                .help("Add work at your hourly rate, or a flat price")
            if let bill {
                let parts = bill.lines.filter { $0.kind == .part }
                if !parts.isEmpty {
                    LabeledContent("Parts") {
                        Text(Money.text(bill.totals.partsCents)).monospacedDigit()
                    }
                    .help(parts.map(\.description).joined(separator: ", "))
                }
                if !bill.unpricedParts.isEmpty {
                    Label("No price yet: \(bill.unpricedParts.joined(separator: ", ")). It is left off.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Discount") {
                    TextField("Discount", value: $discount, format: Money.format, prompt: Text(Money.text(0)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .onSubmit { model.setDiscount(Money.cents(discount) ?? 0, of: repair.id) }
                }
                TotalsBlock(totals: bill.totals)
            }
        }
        .task(id: model.dataVersion) {
            labour = model.read([]) { try $0.labourLines(on: repair.id) }
            bill = model.read(nil) { try $0.bill(for: repair.id) }
            discount = repair.discountCents > 0 ? Money.decimal(repair.discountCents) : nil
        }
    }
}

/// Subtotal, each of the region's taxes, and Total, in the Mac's format.
struct TotalsBlock: View {
    let totals: Totals

    var body: some View {
        VStack(spacing: Space.xs) {
            row("Subtotal", totals.subtotalCents)
            if totals.taxableCents != totals.subtotalCents, !totals.taxes.isEmpty {
                row("Taxable (parts)", totals.taxableCents)
            }
            ForEach(totals.taxes, id: \.kind) { tax in
                row("\(tax.kind.title) (\(Self.percent(tax.rate)))", tax.cents)
            }
            Divider()
            row("Total", totals.totalCents).font(.headline)
        }
    }

    private func row(_ title: LocalizedStringKey, _ cents: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.text(cents)).monospacedDigit()
        }
    }

    /// 99 750 millionths → "9.975 %" (« 9,975 % » in French).
    static func percent(_ millionths: Int) -> String {
        (Decimal(millionths) / 1_000_000).formatted(.percent.precision(.fractionLength(0...3)))
    }
}

/// One labour line: what was done, hours × rate or a flat price, and its amount. Changes
/// save on Return or when the field loses focus.
struct LabourRow: View {
    @Environment(AppModel.self) private var model
    let line: LabourLine
    @State private var description = ""
    @State private var hours: Decimal?
    @State private var price: Decimal?
    @State private var kind: LabourKind = .hourly
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField("Labour", text: $description, prompt: Text("What you did"))
                .labelsHidden()
                .focused($focused)
            HStack(spacing: Space.sm) {
            Picker("Kind", selection: $kind) {
                Text("Hourly").tag(LabourKind.hourly)
                Text("Flat").tag(LabourKind.flat)
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: kind) { commit() }
            if kind == .hourly {
                TextField("Hours", value: $hours, format: .number.precision(.fractionLength(0...2)), prompt: Text("h"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .focused($focused)
                    .help("Hours, like 1.5")
                Text(verbatim: "×").foregroundStyle(.secondary)
            }
            TextField(kind == .hourly ? "Rate" : "Price", value: $price, format: Money.format)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
                .focused($focused)
                .help(kind == .hourly ? "The hourly rate" : "The flat price")
            Spacer()
            Text(Money.text(current.amountCents))
                .monospacedDigit()
            Button("Remove", systemImage: "minus.circle") { model.removeLabour(line.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Remove this labour line")
            }
        }
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .onAppear {
            description = line.description
            kind = line.kind
            hours = Decimal(line.hundredthHours) / 100
            price = Money.decimal(line.unitCents)
        }
    }

    private var current: LabourLine {
        var changed = line
        changed.description = description.trimmingCharacters(in: .whitespaces)
        changed.kind = kind
        changed.hundredthHours = Money.cents(hours) ?? line.hundredthHours
        changed.unitCents = Money.cents(price) ?? 0
        return changed
    }

    private func commit() {
        let changed = current
        guard changed.description != line.description || changed.kind != line.kind
            || changed.hundredthHours != line.hundredthHours || changed.unitCents != line.unitCents else { return }
        model.save(changed)
    }
}

/// The repair's printed documents: the intake slip, estimates, and invoices, with payment
/// and the estimate's decision.
struct RepairDocuments: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    @State private var documents: [Invoice] = []
    @State private var working = false

    var body: some View {
        Group {
            HStack(spacing: Space.sm) {
                Button("Print Intake Slip") { run { await model.printIntakeSlip(for: repair.id) } }
                    .help("Make the slip the customer signs at check-in, and open it to print")
                Button("Print Estimate") { run { await model.issue(.estimate, for: repair.id) } }
                    .help("Make an estimate from the labour and parts, and open it to print")
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Invoice") { run { await model.issue(.invoice, for: repair.id) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(repair.status == .cancelled)
                    .help("Issue an invoice with the next number; it cannot change afterwards")
            }
            .disabled(working)
            ForEach(documents) { document in
                DocumentRow(document: document, creditedBy: documents.first { $0.creditsInvoiceId == document.id })
            }
        }
        .task(id: model.dataVersion) {
            documents = model.read([]) { try $0.invoices(for: repair.id) }
        }
    }

    private func run(_ job: @escaping () async -> Void) {
        working = true
        Task {
            await job()
            working = false
        }
    }
}

struct DocumentRow: View {
    @Environment(AppModel.self) private var model
    let document: Invoice
    /// For an invoice: the credit note that cancels it.
    var creditedBy: Invoice?
    @State private var crediting = false
    @State private var reason = ""

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.text(document.totalCents)).monospacedDigit()
            state
            Button("Open", systemImage: "arrow.up.forward.app") { model.open(document) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(document.fileId == nil)
                .help("Open the PDF in Preview to print or send it")
        }
        .alert("Issue a Credit Note for \(document.numberText ?? "")?", isPresented: $crediting) {
            TextField("Reason (optional)", text: $reason)
            Button("Issue Credit Note") { Task { await model.issueCreditNote(for: document.id, reason: reason) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It cancels the invoice. To correct it, issue a new invoice afterwards. A credit note cannot be changed.")
        }
    }

    private var symbol: String {
        switch document.kind {
        case .invoice: "doc.text"
        case .estimate: "doc.questionmark"
        case .creditNote: "arrow.uturn.backward.circle"
        }
    }

    private var title: String {
        switch document.kind {
        case .invoice: String(localized: "Invoice \(document.numberText ?? "")")
        case .estimate: String(localized: "Estimate")
        case .creditNote: String(localized: "Credit Note \(document.numberText ?? "")")
        }
    }

    private var caption: String {
        let date = document.issuedAt.formatted(date: .abbreviated, time: .omitted)
        if document.kind == .creditNote, let credits = document.document?.credits {
            return String(localized: "\(date) · credits \(credits)")
        }
        if let creditedBy, let number = creditedBy.numberText {
            return String(localized: "\(date) · credited by \(number)")
        }
        return date
    }

    @ViewBuilder
    private var state: some View {
        switch document.kind {
        case .invoice:
            Menu {
                ForEach(PaymentMethod.allCases) { method in
                    Button(method.title) { Task { await model.setPaid(document.id, method: method) } }
                }
                if document.paidAt != nil {
                    Divider()
                    Button("Mark Unpaid") { Task { await model.setPaid(document.id, method: nil) } }
                }
                if creditedBy == nil {
                    Divider()
                    Button("Issue Credit Note…") {
                        reason = ""
                        crediting = true
                    }
                }
            } label: {
                if let method = document.paymentMethod {
                    Label("Paid · \(method.title)", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Unpaid", systemImage: "circle")
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .foregroundStyle(document.paidAt != nil ? .green : .orange)
            .tint(document.paidAt != nil ? .green : .orange)
            .help("Record how the customer paid")
        case .creditNote:
            Menu {
                ForEach(PaymentMethod.allCases) { method in
                    Button(method.title) { Task { await model.setPaid(document.id, method: method) } }
                }
                if document.paidAt != nil {
                    Divider()
                    Button("Mark Not Refunded") { Task { await model.setPaid(document.id, method: nil) } }
                }
            } label: {
                if let method = document.paymentMethod {
                    Label("Refunded · \(method.title)", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Not Refunded", systemImage: "circle")
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .foregroundStyle(document.paidAt != nil ? .green : .secondary)
            .tint(document.paidAt != nil ? .green : .secondary)
            .help("Record how you paid the customer back")
        case .estimate:
            if let decision = document.decision {
                Label(decision == .approved ? "Approved" : "Refused",
                      systemImage: decision == .approved ? "hand.thumbsup" : "hand.thumbsdown")
                    .foregroundStyle(decision == .approved ? .green : .red)
            } else {
                Button("Approve") { model.decide(document.id, approved: true) }
                    .help("The customer accepts: the repair moves on and a note records it")
                Button("Refuse") { model.decide(document.id, approved: false) }
                    .help("The customer declines; a note records it")
            }
        }
    }
}

/// An internal job's cost: the time logged as labour lines, and the parts at cost. No price,
/// no taxes: the shop pays it.
struct InternalCostView: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    @State private var labour: [LabourLine] = []
    @State private var cost: InternalCost?

    var body: some View {
        Group {
            ForEach(labour) { line in
                LabourRow(line: line).id(line.id)
            }
            Button("Log Time") { model.addLabour(to: repair.id) }
                .controlSize(.small)
                .help("Add a line for time spent on this job")
            if let cost {
                LabeledContent("Time spent") {
                    Text("\((Decimal(cost.hundredthHours) / 100).formatted(.number.precision(.fractionLength(0...2)))) h")
                        .monospacedDigit()
                }
                LabeledContent("Parts at cost") {
                    Text(Money.text(cost.partsCents)).monospacedDigit().fontWeight(.semibold)
                }
                if !cost.uncostedParts.isEmpty {
                    Label("No cost yet: \(cost.uncostedParts.joined(separator: ", ")). It is left off.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .task(id: model.dataVersion) {
            labour = model.read([]) { try $0.labourLines(on: repair.id) }
            cost = model.read(nil) { try $0.internalCost(of: repair.id) }
        }
    }
}
