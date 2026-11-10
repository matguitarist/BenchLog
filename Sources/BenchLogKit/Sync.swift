import Foundation
import GRDB

/// A JSON value in a synced row: what a SQLite column holds.
public enum SyncValue: Codable, Hashable, Sendable {
    case null
    case int(Int64)
    case double(Double)
    case string(String)
    case blob(Data)

    private enum BlobKey: String, CodingKey { case blob = "$blob" }

    public init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: BlobKey.self), let base64 = try? object.decode(String.self, forKey: .blob) {
            self = .blob(Data(base64Encoded: base64) ?? Data())
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let int = try? value.decode(Int64.self) { self = .int(int) }
        else if let double = try? value.decode(Double.self) { self = .double(double) }
        else if let bool = try? value.decode(Bool.self) { self = .int(bool ? 1 : 0) }
        else { self = .string(try value.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .blob(let data):
            var object = encoder.container(keyedBy: BlobKey.self)
            try object.encode(data.base64EncodedString(), forKey: .blob)
        case .null: var value = encoder.singleValueContainer(); try value.encodeNil()
        case .int(let int): var value = encoder.singleValueContainer(); try value.encode(int)
        case .double(let double): var value = encoder.singleValueContainer(); try value.encode(double)
        case .string(let string): var value = encoder.singleValueContainer(); try value.encode(string)
        }
    }

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let int): self = .int(int)
        case .double(let double): self = .double(double)
        case .string(let string): self = .string(string)
        case .blob(let data): self = .blob(data)
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .null: .null
        case .int(let int): int.databaseValue
        case .double(let double): double.databaseValue
        case .string(let string): string.databaseValue
        case .blob(let data): data.databaseValue
        }
    }

    var string: String? { if case .string(let string) = self { string } else { nil } }
}

/// One row as it travels to and from the server: its table, id, and every column.
public struct SyncRow: Codable, Hashable, Sendable {
    public var table: String
    public var id: String
    public var updatedAt: String
    public var deletedAt: String?
    public var data: [String: SyncValue]

    public init(table: String, id: String, updatedAt: String, deletedAt: String?, data: [String: SyncValue]) {
        self.table = table
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.data = data
    }
}

/// A queued local change: the row and the version that was read, so a change made while
/// pushing stays queued.
struct QueuedChange: Hashable, Sendable {
    var table: String
    var id: String
    var version: Int
}

extension Library {
    /// Tables whose rows sync one by one. Each has `id`, `updatedAt`, and `deletedAt`, and
    /// triggers that queue local changes. A new table must be added here and get
    /// `queueTriggers`, or be listed in `localTables`; SyncTests fails until it is.
    public static let syncedTables = ["customer", "device", "repair", "note", "attachment", "labourLine", "invoice", "part",
                                      "partUse", "guide", "restock", "restockLine", "stockMove"]
    /// Tables that never sync: derived on each device, carried inside another row, or sync state.
    static let localTables: Set<String> = ["meta", "catalog", "partFit", "guideLink", "syncQueue", "syncFlag", "grdb_migrations"]
    /// The `meta` keys that sync, as rows of the `meta` table.
    static let syncedMetaKeys = ["business"]

    static func queueTriggers(_ table: String) -> String {
        ["INSERT", "UPDATE"].map { event in
            """
            CREATE TRIGGER sync_\(table)_\(event.lowercased()) AFTER \(event) ON \(table)
            WHEN (SELECT applying FROM syncFlag) = 0 BEGIN
                INSERT INTO syncQueue (tbl, id) VALUES ('\(table)', NEW.id) ON CONFLICT DO UPDATE SET version = version + 1;
            END;
            """
        }.joined(separator: "\n")
    }

    // MARK: Local sync state

    /// This library's identity: a server holds one library.
    public func libraryID() throws -> String {
        try metaValue("libraryId") ?? ""
    }

