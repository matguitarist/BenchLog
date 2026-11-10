import Foundation
import GRDB

/// A request the server refuses, with its HTTP status.
public struct ServerError: Error, Equatable {
    public var status: Int
    public var message: String

    public init(_ message: String, status: Int = 400) {
        self.message = message
        self.status = status
    }
}

/// The library on the server: rows it stores without knowing their columns, number sequences,
/// and file records. Last writer wins per row, by `updatedAt`.
///
/// The SQLite file is the same as `server/src/store.js` writes, so either server opens it.
public final class ServerStore: Sendable {
    /// Sequences the server hands out.
    public static let sequences = ["ticket", "invoice", "credit"]

    private let db: DatabaseQueue

    /// - Parameter path: the SQLite file, or nil for one in memory (tests).
    public init(path: String?) throws {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        db = try path.map { try DatabaseQueue(path: $0, configuration: configuration) } ?? DatabaseQueue(configuration: configuration)
        if path != nil { _ = try db.writeWithoutTransaction { try String.fetchOne($0, sql: "PRAGMA journal_mode = WAL") } }
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS row (
                  tbl TEXT NOT NULL,
                  id TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  deletedAt TEXT,
                  data TEXT NOT NULL,
                  seq INTEGER NOT NULL,
                  PRIMARY KEY (tbl, id)
                );
                CREATE UNIQUE INDEX IF NOT EXISTS row_seq ON row(seq);
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sequence (name TEXT PRIMARY KEY, next INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS file (
                  id TEXT PRIMARY KEY,
                  sha256 TEXT NOT NULL,
                  size INTEGER NOT NULL,
                  storedAt TEXT NOT NULL
                );
                """)
            for name in Self.sequences {
                try db.execute(sql: "INSERT OR IGNORE INTO sequence (name, next) VALUES (?, 1)", arguments: [name])
            }
        }
    }

    // MARK: Library

    private static func cursor(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM row") ?? 0
    }

    /// What the server holds, for a client deciding whether to upload or to join.
    public func info() throws -> [String: Any] {
        try db.read { db in
            [
                "libraryId": try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'libraryId'") as Any? ?? NSNull(),
                "rows": try Int.fetchOne(db, sql: "SELECT count(*) FROM row") ?? 0,
                "files": try Int.fetchOne(db, sql: "SELECT count(*) FROM file") ?? 0,
                "cursor": try Self.cursor(db),
                "numbers": try Self.numbers(db),
            ]
        }
    }

    /// Names the library the first time a client uploads; later clients must match it.
    public func claim(_ libraryID: Any?) throws -> String {
        guard let libraryID = libraryID as? String, Self.isID(libraryID) else { throw ServerError("libraryId is missing or malformed") }
        return try db.write { db in
            let current = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'libraryId'")
            if let current, current != libraryID { throw ServerError("this server holds another library", status: 409) }
            try db.execute(sql: "INSERT OR IGNORE INTO meta (key, value) VALUES ('libraryId', ?)", arguments: [libraryID])
            return libraryID
        }
    }

    // MARK: Rows

    /// Stores each row unless the server already has a newer or equal `updatedAt`.
    public func push(_ rows: Any?) throws -> [String: Any] {
        guard let rows = rows as? [Any] else { throw ServerError("rows must be an array") }
        let valid = try rows.map(Self.validate)
        return try db.write { db in
            var seq = try Self.cursor(db)
            var applied = 0
            var kept: [[String: String]] = []
            for row in valid {
                let existing = try String.fetchOne(db, sql: "SELECT updatedAt FROM row WHERE tbl = ? AND id = ?", arguments: [row.table, row.id])
                if let existing, existing >= row.updatedAt {
                    kept.append(["table": row.table, "id": row.id])
                    continue
                }
                seq += 1
                try db.execute(sql: """
                    INSERT INTO row (tbl, id, updatedAt, deletedAt, data, seq) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (tbl, id) DO UPDATE SET updatedAt = excluded.updatedAt, deletedAt = excluded.deletedAt,
                      data = excluded.data, seq = excluded.seq
                    """, arguments: [row.table, row.id, row.updatedAt, row.deletedAt, row.data, seq])
                applied += 1
            }
            return ["applied": applied, "kept": kept, "cursor": try Self.cursor(db)]
        }
    }

    /// Rows changed after `after`, oldest first, at most `limit` (1 to 5,000).
    public func pull(after: Int, limit: Int) throws -> [String: Any] {
        let limit = min(max(limit, 1), 5_000)
        let page = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT tbl, id, updatedAt, deletedAt, data, seq FROM row WHERE seq > ? ORDER BY seq LIMIT ?",
                             arguments: [after, limit + 1])
        }
        let rows: [[String: Any]] = try page.prefix(limit).map { row in
            let text: String = row["data"]
            let data = try JSONSerialization.jsonObject(with: Data(text.utf8))
            return ["table": row["tbl"] as String, "id": row["id"] as String, "updatedAt": row["updatedAt"] as String,
                    "deletedAt": (row["deletedAt"] as String?) as Any? ?? NSNull(), "data": data, "seq": row["seq"] as Int]
        }
        return ["rows": rows, "cursor": (rows.last?["seq"] as? Int) ?? after, "more": page.count > limit]
    }

    private struct ValidRow {
        var table: String
        var id: String
        var updatedAt: String
        var deletedAt: String?
        var data: String
    }

    private static func validate(_ value: Any) throws -> ValidRow {
        guard let row = value as? [String: Any] else { throw ServerError("each row must be an object") }
        guard let table = row["table"] as? String, isTable(table) else { throw ServerError("row.table is missing or malformed") }
        guard let id = row["id"] as? String, isID(id) else { throw ServerError("id is missing or malformed") }
        guard let updatedAt = row["updatedAt"] as? String, updatedAt.count >= 10 else { throw ServerError("row \(table)/\(id) has no updatedAt") }
        let deleted = row["deletedAt"]
        if let deleted, !(deleted is NSNull), !(deleted is String) { throw ServerError("row \(table)/\(id) has a malformed deletedAt") }
        guard let data = row["data"] as? [String: Any] else { throw ServerError("row \(table)/\(id) has no data") }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: data, options: [.withoutEscapingSlashes]), as: UTF8.self)
        return ValidRow(table: table, id: id, updatedAt: updatedAt, deletedAt: deleted as? String, data: text)
    }

    // MARK: Numbers

    private static func numbers(_ db: Database) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT name, next FROM sequence") { result[row["name"]] = row["next"] }
        return result
    }

    public func numbers() throws -> [String: Int] {
        try db.read(Self.numbers)
    }

    private static func checkSequence(_ name: String) throws {
        guard sequences.contains(name) else { throw ServerError("no sequence named \(name)", status: 404) }
    }

    /// Hands out `count` numbers in a row from a sequence; returns the first.
    public func take(_ name: String, count: Any?) throws -> [String: Int] {
        try Self.checkSequence(name)
        guard let count = count == nil || count is NSNull ? 1 : Self.integer(count), (1...100).contains(count) else {
            throw ServerError("count must be 1 to 100")
        }
        if name != "ticket", count != 1 { throw ServerError("invoice and credit numbers are handed out one at a time") }
        return try db.write { db in
            let first = try Int.fetchOne(db, sql: "SELECT next FROM sequence WHERE name = ?", arguments: [name]) ?? 1
            try db.execute(sql: "UPDATE sequence SET next = ? WHERE name = ?", arguments: [first + count, name])
            return ["first": first, "count": count]
        }
    }

    /// Moves a sequence forward so it starts at `atLeast` or later; never backward.
    public func start(_ name: String, atLeast: Any?) throws -> Int {
        try Self.checkSequence(name)
        guard let atLeast = Self.integer(atLeast), atLeast >= 1 else { throw ServerError("atLeast must be a positive integer") }
        return try db.write { db in
            try db.execute(sql: "UPDATE sequence SET next = MAX(next, ?) WHERE name = ?", arguments: [atLeast, name])
            return try Self.numbers(db)[name] ?? atLeast
        }
    }

    /// Takes back a number that went unused, when nothing was handed out after it.
    public func giveBack(_ name: String, number: Any?) throws -> Bool {
        try Self.checkSequence(name)
        guard let number = Self.integer(number), number >= 1 else { throw ServerError("number must be a positive integer") }
        return try db.write { db in
            try db.execute(sql: "UPDATE sequence SET next = ? WHERE name = ? AND next = ?", arguments: [number, name, number + 1])
            return db.changesCount == 1
        }
    }

    // MARK: Files

    public struct FileRecord: Sendable, Equatable {
        public var id: String
        public var sha256: String
        public var size: Int
    }

    public func fileRecord(_ id: String) throws -> FileRecord? {
        try Self.checkID(id)
        return try db.read { db in
            try Row.fetchOne(db, sql: "SELECT id, sha256, size FROM file WHERE id = ?", arguments: [id])
                .map { FileRecord(id: $0["id"], sha256: $0["sha256"], size: $0["size"]) }
        }
    }

    public func recordFile(_ id: String, sha256: String, size: Int) throws {
        try Self.checkID(id)
        let now = ISO8601DateFormatter.withMilliseconds.string(from: .now)
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO file (id, sha256, size, storedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET sha256 = excluded.sha256, size = excluded.size, storedAt = excluded.storedAt
                """, arguments: [id, sha256, size, now])
        }
    }

    // MARK: Checks

    /// Letters, digits, `.`, `_`, `-`, up to 64, never starting with `.`: ids name files.
    public static func isID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, id.unicodeScalars.count <= 64, isAlnum(first) else { return false }
        return id.unicodeScalars.allSatisfy { isAlnum($0) || $0 == "." || $0 == "_" || $0 == "-" }
    }

    public static func checkID(_ id: String) throws {
        guard isID(id) else { throw ServerError("id is missing or malformed") }
    }

    static func isTable(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.unicodeScalars.count <= 64,
              ("a"..."z").contains(first) || ("A"..."Z").contains(first) else { return false }
        return name.unicodeScalars.allSatisfy(isAlnum)
    }

    private static func isAlnum(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c)
    }

    /// A JSON number with no fraction, as JavaScript's Number.isInteger sees it; never a boolean.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 9e15 else { return nil }
        return Int(double)
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
