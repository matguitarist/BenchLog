import Foundation
import GRDB

/// What became of a device the shop owns.
public enum Disposition: String, Codable, CaseIterable, Sendable, Identifiable {
    case forSale, kept, sold
    public var id: String { rawValue }
}

/// What an internal job costs the shop: parts at cost and the hours spent. No taxes, no price.
public struct InternalCost: Hashable, Sendable {
    public var partsCents: Int
    public var hundredthHours: Int
    /// Parts with no cost entered; they are left out of `partsCents`.
    public var uncostedParts: [String]
}

/// A shop device with what it cost and what it made.
public struct ShopDeviceRow: Hashable, Sendable, Identifiable {
    public var device: Device
    /// The buyer, once sold to a customer.
    public var buyer: Customer?
    /// Purchase + parts at cost on its internal repairs.
    public var costCents: Int
    public var hundredthHours: Int
    public var id: UUID { device.id }

    /// Sale price − cost, once sold; an asking price is not a profit yet.
    public var profitCents: Int? {
        guard device.disposition == .sold else { return nil }
        return device.salePriceCents.map { $0 - costCents }
    }
}

public enum ShopError: LocalizedError {
    case internalJob

    public var errorDescription: String? {
        switch self {
        case .internalJob: String(localized: "An internal job has no estimate or invoice.")
        }
    }
}

extension Library {
    /// The shop as an owner, made the first time it is needed, with the business's name.
    public func shop(named name: String, now: Date = .now) throws -> Customer {
        try db.write { db in
            if var shop = try Customer.filter(Column("isShop") == true).fetchOne(db) {
                if shop.name != name, !name.isEmpty {
                    shop.name = name
                    shop.updatedAt = now
                    try shop.update(db)
                }
                return shop
            }
            var shop = Customer(name: name.isEmpty ? "Shop" : name, now: now)
            shop.isShop = true
            try shop.insert(db)
            return shop
        }
    }

    /// The shop, if it exists yet.
    public func existingShop() throws -> Customer? {
        try db.read { try Customer.filter(Column("isShop") == true).fetchOne($0) }
    }

    /// True when the repair is on a device the shop owns.
    public func isInternal(_ repairID: UUID) throws -> Bool {
        try db.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT c.isShop FROM repair r JOIN device d ON d.id = r.deviceId JOIN customer c ON c.id = d.customerId
                WHERE r.id = ?
                """, arguments: [repairID.stored]) ?? false
        }
    }

    /// Parts at cost and hours spent on an internal job.
    public func internalCost(of repairID: UUID) throws -> InternalCost {
        let uses = try partUses(on: repairID)
        let costed = uses.filter { $0.costCents != nil }
        let hours = try labourLines(on: repairID).filter { $0.kind == .hourly }.reduce(0) { $0 + $1.hundredthHours }
        return InternalCost(partsCents: costed.reduce(0) { $0 + ($1.costCents ?? 0) * $1.quantity },
                            hundredthHours: hours,
                            uncostedParts: uses.filter { $0.costCents == nil }.map(\.name))
    }

    /// Every device the shop owns, and the ones it sold, newest first.
    public func shopDevices() throws -> [ShopDeviceRow] {
        guard let shop = try existingShop() else { return [] }
        let devices = try db.read { db in
            try Device.filter(Column("deletedAt") == nil)
                .filter(Column("customerId") == shop.id.stored || Column("disposition") == Disposition.sold.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        return try devices.map { device in
            // Only the work done while the shop owned it counts.
            let repairs = try self.repairs(of: device.id).filter { repair in
                device.soldAt.map { repair.receivedAt <= $0 } ?? true
            }
            let costs = try repairs.map { try internalCost(of: $0.id) }
            let buyer = device.customerId == shop.id ? nil : try customer(device.customerId)
            return ShopDeviceRow(device: device, buyer: buyer,
                                 costCents: (device.purchaseCents ?? 0) + costs.reduce(0) { $0 + $1.partsCents },
                                 hundredthHours: costs.reduce(0) { $0 + $1.hundredthHours })
        }
    }

    /// Keeps, puts up for sale, or sells a shop device. Selling to a customer moves the
    /// device to them, so later repairs are theirs.
    public func setDisposition(_ disposition: Disposition?, priceCents: Int? = nil, buyer: UUID? = nil,
                               of deviceID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var device = try Device.fetchOne(db, key: deviceID.stored) else { return }
            device.disposition = disposition
            device.salePriceCents = disposition == .sold || disposition == .forSale ? priceCents : nil
            device.soldAt = disposition == .sold ? (device.soldAt ?? now) : nil
            if disposition == .sold, let buyer { device.customerId = buyer }
            if disposition != .sold, let shop = try Customer.filter(Column("isShop") == true).fetchOne(db) {
                device.customerId = shop.id
            }
            device.updatedAt = now
            try device.update(db)
        }
    }

    /// What the shop paid for a device.
    public func setPurchase(_ cents: Int?, of deviceID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var device = try Device.fetchOne(db, key: deviceID.stored) else { return }
            device.purchaseCents = cents
            device.updatedAt = now
            try device.update(db)
        }
    }
}
