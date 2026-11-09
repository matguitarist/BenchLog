import CryptoKit
import Foundation
import GRDB

/// What kind of file a guide is.
public enum GuideFormat: String, Codable, Sendable {
    case pdf, markdown

    /// The format a file name implies, or nil when BenchLog cannot read it as a guide.
    public init?(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "md", "markdown": self = .markdown
        default: return nil
        }
    }
}

/// A repair guide: a PDF or a Markdown note, linked to the catalog models it covers.
public struct Guide: BenchRecord {
    public static let databaseTableName = "guide"

    public var id: UUID
    public var title: String
    public var format: GuideFormat
    /// Lowercased tags separated by spaces: "nes power".
    public var tags: String
    /// The attachment that holds the guide's file.
    public var fileId: UUID?
    /// Where an imported guide came from, relative to the imported folder; empty when added by hand.
    public var sourcePath: String
    /// The SHA-256 of the imported file and its images, to tell when a re-import changed it.
    public var sourceHash: String
    /// A model's overview guide (`_index.md` in a vault).
    public var isOverview: Bool
    /// The PDF page the guide was last left at, from 0.
    public var lastPage: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), title: String, format: GuideFormat, tags: [String] = [], sourcePath: String = "",
                sourceHash: String = "", isOverview: Bool = false, now: Date = .now) {
        self.id = id
        self.title = title
        self.format = format
        self.tags = Self.tagText(tags)
        self.sourcePath = sourcePath
        self.sourceHash = sourceHash
        self.isOverview = isOverview
        lastPage = 0
        createdAt = now
        updatedAt = now
    }

    public var tagList: [String] { tags.split(separator: " ").map(String.init) }

    /// Tags as stored: lowercased, without "#", no repeats, space-separated.
    public static func tagText(_ tags: [String]) -> String {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#,")).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: " ")
    }
}

/// The part of the catalog a guide covers. Empty names widen it: no revision means every
/// revision of the model, no model every model of the brand, no brand the whole category.
public struct GuideLink: Hashable, Sendable, Codable {
    public var category: DeviceCategory
    public var brand: String
    public var model: String
    public var revision: String

    public init(category: DeviceCategory, brand: String = "", model: String = "", revision: String = "") {
        self.category = category
        self.brand = brand
        self.model = model
        self.revision = revision
    }

    /// 3 for a revision, 2 a model, 1 a brand, 0 a whole category.
    public var specificity: Int { !revision.isEmpty ? 3 : !model.isEmpty ? 2 : !brand.isEmpty ? 1 : 0 }

    /// "Nintendo NES OLED Model", without the category (the app names it).
    public var names: String { [brand, model, revision].filter { !$0.isEmpty }.joined(separator: " ") }

    /// True when the link covers the device.
    public func covers(_ device: Device) -> Bool {
        func same(_ a: String, _ b: String) -> Bool { a.isEmpty || a.caseInsensitiveCompare(b) == .orderedSame }
        return category == device.category && same(brand, device.brand) && same(model, device.model) && same(revision, device.revision)
    }
}

/// A guide with its links, for lists.
public struct GuideRow: Identifiable, Hashable, Sendable {
    public var guide: Guide
    public var links: [GuideLink]
    public var id: UUID { guide.id }
}

/// A guide that covers a device, and how closely: the link's specificity.
public struct GuideMatch: Identifiable, Hashable, Sendable {
    public var guide: Guide
    public var link: GuideLink
    public var id: UUID { guide.id }
}

extension Library {
    // MARK: Adding

