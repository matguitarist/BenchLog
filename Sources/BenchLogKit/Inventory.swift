import Foundation
import GRDB

/// What the stock is worth: parts at cost (and at price), and the shop devices in stock or
/// for sale at what they cost.
public struct InventoryValue: Hashable, Sendable {
    public var partsCostCents = 0
    public var partsPriceCents = 0
    public var units = 0
    /// Parts in stock with no cost: they count as zero.
    public var partsWithoutCost = 0
    public var devicesCostCents = 0
    public var devices = 0

    public init() {}

    public var totalCents: Int { partsCostCents + devicesCostCents }
}

extension Library {
    /// The inventory's value now, or at the start of `date` (for the end of a period). At a
    /// past date, each part's quantity comes from its stock moves; costs are today's.
    public func inventoryValue(at date: Date? = nil) throws -> InventoryValue {
        var value = InventoryValue()
        try db.read { db in
            let parts = try Part.fetchAll(db).filter { part in
                guard let date else { return part.deletedAt == nil }
                return part.createdAt < date && (part.deletedAt.map { $0 >= date } ?? true)
            }
            var quantities: [String: Int] = [:]
            if let date {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT m.partId, m.quantityAfter FROM stockMove m
                    WHERE m.deletedAt IS NULL AND m.createdAt < ?1 AND m.rowid = (
                        SELECT m2.rowid FROM stockMove m2 WHERE m2.partId = m.partId AND m2.deletedAt IS NULL AND m2.createdAt < ?1
                        ORDER BY m2.createdAt DESC, m2.rowid DESC LIMIT 1)
                    """, arguments: [date])
                for row in rows { quantities[row["partId"]] = row["quantityAfter"] }
            }
            for part in parts {
                let quantity = date == nil ? part.quantity : quantities[part.id.stored] ?? 0
                guard quantity > 0 else { continue }
                value.units += quantity
                value.partsCostCents += quantity * (part.costCents ?? 0)
                value.partsPriceCents += quantity * (part.priceCents ?? part.costCents ?? 0)
                if part.costCents == nil { value.partsWithoutCost += 1 }
            }
        }
        for row in try shopDevices() {
            let device = row.device
            let held: Bool
            if let date {
                held = device.createdAt < date && (device.disposition != .kept)
                    && (device.disposition != .sold || (device.soldAt.map { $0 >= date } ?? false))
            } else {
                held = device.disposition == nil || device.disposition == .forSale
            }
            guard held else { continue }
            value.devices += 1
            value.devicesCostCents += row.costCents
        }
        return value
    }
}
