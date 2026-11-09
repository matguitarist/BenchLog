import Foundation
import GRDB

/// BenchLog's library on disk: the SQLite database and, next to it, the folder
/// of photos and files. The database only stores paths relative to that folder,
/// so the whole library can move, be backed up, or later sync as one unit.
///
///     ~/Library/Application Support/BenchLog/benchlog.sqlite
///     ~/Library/Application Support/BenchLog/Files/
public final class Library: Sendable {
    public let databaseURL: URL
    public let filesURL: URL
    public let db: DatabaseQueue

    /// Opens (or creates) the library at `databaseURL`; the files folder is
    /// `Files` next to it, or `<name>-files` for a database not named benchlog.sqlite.
    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let folder = databaseURL.deletingLastPathComponent()
        let stem = databaseURL.deletingPathExtension().lastPathComponent
        filesURL = stem == "benchlog" ? folder.appending(path: "Files", directoryHint: .isDirectory)
                                      : folder.appending(path: "\(stem)-files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try Self.migrator.migrate(db)
    }

    /// An in-memory library for tests.
    public init() throws {
        databaseURL = URL(fileURLWithPath: "/dev/null")
        filesURL = FileManager.default.temporaryDirectory.appending(path: "BenchLog-\(UUID().uuidString)-files")
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        db = try DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    /// Every schema change is a new migration, never an edit of an old one:
    /// libraries in the field (and, later, other devices) depend on it.
    /// docs/SCHEMA.md describes the tables for other clients.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-meta") { db in
            // Library-wide values: the schema's owner, the next ticket number, …
            try db.execute(sql: """
                CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                INSERT INTO meta (key, value) VALUES ('nextTicketNumber', '1');
                """)
        }
        migrator.registerMigration("v2-core") { db in
            // Customers, their devices, repairs, notes, and the device catalog.
            // Ids are lowercase UUID text; dates are "YYYY-MM-DD HH:MM:SS.SSS" in UTC.
            try db.execute(sql: """
                CREATE TABLE customer (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    phone TEXT NOT NULL DEFAULT '',
                    phoneDigits TEXT NOT NULL DEFAULT '',
                    email TEXT NOT NULL DEFAULT '',
                    address TEXT NOT NULL DEFAULT '',
                    documentsLanguage TEXT NOT NULL DEFAULT 'fr',
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX customer_name ON customer(name COLLATE NOCASE);
                CREATE INDEX customer_phone ON customer(phoneDigits);

                CREATE TABLE device (
                    id TEXT PRIMARY KEY NOT NULL,
                    customerId TEXT NOT NULL REFERENCES customer(id),
                    category TEXT NOT NULL,
                    brand TEXT NOT NULL,
                    model TEXT NOT NULL,
                    revision TEXT NOT NULL DEFAULT '',
                    serial TEXT NOT NULL DEFAULT '',
                    colour TEXT NOT NULL DEFAULT '',
                    condition TEXT NOT NULL DEFAULT '',
                    passcode TEXT NOT NULL DEFAULT '',
                    passcodeIsPattern BOOLEAN NOT NULL DEFAULT 0,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX device_customer ON device(customerId);

                CREATE TABLE repair (
                    id TEXT PRIMARY KEY NOT NULL,
                    deviceId TEXT NOT NULL REFERENCES device(id),
                    ticketNumber INTEGER NOT NULL UNIQUE,
                    status TEXT NOT NULL,
                    complaint TEXT NOT NULL,
                    diagnosis TEXT NOT NULL DEFAULT '',
                    receivedAt DATETIME NOT NULL,
                    promisedAt DATETIME,
                    completedAt DATETIME,
                    pickedUpAt DATETIME,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX repair_device ON repair(deviceId);
                CREATE INDEX repair_status ON repair(status);

                CREATE TABLE note (
                    id TEXT PRIMARY KEY NOT NULL,
                    ownerType TEXT NOT NULL,
                    ownerId TEXT NOT NULL,
                    kind TEXT NOT NULL DEFAULT 'text',
                    text TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX note_owner ON note(ownerType, ownerId);

                CREATE TABLE catalog (
                    category TEXT NOT NULL,
                    brand TEXT NOT NULL,
                    model TEXT NOT NULL,
                    revision TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (category, brand, model, revision)
                );
                """)
            for (category, brand, model, revisions) in CatalogSeed.entries {
                for revision in [""] + revisions {
                    try db.execute(sql: "INSERT OR IGNORE INTO catalog VALUES (?, ?, ?, ?)",
                                   arguments: [category, brand, model, revision])
                }
            }
        }
        migrator.registerMigration("v3-attachments") { db in
            // Photos and files on a customer, device, or repair. The file lives in Files/;
            // `path` is relative to that folder, so the library can move as one unit.
            try db.execute(sql: """
                CREATE TABLE attachment (
                    id TEXT PRIMARY KEY NOT NULL,
                    ownerType TEXT NOT NULL,
                    ownerId TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    path TEXT NOT NULL,
                    originalName TEXT NOT NULL,
                    contentType TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    caption TEXT NOT NULL DEFAULT '',
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX attachment_owner ON attachment(ownerType, ownerId);
                """)
        }
        migrator.registerMigration("v4-parts") { db in
            // Parts kept in stock, the models they fit, and the parts each repair uses
            // (from stock or typed in). Money is integer cents.
            try db.execute(sql: """
                CREATE TABLE part (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    sku TEXT NOT NULL DEFAULT '',
                    vendor TEXT NOT NULL DEFAULT '',
                    url TEXT NOT NULL DEFAULT '',
                    costCents INTEGER,
                    priceCents INTEGER,
                    quantity INTEGER NOT NULL DEFAULT 0,
                    lowStockThreshold INTEGER NOT NULL DEFAULT 0,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX part_name ON part(name COLLATE NOCASE);

                CREATE TABLE partFit (
                    partId TEXT NOT NULL REFERENCES part(id),
                    category TEXT NOT NULL,
                    brand TEXT NOT NULL,
                    model TEXT NOT NULL,
                    PRIMARY KEY (partId, category, brand, model)
                );

                CREATE TABLE partUse (
                    id TEXT PRIMARY KEY NOT NULL,
                    repairId TEXT NOT NULL REFERENCES repair(id),
                    partId TEXT REFERENCES part(id),
                    name TEXT NOT NULL,
                    vendor TEXT NOT NULL DEFAULT '',
                    quantity INTEGER NOT NULL DEFAULT 1,
                    status TEXT NOT NULL,
                    costCents INTEGER,
                    priceCents INTEGER,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX partUse_repair ON partUse(repairId);
                CREATE INDEX partUse_status ON partUse(status);
                """)
        }
        return migrator
    }

    /// The migrations this library has run, oldest first.
    public func appliedMigrations() throws -> [String] {
        try db.read { try Self.migrator.appliedMigrations($0) }
    }

    public func metaValue(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }
}
