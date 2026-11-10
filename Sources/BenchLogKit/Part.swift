import Foundation
import GRDB

/// What a part is, for the inventory's icons and filter.
public enum PartKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case part, accessory, cable, controller, game, supply
    public var id: String { rawValue }
}

/// The state a part is sold in.
public enum PartCondition: String, Codable, CaseIterable, Sendable, Identifiable {
    case new, used, refurbished
    public var id: String { rawValue }
}

/// A part kept in stock.
public struct Part: BenchRecord {
    public static let databaseTableName = "part"

    public var id: UUID
    public var name: String
    public var sku: String
    public var vendor: String
    public var url: String
    public var costCents: Int?
    public var priceCents: Int?
    public var quantity: Int
    public var lowStockThreshold: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var kind: PartKind = .part
    /// Nil when it does not matter (a new component from a vendor).
    public var condition: PartCondition?
    /// Where it sits in the shop: a shelf, a bin, a drawer.
    public var location: String = ""
    public var notes: String = ""
    /// The UPC or EAN on the box, digits only; '' when it has none.
    public var barcode: String = ""

    public init(id: UUID = UUID(), name: String, sku: String = "", vendor: String = "", url: String = "",
                costCents: Int? = nil, priceCents: Int? = nil, quantity: Int = 0, lowStockThreshold: Int = 0,
                kind: PartKind = .part, condition: PartCondition? = nil, location: String = "", notes: String = "",
                barcode: String = "", now: Date = .now) {
        self.barcode = barcode
        self.kind = kind
        self.condition = condition
        self.location = location
        self.notes = notes
        self.id = id
        self.name = name
        self.sku = sku
        self.vendor = vendor
        self.url = url
        self.costCents = costCents
        self.priceCents = priceCents
        self.quantity = quantity
        self.lowStockThreshold = lowStockThreshold
        createdAt = now
        updatedAt = now
    }

    /// Price less cost for one, when both are known.
    public var marginCents: Int? {
        guard let costCents, let priceCents else { return nil }
        return priceCents - costCents
    }

    /// At or below its threshold. A part with no threshold is never low.
    public var isLow: Bool { lowStockThreshold > 0 && quantity <= lowStockThreshold }
}

/// A catalog model a part fits.
public struct PartFit: Hashable, Sendable, Codable {
    public var category: DeviceCategory
    public var brand: String
    public var model: String

    public init(category: DeviceCategory, brand: String, model: String) {
        self.category = category
        self.brand = brand
        self.model = model
    }

    public var title: String { "\(brand) \(model)" }
}

/// Where a part for a repair is.
public enum PartUseStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case needed, ordered, received, installed
    public var id: String { rawValue }
    /// Needed and Ordered mean the repair waits on it.
    public var isMissing: Bool { self == .needed || self == .ordered }
}

/// A part on a repair: from stock (`partId`) or typed in (no `partId`).
public struct PartUse: BenchRecord {
    public static let databaseTableName = "partUse"

    public var id: UUID
    public var repairId: UUID
    public var partId: UUID?
    public var name: String
    public var vendor: String
    public var quantity: Int
    public var status: PartUseStatus
    public var costCents: Int?
    /// What the customer is charged for one; starts at the part's price.
    public var priceCents: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}

/// A repair a stocked part is on, for the part's details.
public struct PartRepairRow: Hashable, Sendable, Identifiable {
    public var use: PartUse
    public var ticketNumber: Int
    public var customerName: String
    public var deviceTitle: String
    public var repairStatus: RepairStatus
    public var id: UUID { use.id }
}

/// A part on a repair, with the repair's ticket and customer, for To Order and Incoming.
public struct PartUseRow: Hashable, Sendable, Identifiable {
    public var use: PartUse
    public var ticketNumber: Int
    public var customerName: String
    public var deviceTitle: String
    public var id: UUID { use.id }
}

extension Library {
    // MARK: Inventory

