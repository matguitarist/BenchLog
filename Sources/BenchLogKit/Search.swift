import Foundation
import GRDB

/// What a search result is.
public enum SearchKind: String, Codable, CaseIterable, Sendable {
    case repair, customer, device, part, guide, note
}

/// One search result: what it is, what opens when it is chosen, and how it reads in a list.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public var kind: SearchKind
    public var id: UUID
    /// What opens: the record itself, or for a note, the customer, device, repair, or guide it is on.
    public var target: Target
    public var title: String
    public var subtitle: String

    public struct Target: Hashable, Sendable {
        public var kind: SearchKind
        public var id: UUID
    }
}

/// The full-text index behind global search: one FTS5 table, `search`, kept current by
/// triggers on every table it covers, so no write path can forget it. Passcodes are never
/// indexed. Rows that are in the trash drop out.
enum SearchIndex {
    /// One kind of row in the index: how to select its rows (`{where}` is a condition on the
    /// table's alias), and which other kinds to refresh when one of its rows changes.
    struct Source {
        var kind: SearchKind
        var table: String
        var alias: String
        var select: String
        /// Kinds whose rows show this row's text (a repair shows its customer's name), and the
        /// condition that picks them, with `NEW.id` for the changed row.
        var dependents: [(kind: SearchKind, condition: String)] = []
    }

    /// `a · b · c`, skipping the empty ones.
    static func joined(_ parts: String...) -> String {
        let tail = parts.dropFirst().map { "iif(\($0) <> '', ' · ' || \($0), '')" }
        return "trim(\(([parts[0]] + tail).joined(separator: " || ")), ' ·')"
    }

    static let sources: [Source] = [
        Source(kind: .customer, table: "customer", alias: "c", select: """
            SELECT 'customer', c.id, 'customer', c.id, c.name, \(joined("c.phone", "c.email")),
                   c.phoneDigits || ' ' || substr(c.phoneDigits, -7) || ' ' || c.address
            FROM customer c WHERE c.deletedAt IS NULL AND {where}
            """,
            dependents: [(.device, "d.customerId = NEW.id"),
                         (.repair, "r.deviceId IN (SELECT id FROM device WHERE customerId = NEW.id)")]),
        Source(kind: .device, table: "device", alias: "d", select: """
            SELECT 'device', d.id, 'device', d.id,
                   d.brand || ' ' || d.model || iif(d.revision <> '', ' ' || d.revision, ''),
                   \(joined("c.name", "d.serial")), d.colour
            FROM device d JOIN customer c ON c.id = d.customerId
            WHERE d.deletedAt IS NULL AND {where}
            """,
            dependents: [(.repair, "r.deviceId = NEW.id")]),
        Source(kind: .repair, table: "repair", alias: "r", select: """
            SELECT 'repair', r.id, 'repair', r.id,
                   '#' || printf('%04d', r.ticketNumber) || ' ' || c.name,
                   \(joined("d.brand || ' ' || d.model", "r.complaint")),
                   r.ticketNumber || ' ' || r.diagnosis
            FROM repair r JOIN device d ON d.id = r.deviceId JOIN customer c ON c.id = d.customerId
            WHERE r.deletedAt IS NULL AND {where}
            """),
        Source(kind: .note, table: "note", alias: "n", select: """
            SELECT 'note', n.id, n.ownerType, n.ownerId,
                   substr(n.text, 1, iif(instr(n.text, char(10)) BETWEEN 1 AND 120, instr(n.text, char(10)) - 1, 120)),
                   CASE n.ownerType
                       WHEN 'repair' THEN (SELECT '#' || printf('%04d', ticketNumber) FROM repair WHERE id = n.ownerId)
                       WHEN 'customer' THEN (SELECT name FROM customer WHERE id = n.ownerId)
                       WHEN 'device' THEN (SELECT brand || ' ' || model FROM device WHERE id = n.ownerId)
                       WHEN 'guide' THEN (SELECT title FROM guide WHERE id = n.ownerId)
                       ELSE '' END,
                   n.text
            FROM note n WHERE n.kind = 'text' AND n.deletedAt IS NULL AND {where}
            """),
        Source(kind: .part, table: "part", alias: "p", select: """
            SELECT 'part', p.id, 'part', p.id, p.name, \(joined("p.sku", "p.vendor")), ''
            FROM part p WHERE p.deletedAt IS NULL AND {where}
            """),
        Source(kind: .guide, table: "guide", alias: "g", select: """
            SELECT 'guide', g.id, 'guide', g.id, g.title, g.tags, ''
            FROM guide g WHERE g.deletedAt IS NULL AND {where}
            """),
    ]

