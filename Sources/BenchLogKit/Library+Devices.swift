import Foundation
import GRDB

/// Devices and the catalog of categories, brands, models, and revisions.
extension Library {
    // MARK: Devices

    public func devices(of customerID: UUID) throws -> [Device] {
        try db.read { db in
            try Device.filter(Column("customerId") == customerID.stored && Column("deletedAt") == nil)
                .order(Column("createdAt")).fetchAll(db)
        }
    }

    public func device(_ id: UUID) throws -> Device? {
        try db.read { try Device.fetchOne($0, key: id.stored) }
    }

    /// Every device with its customer and the status of its latest repair, newest device first.
    /// `search` matches the brand, model, revision, serial, or the customer's name.
    public func deviceRows(matching search: String = "") throws -> [DeviceRow] {
        try db.read { db in
            let text = search.trimmingCharacters(in: .whitespaces)
            var sql = """
                SELECT device.*, customer.*, (
                    SELECT status FROM repair WHERE repair.deviceId = device.id AND repair.deletedAt IS NULL
                    ORDER BY receivedAt DESC LIMIT 1) AS lastStatus
                FROM device JOIN customer ON customer.id = device.customerId
                WHERE device.deletedAt IS NULL AND customer.deletedAt IS NULL
                """
            var arguments: StatementArguments = []
            if !text.isEmpty {
                sql += " AND (device.brand || ' ' || device.model || ' ' || device.revision || ' ' || device.serial || ' ' || customer.name) LIKE ?"
                arguments += ["%\(text)%"]
            }
            sql += " ORDER BY device.createdAt DESC"
            let deviceWidth = try db.columns(in: "device").count
            let customerWidth = try db.columns(in: "customer").count
            let adapter = ScopeAdapter([
                "device": RangeRowAdapter(0..<deviceWidth),
                "customer": RangeRowAdapter(deviceWidth..<(deviceWidth + customerWidth)),
            ])
            return try Row.fetchAll(db, sql: sql, arguments: arguments, adapter: adapter).map { row in
                DeviceRow(device: try Device(row: row.scopes["device"]!),
                          customer: try Customer(row: row.scopes["customer"]!),
                          lastStatus: (row["lastStatus"] as String?).flatMap(RepairStatus.init(rawValue:)))
            }
        }
    }

    /// Adds or updates a device, and adds any new brand, model, or revision to the catalog.
    @discardableResult
    public func save(_ device: Device, now: Date = .now) throws -> Device {
        var device = device
        device.updatedAt = now
        try db.write { db in
            try device.save(db)
            try Self.addToCatalog(db, category: device.category, brand: device.brand, model: device.model, revision: device.revision)
        }
        return device
    }

    // MARK: Catalog

    public func catalogBrands(_ category: DeviceCategory) throws -> [String] {
        try db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT brand FROM catalog WHERE category = ? ORDER BY brand COLLATE NOCASE",
                                arguments: [category.rawValue])
        }
    }

    public func catalogModels(_ category: DeviceCategory, brand: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT model FROM catalog WHERE category = ? AND brand = ? COLLATE NOCASE ORDER BY model COLLATE NOCASE",
                                arguments: [category.rawValue, brand])
        }
    }

    public func catalogRevisions(_ category: DeviceCategory, brand: String, model: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT revision FROM catalog WHERE category = ? AND brand = ? COLLATE NOCASE AND model = ? COLLATE NOCASE
                AND revision != '' ORDER BY rowid
                """, arguments: [category.rawValue, brand, model])
        }
    }

    /// True when the value is already in the catalog (the sheet says "Adds … to the catalog" otherwise).
    public func catalogContains(_ category: DeviceCategory, brand: String, model: String? = nil, revision: String? = nil) throws -> Bool {
        try db.read { db in
            var sql = "SELECT COUNT(*) FROM catalog WHERE category = ? AND brand = ? COLLATE NOCASE"
            var arguments: StatementArguments = [category.rawValue, brand]
            if let model { sql += " AND model = ? COLLATE NOCASE"; arguments += [model] }
            if let revision { sql += " AND revision = ? COLLATE NOCASE"; arguments += [revision] }
            return try Int.fetchOne(db, sql: sql, arguments: arguments)! > 0
        }
    }

    static func addToCatalog(_ db: Database, category: DeviceCategory, brand: String, model: String, revision: String) throws {
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let model = model.trimmingCharacters(in: .whitespaces)
        let revision = revision.trimmingCharacters(in: .whitespaces)
        guard !brand.isEmpty, !model.isEmpty else { return }
        // Keep the catalog's spelling when it only differs in case.
        let known = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM catalog WHERE category = ? AND brand = ? COLLATE NOCASE AND model = ? COLLATE NOCASE AND revision = ? COLLATE NOCASE
            """, arguments: [category.rawValue, brand, model, revision])!
        guard known == 0 else { return }
        try db.execute(sql: "INSERT OR IGNORE INTO catalog VALUES (?, ?, ?, '')", arguments: [category.rawValue, brand, model])
        if !revision.isEmpty {
            try db.execute(sql: "INSERT OR IGNORE INTO catalog VALUES (?, ?, ?, ?)", arguments: [category.rawValue, brand, model, revision])
        }
    }
}