    /// Parts sorted by name. `search` matches the name, SKU, vendor, or location.
    public func parts(matching search: String = "", lowOnly: Bool = false, kind: PartKind? = nil) throws -> [Part] {
        try db.read { db in
            var request = Part.filter(Column("deletedAt") == nil)
            let text = search.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                request = request.filter(Column("name").like("%\(text)%") || Column("sku").like("%\(text)%") || Column("vendor").like("%\(text)%")
                                         || Column("location").like("%\(text)%") || Column("barcode").like("%\(text)%"))
            }
            if let kind { request = request.filter(Column("kind") == kind.rawValue) }
            if lowOnly {
                request = request.filter(Column("lowStockThreshold") > 0 && Column("quantity") <= Column("lowStockThreshold"))
            }
            return try request.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }
    }

    public func part(_ id: UUID) throws -> Part? {
        try db.read { try Part.fetchOne($0, key: id.stored) }
    }

    /// The part with this barcode (a 12-digit UPC and its 13-digit EAN are the same code).
    public func part(barcode: String) throws -> Part? {
        guard let code = BarcodeLookup.normalized(barcode) else { return nil }
        return try db.read { db in
            try Part.filter(Column("deletedAt") == nil && [code, "0" + code].contains(Column("barcode")))
                .order(Column("createdAt")).fetchOne(db)
        }
    }

    /// One more unit of a scanned part goes on the shelf, recorded as received.
    public func receiveScanned(_ partID: UUID, now: Date = .now) throws {
        try db.write { db in
            _ = try Self.moveStock(db, partID: partID, by: 1, reason: .received, from: StockSource(note: "Barcode"), now: now)
        }
    }

    public func lowStockCount() throws -> Int {
        try parts(lowOnly: true).count
    }

    /// Adds or updates a part and replaces the models it fits.
    @discardableResult
    public func save(_ part: Part, fits: [PartFit], now: Date = .now) throws -> Part {
        var part = part
        part.barcode = BarcodeLookup.normalized(part.barcode) ?? ""
        part.quantity = max(0, part.quantity)
        part.updatedAt = now
        try db.write { db in
            let old = try Part.fetchOne(db, key: part.id.stored)
            try part.save(db)
            // A new part opens its stock history; a changed count is recorded as adjusted.
            let delta = part.quantity - (old?.quantity ?? 0)
            if delta != 0 {
                try StockMove(id: UUID(), partId: part.id, delta: delta, quantityAfter: part.quantity,
                              reason: old == nil ? .opening : .adjusted, repairId: nil, invoiceId: nil, restockId: nil,
                              note: "", createdAt: now, updatedAt: now, deletedAt: nil).insert(db)
            }
            try db.execute(sql: "DELETE FROM partFit WHERE partId = ?", arguments: [part.id.stored])
            for fit in Set(fits) {
                try db.execute(sql: "INSERT INTO partFit VALUES (?, ?, ?, ?)",
                               arguments: [part.id.stored, fit.category.rawValue, fit.brand, fit.model])
            }
        }
        return part
    }

    public func fits(of partID: UUID) throws -> [PartFit] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT category, brand, model FROM partFit WHERE partId = ? ORDER BY brand, model",
                             arguments: [partID.stored]).compactMap { row in
                DeviceCategory(rawValue: row["category"]).map { PartFit(category: $0, brand: row["brand"], model: row["model"]) }
            }
        }
    }

    /// Parts for a repair's search: the ones that fit the device's model first, then the rest.
    public func parts(for device: Device, matching search: String = "") throws -> (fitting: [Part], others: [Part]) {
        let all = try parts(matching: search)
        let fitting = try db.read { db in
            try Set(String.fetchAll(db, sql: """
                SELECT partId FROM partFit WHERE category = ? AND brand = ? COLLATE NOCASE AND model = ? COLLATE NOCASE
                """, arguments: [device.category.rawValue, device.brand, device.model]))
        }
        return (all.filter { fitting.contains($0.id.stored) }, all.filter { !fitting.contains($0.id.stored) })
    }

    /// Changes the stock count by `delta` (never below zero), recorded as adjusted.
    public func adjustStock(of partID: UUID, by delta: Int, now: Date = .now) throws {
        try db.write { db in _ = try Self.moveStock(db, partID: partID, by: delta, reason: .adjusted, now: now) }
    }

    // MARK: Parts on repairs

    /// Adds a stocked part to a repair. It starts Received when enough is in stock, else Needed.
    @discardableResult
    public func usePart(_ partID: UUID, on repairID: UUID, quantity: Int = 1, now: Date = .now) throws -> PartUse {
        try db.write { db in
            guard let part = try Part.fetchOne(db, key: partID.stored) else { throw DatabaseError(message: "No such part") }
            let use = PartUse(id: UUID(), repairId: repairID, partId: partID, name: part.name, vendor: part.vendor,
                              quantity: quantity, status: part.quantity >= quantity ? .received : .needed,
                              costCents: part.costCents, priceCents: part.priceCents,
                              createdAt: now, updatedAt: now, deletedAt: nil)
            try use.insert(db)
            return use
        }
    }

    /// Adds a part typed in by name (not kept in stock). It starts Needed.
    @discardableResult
    public func useFreePart(_ name: String, on repairID: UUID, quantity: Int = 1, vendor: String = "",
                            priceCents: Int? = nil, now: Date = .now) throws -> PartUse {
        let use = PartUse(id: UUID(), repairId: repairID, partId: nil, name: name.trimmingCharacters(in: .whitespaces),
                          vendor: vendor, quantity: quantity, status: .needed, costCents: nil, priceCents: priceCents,
                          createdAt: now, updatedAt: now, deletedAt: nil)
        try db.write { try use.insert($0) }
        return use
    }

    public func partUses(on repairID: UUID) throws -> [PartUse] {
        try db.read { db in
            try PartUse.filter(Column("repairId") == repairID.stored && Column("deletedAt") == nil)
                .order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
    }

    /// Changes a part's status on a repair. Installing a stocked part takes it out of stock;
    /// moving it back from Installed puts it back.
    public func setStatus(_ status: PartUseStatus, ofUse useID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var use = try PartUse.fetchOne(db, key: useID.stored), use.status != status else { return }
            if let partID = use.partId {
                let source = StockSource(repair: use.repairId)
                if status == .installed { try Self.moveStock(db, partID: partID, by: -use.quantity, reason: .installed, from: source, now: now) }
                if use.status == .installed { try Self.moveStock(db, partID: partID, by: use.quantity, reason: .returned, from: source, now: now) }
            }
            use.status = status
            use.updatedAt = now
            try use.update(db)
        }
    }

    /// Saves the quantity and price of a part on a repair, keeping stock right for an installed part.
    public func update(_ use: PartUse, now: Date = .now) throws {
        try db.write { db in
            guard let old = try PartUse.fetchOne(db, key: use.id.stored) else { return }
            if let partID = use.partId, old.status == .installed, old.quantity != use.quantity {
                let delta = old.quantity - use.quantity
                try Self.moveStock(db, partID: partID, by: delta, reason: delta < 0 ? .installed : .returned,
                                   from: StockSource(repair: use.repairId), now: now)
            }
            var use = use
            use.updatedAt = now
            try use.update(db)
        }
    }

    /// Takes a part off a repair (to the trash). An installed stocked part goes back in stock.
    public func removeUse(_ useID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var use = try PartUse.fetchOne(db, key: useID.stored) else { return }
            if let partID = use.partId, use.status == .installed {
                try Self.moveStock(db, partID: partID, by: use.quantity, reason: .returned, from: StockSource(repair: use.repairId), now: now)
            }
            use.deletedAt = now
            use.updatedAt = now
            try use.update(db)
        }
    }

    /// The repairs a stocked part is on, newest first.
    public func repairs(usingPart partID: UUID) throws -> [PartRepairRow] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT partUse.id AS useId, repair.ticketNumber, repair.status, customer.name AS customerName,
                       device.brand || ' ' || device.model AS deviceTitle
                FROM partUse
                JOIN repair ON repair.id = partUse.repairId
                JOIN device ON device.id = repair.deviceId
                JOIN customer ON customer.id = device.customerId
                WHERE partUse.partId = ? AND partUse.deletedAt IS NULL AND repair.deletedAt IS NULL
                ORDER BY repair.receivedAt DESC, partUse.createdAt DESC
                """, arguments: [partID.stored]).compactMap { row in
                guard let use = try PartUse.fetchOne(db, key: row["useId"] as String),
                      let status = RepairStatus(rawValue: row["status"]) else { return nil }
                return PartRepairRow(use: use, ticketNumber: row["ticketNumber"], customerName: row["customerName"],
                                     deviceTitle: row["deviceTitle"], repairStatus: status)
            }
        }
    }

    /// True when a part on the repair is Needed or Ordered.
    public func isWaitingOnParts(_ repairID: UUID) throws -> Bool {
        try partUses(on: repairID).contains { $0.status.isMissing }
    }

    /// Parts with these statuses across open repairs, oldest first: To Order (needed), Incoming (ordered).
    public func partUseRows(_ status: PartUseStatus) throws -> [PartUseRow] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT partUse.id AS useId, repair.ticketNumber, customer.name AS customerName,
                       device.brand || ' ' || device.model AS deviceTitle
                FROM partUse
                JOIN repair ON repair.id = partUse.repairId
                JOIN device ON device.id = repair.deviceId
                JOIN customer ON customer.id = device.customerId
                WHERE partUse.status = ? AND partUse.deletedAt IS NULL AND repair.deletedAt IS NULL
                  AND repair.status NOT IN ('pickedUp', 'cancelled')
                ORDER BY partUse.createdAt
                """, arguments: [status.rawValue]).compactMap { row in
                guard let use = try PartUse.fetchOne(db, key: row["useId"] as String) else { return nil }
                return PartUseRow(use: use, ticketNumber: row["ticketNumber"], customerName: row["customerName"],
                                  deviceTitle: row["deviceTitle"])
            }
        }
    }
}
