import Foundation
import GRDB

/// Reading and changing the library. Every write sets `updatedAt`; deleting sets `deletedAt`.
extension Library {
    // MARK: Customers

    /// Customers sorted by name. `search` matches the name, the email, or the phone's digits.
    public func customers(matching search: String = "") throws -> [Customer] {
        try db.read { db in
            var request = Customer.filter(Column("deletedAt") == nil)
            let text = search.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                let digits = Customer.digits(text)
                var condition = Column("name").like("%\(text)%") || Column("email").like("%\(text)%")
                if digits.count >= 3 { condition = condition || Column("phoneDigits").like("%\(digits)%") }
                request = request.filter(condition)
            }
            return try request.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }
    }

    public func customer(_ id: UUID) throws -> Customer? {
        try db.read { try Customer.fetchOne($0, key: id.stored) }
    }

    /// Adds or updates a customer. Returns it as stored.
    @discardableResult
    public func save(_ customer: Customer, now: Date = .now) throws -> Customer {
        var customer = customer
        customer.phoneDigits = Customer.digits(customer.phone)
        customer.updatedAt = now
        try db.write { try customer.save($0) }
        return customer
    }

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

    // MARK: Repairs

    /// Opens a repair with the next ticket number, in Intake.
    public func createRepair(deviceID: UUID, complaint: String, promisedAt: Date? = nil, now: Date = .now) throws -> Repair {
        try db.write { db in
            let stored = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'nextTicketNumber'")
            // Never reuse a number, even if the counter was edited by hand.
            let highest = try Int.fetchOne(db, sql: "SELECT MAX(ticketNumber) FROM repair") ?? 0
            let number = max(Int(stored ?? "1") ?? 1, highest + 1)
            let repair = Repair(id: UUID(), deviceId: deviceID, ticketNumber: number, status: .intake,
                                complaint: complaint, diagnosis: "", receivedAt: now, promisedAt: promisedAt,
                                completedAt: nil, pickedUpAt: nil, createdAt: now, updatedAt: now, deletedAt: nil)
            try repair.insert(db)
            try db.execute(sql: "UPDATE meta SET value = ? WHERE key = 'nextTicketNumber'", arguments: [String(number + 1)])
            return repair
        }
    }

    public func repair(_ id: UUID) throws -> Repair? {
        try db.read { try Repair.fetchOne($0, key: id.stored) }
    }

    private static var rowRequest: QueryInterfaceRequest<RepairRow> {
        Repair.filter(Column("deletedAt") == nil)
            .including(required: Repair.device.including(required: Device.customer))
            .asRequest(of: RepairRow.self)
    }

    /// Repairs with their device and customer, in workflow order, oldest first within a status.
    public func repairRows(statuses: Set<RepairStatus> = Set(RepairStatus.allCases)) throws -> [RepairRow] {
        let rows = try db.read { db in
            try Self.rowRequest.filter(statuses.map(\.rawValue).contains(Column("status")))
                .order(Column("receivedAt")).fetchAll(db)
        }
        let order = Dictionary(uniqueKeysWithValues: RepairStatus.allCases.enumerated().map { ($1, $0) })
        return rows.sorted { order[$0.repair.status]! < order[$1.repair.status]! }
    }

    public func repairRow(_ id: UUID) throws -> RepairRow? {
        try db.read { try Self.rowRequest.filter(key: id.stored).fetchOne($0) }
    }

    /// A device's repairs, newest first.
    public func repairs(of deviceID: UUID) throws -> [Repair] {
        try db.read { db in
            try Repair.filter(Column("deviceId") == deviceID.stored && Column("deletedAt") == nil)
                .order(Column("receivedAt").desc).fetchAll(db)
        }
    }

    /// How many repairs are not closed (the Repairs badge).
    public func openRepairCount() throws -> Int {
        try db.read { db in
            try Repair.filter(Column("deletedAt") == nil && ![RepairStatus.pickedUp.rawValue, RepairStatus.cancelled.rawValue].contains(Column("status")))
                .fetchCount(db)
        }
    }

    /// Changes a repair's status, records the dates that go with it, and adds a status note.
    @discardableResult
    public func setStatus(_ status: RepairStatus, of repairID: UUID, now: Date = .now) throws -> Repair? {
        try db.write { db in
            guard var repair = try Repair.fetchOne(db, key: repairID.stored), repair.status != status else { return nil }
            repair.status = status
            switch status {
            case .ready: repair.completedAt = repair.completedAt ?? now
            case .pickedUp:
                repair.completedAt = repair.completedAt ?? now
                repair.pickedUpAt = now
            default:
                // Back on the bench: it is no longer done or picked up.
                if !status.isClosed { repair.pickedUpAt = nil }
                if status != .cancelled { repair.completedAt = nil }
            }
            repair.updatedAt = now
            try repair.update(db)
            try Note(owner: .repair, ownerId: repairID, kind: .status, text: status.rawValue, now: now).insert(db)
            return repair
        }
    }

    /// Saves the complaint, diagnosis, and promised date.
    public func update(_ repair: Repair, now: Date = .now) throws {
        var repair = repair
        repair.updatedAt = now
        try db.write { try repair.update($0) }
    }

    // MARK: Notes

    /// Notes on one customer, device, or repair, oldest first.
    public func notes(for owner: NoteOwner, id: UUID) throws -> [Note] {
        try db.read { db in
            try Note.filter(Column("ownerType") == owner.rawValue && Column("ownerId") == id.stored && Column("deletedAt") == nil)
                .order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
    }

    @discardableResult
    public func addNote(_ text: String, to owner: NoteOwner, id: UUID, now: Date = .now) throws -> Note? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let note = Note(owner: owner, ownerId: id, text: text, now: now)
        try db.write { try note.insert($0) }
        return note
    }

    public func editNote(_ id: UUID, text: String, now: Date = .now) throws {
        try db.write { db in
            guard var note = try Note.fetchOne(db, key: id.stored), note.kind == .text else { return }
            note.text = text
            note.updatedAt = now
            try note.update(db)
        }
    }

    // MARK: Trash

    /// Moves a record to the trash (sets deletedAt). Undo with `restore`.
    public func trash<R: BenchRecord>(_ type: R.Type, id: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var record = try R.fetchOne(db, key: id.stored) else { return }
            record.deletedAt = now
            record.updatedAt = now
            try record.update(db)
        }
    }

    public func restore<R: BenchRecord>(_ type: R.Type, id: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var record = try R.fetchOne(db, key: id.stored) else { return }
            record.deletedAt = nil
            record.updatedAt = now
            try record.update(db)
        }
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
