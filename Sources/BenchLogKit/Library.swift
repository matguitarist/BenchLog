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
        migrator.registerMigration("v5-guides") { db in
            // Repair guides (PDF or Markdown). The file and a Markdown guide's images are
            // attachments owned by the guide. A link with an empty brand covers a whole
            // category; an empty model a whole brand; an empty revision a whole model.
            try db.execute(sql: """
                CREATE TABLE guide (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    format TEXT NOT NULL,
                    tags TEXT NOT NULL DEFAULT '',
                    fileId TEXT REFERENCES attachment(id),
                    sourcePath TEXT NOT NULL DEFAULT '',
                    sourceHash TEXT NOT NULL DEFAULT '',
                    isOverview BOOLEAN NOT NULL DEFAULT 0,
                    lastPage INTEGER NOT NULL DEFAULT 0,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX guide_title ON guide(title COLLATE NOCASE);
                CREATE INDEX guide_source ON guide(sourcePath);

                CREATE TABLE guideLink (
                    guideId TEXT NOT NULL REFERENCES guide(id),
                    category TEXT NOT NULL,
                    brand TEXT NOT NULL DEFAULT '',
                    model TEXT NOT NULL DEFAULT '',
                    revision TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (guideId, category, brand, model, revision)
                );
                CREATE INDEX guideLink_model ON guideLink(category, brand, model);
                """)
        }
        migrator.registerMigration("v6-billing") { db in
            // Labour lines and the discount price a repair. Invoices and estimates freeze
            // what they printed (lines, rates, totals, business and customer) as JSON, so
            // later changes never alter a document already issued. Rates are in millionths
            // (5 % = 50000), money in cents.
            try db.execute(sql: """
                ALTER TABLE repair ADD COLUMN discountCents INTEGER NOT NULL DEFAULT 0;

                CREATE TABLE labourLine (
                    id TEXT PRIMARY KEY NOT NULL,
                    repairId TEXT NOT NULL REFERENCES repair(id),
                    description TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    hundredthHours INTEGER NOT NULL DEFAULT 100,
                    unitCents INTEGER NOT NULL DEFAULT 0,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX labourLine_repair ON labourLine(repairId);

                CREATE TABLE invoice (
                    id TEXT PRIMARY KEY NOT NULL,
                    repairId TEXT NOT NULL REFERENCES repair(id),
                    kind TEXT NOT NULL,
                    number INTEGER,
                    issuedAt DATETIME NOT NULL,
                    validUntil DATETIME,
                    language TEXT NOT NULL,
                    content TEXT NOT NULL,
                    totalCents INTEGER NOT NULL,
                    paidAt DATETIME,
                    paymentMethod TEXT,
                    decision TEXT,
                    decidedAt DATETIME,
                    fileId TEXT REFERENCES attachment(id),
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX invoice_repair ON invoice(repairId);
                CREATE UNIQUE INDEX invoice_number ON invoice(number) WHERE number IS NOT NULL;

                INSERT OR IGNORE INTO meta (key, value) VALUES ('nextInvoiceNumber', '1');
                """)
        }
        migrator.registerMigration("v7-search") { db in
            // Global search: an FTS5 index over customers, devices, repairs, notes, parts,
            // and guides, kept current by triggers (Search.swift).
            try SearchIndex.install(db, version: 1)
        }
        migrator.registerMigration("v8-approval") { db in
            // What the customer said at check-in: go ahead, ask first (an estimate is
            // required), or go ahead up to an amount before taxes.
            try db.execute(sql: """
                ALTER TABLE repair ADD COLUMN approvalRule TEXT NOT NULL DEFAULT 'go';
                ALTER TABLE repair ADD COLUMN approvalLimitCents INTEGER;
                """)
        }
        migrator.registerMigration("v9-shop") { db in
            // The shop as an owner, for internal jobs on devices it resells or keeps; a shop
            // device's purchase price and what became of it.
            try db.execute(sql: """
                ALTER TABLE customer ADD COLUMN isShop BOOLEAN NOT NULL DEFAULT 0;
                ALTER TABLE device ADD COLUMN purchaseCents INTEGER;
                ALTER TABLE device ADD COLUMN disposition TEXT;
                ALTER TABLE device ADD COLUMN salePriceCents INTEGER;
                ALTER TABLE device ADD COLUMN soldAt DATETIME;
                """)
            // The shop stays out of search.
            try SearchIndex.reinstall(db, version: 2)
        }
        migrator.registerMigration("v10-credit-notes") { db in
            // A credit note cancels an invoice: its own number (NC-0001) and the invoice it credits.
            try db.execute(sql: """
                ALTER TABLE invoice ADD COLUMN creditNumber INTEGER;
                ALTER TABLE invoice ADD COLUMN creditsInvoiceId TEXT REFERENCES invoice(id);
                CREATE UNIQUE INDEX invoice_creditNumber ON invoice(creditNumber);
                CREATE UNIQUE INDEX invoice_creditsInvoiceId ON invoice(creditsInvoiceId);
                """)
        }
        migrator.registerMigration("v11-sales") { db in
            // A sale invoice is for a shop device, not a repair: repairId becomes optional and
            // deviceId is added. SQLite cannot drop NOT NULL, so the table is rebuilt.
            let columns = "id, repairId, kind, number, issuedAt, validUntil, language, content, totalCents, paidAt, paymentMethod, "
                + "decision, decidedAt, fileId, createdAt, updatedAt, deletedAt, creditNumber, creditsInvoiceId"
            try db.execute(sql: """
                CREATE TABLE invoice_new (
                    id TEXT PRIMARY KEY NOT NULL,
                    repairId TEXT REFERENCES repair(id),
                    deviceId TEXT REFERENCES device(id),
                    kind TEXT NOT NULL,
                    number INTEGER,
                    issuedAt DATETIME NOT NULL,
                    validUntil DATETIME,
                    language TEXT NOT NULL,
                    content TEXT NOT NULL,
                    totalCents INTEGER NOT NULL,
                    paidAt DATETIME,
                    paymentMethod TEXT,
                    decision TEXT,
                    decidedAt DATETIME,
                    fileId TEXT REFERENCES attachment(id),
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME,
                    creditNumber INTEGER,
                    creditsInvoiceId TEXT REFERENCES invoice(id),
                    CHECK (repairId IS NOT NULL OR deviceId IS NOT NULL)
                );
                INSERT INTO invoice_new (\(columns)) SELECT \(columns) FROM invoice;
                DROP TABLE invoice;
                ALTER TABLE invoice_new RENAME TO invoice;
                CREATE INDEX invoice_repair ON invoice(repairId);
                CREATE INDEX invoice_device ON invoice(deviceId);
                CREATE UNIQUE INDEX invoice_number ON invoice(number) WHERE number IS NOT NULL;
                CREATE UNIQUE INDEX invoice_creditNumber ON invoice(creditNumber);
                CREATE UNIQUE INDEX invoice_creditsInvoiceId ON invoice(creditsInvoiceId);
                """)
        }
        migrator.registerMigration("v12-stock") { db in
            // Every change to a part's stock, with why. What is on the shelf today opens the history.
            try db.execute(sql: """
                CREATE TABLE stockMove (
                    id TEXT PRIMARY KEY NOT NULL,
                    partId TEXT NOT NULL REFERENCES part(id),
                    delta INTEGER NOT NULL,
                    quantityAfter INTEGER NOT NULL,
                    reason TEXT NOT NULL,
                    repairId TEXT REFERENCES repair(id),
                    invoiceId TEXT REFERENCES invoice(id),
                    restockId TEXT,
                    note TEXT NOT NULL DEFAULT '',
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX stockMove_part ON stockMove(partId, createdAt);
                INSERT INTO stockMove (id, partId, delta, quantityAfter, reason, createdAt, updatedAt)
                    SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-'
                                 || substr('89ab', 1 + abs(random()) % 4, 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))),
                           id, quantity, quantity, 'opening', updatedAt, updatedAt
                    FROM part WHERE quantity > 0;
                """)
        }
        migrator.registerMigration("v13-restock") { db in
            // Orders of stock for the shelf, one vendor each.
            try db.execute(sql: """
                CREATE TABLE restock (
                    id TEXT PRIMARY KEY NOT NULL,
                    vendor TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT 'draft',
                    orderedAt DATETIME,
                    receivedAt DATETIME,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE TABLE restockLine (
                    id TEXT PRIMARY KEY NOT NULL,
                    restockId TEXT NOT NULL REFERENCES restock(id),
                    partId TEXT NOT NULL REFERENCES part(id),
                    quantity INTEGER NOT NULL,
                    costCents INTEGER,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME
                );
                CREATE INDEX restockLine_restock ON restockLine(restockId);
                """)
        }
        migrator.registerMigration("v14-counter-sales") { db in
            // A counter sale has neither a repair nor a device, only a customer (the shop for a
            // walk-in). The CHECK changes, so the table is rebuilt again.
            let columns = "id, repairId, deviceId, kind, number, issuedAt, validUntil, language, content, totalCents, paidAt, "
                + "paymentMethod, decision, decidedAt, fileId, createdAt, updatedAt, deletedAt, creditNumber, creditsInvoiceId"
            try db.execute(sql: """
                CREATE TABLE invoice_new (
                    id TEXT PRIMARY KEY NOT NULL,
                    repairId TEXT REFERENCES repair(id),
                    deviceId TEXT REFERENCES device(id),
                    customerId TEXT REFERENCES customer(id),
                    kind TEXT NOT NULL,
                    number INTEGER,
                    issuedAt DATETIME NOT NULL,
                    validUntil DATETIME,
                    language TEXT NOT NULL,
                    content TEXT NOT NULL,
                    totalCents INTEGER NOT NULL,
                    paidAt DATETIME,
                    paymentMethod TEXT,
                    decision TEXT,
                    decidedAt DATETIME,
                    fileId TEXT REFERENCES attachment(id),
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    deletedAt DATETIME,
                    creditNumber INTEGER,
                    creditsInvoiceId TEXT REFERENCES invoice(id),
                    CHECK (repairId IS NOT NULL OR deviceId IS NOT NULL OR customerId IS NOT NULL)
                );
                INSERT INTO invoice_new (\(columns)) SELECT \(columns) FROM invoice;
                DROP TABLE invoice;
                ALTER TABLE invoice_new RENAME TO invoice;
                CREATE INDEX invoice_repair ON invoice(repairId);
                CREATE INDEX invoice_device ON invoice(deviceId);
                CREATE INDEX invoice_customer ON invoice(customerId);
                CREATE UNIQUE INDEX invoice_number ON invoice(number) WHERE number IS NOT NULL;
                CREATE UNIQUE INDEX invoice_creditNumber ON invoice(creditNumber);
                CREATE UNIQUE INDEX invoice_creditsInvoiceId ON invoice(creditsInvoiceId);
                """)
        }
        migrator.registerMigration("v15-sync") { db in
            // Every local change queues its row for the server (S-052). Rows applied from the
            // server set syncFlag.applying, so they are never queued again.
            try db.execute(sql: """
                CREATE TABLE syncQueue (
                    tbl TEXT NOT NULL,
                    id TEXT NOT NULL,
                    version INTEGER NOT NULL DEFAULT 1,
                    PRIMARY KEY (tbl, id)
                );
                CREATE TABLE syncFlag (applying INTEGER NOT NULL);
                INSERT INTO syncFlag VALUES (0);
                ALTER TABLE meta ADD COLUMN updatedAt DATETIME;
                UPDATE meta SET updatedAt = strftime('%Y-%m-%d %H:%M:%f', 'now') WHERE key = 'business';
                INSERT OR IGNORE INTO meta (key, value) VALUES ('libraryId', lower(hex(randomblob(16))));
                """)
            // A frozen copy of the tables of the time; later tables add their own triggers.
            for table in ["attachment", "customer", "device", "guide", "invoice", "labourLine", "note", "part",
                          "partUse", "repair", "restock", "restockLine", "stockMove"] {
                try db.execute(sql: Library.queueTriggers(table))
            }
            // Fits and guide links travel inside their part or guide: a change touches the parent.
            for (child, parent, key) in [("partFit", "part", "partId"), ("guideLink", "guide", "guideId")] {
                for (event, row) in [("INSERT", "NEW"), ("DELETE", "OLD")] {
                    try db.execute(sql: """
                        CREATE TRIGGER sync_\(child)_\(event.lowercased()) AFTER \(event) ON \(child)
                        WHEN (SELECT applying FROM syncFlag) = 0 BEGIN
                            UPDATE \(parent) SET updatedAt = strftime('%Y-%m-%d %H:%M:%f', 'now') WHERE id = \(row).\(key);
                        END
                        """)
                }
            }
            for event in ["INSERT", "UPDATE OF value"] {
                try db.execute(sql: """
                    CREATE TRIGGER sync_meta_\(event.prefix(6).lowercased()) AFTER \(event) ON meta
                    WHEN NEW.key = 'business' AND (SELECT applying FROM syncFlag) = 0 BEGIN
                        UPDATE meta SET updatedAt = strftime('%Y-%m-%d %H:%M:%f', 'now') WHERE key = NEW.key;
                        INSERT INTO syncQueue (tbl, id) VALUES ('meta', NEW.key) ON CONFLICT DO UPDATE SET version = version + 1;
                    END
                    """)
            }
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
