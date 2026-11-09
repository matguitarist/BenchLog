import BenchLogKit
import SwiftUI

/// The Devices page shows every device, or only the shop's.
enum DeviceScope: String, CaseIterable, Identifiable {
    case all, shop
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All Devices")
        case .shop: String(localized: "Shop")
        }
    }
}

extension Disposition {
    var title: String {
        switch self {
        case .forSale: String(localized: "For Sale")
        case .kept: String(localized: "Kept")
        case .sold: String(localized: "Sold")
        }
    }

    var symbol: String {
        switch self {
        case .forSale: "tag"
        case .kept: "house"
        case .sold: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .forSale: .blue
        case .kept: .secondary
        case .sold: .green
        }
    }
}

/// One shop device in the list: what it is, its state, its cost, and its price or profit.
struct ShopDeviceListRow: View {
    let row: ShopDeviceRow

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: row.device.category.symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(row.device.category.title))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.device.title).fontWeight(.medium).lineLimit(1).help(row.device.title)
                Text("Cost \(Money.text(row.costCents))").foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: 2) {
                DispositionLabel(disposition: row.device.disposition)
                if let profit = row.profitCents {
                    Text(profit >= 0 ? "Profit \(Money.text(profit))" : "Loss \(Money.text(-profit))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(profit >= 0 ? .green : .red)
                } else if let price = row.device.salePriceCents {
                    Text("Asking \(Money.text(price))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// "In Stock", "For Sale", "Kept", or "Sold": symbol and words.
struct DispositionLabel: View {
    let disposition: Disposition?

    var body: some View {
        Label(disposition?.title ?? String(localized: "In Stock"), systemImage: disposition?.symbol ?? "shippingbox")
            .font(.caption.weight(.medium))
            .foregroundStyle(disposition?.color ?? .secondary)
    }
}

/// On a shop device: what the shop paid, what became of it, and the cost and profit.
struct ShopSection: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var purchase: Decimal?
    @State private var disposition: Disposition?
    @State private var price: Decimal?
    @State private var buyer: UUID?
    @State private var row: ShopDeviceRow?

    var body: some View {
        Section("Shop") {
            LabeledContent("Paid") {
                TextField("Paid", value: $purchase, format: Money.format, prompt: Text(Money.text(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .onSubmit { model.setPurchase(Money.cents(purchase), of: device.id) }
                    .help("What the shop paid for this device")
            }
            Picker("State", selection: $disposition) {
                Text("In Stock").tag(Disposition?.none)
                ForEach(Disposition.allCases) { Text($0.title).tag(Disposition?.some($0)) }
            }
            if disposition == .forSale || disposition == .sold {
                LabeledContent(disposition == .sold ? "Sold for" : "Asking") {
                    TextField("Price", value: $price, format: Money.format, prompt: Text(Money.text(0)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .onSubmit(saveDisposition)
                }
            }
            if disposition == .sold {
                Picker("Buyer", selection: $buyer) {
                    Text("No buyer on file").tag(UUID?.none)
                    ForEach(model.read([]) { try $0.customers() }) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
                .help("Selling to a customer moves the device to them; later repairs are theirs")
            }
            if let row {
                LabeledContent("Cost") {
                    Text(Money.text(row.costCents)).monospacedDigit()
                }
                .help("What the shop paid, plus the parts at cost on its internal jobs")
                if let profit = row.profitCents {
                    LabeledContent(profit >= 0 ? "Profit" : "Loss") {
                        Text(Money.text(abs(profit))).monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(profit >= 0 ? .green : .red)
                    }
                }
            }
        }
        .onAppear {
            purchase = Money.decimal(device.purchaseCents)
            disposition = device.disposition
            price = Money.decimal(device.salePriceCents)
            buyer = device.disposition == .sold && model.read(nil, { try $0.existingShop() })?.id != device.customerId ? device.customerId : nil
        }
        .onChange(of: disposition) { saveDisposition() }
        .onChange(of: buyer) { saveDisposition() }
        .task(id: model.dataVersion) {
            row = model.read([]) { try $0.shopDevices() }.first { $0.id == device.id }
        }
    }

    private func saveDisposition() {
        let cents = Money.cents(price)
        guard disposition != device.disposition || cents != device.salePriceCents
            || (disposition == .sold && buyer != nil && buyer != device.customerId) else { return }
        model.setDisposition(disposition, priceCents: cents, buyer: buyer, of: device.id)
    }
}
