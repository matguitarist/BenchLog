import Foundation
import GRDB
import UniformTypeIdentifiers

/// What a photo or file records.
public enum AttachmentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The device's condition when it came in.
    case intake
    /// Taken during the repair.
    case progress
    /// The device as it goes back.
    case final
    /// A PDF, a boardview, or any other file.
    case document

    public var id: String { rawValue }
}

/// A photo or file attached to a customer, device, or repair.
public struct Attachment: BenchRecord {
    public static let databaseTableName = "attachment"

    public var id: UUID
    public var ownerType: NoteOwner
    public var ownerId: UUID
    public var kind: AttachmentKind
    /// Relative to the library's Files folder: "2026/3f2a….jpg".
    public var path: String
    /// The name the file had before it was added: "IMG_1042.HEIC".
    public var originalName: String
    /// A Uniform Type Identifier: "public.jpeg", "com.adobe.pdf".
    public var contentType: String
    public var size: Int64
    public var caption: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public var type: UTType? { UTType(contentType) }
    public var isImage: Bool { type?.conforms(to: .image) ?? false }

    /// Boardview files from the common viewers (OpenBoardView, FlexBV, BoardViewer, Allegro, TVW).
    public static let boardviewExtensions: Set<String> = ["brd", "bdv", "bv", "fz", "cad", "tvw", "asc", "cst", "gr", "f2b", "bvr"]
    public var isBoardview: Bool {
        Self.boardviewExtensions.contains((originalName as NSString).pathExtension.lowercased())
    }
}

extension Library {
    /// Copies a file into the library and attaches it. The original is left where it was.
    @discardableResult
    public func addAttachment(copying source: URL, to owner: NoteOwner, id ownerID: UUID,
                              kind: AttachmentKind? = nil, now: Date = .now) throws -> Attachment {
        let data = try Data(contentsOf: source)
        return try addAttachment(data: data, originalName: source.lastPathComponent, to: owner, id: ownerID, kind: kind, now: now)
    }

    /// Stores bytes (a pasted image, a photo from Continuity Camera) as a file and attaches it.
    /// Without a kind: images on a repair still in Intake are intake photos, other images are
    /// progress photos, and everything else is a document.
    @discardableResult
    public func addAttachment(data: Data, originalName: String, to owner: NoteOwner, id ownerID: UUID,
                              kind: AttachmentKind? = nil, now: Date = .now) throws -> Attachment {
        let ext = (originalName as NSString).pathExtension.lowercased()
        let type = UTType(filenameExtension: ext) ?? .data
        let id = UUID()
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        let relative = "\(year)/\(id.stored)" + (ext.isEmpty ? "" : ".\(ext)")
        let destination = filesURL.appending(path: relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)

        var chosen = kind ?? .document
        if kind == nil, type.conforms(to: .image) {
            let inIntake = try owner == .repair && repair(ownerID)?.status == .intake
            chosen = inIntake ? .intake : .progress
        }
        let attachment = Attachment(id: id, ownerType: owner, ownerId: ownerID, kind: chosen, path: relative,
                                    originalName: originalName, contentType: type.identifier, size: Int64(data.count),
                                    caption: "", createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try db.write { try attachment.insert($0) }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return attachment
    }

    /// Photos and files on one record: intake photos first, then the rest, each oldest first.
    public func attachments(for owner: NoteOwner, id: UUID) throws -> [Attachment] {
        let all = try db.read { db in
            try Attachment.filter(Column("ownerType") == owner.rawValue && Column("ownerId") == id.stored && Column("deletedAt") == nil)
                .order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
        return all.filter { $0.kind == .intake } + all.filter { $0.kind != .intake }
    }

    public func attachment(_ id: UUID) throws -> Attachment? {
        try db.read { try Attachment.fetchOne($0, key: id.stored) }
    }

    /// Where an attachment's file is on disk.
    public func fileURL(for attachment: Attachment) -> URL {
        filesURL.appending(path: attachment.path)
    }

    public func setKind(_ kind: AttachmentKind, of id: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var attachment = try Attachment.fetchOne(db, key: id.stored) else { return }
            attachment.kind = kind
            attachment.updatedAt = now
            try attachment.update(db)
        }
    }

    public func setCaption(_ caption: String, of id: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var attachment = try Attachment.fetchOne(db, key: id.stored) else { return }
            attachment.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            attachment.updatedAt = now
            try attachment.update(db)
        }
    }
}
