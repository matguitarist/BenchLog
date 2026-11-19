import Foundation
import GRDB

/// What a meter was set to for a reading on a board.
public enum ReadingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Diode mode, black probe on ground: a drop in volts, or OL.
    case diode
    case voltage
    case resistance

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .diode: String(localized: "Diode")
        case .voltage: String(localized: "Voltage")
        case .resistance: String(localized: "Resistance")
        }
    }

    /// The unit the value is kept in.
    public var unit: String {
        switch self {
        case .diode, .voltage: "V"
        case .resistance: "Ω"
        }
    }

    /// Reads what was typed: "0.452", "452 mV", "3.3V", "12k", "1.2 MΩ", "OL". A diode value
    /// with no unit above 3 is millivolts, as many meters show it. Returns `.some(nil)` for OL
    /// (open loop), nil when the text isn't a reading.
    public func parse(_ text: String) -> Double?? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if s.uppercased() == "OL" || s.uppercased() == "O.L" || s.uppercased() == "O.L." { return .some(nil) }
        for unit in ["ohms", "ohm", "Ω", "V", "v"] where s.hasSuffix(unit) {
            s = String(s.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let hadUnit = s.count != text.trimmingCharacters(in: .whitespaces).count
        var factor = 1.0
        var prefixed = false
        if let last = s.last, let f = ["m": 0.001, "k": 1000, "K": 1000, "M": 1_000_000][String(last)] {
            // "m" is milli, but "M" (mega) only makes sense for resistance.
            if last != "M" || self == .resistance {
                factor = f
                prefixed = true
                s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let number = Double(s), number.isFinite else { return nil }
        if self == .diode, !hadUnit, !prefixed, number > 3 { return .some(number / 1000) }
        return .some(number * factor)
    }

    /// "0.452 V", "3.30 V", "12.4 kΩ", or "OL".
    public func format(_ value: Double?) -> String {
        guard let value else { return "OL" }
        switch self {
        case .diode:
            return value.formatted(.number.precision(.fractionLength(3))) + " V"
        case .voltage:
            return value.formatted(.number.precision(.fractionLength(2))) + " V"
        case .resistance:
            let (scaled, prefix): (Double, String) = abs(value) >= 1_000_000 ? (value / 1_000_000, "M")
                : abs(value) >= 1000 ? (value / 1000, "k") : (value, "")
            return scaled.formatted(.number.precision(.significantDigits(1...3))) + " \(prefix)Ω"
        }
    }
}

/// A measurement taken on a board during a repair: on one pin ("U7100.3") or a whole net.
public struct BoardReading: BenchRecord {
    public static let databaseTableName = "boardReading"

    public var id: UUID
    public var repairId: UUID
    /// The board file's name, so readings show on the board they were taken on.
    public var board: String
    /// A net's name, or a pin as "<part>.<pin number>".
    public var target: String
    public var isPin: Bool
    public var mode: ReadingMode
    /// In volts or ohms; nil is OL (open loop).
    public var value: Double?
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), repairId: UUID, board: String, target: String, isPin: Bool, mode: ReadingMode,
                value: Double?, note: String = "", now: Date = .now) {
        self.id = id
        self.repairId = repairId
        self.board = board
        self.target = target
        self.isPin = isPin
        self.mode = mode
        self.value = value
        self.note = note
        createdAt = now
        updatedAt = now
    }

    /// "0.452 V (diode)".
    public var summary: String { "\(mode.format(value)) (\(mode.label.lowercased()))" }
}

extension Library {
    /// The readings on a repair, oldest first; only those on `board` when it is given.
    public func boardReadings(repair: UUID, board: String? = nil) throws -> [BoardReading] {
        try db.read { db in
            var request = BoardReading.filter(Column("repairId") == repair.stored && Column("deletedAt") == nil)
            if let board { request = request.filter(Column("board") == board) }
            return try request.order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
    }

    @discardableResult
    public func addBoardReading(_ reading: BoardReading) throws -> BoardReading {
        var reading = reading
        reading.note = reading.note.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.write { try reading.insert($0) }
        return reading
    }

    /// The repair a board's readings go on: the repair it is attached to, or for a board on a
    /// device, that device's latest repair not yet picked up or cancelled.
    public func readingRepair(forAttachment id: UUID) throws -> UUID? {
        guard let file = try attachment(id) else { return nil }
        switch file.ownerType {
        case .repair:
            return file.ownerId
        case .device:
            return try db.read { db in
                try String.fetchOne(db, sql: """
                    SELECT id FROM repair WHERE deviceId = ? AND deletedAt IS NULL AND status NOT IN (?, ?)
                    ORDER BY receivedAt DESC, ticketNumber DESC LIMIT 1
                    """, arguments: [file.ownerId.stored, RepairStatus.pickedUp.rawValue, RepairStatus.cancelled.rawValue])
            }.flatMap(UUID.init(uuidString:))
        default:
            return nil
        }
    }
}
