import Foundation
import GRDB

// The records BenchLog keeps. Each is one SQLite table (docs/SCHEMA.md).
// Every row has a UUID id stored as lowercase text, createdAt, updatedAt,
// and a nullable deletedAt: deleting sets deletedAt, so a later sync can
// send the deletion and Undo can bring the row back.

/// What every stored record shares.
public protocol BenchRecord: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord
    where ID == UUID {
    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension BenchRecord {
    /// Ids are text ("3f2a…"), readable by any SQLite client.
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }
}

extension UUID {
    /// The id as it is stored, for queries: UUID's own database value is a 16-byte blob.
    public var stored: String { uuidString.lowercased() }
}

// MARK: - Customer

/// The language a customer's intake slips, estimates, and invoices print in.
public enum DocumentsLanguage: String, Codable, CaseIterable, Sendable {
    case french = "fr"
    case english = "en"
}

public struct Customer: BenchRecord {
    public static let databaseTableName = "customer"

    public var id: UUID
    public var name: String
    public var phone: String
    /// The phone's digits only, so "514 555-1234" and "5145551234" find each other.
    public var phoneDigits: String
    public var email: String
    public var address: String
    public var documentsLanguage: DocumentsLanguage
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, phone: String = "", email: String = "", address: String = "",
                documentsLanguage: DocumentsLanguage = .french, now: Date = .now) {
        self.id = id
        self.name = name
        self.phone = phone
        phoneDigits = Self.digits(phone)
        self.email = email
        self.address = address
        self.documentsLanguage = documentsLanguage
        createdAt = now
        updatedAt = now
    }

    public static func digits(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) && $0.isASCII }.map(Character.init))
    }

    static let devices = hasMany(Device.self)
}

// MARK: - Device

public enum DeviceCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }
    case computer, phone, tablet, console, handheld, other
}

public struct Device: BenchRecord {
    public static let databaseTableName = "device"

    public var id: UUID
    public var customerId: UUID
    public var category: DeviceCategory
    public var brand: String
    public var model: String
    public var revision: String
    public var serial: String
    public var colour: String
    public var condition: String
    /// The unlock code, or a pattern as the dots in order ("1-5-9-6").
    public var passcode: String
    public var passcodeIsPattern: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), customerId: UUID, category: DeviceCategory, brand: String, model: String,
                revision: String = "", serial: String = "", colour: String = "", condition: String = "",
                passcode: String = "", passcodeIsPattern: Bool = false, now: Date = .now) {
        self.id = id
        self.customerId = customerId
        self.category = category
        self.brand = brand
        self.model = model
        self.revision = revision
        self.serial = serial
        self.colour = colour
        self.condition = condition
        self.passcode = passcode
        self.passcodeIsPattern = passcodeIsPattern
        createdAt = now
        updatedAt = now
    }

    /// "Nintendo Switch OLED Model".
    public var title: String {
        [brand, model, revision].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static let customer = belongsTo(Customer.self)
    static let repairs = hasMany(Repair.self)
}

// MARK: - Repair

/// Where a repair is, in workflow order.
public enum RepairStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }
    case intake, diagnosing, awaitingApproval, waitingOnParts, inProgress, ready, pickedUp, cancelled

    /// Picked Up and Cancelled close a repair.
    public var isClosed: Bool { self == .pickedUp || self == .cancelled }
}

public struct Repair: BenchRecord {
    public static let databaseTableName = "repair"

    public var id: UUID
    public var deviceId: UUID
    public var ticketNumber: Int
    public var status: RepairStatus
    public var complaint: String
    public var diagnosis: String
    public var receivedAt: Date
    public var promisedAt: Date?
    public var completedAt: Date?
    public var pickedUpAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public var ticket: TicketNumber { TicketNumber(ticketNumber) }

    /// Whole days on the bench: from check-in to pickup, or to now while it is still here.
    public func benchDays(now: Date = .now, calendar: Calendar = .current) -> Int {
        let end = pickedUpAt ?? now
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: receivedAt),
                                              to: calendar.startOfDay(for: end)).day ?? 0)
    }

    static let device = belongsTo(Device.self)
}

// MARK: - Note

/// What a note is attached to.
public enum NoteOwner: String, Codable, Sendable {
    case customer, device, repair, guide
}

public enum NoteKind: String, Codable, Sendable {
    /// Text someone typed.
    case text
    /// Written by BenchLog when a repair's status changes; `text` is the new status's raw value.
    case status
}

public struct Note: BenchRecord {
    public static let databaseTableName = "note"

    public var id: UUID
    public var ownerType: NoteOwner
    public var ownerId: UUID
    public var kind: NoteKind
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), owner: NoteOwner, ownerId: UUID, kind: NoteKind = .text, text: String, now: Date = .now) {
        self.id = id
        ownerType = owner
        self.ownerId = ownerId
        self.kind = kind
        self.text = text
        createdAt = now
        updatedAt = now
    }

    /// For a status note, the status it records.
    public var status: RepairStatus? { kind == .status ? RepairStatus(rawValue: text) : nil }
}

// MARK: - Joined rows for lists

/// A repair with its device and the device's customer, for lists and the detail page.
public struct RepairRow: Decodable, FetchableRecord, Hashable, Sendable, Identifiable {
    public var repair: Repair
    public var device: Device
    public var customer: Customer
    public var id: UUID { repair.id }
}

/// A device with its customer and the status of its latest repair.
public struct DeviceRow: Hashable, Sendable, Identifiable {
    public var device: Device
    public var customer: Customer
    public var lastStatus: RepairStatus?
    public var id: UUID { device.id }
}
