import Foundation
import GRDB

/// Something that can go to the Trash on its own. Its children go with it: a customer's
/// devices, a device's repairs, and the notes and files on each.
public enum TrashItem: Hashable, Sendable {
    case customer(UUID), device(UUID), repair(UUID), part(UUID), guide(UUID)
}

public enum TrashError: LocalizedError, Equatable {
    /// Invoices are tax records: a repair with one stays.
    case hasInvoices([String])
    case isShop

    public var errorDescription: String? {
        switch self {
        case .hasInvoices(let numbers):
            String(localized: "Unable to move to the Trash: invoice \(numbers.joined(separator: ", ")) must be kept for your records.")
        case .isShop:
            String(localized: "The shop cannot be moved to the Trash.")
        }
    }
}

extension Library {
    /// How long a row stays in the Trash before Empty Trash removes it.
    public static let trashDays = 30

    /// Every foreign key Empty Trash deletes or clears before the row it points at goes.
    /// A new table that points at a customer, device, repair, part, guide, or attachment
    /// must be handled in `emptyTrash` and listed here; TrashTests fails until it is.
    static let purgedReferences: Set<String> = [
        "device.customerId", "repair.deviceId",
        "partUse.repairId", "partUse.partId", "labourLine.repairId", "invoice.repairId",
        "partFit.partId", "guideLink.guideId", "guide.fileId", "invoice.fileId",
    ]

