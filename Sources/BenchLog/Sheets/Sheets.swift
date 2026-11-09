import BenchLogKit
import SwiftUI

/// Shows the sheet the model asks for.
struct SheetHost: View {
    let kind: SheetKind

    var body: some View {
        switch kind {
        case .newCustomer: CustomerSheet(customerID: nil)
        case .editCustomer(let id): CustomerSheet(customerID: id)
        case .addDevice(let customer): DeviceSheet(customerID: customer, deviceID: nil)
        case .editDevice(let id): DeviceSheet(customerID: nil, deviceID: id)
        case .newRepair(let customer, let device): NewRepairSheet(customerID: customer, deviceID: device)
        case .newPart: PartSheet(partID: nil)
        case .editPart(let id): PartSheet(partID: id)
        case .editGuide(let id): GuideSheet(guideID: id)
        case .importGuides(let folder): GuideImportSheet(folder: folder)
        }
    }
}

/// New Customer and Edit Customer.
struct CustomerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerID: UUID?

    @State private var existing: Customer?
    @State private var draft = CustomerDraft()
    @State private var showErrors = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            Text(customerID == nil ? LocalizedStringKey("New Customer") : "Edit Customer")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                Section {
                    CustomerFields(draft: $draft, isNew: customerID == nil, showErrors: showErrors)
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            SheetButtons(confirm: customerID == nil ? String(localized: "Add Customer") : String(localized: "Save"),
                         cancel: cancel, action: save)
        }
        .frame(width: 480)
        .confirmationDialog("Discard this customer?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("What you typed is not saved.")
        }
        .onAppear {
            if let customerID, let customer = model.read(nil, { try $0.customer(customerID) }) {
                existing = customer
                draft = CustomerDraft(customer)
            }
        }
    }

    private func cancel() {
        if existing == nil, !draft.isEmpty { confirmDiscard = true } else { dismiss() }
    }

    private func save() {
        guard draft.isValid else {
            showErrors = true
            return
        }
        guard let saved = model.save(draft.customer(updating: existing), firstNote: draft.firstNote) else { return }
        if existing == nil { model.open(.customer(saved.id)) }
        dismiss()
    }
}

/// Add Device and Edit Device.
struct DeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerID: UUID?
    let deviceID: UUID?

    @State private var existing: Device?
    @State private var draft = DeviceDraft()
    @State private var showErrors = false

    var body: some View {
        VStack(spacing: 0) {
            Text(deviceID == nil ? LocalizedStringKey("Add Device") : "Edit Device")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                Section {
                    DeviceFields(draft: $draft, showErrors: showErrors)
                }
            }
            .formStyle(.grouped)
            .fitsContent()
            SheetButtons(confirm: deviceID == nil ? String(localized: "Add Device") : String(localized: "Save"),
                         cancel: { dismiss() }, action: save)
        }
        .frame(width: 480)
        .onAppear {
            if let deviceID, let device = model.read(nil, { try $0.device(deviceID) }) {
                existing = device
                draft = DeviceDraft(device)
            }
        }
    }

    private func save() {
        guard draft.isValid else {
            showErrors = true
            return
        }
        guard let owner = existing?.customerId ?? customerID,
              let saved = model.save(draft.device(for: owner, updating: existing)) else { return }
        if existing == nil { model.selectedDevice = saved.id }
        dismiss()
    }
}
