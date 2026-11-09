import BenchLogKit
import SwiftUI

// The customer and device fields, shared by their own sheets and by the
// New Repair sheet, which adds a customer and a device inline.

struct CustomerDraft: Equatable {
    var name = ""
    var phone = ""
    var email = ""
    var address = ""
    var firstNote = ""
    var language: DocumentsLanguage = .french

    init() {}

    init(_ customer: Customer) {
        name = customer.name
        phone = customer.phone
        email = customer.email
        address = customer.address
        language = customer.documentsLanguage
    }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var isEmpty: Bool { self == CustomerDraft() }

    /// The customer with these values: `existing` changed, or a new one.
    func customer(updating existing: Customer? = nil) -> Customer {
        var customer = existing ?? Customer(name: "")
        customer.name = name.trimmingCharacters(in: .whitespaces)
        customer.phone = phone.trimmingCharacters(in: .whitespaces)
        customer.email = email.trimmingCharacters(in: .whitespaces)
        customer.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        customer.documentsLanguage = language
        return customer
    }
}

struct CustomerFields: View {
    @Binding var draft: CustomerDraft
    var isNew = true
    var showErrors = false
    /// Puts the cursor in Name when the fields appear.
    var focusName = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        TextField("Name", text: $draft.name)
            .focused($nameFocused)
            .onAppear { if focusName { nameFocused = true } }
        if showErrors, !draft.isValid {
            Text("Enter a name.").font(.callout).foregroundStyle(.red)
        }
        TextField("Phone", text: $draft.phone)
        TextField("Email", text: $draft.email)
        TextField("Address", text: $draft.address, axis: .vertical)
            .lineLimit(1...3)
        if isNew {
            TextField("Notes", text: $draft.firstNote, prompt: Text("Goes on the customer's timeline"), axis: .vertical)
                .lineLimit(1...4)
        }
        Picker("Documents language", selection: $draft.language) {
            ForEach(DocumentsLanguage.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
        }
        .help("The language of this customer's intake slips, estimates, and invoices")
    }
}

struct DeviceDraft: Equatable {
    var category: DeviceCategory = .phone
    var brand = ""
    var model = ""
    var revision = ""
    var serial = ""
    var colour = ""
    var condition = ""
    var passcode = ""
    var isPattern = false

    init() {}

    init(_ device: Device) {
        category = device.category
        brand = device.brand
        model = device.model
        revision = device.revision
        serial = device.serial
        colour = device.colour
        condition = device.condition
        passcode = device.passcode
        isPattern = device.passcodeIsPattern
    }

    var isValid: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func device(for customerID: UUID, updating existing: Device? = nil) -> Device {
        var device = existing ?? Device(customerId: customerID, category: category, brand: "", model: "")
        device.category = category
        device.brand = brand.trimmingCharacters(in: .whitespaces)
        device.model = model.trimmingCharacters(in: .whitespaces)
        device.revision = revision.trimmingCharacters(in: .whitespaces)
        device.serial = serial.trimmingCharacters(in: .whitespaces)
        device.colour = colour.trimmingCharacters(in: .whitespaces)
        device.condition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        device.passcode = passcode
        device.passcodeIsPattern = isPattern
        return device
    }
}

/// Category, then Brand → Model → Revision suggested from the catalog (each filtered
/// by the field before it), then the serial, colour, condition, and passcode.
struct DeviceFields: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: DeviceDraft
    var showErrors = false

    var body: some View {
        Picker("Category", selection: $draft.category) {
            ForEach(DeviceCategory.allCases) { category in
                Label(category.title, systemImage: category.symbol).tag(category)
            }
        }
        catalogField("Brand", text: $draft.brand,
                     suggestions: model.read([]) { try $0.catalogBrands(draft.category) },
                     isNew: !draft.brand.isEmpty && !model.read(true) { try $0.catalogContains(draft.category, brand: draft.brand) })
        catalogField("Model", text: $draft.model,
                     suggestions: draft.brand.isEmpty ? [] : model.read([]) { try $0.catalogModels(draft.category, brand: draft.brand) },
                     isNew: !draft.brand.isEmpty && !draft.model.isEmpty
                         && !model.read(true) { try $0.catalogContains(draft.category, brand: draft.brand, model: draft.model) })
        catalogField("Revision", text: $draft.revision,
                     suggestions: draft.model.isEmpty ? [] : model.read([]) { try $0.catalogRevisions(draft.category, brand: draft.brand, model: draft.model) },
                     isNew: !draft.model.isEmpty && !draft.revision.isEmpty
                         && !model.read(true) { try $0.catalogContains(draft.category, brand: draft.brand, model: draft.model, revision: draft.revision) })
        if showErrors, !draft.isValid {
            Text("Choose a brand and model.").font(.callout).foregroundStyle(.red)
        }
        TextField("Serial or IMEI", text: $draft.serial)
        TextField("Colour", text: $draft.colour)
        TextField("Condition", text: $draft.condition, prompt: Text("Scratches, cracks, missing screws…"), axis: .vertical)
            .lineLimit(1...4)
        PasscodeField(passcode: $draft.passcode, isPattern: $draft.isPattern)
    }

    @ViewBuilder
    private func catalogField(_ title: LocalizedStringKey, text: Binding<String>, suggestions: [String], isNew: Bool) -> some View {
        let typed = text.wrappedValue.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = suggestions.filter { typed.isEmpty || $0.lowercased().contains(typed) }.prefix(12)
        TextField(title, text: text)
            .textInputSuggestions {
                ForEach(Array(matches), id: \.self) { value in
                    Text(verbatim: value).textInputCompletion(value)
                }
            }
        if isNew {
            Text("Adds “\(text.wrappedValue)” to the catalog")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The buttons at the bottom of every sheet: Cancel on the left of the confirm button.
struct SheetButtons: View {
    let confirm: String
    var canConfirm = true
    var shortcut: KeyboardShortcut = .defaultAction
    let cancel: () -> Void
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(confirm, action: action)
                .keyboardShortcut(shortcut)
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirm)
        }
        .padding(Space.lg)
    }
}
