import BenchLogKit
import SwiftUI

/// What one scan did.
enum ScanResult: Equatable {
    /// The text is not a UPC or EAN.
    case invalid
    /// The inventory knows the barcode: one more unit went into stock.
    case added(Part)
    /// A new barcode the lookup found. Nothing is saved until the review says Add Part.
    case found(ProductInfo)
    /// No part has the barcode and the lookup found no product (or failed, with why).
    case unknown(barcode: String, problem: String?)
}

/// Add by Barcode: each scan puts one unit on the shelf. A barcode the inventory knows adds
/// to its part. A new one is looked up online and shown for review (name, kind, cost, price)
/// before it becomes a part; one the lookup does not know gets the same review with an empty name.
/// A USB or Bluetooth scanner types the digits and Return into the field.
struct BarcodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Parts shown as already added (snapshots).
    var start: [UUID] = []
    /// A product shown as just looked up (snapshots).
    var startReview: ProductInfo?

    @State private var code = ""
    @State private var busy = false
    @State private var invalid = false
    /// The barcode under review: a new part waits for Add Part or Skip.
    @State private var pending: String?
    /// Whether the lookup found the product under review.
    @State private var found = false
    @State private var problem: String?
    @State private var name = ""
    @State private var kind = PartKind.part
    @State private var cost: Decimal?
    @State private var price: Decimal?
    @State private var added: [Entry] = []
    @FocusState private var focus: Field?

    private enum Field { case code, name }

    private struct Entry: Identifiable {
        let id = UUID()
        var part: Part
        var isNew: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add by Barcode")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                Section {
                    HStack(spacing: Space.sm) {
                        TextField("Barcode", text: $code, prompt: Text("Scan or type a UPC or EAN"))
                            .focused($focus, equals: .code)
                            .onSubmit(scan)
                            .disabled(busy || pending != nil)
                        if busy { ProgressView().controlSize(.small) }
                    }
                    if invalid {
                        Text("That is not a barcode. Check the digits.").font(.callout).foregroundStyle(.red)
                    }
                } footer: {
                    Text("A barcode the inventory knows adds one to stock. A new one is looked up at upcitemdb.com for you to review; only the barcode is sent.")
                }
                if let pending {
                    Section {
                        if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
                        TextField("Name", text: $name, prompt: Text("What is it?"))
                            .focused($focus, equals: .name)
                        Picker("Kind", selection: $kind) {
                            ForEach(PartKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        TextField("Cost", value: $cost, format: Money.format)
                        TextField("Price", value: $price, format: Money.format)
                            .help("What a customer pays for one")
                        HStack {
                            Spacer()
                            Button("Skip") { clearReview() }
                                .help("Leave this barcode out")
                            Button("Add Part", action: addReviewed)
                                .keyboardShortcut(.defaultAction)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                                .help("Add it with one in stock")
                        }
                    } header: {
                        Text(found ? "Review the new part for \(pending)" : "No product found for \(pending)")
                    }
                }
                if !added.isEmpty {
                    Section("Added") {
                        ForEach(added.reversed()) { entry in
                            HStack(spacing: Space.sm) {
                                Image(systemName: entry.part.kind.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                    .accessibilityLabel(Text(entry.part.kind.title))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.part.name).lineLimit(1).help(entry.part.name)
                                    Text(entry.isNew ? "New part · \(entry.part.quantity) in stock" : "\(entry.part.quantity) in stock")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Edit…") { model.sheet = .editPart(entry.part.id) }
                                    .help("Set its kind, cost, and price")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.lg)
        }
        .frame(width: 480)
        .onAppear {
            added = start.compactMap { id in model.read(nil) { try $0.part(id) } }.map { Entry(part: $0, isNew: false) }
            if let startReview { review(startReview) } else { focus = .code }
        }
    }

    private func scan() {
        let text = code
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !busy, pending == nil else { return }
        invalid = false
        busy = true
        Task {
            let result = await model.addScanned(text)
            busy = false
            switch result {
            case .invalid:
                invalid = true
                focus = .code
            case .added(let part):
                code = ""
                added.append(Entry(part: part, isNew: false))
                focus = .code
            case .found(let product):
                code = ""
                review(product)
            case .unknown(let barcode, let why):
                code = ""
                pending = barcode
                found = false
                problem = why
                focus = .name
            }
        }
    }

    /// Shows what the lookup found, to change or confirm.
    private func review(_ product: ProductInfo) {
        pending = product.barcode
        found = true
        problem = nil
        name = product.title
        kind = product.suggestedKind
        focus = .name
    }

    private func addReviewed() {
        guard let pending, let part = model.addReviewed(barcode: pending, name: name, kind: kind,
                                                        costCents: Money.cents(cost), priceCents: Money.cents(price)) else { return }
        added.append(Entry(part: part, isNew: true))
        clearReview()
    }

    private func clearReview() {
        pending = nil
        found = false
        problem = nil
        name = ""
        kind = .part
        cost = nil
        price = nil
        focus = .code
    }
}
