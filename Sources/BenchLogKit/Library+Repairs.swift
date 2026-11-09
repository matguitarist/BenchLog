import Foundation
import GRDB

/// Repairs: ticket numbers, statuses and their dates, and the joined rows for lists.
extension Library {
    // MARK: Repairs

    /// Opens a repair with the next ticket number, in Intake.
    public func createRepair(deviceID: UUID, complaint: String, promisedAt: Date? = nil,
                             approval: ApprovalRule = .go, approvalLimitCents: Int? = nil, now: Date = .now) throws -> Repair {
        try db.write { db in
            let stored = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'nextTicketNumber'")
            // Never reuse a number, even if the counter was edited by hand.
            let highest = try Int.fetchOne(db, sql: "SELECT MAX(ticketNumber) FROM repair") ?? 0
            let number = max(Int(stored ?? "1") ?? 1, highest + 1)
            var repair = Repair(id: UUID(), deviceId: deviceID, ticketNumber: number, status: .intake,
                                complaint: complaint, diagnosis: "", receivedAt: now, promisedAt: promisedAt,
                                completedAt: nil, pickedUpAt: nil, createdAt: now, updatedAt: now, deletedAt: nil)
            repair.approvalRule = approval
            repair.approvalLimitCents = approval == .upTo ? max(approvalLimitCents ?? 0, 0) : nil
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
}
