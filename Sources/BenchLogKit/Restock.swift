import Foundation
import GRDB

/// Where a restock order is: being written, sent to the vendor, or on the shelf.
public enum RestockStatus: String, Codable, CaseIterable, Sendable {
    case draft, ordered, received
}

/// An order of stock from one vendor, for the shelf rather than for one repair.
public struct Restock: BenchRecord {
    public static let databaseTableName = "restock"

    public var id: UUID
    public var vendor: String
    public var status: RestockStatus
    public var orderedAt: Date?
    public var receivedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}

/// One part on a restock order, at the cost the vendor charges.
public struct RestockLine: BenchRecord {
    public static let databaseTableName = "restockLine"

    public var id: UUID
    public var restockId: UUID
    public var partId: UUID
    public var quantity: Int
    public var costCents: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}

/// A restock order with its lines and their parts, for the Restock tab.
public struct RestockOrder: Hashable, Sendable, Identifiable {
    public struct Line: Hashable, Sendable, Identifiable {
        public var line: RestockLine
        public var part: Part
        public var id: UUID { line.id }
    }

    public var restock: Restock
    public var lines: [Line]
    public var id: UUID { restock.id }

    /// The order's total at cost; lines with no cost count as zero.
    public var totalCents: Int { lines.reduce(0) { $0 + $1.line.quantity * ($1.line.costCents ?? 0) } }
    public var units: Int { lines.reduce(0) { $0 + $1.line.quantity } }
}

public enum RestockError: Error, Equatable {
    /// Only a draft can change; only a draft with lines can be ordered; only an ordered order can be received.
    case wrongStatus
    case empty
}

extension Library {
    /// How many to order so the part reaches twice its threshold (at least one).
    static func refillQuantity(_ part: Part) -> Int { max(1, part.lowStockThreshold * 2 - part.quantity) }

    /// Adds a part to its vendor's draft order (made if needed), or raises its quantity there.
    /// With no quantity, enough to reach twice its threshold. Returns the order.
    @discardableResult
    public func orderMore(_ partID: UUID, quantity: Int? = nil, now: Date = .now) throws -> UUID? {
        try db.write { db in try Self.orderMore(db, partID: partID, quantity: quantity, now: now) }
    }

    @discardableResult
    private static func orderMore(_ db: Database, partID: UUID, quantity: Int?, now: Date) throws -> UUID? {
        guard let part = try Part.fetchOne(db, key: partID.stored), part.deletedAt == nil else { return nil }
        let units = max(1, quantity ?? refillQuantity(part))
        var restock = try Restock.filter(Column("status") == RestockStatus.draft.rawValue && Column("deletedAt") == nil)
            .filter(Column("vendor") == part.vendor)
            .fetchOne(db)
        if restock == nil {
            restock = Restock(id: UUID(), vendor: part.vendor, status: .draft, createdAt: now, updatedAt: now)
            try restock!.insert(db)
        }
        let order = restock!
        if var line = try RestockLine.filter(Column("restockId") == order.id.stored && Column("partId") == partID.stored
                                             && Column("deletedAt") == nil).fetchOne(db) {
            line.quantity += units
            line.updatedAt = now
            try line.update(db)
        } else {
            try RestockLine(id: UUID(), restockId: order.id, partId: partID, quantity: units, costCents: part.costCents,
                            createdAt: now, updatedAt: now).insert(db)
        }
        return order.id
    }

    /// Puts every low part that is not already on a draft or ordered restock on its vendor's
    /// draft. Returns how many parts were added.
    @discardableResult
    public func addLowParts(now: Date = .now) throws -> Int {
        try db.write { db in
            let waiting = Set(try String.fetchAll(db, sql: """
                SELECT l.partId FROM restockLine l JOIN restock r ON r.id = l.restockId
                WHERE l.deletedAt IS NULL AND r.deletedAt IS NULL AND r.status IN ('draft', 'ordered')
                """))
            let low = try Part.filter(Column("deletedAt") == nil).fetchAll(db).filter { $0.isLow && !waiting.contains($0.id.stored) }
            for part in low { try Self.orderMore(db, partID: part.id, quantity: nil, now: now) }
            return low.count
        }
    }