    /// Copies a guide file (and the images a Markdown guide embeds) into the library.
    @discardableResult
    public func addGuide(file: URL, title: String? = nil, tags: [String] = [], links: [GuideLink] = [],
                         images: [URL] = [], sourcePath: String = "", isOverview: Bool = false, now: Date = .now) throws -> Guide {
        guard let format = GuideFormat(fileName: file.lastPathComponent) else { throw GuideError.unsupported(file.lastPathComponent) }
        let data = try Data(contentsOf: file)
        let imageData = try images.map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
        var guide = Guide(title: title ?? Self.guessTitle(fileName: file.lastPathComponent, format == .markdown ? String(decoding: data, as: UTF8.self) : nil),
                          format: format, tags: tags, sourcePath: sourcePath,
                          sourceHash: Self.hash(data, imageData.map(\.1)), isOverview: isOverview, now: now)
        try db.write { try guide.insert($0) }
        let file = try addAttachment(data: data, originalName: file.lastPathComponent, to: .guide, id: guide.id, kind: .document, now: now)
        for (name, bytes) in imageData {
            try addAttachment(data: bytes, originalName: name, to: .guide, id: guide.id, kind: .document, now: now)
        }
        guide.fileId = file.id
        try db.write { db in
            try guide.update(db)
            try Self.replaceLinks(db, of: guide.id, with: links)
        }
        return guide
    }

    /// Replaces a guide's file and images with new ones (a re-import of a changed note).
    public func replaceGuideFile(_ guideID: UUID, file: URL, images: [URL], title: String, tags: [String], now: Date = .now) throws {
        guard var guide = try self.guide(guideID) else { return }
        let data = try Data(contentsOf: file)
        let imageData = try images.map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
        for old in try attachments(for: .guide, id: guideID) { try trash(Attachment.self, id: old.id, now: now) }
        let stored = try addAttachment(data: data, originalName: file.lastPathComponent, to: .guide, id: guideID, kind: .document, now: now)
        for (name, bytes) in imageData {
            try addAttachment(data: bytes, originalName: name, to: .guide, id: guideID, kind: .document, now: now)
        }
        guide.fileId = stored.id
        guide.title = title
        guide.tags = Guide.tagText(tags)
        guide.sourceHash = Self.hash(data, imageData.map(\.1))
        guide.updatedAt = now
        try db.write { try guide.update($0) }
    }

    // MARK: Reading

    public func guide(_ id: UUID) throws -> Guide? {
        try db.read { try Guide.fetchOne($0, key: id.stored) }
    }

    /// Guides whose title or tags match, overviews first, then by title.
    public func guideRows(matching search: String = "") throws -> [GuideRow] {
        try db.read { db in
            var request = Guide.filter(Column("deletedAt") == nil)
            let words = search.split(separator: " ").map(String.init)
            for word in words {
                let pattern = "%\(word)%"
                request = request.filter(sql: "(title LIKE ? OR tags LIKE ?)", arguments: [pattern, pattern])
            }
            let guides = try request.order(sql: "isOverview DESC, title COLLATE NOCASE").fetchAll(db)
            let links = try Self.allLinks(db)
            return guides.map { GuideRow(guide: $0, links: links[$0.id] ?? []) }
        }
    }

    public func links(of guideID: UUID) throws -> [GuideLink] {
        try db.read { try Self.allLinks($0, guideID: guideID)[guideID] ?? [] }
    }

    /// The guides that cover a device, most specific first: revision, model, brand, category.
    public func guides(for device: Device) throws -> [GuideMatch] {
        let rows = try guideRows()
        let matches = rows.compactMap { row -> GuideMatch? in
            guard let best = row.links.filter({ $0.covers(device) }).max(by: { $0.specificity < $1.specificity }) else { return nil }
            return GuideMatch(guide: row.guide, link: best)
        }
        return matches.sorted { a, b in
            if a.link.specificity != b.link.specificity { return a.link.specificity > b.link.specificity }
            if a.guide.isOverview != b.guide.isOverview { return a.guide.isOverview }
            return a.guide.title.localizedStandardCompare(b.guide.title) == .orderedAscending
        }
    }

    /// The attachment holding the guide's file.
    public func guideFile(_ guide: Guide) throws -> Attachment? {
        guard let fileId = guide.fileId else { return nil }
        return try attachment(fileId)
    }

