import BenchLogKit
import SwiftUI

/// Devices: every device with its customer and the status of its last repair.
struct DevicesPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [DeviceRow] = []
    @State private var shopRows: [ShopDeviceRow] = []

    var body: some View {
        @Bindable var model = model
        HSplitView {
            list
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 520, maxHeight: .infinity)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Devices")
        .searchable(text: $model.deviceSearch, prompt: Text("Model, serial, or customer"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Show", selection: $model.deviceScope) {
                    ForEach(DeviceScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Show every device, or the shop's own")
            }
        }
        .task(id: "\(model.dataVersion) \(model.deviceSearch)") {
            rows = model.read([]) { try $0.deviceRows(matching: model.deviceSearch) }
            shopRows = model.read([]) { try $0.shopDevices() }
        }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var model = model
        if model.deviceScope == .shop {
            shopList
        } else if rows.isEmpty {
            if model.deviceSearch.isEmpty {
                ContentUnavailableView {
                    Label("No Devices", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text("Devices appear here when you open a repair or add one to a customer.")
                } actions: {
                    Button("New Repair") { model.newRepair() }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: model.deviceSearch)
            }
        } else {
            List(rows, selection: $model.selectedDevice) { row in
                HStack(spacing: Space.sm) {
                    Image(systemName: row.device.category.symbol)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(row.device.category.title))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.device.title)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .help(row.device.title)
                        Text(row.customer.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.sm)
                    if let status = row.lastStatus { StatusPill(status: status) }
                }
                .padding(.vertical, 2)
                .tag(row.id)
                .contextMenu { Button("Move to Trash", role: .destructive) { model.moveToTrash(.device(row.id)) } }
            }
            .onDeleteCommand { model.trashFocused() }
        }
    }

    /// The shop's devices: to resell or keep, with what each cost and made.
    @ViewBuilder
    private var shopList: some View {
        @Bindable var model = model
        let search = model.deviceSearch.lowercased()
        let shown = search.isEmpty ? shopRows : shopRows.filter { $0.device.title.lowercased().contains(search) || $0.device.serial.lowercased().contains(search) }
        VStack(spacing: 0) {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No Shop Devices", systemImage: "building.2")
                } description: {
                    Text("Devices the shop buys to repair and resell, or keeps, appear here.")
                } actions: {
                    Button("Add Shop Device…") { addShopDevice() }.buttonStyle(.borderedProminent)
                }
            } else {
                List(shown, selection: $model.selectedDevice) { row in
                    ShopDeviceListRow(row: row).tag(row.id)
                        .contextMenu { Button("Move to Trash", role: .destructive) { model.moveToTrash(.device(row.id)) } }
                }
                .onDeleteCommand { model.trashFocused() }
                Divider()
                HStack {
                    Button("Add Shop Device…") { addShopDevice() }
                        .controlSize(.small)
                        .help("Add a device the shop owns")
                    Spacer()
                    let sold = shown.compactMap(\.profitCents)
                    if !sold.isEmpty {
                        Text("Profit on \(sold.count) sold: \(Money.text(sold.reduce(0, +)))")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Space.sm)
            }
        }
    }

    private func addShopDevice() {
        if let shop = model.shopOwner() { model.sheet = .addDevice(customer: shop.id) }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedDevice {
            DeviceDetail(deviceID: id).id(id)
        } else {
            ContentUnavailableView("No Device Selected", systemImage: "laptopcomputer.and.iphone",
                                   description: Text("Select a device to see its details and repair history."))
        }
    }
}

/// One device: what it is, whose it is, its passcode, its repairs, and its notes.
struct DeviceDetail: View {
    @Environment(AppModel.self) private var model
    let deviceID: UUID
    @State private var device: Device?
    @State private var customer: Customer?
    @State private var repairs: [Repair] = []

    var body: some View {
        Group {
            if let device {
                TwoColumnForm { wide in
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            Image(systemName: device.category.symbol)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text(device.category.title))
                            Text(device.title)
                                .font(.title.weight(.semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Edit…") { model.sheet = .editDevice(device.id) }
                                .help("Change this device's details")
                        }
                        if let customer {
                            if customer.isShop {
                                LabeledContent("Owner", value: String(localized: "The shop"))
                            } else {
                                LabeledContent("Customer") {
                                    Button(customer.name) { model.open(.customer(customer.id)) }
                                        .buttonStyle(.link)
                                        .help("Open customer \(customer.name)")
                                }
                            }
                        }
                        LabeledContent("Category", value: device.category.title)
                        if !device.serial.isEmpty { LabeledContent("Serial or IMEI") { Text(device.serial).monospaced().textSelection(.enabled) } }
                        if !device.colour.isEmpty { LabeledContent("Colour", value: device.colour) }
                        if !device.condition.isEmpty { LabeledContent("Condition") { Text(device.condition).textSelection(.enabled) } }
                        PasscodeView(passcode: device.passcode, isPattern: device.passcodeIsPattern)
                    } header: {
                        if wide { Text("Details") }
                    }
                    Section {
                        if repairs.isEmpty {
                            Text("No repairs yet").foregroundStyle(.secondary)
                        }
                        ForEach(repairs) { repair in
                            Button {
                                model.open(.repair(repair.id))
                            } label: {
                                HStack(spacing: Space.sm) {
                                    Text(repair.ticket.text).monospacedDigit()
                                    Text(repair.complaint).lineLimit(1).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(repair.receivedAt.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.secondary)
                                    StatusPill(status: repair.status)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open repair \(repair.ticket.text)")
                        }
                    } header: {
                        HStack {
                            Text("Repairs")
                            Spacer()
                            Button("New Repair…") { model.sheet = .newRepair(customer: device.customerId, device: device.id) }
                                .controlSize(.small)
                                .help("Open a repair for this device (⌘N)")
                        }
                    }
                    if customer?.isShop == true || device.disposition == .sold {
                        ShopSection(device: device).id("\(device.id) \(device.customerId)")
                    }
                } side: {
                    Section("Photos and Files") {
                        AttachmentsSection(owner: .device, ownerID: device.id)
                    }
                    Section("Notes") {
                        Timeline(owner: .device, ownerID: device.id)
                    }
                }
                .acceptsAttachments(owner: .device, id: device.id, model: model)
            } else {
                ContentUnavailableView("No Device Selected", systemImage: "laptopcomputer.and.iphone")
            }
        }
        .task(id: model.dataVersion) {
            device = model.read(nil) { try $0.device(deviceID) }
            customer = device.flatMap { device in model.read(nil) { try $0.customer(device.customerId) } }
            repairs = model.read([]) { try $0.repairs(of: deviceID) }
        }
    }
}