    /// Changes waiting to be pushed.
    public func pendingSyncCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM syncQueue") ?? 0 }
    }

    func syncCursor() throws -> Int { Int(try metaValue("syncCursor") ?? "0") ?? 0 }

    func setLocalMeta(_ key: String, _ value: String?) throws {
        try db.write { db in
            if let value {
                try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                               arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [key])
            }
        }
    }

    /// Queues every row, for the first upload to an empty server.
    func queueEverything() throws {
        try db.write { db in
            for table in Self.syncedTables {
                try db.execute(sql: "INSERT OR IGNORE INTO syncQueue (tbl, id) SELECT ?, id FROM \(table)", arguments: [table])
            }
            for key in Self.syncedMetaKeys {
                try db.execute(sql: "INSERT OR IGNORE INTO syncQueue (tbl, id) SELECT 'meta', key FROM meta WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Push

    /// Up to `limit` queued changes with their rows, parents first.
    func queuedChanges(limit: Int = 500) throws -> [(QueuedChange, SyncRow?)] {
        try db.read { db in
            let order = (["meta"] + Self.syncedTables).enumerated().map { "WHEN '\($1)' THEN \($0)" }.joined(separator: " ")
            let queued = try Row.fetchAll(db, sql: "SELECT tbl, id, version FROM syncQueue ORDER BY CASE tbl \(order) ELSE 99 END, rowid LIMIT ?",
                                          arguments: [limit])
                .map { QueuedChange(table: $0["tbl"], id: $0["id"], version: $0["version"]) }
            return try queued.map { ($0, try Self.export(db, table: $0.table, id: $0.id)) }
        }
    }

    /// Drops pushed changes, unless the row changed again since it was read.
    func dequeue(_ changes: [QueuedChange]) throws {
        try db.write { db in
            for change in changes {
                try db.execute(sql: "DELETE FROM syncQueue WHERE tbl = ? AND id = ? AND version = ?",
                               arguments: [change.table, change.id, change.version])
            }
        }
    }

    /// A row as it goes to the server. Parts carry their fits and guides their links.
    static func export(_ db: Database, table: String, id: String) throws -> SyncRow? {
        if table == "meta" {
            guard Self.syncedMetaKeys.contains(id),
                  let row = try Row.fetchOne(db, sql: "SELECT value, updatedAt FROM meta WHERE key = ?", arguments: [id]) else { return nil }
            return SyncRow(table: "meta", id: id, updatedAt: row["updatedAt"] ?? "1970-01-01 00:00:00.000", deletedAt: nil,
                           data: ["value": SyncValue(row["value"] as DatabaseValue)])
        }
        guard Self.syncedTables.contains(table),
              let row = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id]) else { return nil }
        var data: [String: SyncValue] = [:]
        for (column, value) in row { data[column] = SyncValue(value) }
        if table == "part" {
            let fits = try Row.fetchAll(db, sql: "SELECT category, brand, model FROM partFit WHERE partId = ? ORDER BY rowid", arguments: [id])
            data["_fits"] = .string(Self.encodeChildren(fits))
        }
        if table == "guide" {
            let links = try Row.fetchAll(db, sql: "SELECT category, brand, model, revision FROM guideLink WHERE guideId = ? ORDER BY rowid",
                                         arguments: [id])
            data["_links"] = .string(Self.encodeChildren(links))
        }
        return SyncRow(table: table, id: id, updatedAt: data["updatedAt"]?.string ?? "1970-01-01 00:00:00.000",
                       deletedAt: data["deletedAt"]?.string, data: data)
    }

    private static func encodeChildren(_ rows: [Row]) -> String {
        let objects = rows.map { row in Dictionary(uniqueKeysWithValues: row.map { ($0, $1.storage.value as? String ?? "") }) }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])) ?? Data("[]".utf8), as: UTF8.self)
    }

    private static func decodeChildren(_ value: SyncValue?) -> [[String: String]] {
        guard let text = value?.string, let objects = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: String]] else { return [] }
        return objects
    }

    // MARK: Pull

    /// Applies rows from the server in one transaction: a row replaces the local one when it
    /// is newer, and is never queued again. Returns the attachments that arrived.
    @discardableResult
    func apply(_ rows: [SyncRow]) throws -> (applied: Int, attachments: [UUID]) {
        try db.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            try db.execute(sql: "UPDATE syncFlag SET applying = 1")
            defer { try? db.execute(sql: "UPDATE syncFlag SET applying = 0") }
            var columns: [String: [String]] = [:]
            var applied = 0
            var attachments: [UUID] = []
            for row in rows {
                if row.table == "meta" {
                    guard Self.syncedMetaKeys.contains(row.id) else { continue }
                    let local = try String.fetchOne(db, sql: "SELECT updatedAt FROM meta WHERE key = ?", arguments: [row.id])
                    if let local, local >= row.updatedAt { continue }
                    try db.execute(sql: """
                        INSERT INTO meta (key, value, updatedAt) VALUES (?, ?, ?)
                        ON CONFLICT (key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                        """, arguments: [row.id, row.data["value"]?.databaseValue ?? .null, row.updatedAt])
                    try db.execute(sql: "DELETE FROM syncQueue WHERE tbl = 'meta' AND id = ?", arguments: [row.id])
                    applied += 1
                    continue
                }
                guard Self.syncedTables.contains(row.table) else { continue }
                let local = try String.fetchOne(db, sql: "SELECT updatedAt FROM \(row.table) WHERE id = ?", arguments: [row.id])
                if let local, local >= row.updatedAt { continue }
                if columns[row.table] == nil { columns[row.table] = try db.columns(in: row.table).map(\.name) }
                // Columns this version knows; a newer client's extra columns wait for an update.
                let names = columns[row.table]!.filter { row.data[$0] != nil }
                guard names.contains("id") else { continue }
                let values = names.map { row.data[$0]!.databaseValue }
                let updates = names.filter { $0 != "id" }.map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    INSERT INTO \(row.table) (\(names.joined(separator: ", "))) VALUES (\(names.map { _ in "?" }.joined(separator: ", ")))
                    ON CONFLICT (id) DO UPDATE SET \(updates)
                    """, arguments: StatementArguments(values))
                try Self.applyExtras(db, row)
                try db.execute(sql: "DELETE FROM syncQueue WHERE tbl = ? AND id = ?", arguments: [row.table, row.id])
                if row.table == "attachment", let id = UUID(uuidString: row.id) { attachments.append(id) }
                applied += 1
            }
            return (applied, attachments)
        }
    }

    /// Fits and links carried in a part or guide row, and catalog entries for what arrived.
    private static func applyExtras(_ db: Database, _ row: SyncRow) throws {
        switch row.table {
        case "part":
            try db.execute(sql: "DELETE FROM partFit WHERE partId = ?", arguments: [row.id])
            for fit in decodeChildren(row.data["_fits"]) {
                try db.execute(sql: "INSERT OR IGNORE INTO partFit (partId, category, brand, model) VALUES (?, ?, ?, ?)",
                               arguments: [row.id, fit["category"], fit["brand"], fit["model"]])
                try addToCatalog(db, category: DeviceCategory(rawValue: fit["category"] ?? "") ?? .other,
                                 brand: fit["brand"] ?? "", model: fit["model"] ?? "", revision: "")
            }
        case "guide":
            try db.execute(sql: "DELETE FROM guideLink WHERE guideId = ?", arguments: [row.id])
            for link in decodeChildren(row.data["_links"]) {
                try db.execute(sql: "INSERT OR IGNORE INTO guideLink (guideId, category, brand, model, revision) VALUES (?, ?, ?, ?, ?)",
                               arguments: [row.id, link["category"], link["brand"], link["model"], link["revision"]])
            }
        case "device":
            if let category = row.data["category"]?.string.flatMap(DeviceCategory.init(rawValue:)) {
                try addToCatalog(db, category: category, brand: row.data["brand"]?.string ?? "",
                                 model: row.data["model"]?.string ?? "", revision: row.data["revision"]?.string ?? "")
            }
        default:
            break
        }
    }

    /// Empties this library before it joins a server's library. The caller backs it up first.
    func clearForJoin(libraryID: String) throws {
        try db.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            try db.execute(sql: "UPDATE syncFlag SET applying = 1")
            defer { try? db.execute(sql: "UPDATE syncFlag SET applying = 0") }
            for table in ["partFit", "guideLink", "stockMove", "restockLine", "restock", "partUse", "labourLine", "invoice", "note",
                          "attachment", "guide", "part", "repair", "device", "customer", "syncQueue"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(sql: "DELETE FROM meta WHERE key = 'business'")
            try db.execute(sql: "UPDATE meta SET value = ? WHERE key = 'libraryId'", arguments: [libraryID])
            try db.execute(sql: "DELETE FROM meta WHERE key IN ('syncCursor', 'ticketBlocks')")
        }
    }
}

extension Library {
    /// The server this library syncs with, or nil when it is not connected. Kept on this
    /// device only; the token lives in the Keychain.
    public func syncServer() throws -> URL? {
        try metaValue("syncServer").flatMap(URL.init(string:))
    }

    public func setSyncServer(_ url: URL?) throws {
        try setLocalMeta("syncServer", url?.absoluteString)
        if url == nil { try setLocalMeta("syncedAt", nil) }
    }

    /// When the last sync finished.
    public func syncedAt() throws -> Date? {
        try metaValue("syncedAt").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    public func setSyncedAt(_ date: Date) throws {
        try setLocalMeta("syncedAt", String(date.timeIntervalSince1970))
    }
}
