import Foundation
import GRDB

/// Notes on any record, and the trash (soft delete) every record shares.
extension Library {
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
}
