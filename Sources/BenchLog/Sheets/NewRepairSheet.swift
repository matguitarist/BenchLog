import BenchLogKit
import SwiftUI

/// New Repair: pick (or add) the customer, pick (or add) their device, describe the
/// complaint. "New Customer…" and "Add Device…" open inline, never a second sheet.
struct NewRepairSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerID: UUID?
    let deviceID: UUID?

    @State private var customer: Customer?
    @State private var search = ""
    @State private var addingCustomer = false
    @State private var customerDraft = CustomerDraft()

    @State private var devices: [Device] = []
    @State private var device: UUID?
    @State private var addingDevice = false
    @State private var deviceDraft = DeviceDraft()

    @State private var complaint = ""
    @State private var hasPromise = false
    @State private var promised = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var showErrors = false
    /// The rule chosen last time is the default for the next repair.
    @AppStorage("approvalRule") private var approval: ApprovalRule = .go
    @State private var approvalLimit: Decimal? = 150
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case search, complaint }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Repair")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                customerSection
                if customer != nil || addingCustomer { deviceSection }
                Section("Complaint") {
                    TextField("Complaint", text: $complaint, prompt: Text("What the customer says is wrong"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...6)
                        .focused($focus, equals: .complaint)
                    if showErrors, complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe the complaint.").font(.callout).foregroundStyle(.red)
                    }
                    Toggle("Promised", isOn: $hasPromise)
                    if hasPromise {
                        DatePicker("Promised for", selection: $promised, displayedComponents: .date)
                    }
                }
                Section("Approval") {
                    ApprovalPicker(rule: $approval, limit: $approvalLimit)
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 620)
            SheetButtons(confirm: String(localized: "Create Repair"), shortcut: KeyboardShortcut(.return, modifiers: .command),
                         cancel: cancel, action: create)
        }
        .frame(width: 520)
        .confirmationDialog("Discard this repair?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("What you typed is not saved.")
        }
        .onAppear(perform: start)
    }

    // MARK: Customer

    @ViewBuilder
    private var customerSection: some View {
        Section {
            if let customer {
                LabeledContent("Customer") {
                    HStack(spacing: Space.sm) {
                        Text(customer.name).fontWeight(.medium)
                        if customerID == nil {
                            Button("Change") {
                                self.customer = nil
                                device = nil
                                focus = .search
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } else if addingCustomer {
                CustomerFields(draft: $customerDraft, isNew: true, showErrors: showErrors)
                Button("Choose an Existing Customer") {
                    addingCustomer = false
                    focus = .search
                }
                .controlSize(.small)
            } else {
                TextField("Customer", text: $search, prompt: Text("Name or phone"))
                    .focused($focus, equals: .search)
                let matches = model.read([]) { try $0.customers(matching: search) }.prefix(6)
                ForEach(Array(matches)) { match in
                    Button {
                        pick(match)
                    } label: {
                        HStack {
                            Text(match.name)
                            Spacer()
                            Text(match.phone).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if showErrors {
                    Text("Choose a customer, or add a new one.").font(.callout).foregroundStyle(.red)
                }
                Button("New Customer…") {
                    customerDraft.name = search
                    addingCustomer = true
                    addingDevice = true
                }
                .controlSize(.small)
            }
        } header: {
            Text("Customer")
        }
    }

    // MARK: Device

    @ViewBuilder
    private var deviceSection: some View {
        Section("Device") {
            if !addingDevice, !devices.isEmpty {
                Picker("Device", selection: $device) {
                    ForEach(devices) { device in
                        Label(device.title, systemImage: device.category.symbol).tag(Optional(device.id))
                    }
                }
                Button("Add Device…") { addingDevice = true }
                    .controlSize(.small)
            } else {
                DeviceFields(draft: $deviceDraft, showErrors: showErrors)
                if !devices.isEmpty {
                    Button("Choose an Existing Device") { addingDevice = false }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Actions

    private func start() {
        if let customerID, let found = model.read(nil, { try $0.customer(customerID) }) {
            pick(found)
            if let deviceID { device = deviceID }
            focus = .complaint
        } else {
            focus = .search
        }
    }

    private func pick(_ picked: Customer) {
        customer = picked
        devices = model.read([]) { try $0.devices(of: picked.id) }
        device = devices.first?.id
        // A customer with no devices opens Add Device right away.
        addingDevice = devices.isEmpty
        focus = .complaint
    }

    private var isDirty: Bool {
        !complaint.isEmpty || !customerDraft.isEmpty || deviceDraft != DeviceDraft() || (customerID == nil && customer != nil)
    }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    private func create() {
        let text = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
        let customerReady = customer != nil || (addingCustomer && customerDraft.isValid)
        let deviceReady = addingDevice ? deviceDraft.isValid : device != nil
        guard customerReady, deviceReady, !text.isEmpty else {
            showErrors = true
            return
        }
        var owner = customer
        if owner == nil {
            owner = model.save(customerDraft.customer(), firstNote: customerDraft.firstNote)
        }
        guard let owner else { return }
        var deviceID = device
        if addingDevice {
            deviceID = model.save(deviceDraft.device(for: owner.id))?.id
        }
        guard let deviceID,
              let repair = model.createRepair(deviceID: deviceID, complaint: text, promisedAt: hasPromise ? promised : nil,
                                                   approval: approval, approvalLimitCents: Money.cents(approvalLimit)) else { return }
        model.open(.repair(repair.id))
        dismiss()
    }
}