    /// A Markdown guide's text.
    public func guideText(_ guide: Guide) throws -> String {
        guard guide.format == .markdown, let file = try guideFile(guide) else { return "" }
        return String(decoding: try Data(contentsOf: fileURL(for: file)), as: UTF8.self)
    }

    /// The guide a vault wiki link points to: `[[blinking-red-light]]` or `[[Nintendo/Consoles/NES/audio-problems]]`.
    public func guide(wikiTarget: String) throws -> Guide? {
        let stem = ((wikiTarget as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        return try guideRows().first { row in
            let source = ((row.guide.sourcePath as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            return (!source.isEmpty && source == stem) || row.guide.title.lowercased() == stem
        }?.guide
    }

    /// The imported guide from this source path, if any.
    public func guide(sourcePath: String) throws -> Guide? {
        guard !sourcePath.isEmpty else { return nil }
        return try db.read { try Guide.filter(Column("sourcePath") == sourcePath && Column("deletedAt") == nil).fetchOne($0) }
    }

    // MARK: Changing

    /// Saves a guide's title, tags, and links.
    @discardableResult
    public func save(_ guide: Guide, links: [GuideLink], now: Date = .now) throws -> Guide {
        var guide = guide
        guide.updatedAt = now
        try db.write { db in
            try guide.save(db)
            try Self.replaceLinks(db, of: guide.id, with: links)
        }
        return guide
    }

    /// Remembers the PDF page a guide was left at. Changes nothing else, not even updatedAt.
    public func setLastPage(_ page: Int, of guideID: UUID) throws {
        try db.write { try $0.execute(sql: "UPDATE guide SET lastPage = ? WHERE id = ?", arguments: [page, guideID.stored]) }
    }

    // MARK: Helpers

    static func replaceLinks(_ db: Database, of guideID: UUID, with links: [GuideLink]) throws {
        try db.execute(sql: "DELETE FROM guideLink WHERE guideId = ?", arguments: [guideID.stored])
        for link in links {
            try db.execute(sql: "INSERT OR IGNORE INTO guideLink VALUES (?, ?, ?, ?, ?)",
                           arguments: [guideID.stored, link.category.rawValue, link.brand, link.model, link.revision])
        }
    }

    static func allLinks(_ db: Database, guideID: UUID? = nil) throws -> [UUID: [GuideLink]] {
        var sql = "SELECT guideId, category, brand, model, revision FROM guideLink"
        var arguments: StatementArguments = []
        if let guideID {
            sql += " WHERE guideId = ?"
            arguments = [guideID.stored]
        }
        sql += " ORDER BY category, brand COLLATE NOCASE, model COLLATE NOCASE, revision COLLATE NOCASE"
        var result: [UUID: [GuideLink]] = [:]
        for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
            guard let id = UUID(uuidString: row["guideId"]), let category = DeviceCategory(rawValue: row["category"]) else { continue }
            result[id, default: []].append(GuideLink(category: category, brand: row["brand"], model: row["model"], revision: row["revision"]))
        }
        return result
    }

    /// The first `# ` heading of a Markdown note, or the file name as words:
    /// "blinking-red-light.md" → "Blinking Red Light".
    public static func guessTitle(fileName: String, _ markdown: String?) -> String {
        if let markdown {
            for line in markdown.split(separator: "\n", omittingEmptySubsequences: true).prefix(40) where line.hasPrefix("# ") {
                let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        let stem = (fileName as NSString).deletingPathExtension
        let words = stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map { word in word.prefix(1).uppercased() + word.dropFirst() }
        return words.joined(separator: " ")
    }

    static func hash(_ file: Data, _ images: [Data]) -> String {
        var hasher = SHA256()
        hasher.update(data: file)
        for image in images { hasher.update(data: image) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum GuideError: LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): "“\(name)” is not a PDF or a Markdown file."
        }
    }
}
