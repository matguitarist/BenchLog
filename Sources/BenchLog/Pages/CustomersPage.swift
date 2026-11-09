import BenchLogKit
import SwiftUI

/// Customers: the list, searchable by name, email, or phone digits, beside the selected customer.
struct CustomersPage: View {
    @Environment(AppModel.self) private var model
    @State private var customers: [Customer] = []

    var body: some View {
        @Bindable var model = model
        HSplitView {
            list
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 480, maxHeight: .infinity)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Customers")
        .searchable(text: $model.customerSearch, prompt: Text("Name, phone, or email"))
        .toolbar {
            ToolbarItem {
                Button("New Customer", systemImage: "person.badge.plus") { model.sheet = .newCustomer }
                    .help("Add a customer (⌘⇧N)")
            }
        }
        .task(id: "\(model.dataVersion) \(model.customerSearch)") {
            customers = model.read([]) { try $0.customers(matching: model.customerSearch) }
        }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var model = model
        if customers.isEmpty {
            if model.customerSearch.isEmpty {
                ContentUnavailableView {
                    Label("No Customers", systemImage: "person.2")
                } description: {
                    Text("Add the people who bring you devices.")
                } actions: {
                    Button("New Customer") { model.sheet = .newCustomer }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: model.customerSearch)
            }
        } else {
            List(customers, selection: $model.selectedCustomer) { customer in
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .help(customer.name)
                    if !customer.phone.isEmpty || !customer.email.isEmpty {
                        Text(customer.phone.isEmpty ? customer.email : customer.phone)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .tag(customer.id)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedCustomer {
            CustomerDetail(customerID: id).id(id)
        } else {
            ContentUnavailableView("No Customer Selected", systemImage: "person.2",
                                   description: Text("Select a customer to see their devices and notes."))
        }
    }
}

/// One customer: contact details, their devices, and their notes.
struct CustomerDetail: View {
    @Environment(AppModel.self) private var model
    let customerID: UUID
    @State private var customer: Customer?
    @State private var devices: [Device] = []

    var body: some View {
        Group {
            if let customer {
                Form {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text(customer.name)
                                .font(.title.weight(.semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Edit…") { model.sheet = .editCustomer(customer.id) }
                                .help("Change this customer's details")
                        }
                        if !customer.phone.isEmpty { LabeledContent("Phone") { Text(customer.phone).textSelection(.enabled) } }
                        if !customer.email.isEmpty { LabeledContent("Email") { Text(customer.email).textSelection(.enabled) } }
                        if !customer.address.isEmpty { LabeledContent("Address") { Text(customer.address).textSelection(.enabled) } }
                        LabeledContent("Documents language", value: customer.documentsLanguage.title)
                    }
                    Section {
                        if devices.isEmpty {
                            Text("No devices yet").foregroundStyle(.secondary)
                        }
                        ForEach(devices) { device in
                            Button {
                                model.open(.device(device.id))
                            } label: {
                                DeviceLine(device: device)
                            }
                            .buttonStyle(.plain)
                            .help("Open device \(device.title)")
                        }
                    } header: {
                        HStack {
                            Text("Devices")
                            Spacer()
                            Button("Add Device…") { model.sheet = .addDevice(customer: customer.id) }
                                .controlSize(.small)
                                .help("Add a device to this customer (⌘⇧D)")
                        }
                    }
                    Section("Photos and Files") {
                        AttachmentsSection(owner: .customer, ownerID: customer.id)
                    }
                    Section("Notes") {
                        Timeline(owner: .customer, ownerID: customer.id)
                    }
                }
                .formStyle(.grouped)
                .acceptsAttachments(owner: .customer, id: customer.id, model: model)
            } else {
                ContentUnavailableView("No Customer Selected", systemImage: "person.2")
            }
        }
        .task(id: model.dataVersion) {
            customer = model.read(nil) { try $0.customer(customerID) }
            devices = model.read([]) { try $0.devices(of: customerID) }
        }
    }
}

/// A device on one line: category icon, brand and model, and serial.
struct DeviceLine: View {
    let device: Device

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: device.category.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(device.category.title))
            Text(device.title)
                .lineLimit(1)
            Spacer()
            if !device.serial.isEmpty {
                Text(device.serial)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
