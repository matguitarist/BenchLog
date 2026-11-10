import BenchLogKit
import SwiftUI

/// New Part and Edit Part: the part, its prices and stock, and the catalog models it fits.
struct PartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let partID: UUID?

    @State private var existing: Part?
    @State private var name = ""
    @State private var sku = ""
    @State private var vendor = ""
    @State private var url = ""
    @State private var cost: Decimal?
    @State private var price: Decimal?
    @State private var quantity = 0
    @State private var threshold = 0
    @State private var kind = PartKind.part
    @State private var condition: PartCondition?
    @State private var location = ""
    @State private var notes = ""
    @State private var fits: [PartFit] = []
    @State private var fitDraft = DeviceDraft()
    @State private var showErrors = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(partID == nil ? LocalizedStringKey("New Part") : "Edit Part")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                    if showErrors, name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Enter a name.").font(.callout).foregroundStyle(.red)
                    }
                    Picker("Kind", selection: $kind) {
                        ForEach(PartKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Condition", selection: $condition) {
                        Text("Not set").tag(PartCondition?.none)
                        Divider()
                        ForEach(PartCondition.allCases) { Text($0.title).tag(PartCondition?.some($0)) }
                    }
                    TextField("SKU", text: $sku)
                    TextField("Vendor", text: $vendor)
                    TextField("Link", text: $url, prompt: Text("https://…"))
                    TextField("Location", text: $location, prompt: Text("Shelf, bin, or drawer"))
                }
                Section {
                    TextField("Cost", value: $cost, format: Money.format)
                    TextField("Price", value: $price, format: Money.format)
                        .help("What a customer pays for one")
                    LabeledContent("In stock") {
                        HStack(spacing: Space.sm) {
                            Text(verbatim: "\(quantity)").monospacedDigit()
                            Stepper("In stock", value: $quantity, in: 0...9999).labelsHidden()
                        }
                    }
                    LabeledContent("Low-stock threshold") {
                        HStack(spacing: Space.sm) {
                            Text(threshold > 0 ? "\(threshold)" : String(localized: "None")).monospacedDigit()
                            Stepper("Low-stock threshold", value: $threshold, in: 0...999).labelsHidden()
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...5)
                        .labelsHidden()
                }
                Section("Fits") {
                    ForEach(fits, id: \.self) { fit in
                        HStack {
                            Label(fit.title, systemImage: fit.category.symbol)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { fits.removeAll { $0 == fit } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Remove \(fit.title)")
                        }
                    }
                    FitPicker(draft: $fitDraft) { fit in
                        if !fits.contains(fit) { fits.append(fit) }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 640)
            SheetButtons(confirm: partID == nil ? String(localized: "Add Part") : String(localized: "Save"),
                         cancel: { dismiss() }, action: save)
        }
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        if let partID, let part = model.read(nil, { try $0.part(partID) }) {
            existing = part
            name = part.name
            sku = part.sku
            vendor = part.vendor
            url = part.url
            cost = Money.decimal(part.costCents)
            price = Money.decimal(part.priceCents)
            quantity = part.quantity
            threshold = part.lowStockThreshold
            kind = part.kind
            condition = part.condition
            location = part.location
            notes = part.notes
            fits = model.read([]) { try $0.fits(of: partID) }
            if let last = fits.last {
                fitDraft.category = last.category
                fitDraft.brand = last.brand
            }
        }
        nameFocused = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showErrors = true
            return
        }
        var part = existing ?? Part(name: trimmed)
        part.name = trimmed
        part.sku = sku.trimmingCharacters(in: .whitespaces)
        part.vendor = vendor.trimmingCharacters(in: .whitespaces)
        part.url = url.trimmingCharacters(in: .whitespaces)
        part.costCents = Money.cents(cost)
        part.priceCents = Money.cents(price)
        part.quantity = quantity
        part.lowStockThreshold = threshold
        part.kind = kind
        part.condition = condition
        part.location = location.trimmingCharacters(in: .whitespaces)
        part.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved = model.save(part, fits: fits) else { return }
        model.selectedPart = saved.id
        dismiss()
    }
}

/// Picks a catalog model (category, brand, model) for a part to fit.
private struct FitPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: DeviceDraft
    let add: (PartFit) -> Void

    var body: some View {
        Picker("Category", selection: $draft.category) {
            ForEach(DeviceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        Group {
            TextField("Brand", text: $draft.brand)
                .textInputSuggestions {
                    ForEach(model.read([]) { try $0.catalogBrands(draft.category) }.filter(matches(draft.brand)).prefix(12), id: \.self) {
                        Text(verbatim: $0).textInputCompletion($0)
                    }
                }
            TextField("Model", text: $draft.model)
                .textInputSuggestions {
                    ForEach(model.read([]) { try $0.catalogModels(draft.category, brand: draft.brand) }.filter(matches(draft.model)).prefix(12), id: \.self) {
                        Text(verbatim: $0).textInputCompletion($0)
                    }
                }
            HStack {
                Spacer()
                Button("Add Model") {
                    add(PartFit(category: draft.category, brand: draft.brand.trimmingCharacters(in: .whitespaces),
                                model: draft.model.trimmingCharacters(in: .whitespaces)))
                    draft.model = ""
                }
                .disabled(!draft.isValid)
                .help("Add this model to the ones the part fits")
            }
        }
    }

    private func matches(_ typed: String) -> (String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return { typed.isEmpty || $0.lowercased().contains(typed) }
    }
}
