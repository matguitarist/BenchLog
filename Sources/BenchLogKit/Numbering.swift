import Foundation
import GRDB

/// Numbers that must be unique across devices: tickets, invoices, and credit notes.
public enum NumberingError: LocalizedError, Equatable {
    /// A connected library takes invoice and credit numbers from the server, which is away.
    case needsServer
    /// A connected library used all the ticket numbers it had reserved while offline.
    case noTicketNumbers

    public var errorDescription: String? {
        switch self {
        case .needsServer:
            String(localized: "Unable to number the document: the BenchLog server is out of reach. Invoice and credit note numbers come from the server, so two devices never use the same one. Try again once it is back.")
        case .noTicketNumbers:
            String(localized: "No ticket numbers are left on this Mac while the server is out of reach. Try again once it is back.")
        }
    }
}

/// A run of ticket numbers the server gave this device: `next` up to, not including, `end`.
struct TicketBlock: Codable, Hashable, Sendable {
    var next: Int
    var end: Int
    var remaining: Int { max(0, end - next) }
}

extension Library {
    /// How many ticket numbers a device keeps in reserve, and how many it asks for at once.
    static let ticketReserve = 10
    static let ticketBlockSize = 20

    static func ticketBlocks(_ db: Database) throws -> [TicketBlock] {
        guard let json = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'ticketBlocks'") else { return [] }
        return (try? JSONDecoder().decode([TicketBlock].self, from: Data(json.utf8))) ?? []
    }

    static func saveTicketBlocks(_ blocks: [TicketBlock], _ db: Database) throws {
        let live = blocks.filter { $0.remaining > 0 }
        let json = String(decoding: try JSONEncoder().encode(live), as: UTF8.self)
        try db.execute(sql: "INSERT INTO meta (key, value) VALUES ('ticketBlocks', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                       arguments: [json])
    }

    /// The next reserved ticket number, or nil when this library is not connected.
    static func takeReservedTicket(_ db: Database) throws -> Int? {
        guard try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'syncServer'") != nil else { return nil }
        var blocks = try ticketBlocks(db)
        guard let index = blocks.firstIndex(where: { $0.remaining > 0 }) else { throw NumberingError.noTicketNumbers }
        let number = blocks[index].next
        blocks[index].next += 1
        try saveTicketBlocks(blocks, db)
        return number
    }

    /// Ticket numbers this device still holds.
    public func reservedTickets() throws -> Int {
        try db.read { try Self.ticketBlocks($0).reduce(0) { $0 + $1.remaining } }
    }

    func addTicketBlock(first: Int, count: Int) throws {
        try db.write { db in
            try Self.saveTicketBlocks(try Self.ticketBlocks(db) + [TicketBlock(next: first, end: first + count)], db)
        }
    }
}
