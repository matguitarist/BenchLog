import Foundation
import GRDB

/// Why a part's stock changed.
public enum StockReason: String, Codable, CaseIterable, Sendable {
    /// What was on the shelf when the part was added, or when stock history began.
    case opening
    /// Installed on a repair, or put back when it no longer is.
    case installed, returned
    /// Arrived with a restock order.
    case received
    /// Set to what was counted on the shelf.
    case counted
    /// Taken out broken or lost.
    case damaged
    /// Sold over the counter.
    case sold
    /// Changed by hand in the part's details.
    case adjusted
}

/// One change to a part's stock. A part's quantity is the sum of its moves.
public struct StockMove: BenchRecord {
    public static let databaseTableName = "stockMove"

    public var id: UUID
    public var partId: UUID
    /// Units added (positive) or taken out (negative).
    public var delta: Int
    /// The quantity after this move.
    public var quantityAfter: Int
    public var reason: StockReason
    public var repairId: UUID?
    public var invoiceId: UUID?
    public var restockId: UUID?
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}

/// A stock move with what it came from, for the part's history.
public struct StockMoveRow: Hashable, Sendable, Identifiable {
    public var move: StockMove
    /// "#0042" for a repair, "F-0007" for a sale.
    public var source: String?
    public var id: UUID { move.id }
}

/// Where a stock change comes from.
public struct StockSource: Sendable {
    public var repairId: UUID?
    public var invoiceId: UUID?
    public var restockId: UUID?
    public var note: String

    public init(repair: UUID? = nil, invoice: UUID? = nil, restock: UUID? = nil, note: String = "") {
        repairId = repair
        invoiceId = invoice
        restockId = restock
        self.note = note
    }
}

extension Library {
    /// Changes a part's stock (never below zero) and records why. Returns the units that
    /// actually moved.
    @discardableResult
    static func moveStock(_ db: Database, partID: UUID, by delta: Int, reason: StockReason,
                          from source: StockSource = StockSource(), now: Date) throws -> Int {
        guard var part = try Part.fetchOne(db, key: partID.stored) else { return 0 }
        let after = max(0, part.quantity + delta)
        let moved = after - part.quantity
        guard moved != 0 else { return 0 }
        part.quantity = after
        part.updatedAt = now
        try part.update(db)
        try StockMove(id: UUID(), partId: partID, delta: moved, quantityAfter: after, reason: reason,
                      repairId: source.repairId, invoiceId: source.invoiceId, restockId: source.restockId,
                      note: source.note, createdAt: now, updatedAt: now, deletedAt: nil).insert(db)
        return moved
    }

    /// Sets the stock to what was counted on the shelf; the difference is recorded.
    public func count(_ partID: UUID, counted: Int, note: String = "", now: Date = .now) throws {
        try db.write { db in
            guard let part = try Part.fetchOne(db, key: partID.stored) else { return }
            try Self.moveStock(db, partID: partID, by: max(0, counted) - part.quantity, reason: .counted,
                               from: StockSource(note: note), now: now)
        }
    }

    /// Takes broken or lost units out of stock.
    public func removeDamaged(_ partID: UUID, quantity: Int, note: String = "", now: Date = .now) throws {
        try db.write { db in
            _ = try Self.moveStock(db, partID: partID, by: -abs(quantity), reason: .damaged, from: StockSource(note: note), now: now)
        }
    }

    /// A part's stock moves, newest first, with the ticket or invoice each came from.
    public func stockHistory(of partID: UUID) throws -> [StockMoveRow] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id, r.ticketNumber, i.kind, i.number, i.creditNumber
                FROM stockMove m
                LEFT JOIN repair r ON r.id = m.repairId
                LEFT JOIN invoice i ON i.id = m.invoiceId
                WHERE m.partId = ? AND m.deletedAt IS NULL
                ORDER BY m.createdAt DESC, m.rowid DESC
                """, arguments: [partID.stored]).compactMap { row in
                guard let move = try StockMove.fetchOne(db, key: row["id"] as String) else { return nil }
                var source: String?
                if let ticket = row["ticketNumber"] as Int? { source = TicketNumber(ticket).text }
                if let number = row["number"] as Int? { source = "F-" + String(format: "%04d", number) }
                if let number = row["creditNumber"] as Int? { source = "NC-" + String(format: "%04d", number) }
                return StockMoveRow(move: move, source: source)
            }
        }
    }
}