    static func source(_ kind: SearchKind) -> Source { sources.first { $0.kind == kind }! }

    /// Deletes and re-adds the rows of `kind` that `condition` picks.
    static func refresh(_ kind: SearchKind, where condition: String) -> String {
        let source = source(kind)
        return """
            DELETE FROM search WHERE kind = '\(kind.rawValue)'
                AND itemId IN (SELECT \(source.alias).id FROM \(source.table) \(source.alias) WHERE \(condition));
            INSERT INTO search (kind, itemId, targetKind, targetId, title, subtitle, keys)
                \(source.select.replacingOccurrences(of: "{where}", with: condition));
            """
    }

    /// Creates the index, fills it, and adds the triggers that keep it current.
    static func install(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE search USING fts5(
                kind UNINDEXED, itemId UNINDEXED, targetKind UNINDEXED, targetId UNINDEXED,
                title, subtitle, keys,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """)
        for source in sources {
            try db.execute(sql: "INSERT INTO search (kind, itemId, targetKind, targetId, title, subtitle, keys) "
                + source.select.replacingOccurrences(of: "{where}", with: "1"))
            let changed = refresh(source.kind, where: "\(source.alias).id = NEW.id")
                + source.dependents.map { refresh($0.kind, where: $0.condition) }.joined()
            try db.execute(sql: """
                CREATE TRIGGER search_\(source.table)_insert AFTER INSERT ON \(source.table) BEGIN \(changed) END;
                CREATE TRIGGER search_\(source.table)_update AFTER UPDATE ON \(source.table) BEGIN \(changed) END;
                CREATE TRIGGER search_\(source.table)_delete AFTER DELETE ON \(source.table) BEGIN
                    DELETE FROM search WHERE kind = '\(source.kind.rawValue)' AND itemId = OLD.id;
                END;
                """)
        }
    }

    /// The FTS5 query for what someone typed: every word must match the start of a word, so
    /// "#12" finds ticket 12 and "555-01" finds a phone number. Nil when nothing is left.
    static func query(_ text: String) -> String? {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(8)
            .map { "\"\($0)\"*" }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

extension Library {
    /// Finds customers, devices, repairs, notes, parts, and guides at once. Results come
    /// grouped by kind, the kind with the best match first, each kind's best match first.
    public func search(_ text: String, limitPerKind: Int = 6) throws -> [SearchHit] {
        guard let query = SearchIndex.query(text) else { return [] }
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT kind, itemId, targetKind, targetId, title, subtitle,
                       bm25(search, 0, 0, 0, 0, 10, 4, 2) AS rank
                FROM search WHERE search MATCH ? ORDER BY rank LIMIT 200
                """, arguments: [query])
        }
        var groups: [SearchKind: [SearchHit]] = [:]
        var order: [SearchKind] = []
        for row in rows {
            guard let kind = SearchKind(rawValue: row["kind"]), let id = UUID(uuidString: row["itemId"]),
                  let targetKind = SearchKind(rawValue: row["targetKind"]), let targetID = UUID(uuidString: row["targetId"]) else { continue }
            if groups[kind] == nil { order.append(kind) }
            guard groups[kind, default: []].count < limitPerKind else { continue }
            groups[kind, default: []].append(SearchHit(kind: kind, id: id, target: .init(kind: targetKind, id: targetID),
                                                       title: row["title"], subtitle: row["subtitle"] ?? ""))
        }
        return order.flatMap { groups[$0] ?? [] }
    }
}
