import Foundation
import GRDB
import Testing
@testable import BenchLogKit

/// S-044 Stock history and counts.
@Suite struct StockTests {
    let library: Library
    let part: Part
    let repair: Repair

    init() throws {
        library = try Library()
        part = try library.save(Part(name: "iPhone 13 screen", costCents: 6_000, priceCents: 12_000, quantity: 5), fits: [])
        let customer = try library.save(Customer(name: "Léa"))
        let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Écran")
    }

    private func sum() throws -> Int { try library.stockHistory(of: part.id).reduce(0) { $0 + $1.move.delta } }

    @Test func everyChangeIsAMoveAndTheyAddUpToTheQuantity() throws {
        let use = try library.usePart(part.id, on: repair.id, quantity: 2)
        try library.setStatus(.installed, ofUse: use.id)
        try library.count(part.id, counted: 2, note: "Inventaire")
        try library.removeDamaged(part.id, quantity: 1, note: "Fissuré à la réception")
        try library.removeUse(use.id)
        let history = try library.stockHistory(of: part.id)
        #expect(history.map(\.move.reason) == [.returned, .damaged, .counted, .installed, .opening])
        #expect(history.map(\.move.delta) == [2, -1, -1, -2, 5])
        #expect(history[3].source == "#0001")
        #expect(history[2].move.note == "Inventaire")
        #expect(try sum() == library.part(part.id)?.quantity)
        #expect(try library.part(part.id)?.quantity == 3)
    }

    @Test func editingTheQuantityIsRecordedAsAdjusted() throws {
        var edited = part
        edited.quantity = 9
        try library.save(edited, fits: [])
        try library.adjustStock(of: part.id, by: -20)          // never below zero
        #expect(try library.stockHistory(of: part.id).map(\.move.delta) == [-9, 4, 5])
        #expect(try sum() == 0)
    }

    @Test func partsInStockBeforeHistoryGetAnOpeningMove() throws {
        let queue = try DatabaseQueue()
        try Library.migrator.migrate(queue, upTo: "v11-sales")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO part (id, name, quantity, createdAt, updatedAt) VALUES ('7c9e6679-7425-40de-944b-e07fc1f90ae7', 'Fan', 4, '2026-01-01', '2026-01-01');
                INSERT INTO part (id, name, quantity, createdAt, updatedAt) VALUES ('16fd2706-8baf-433b-82eb-8c7fada847da', 'Glue', 0, '2026-01-01', '2026-01-01');
                """)
        }
        try Library.migrator.migrate(queue)
        let moves = try queue.read { try StockMove.fetchAll($0) }
        #expect(moves.count == 1 && moves.first?.delta == 4 && moves.first?.reason == .opening)
    }
}