    /// Repairs not yet Picked Up across a customer's devices.
    public func openRepairCount(ofCustomer id: UUID) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM repair r JOIN device d ON d.id = r.deviceId
                WHERE d.customerId = ? AND r.deletedAt IS NULL AND d.deletedAt IS NULL AND r.status <> ?
                """, arguments: [id.stored, RepairStatus.pickedUp.rawValue]) ?? 0
        }
    }

    /// Moves the item and its children to the Trash, all with the same time, and returns it:
    /// `putBack` brings back exactly what went with it. Children already in the Trash keep
    /// their own time, so they stay there.
    @discardableResult
    public func moveToTrash(_ item: TrashItem, now: Date = .now) throws -> Date {
        try db.write { db in
            let scope = try Self.scope(of: item, db)
            if scope.isShop { throw TrashError.isShop }
            let invoiced = try String.fetchAll(db, sql: """
                SELECT printf('F-%04d', number) FROM invoice
                WHERE kind = 'invoice' AND repairId IN (\(Self.list(scope.repairs))) ORDER BY number
                """)
            if !invoiced.isEmpty { throw TrashError.hasInvoices(invoiced) }
            try Self.stamp(scope, set: now, where: "deletedAt IS NULL", db)
            return now
        }
    }

    /// Takes the item and what went with it out of the Trash.
    public func putBack(_ item: TrashItem, trashedAt: Date, now: Date = .now) throws {
        try db.write { db in
            try Self.stamp(try Self.scope(of: item, db), set: nil, where: "deletedAt = ?", matching: trashedAt, updatedAt: now, db)
        }
    }

    /// Rows in the Trash for longer than `days`: customers, devices, repairs, parts, guides,
    /// notes, and files.
    public func trashCount(olderThan days: Int = trashDays, now: Date = .now) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return try db.read { try Self.count(olderThan: cutoff, $0) }
    }

    /// Deletes for good what has been in the Trash longer than `days`, with its files.
    /// Returns how many rows went.
    @discardableResult
    public func emptyTrash(olderThan days: Int = trashDays, now: Date = .now) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var paths: [String] = []
        let removed = try db.write { db -> Int in
            let before = try Self.count(olderThan: cutoff, db)
            // Repairs and what hangs off them. A repair with an invoice never gets here.
            let repairs = try String.fetchAll(db, sql: """
                SELECT id FROM repair WHERE deletedAt < ?
                AND NOT EXISTS (SELECT 1 FROM invoice WHERE repairId = repair.id AND kind = 'invoice')
                """, arguments: [cutoff])
            paths += try Self.deleteOwned(by: "repair", repairs, db)
            try db.execute(sql: """
                DELETE FROM invoice WHERE repairId IN (\(Self.list(repairs)));
                DELETE FROM partUse WHERE repairId IN (\(Self.list(repairs)));
                DELETE FROM labourLine WHERE repairId IN (\(Self.list(repairs)));
                DELETE FROM repair WHERE id IN (\(Self.list(repairs)));
                """)
            // Devices and customers, once nothing points at them.
            let devices = try String.fetchAll(db, sql: """
                SELECT id FROM device WHERE deletedAt < ? AND NOT EXISTS (SELECT 1 FROM repair WHERE deviceId = device.id)
                """, arguments: [cutoff])
            paths += try Self.deleteOwned(by: "device", devices, db)
            try db.execute(sql: "DELETE FROM device WHERE id IN (\(Self.list(devices)))")
            let customers = try String.fetchAll(db, sql: """
                SELECT id FROM customer WHERE deletedAt < ? AND isShop = 0
                AND NOT EXISTS (SELECT 1 FROM device WHERE customerId = customer.id)
                """, arguments: [cutoff])
            paths += try Self.deleteOwned(by: "customer", customers, db)
            try db.execute(sql: "DELETE FROM customer WHERE id IN (\(Self.list(customers)))")
            // Parts: repairs that used one keep its name.
            let parts = try String.fetchAll(db, sql: "SELECT id FROM part WHERE deletedAt < ?", arguments: [cutoff])
            try db.execute(sql: """
                DELETE FROM partFit WHERE partId IN (\(Self.list(parts)));
                UPDATE partUse SET partId = NULL WHERE partId IN (\(Self.list(parts)));
                DELETE FROM part WHERE id IN (\(Self.list(parts)));
                """)
            // Guides, then their PDF or folder file.
            let guides = try Row.fetchAll(db, sql: "SELECT id, fileId FROM guide WHERE deletedAt < ?", arguments: [cutoff])
            let guideIDs: [String] = guides.map { $0["id"] }
            let guideFiles: [String] = guides.compactMap { $0["fileId"] }
            try db.execute(sql: """
                DELETE FROM guideLink WHERE guideId IN (\(Self.list(guideIDs)));
                DELETE FROM guide WHERE id IN (\(Self.list(guideIDs)));
                """)
            paths += try Self.deleteOwned(by: "guide", guideIDs, db)
            paths += try Self.deleteAttachments(where: "id IN (\(Self.list(guideFiles)))", db)
            // Single notes, files, and lines moved to the Trash on their own.
            for table in ["note", "partUse", "labourLine"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE deletedAt < ?", arguments: [cutoff])
            }
            paths += try Self.deleteAttachments(where: """
                deletedAt < ? AND id NOT IN (SELECT fileId FROM guide WHERE fileId IS NOT NULL)
                AND id NOT IN (SELECT fileId FROM invoice WHERE fileId IS NOT NULL)
                """, arguments: [cutoff], db)
            return before - (try Self.count(olderThan: cutoff, db))
        }
        for path in paths { try? FileManager.default.removeItem(at: filesURL.appending(path: path)) }
        return removed
    }

    // MARK: - Helpers

    private static func count(olderThan cutoff: Date, _ db: Database) throws -> Int {
        try ["customer", "device", "repair", "part", "guide", "note", "attachment"].reduce(0) { total, table in
            total + (try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table) WHERE deletedAt < ?", arguments: [cutoff]) ?? 0)
        }
    }

    /// The rows an item takes with it.
    private struct Scope {
        var table: String
        var id: String
        var isShop = false
        var devices: [String] = []
        var repairs: [String] = []
    }

    private static func scope(of item: TrashItem, _ db: Database) throws -> Scope {
        switch item {
        case .customer(let id):
            let devices = try String.fetchAll(db, sql: "SELECT id FROM device WHERE customerId = ?", arguments: [id.stored])
            return Scope(table: "customer", id: id.stored,
                         isShop: try Bool.fetchOne(db, sql: "SELECT isShop FROM customer WHERE id = ?", arguments: [id.stored]) ?? false,
                         devices: devices,
                         repairs: try String.fetchAll(db, sql: "SELECT id FROM repair WHERE deviceId IN (\(list(devices)))"))
        case .device(let id):
            return Scope(table: "device", id: id.stored, devices: [id.stored],
                         repairs: try String.fetchAll(db, sql: "SELECT id FROM repair WHERE deviceId = ?", arguments: [id.stored]))
        case .repair(let id): return Scope(table: "repair", id: id.stored, repairs: [id.stored])
        case .part(let id): return Scope(table: "part", id: id.stored)
        case .guide(let id): return Scope(table: "guide", id: id.stored)
        }
    }

    /// Sets `deletedAt` on the item, its devices and repairs, and the notes and files on each.
    private static func stamp(_ scope: Scope, set value: Date?, where condition: String, matching: Date? = nil,
                              updatedAt: Date? = nil, _ db: Database) throws {
        let changed = updatedAt ?? value ?? .now
        func update(_ table: String, _ filter: String) throws {
            var arguments: StatementArguments = [value, changed]
            if let matching { arguments += [matching] }
            try db.execute(sql: "UPDATE \(table) SET deletedAt = ?, updatedAt = ? WHERE \(filter) AND \(condition)", arguments: arguments)
        }
        try update(scope.table, "id = '\(scope.id)'")
        if scope.table == "customer" { try update("device", "id IN (\(list(scope.devices)))") }
        try update("repair", "id IN (\(list(scope.repairs)))")
        let owners: [(String, [String])] = [(scope.table, [scope.id]), ("device", scope.devices), ("repair", scope.repairs)]
        for (type, ids) in owners where ["customer", "device", "repair", "guide"].contains(type) {
            for table in ["note", "attachment"] {
                try update(table, "ownerType = '\(type)' AND ownerId IN (\(list(ids)))")
            }
        }
    }

    /// Deletes the notes and files owned by these rows; returns the file paths to remove.
    private static func deleteOwned(by type: String, _ ids: [String], _ db: Database) throws -> [String] {
        try db.execute(sql: "DELETE FROM note WHERE ownerType = ? AND ownerId IN (\(list(ids)))", arguments: [type])
        return try deleteAttachments(where: "ownerType = '\(type)' AND ownerId IN (\(list(ids)))", db)
    }

    private static func deleteAttachments(where condition: String, arguments: StatementArguments = [],
                                          _ db: Database) throws -> [String] {
        let paths = try String.fetchAll(db, sql: "SELECT path FROM attachment WHERE \(condition)", arguments: arguments)
        try db.execute(sql: "DELETE FROM attachment WHERE \(condition)", arguments: arguments)
        return paths
    }

    /// `'a', 'b'` for an `IN (…)`; ids are UUID text, so they need no escaping beyond quotes.
    private static func list(_ ids: [String]) -> String {
        ids.isEmpty ? "NULL" : ids.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
    }
}