    /// Changes a line on a draft: its quantity (zero removes it) and its cost.
    public func updateRestockLine(_ lineID: UUID, quantity: Int, costCents: Int?, now: Date = .now) throws {
        try db.write { db in
            guard var line = try RestockLine.fetchOne(db, key: lineID.stored) else { return }
            guard try Restock.fetchOne(db, key: line.restockId.stored)?.status == .draft else { throw RestockError.wrongStatus }
            line.quantity = max(0, quantity)
            line.costCents = costCents
            line.updatedAt = now
            if line.quantity == 0 { line.deletedAt = now }
            try line.update(db)
        }
    }

    /// Marks a draft as sent to the vendor.
    public func markOrdered(_ restockID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var restock = try Restock.fetchOne(db, key: restockID.stored) else { return }
            guard restock.status == .draft else { throw RestockError.wrongStatus }
            guard try RestockLine.filter(Column("restockId") == restockID.stored && Column("deletedAt") == nil).fetchCount(db) > 0
            else { throw RestockError.empty }
            restock.status = .ordered
            restock.orderedAt = now
            restock.updatedAt = now
            try restock.update(db)
        }
    }

    /// Puts an ordered restock on the shelf: each line goes into stock as Received, and each
    /// part's cost becomes what the line cost.
    public func receive(_ restockID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var restock = try Restock.fetchOne(db, key: restockID.stored) else { return }
            guard restock.status == .ordered else { throw RestockError.wrongStatus }
            let lines = try RestockLine.filter(Column("restockId") == restockID.stored && Column("deletedAt") == nil).fetchAll(db)
            for line in lines {
                if let cost = line.costCents, var part = try Part.fetchOne(db, key: line.partId.stored), part.costCents != cost {
                    part.costCents = cost
                    part.updatedAt = now
                    try part.update(db)
                }
                _ = try Self.moveStock(db, partID: line.partId, by: line.quantity, reason: .received,
                                       from: StockSource(restock: restockID), now: now)
            }
            restock.status = .received
            restock.receivedAt = now
            restock.updatedAt = now
            try restock.update(db)
        }
    }

    /// Throws away a draft, or cancels an order not yet received.
    public func discardRestock(_ restockID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var restock = try Restock.fetchOne(db, key: restockID.stored) else { return }
            guard restock.status != .received else { throw RestockError.wrongStatus }
            restock.deletedAt = now
            restock.updatedAt = now
            try restock.update(db)
        }
    }

    /// Drafts and orders on their way, then the last `received` orders received.
    public func restockOrders(received: Int = 10) throws -> [RestockOrder] {
        try db.read { db in
            let open = try Restock.filter(Column("deletedAt") == nil && Column("status") != RestockStatus.received.rawValue)
                .order(Column("status"), Column("vendor")).fetchAll(db)   // drafts first, then ordered
            let done = try Restock.filter(Column("deletedAt") == nil && Column("status") == RestockStatus.received.rawValue)
                .order(Column("receivedAt").desc).limit(received).fetchAll(db)
            return try (open + done).map { restock in
                let lines = try RestockLine.filter(Column("restockId") == restock.id.stored && Column("deletedAt") == nil)
                    .order(Column("createdAt")).fetchAll(db)
                let parts = try Part.fetchAll(db, keys: lines.map(\.partId.stored))
                let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                return RestockOrder(restock: restock, lines: lines.compactMap { line in
                    byID[line.partId].map { RestockOrder.Line(line: line, part: $0) }
                })
            }
        }
    }

    /// Units of a part ordered and on their way, for its page.
    public func unitsOnOrder(_ partID: UUID) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(l.quantity), 0) FROM restockLine l JOIN restock r ON r.id = l.restockId
                WHERE l.partId = ? AND l.deletedAt IS NULL AND r.deletedAt IS NULL AND r.status = 'ordered'
                """, arguments: [partID.stored]) ?? 0
        }
    }
}
