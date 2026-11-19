import Foundation
import GRDB

public enum RepairError: LocalizedError, Equatable {
    /// A warranty repair must follow a repair of the same device.
    case warrantyOfAnotherDevice

    public var errorDescription: String? {
        switch self {
        case .warrantyOfAnotherDevice:
            String(localized: "A warranty repair must follow an earlier repair of the same device.")
        }
    }
}

// S-085: a repair opened as the warranty of an earlier one ("warranty of #0042").
extension Library {
    /// The device's earlier repairs a new one can be the warranty of: those Ready or Picked
    /// Up, newest first.
    public func warrantyCandidates(deviceID: UUID, excluding: UUID? = nil) throws -> [Repair] {
        try db.read { db in
            var request = Repair.filter(Column("deviceId") == deviceID.stored && Column("deletedAt") == nil
                                        && [RepairStatus.ready.rawValue, RepairStatus.pickedUp.rawValue].contains(Column("status")))
            if let excluding { request = request.filter(Column("id") != excluding.stored) }
            return try request.order(Column("receivedAt").desc, Column("ticketNumber").desc).fetchAll(db)
        }
    }

    /// The repairs opened as the warranty of this one, oldest first.
    public func warrantyRepairs(of id: UUID) throws -> [Repair] {
        try db.read { db in
            try Repair.filter(Column("warrantyOfId") == id.stored && Column("deletedAt") == nil)
                .order(Column("receivedAt"), Column("ticketNumber")).fetchAll(db)
        }
    }

    /// Days from pickup (or from Ready, when never picked up) to `now`: how far into its
    /// warranty a repair is.
    public static func daysSinceDone(_ repair: Repair, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let done = repair.pickedUpAt ?? repair.completedAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: done), to: calendar.startOfDay(for: now)).day
    }
}
