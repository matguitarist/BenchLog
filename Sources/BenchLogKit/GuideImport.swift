import Foundation

/// One guide found in a folder, with what BenchLog guessed from its path. The import
/// review sheet lets people fix the guess before anything is added.
public struct GuideCandidate: Identifiable, Hashable, Sendable {
    public var id: String { sourcePath }
    /// Relative to the folder: "Nintendo/Consoles/NES/blinking-red-light.md".
    public var sourcePath: String
    public var file: URL
    public var format: GuideFormat
    public var title: String
    public var tags: [String]
    /// The images a Markdown guide embeds, found anywhere in the folder as Obsidian does.
    public var images: [URL]
    public var isOverview: Bool
    /// The guessed link, or nil for a general guide (a note at the top of the folder).
    public var link: GuideLink?
    /// Images the note names that are not in the folder.
    public var missingImages: [String]
}

/// Reads a folder of guides (an Obsidian vault, a folder of PDFs) and guesses each guide's
/// title, tags, and catalog link from its path:
/// `Nintendo/Consoles/NES/blinking-red-light.md` → Console, Nintendo, NES.
public struct GuideScanner {
    /// Category folder names, lowercased.
    static let categoryFolders: [String: DeviceCategory] = [
        "consoles": .console, "console": .console, "home consoles": .console,
        "portable consoles": .handheld, "portables": .handheld, "handhelds": .handheld, "handheld": .handheld,
        "phones": .phone, "phone": .phone, "smartphones": .phone, "mobile": .phone,
        "computers": .computer, "computer": .computer, "laptops": .computer, "desktops": .computer, "macs": .computer,
        "tablets": .tablet, "tablet": .tablet,
    ]
    /// Folder names that mean a catalog brand by another name.
    static let brandAliases: [String: String] = ["playstation": "Sony", "xbox": "Microsoft"]
    /// Folders that hold images, not models.
    static let pictureFolders: Set<String> = ["pictures", "images", "attachments", "assets", "media"]

    let library: Library

    public init(library: Library) {
        self.library = library
    }

    public func scan(_ root: URL) throws -> [GuideCandidate] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var guides: [URL] = []
        var images: [String: URL] = [:]
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == ".obsidian" || name == ".trash" { walker.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            if GuideFormat(fileName: name) != nil {
                guides.append(url)
            } else if MarkdownHTML.isImage(name), images[name.lowercased()] == nil {
                images[name.lowercased()] = url
            }
        }
        let catalog = try CatalogIndex(library)
        return try guides.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.map { file in
            let relative = String(file.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            let format = GuideFormat(fileName: file.lastPathComponent)!
            let text = format == .markdown ? (try String(contentsOf: file, encoding: .utf8)) : nil
            var embedded: [URL] = []
            var missing: [String] = []
            if let text {
                for name in Self.imageNames(in: text) {
                    let local = file.deletingLastPathComponent().appending(path: name).standardizedFileURL
                    if FileManager.default.fileExists(atPath: local.path) {
                        embedded.append(local)
                    } else if let found = images[(name as NSString).lastPathComponent.lowercased()] {
                        embedded.append(found)
                    } else {
                        missing.append(name)
                    }
                }
            }
            var seen = Set<String>()
            embedded = embedded.filter { seen.insert($0.lastPathComponent.lowercased()).inserted }
            let folders = relative.split(separator: "/").dropLast().map(String.init)
            return GuideCandidate(sourcePath: relative, file: file, format: format,
                                  title: Library.guessTitle(fileName: file.lastPathComponent, text),
                                  tags: text.map(Self.tags) ?? [], images: embedded,
                                  isOverview: file.lastPathComponent.lowercased() == "_index.md",
                                  link: catalog.guess(folders), missingImages: missing)
        }
    }

    /// The images a note names: `![[a.png]]`, `![[a.png|300]]`, and `![alt](Pictures/a.png)`.
    static func imageNames(in text: String) -> [String] {
        var names: [String] = []
        for match in text.matches(of: /!\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]/) {
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            if MarkdownHTML.isImage(name) { names.append(name) }
        }
        for match in text.matches(of: /!\[[^\]]*\]\(([^)\s]+)\)/) {
            let path = String(match.1)
            if !path.hasPrefix("http"), MarkdownHTML.isImage(path) { names.append(path.removingPercentEncoding ?? path) }
        }
        return names
    }

    /// Tags from front matter (`tags: [a, b]` or a list) and from lines that hold only tags.
    static func tags(_ text: String) -> [String] {
        var tags: [String] = []
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            var inTags = false
            for line in lines[1..<end] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("tags:") {
                    let value = trimmed.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                    tags += value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    inTags = value.isEmpty
                } else if inTags, trimmed.hasPrefix("- ") {
                    tags.append(String(trimmed.dropFirst(2)))
                } else {
                    inTags = false
                }
            }
        }
        for line in lines {
            let words = line.split(separator: " ")
            guard !words.isEmpty, words.allSatisfy({ $0.hasPrefix("#") && $0.count > 1 && !$0.dropFirst().hasPrefix("#") }) else { continue }
            tags += words.map { String($0.dropFirst()) }
        }
        return Guide.tagText(tags).split(separator: " ").map(String.init)
    }
}

/// The catalog in memory, to match folder names against it.
struct CatalogIndex {
    /// category → brand → models, in the catalog's spelling.
    var brands: [DeviceCategory: [String: [String: [String]]]] = [:]

    init(_ library: Library) throws {
        for (category, nodes) in try library.catalogOutline() {
            for brand in nodes {
                var models: [String: [String]] = [:]
                for model in brand.children ?? [] {
                    models[model.name] = (model.children ?? []).map(\.name)
                }
                brands[category, default: [:]][brand.name] = models
            }
        }
    }

    /// The link a guide's folders imply: [brand, category folder?, model?, revision?] in any
    /// order the vault uses, with names matched to the catalog's spelling.
    func guess(_ folders: [String]) -> GuideLink? {
        var names = folders.filter { !GuideScanner.pictureFolders.contains($0.lowercased()) }
        var category: DeviceCategory?
        if let index = names.firstIndex(where: { GuideScanner.categoryFolders[$0.lowercased()] != nil }) {
            category = GuideScanner.categoryFolders[names[index].lowercased()]
            names.remove(at: index)
        }
        guard let folderBrand = names.first else {
            return category.map { GuideLink(category: $0) }
        }
        let brandName = GuideScanner.brandAliases[folderBrand.lowercased()] ?? folderBrand
        let modelName = names.count > 1 ? names[1] : ""
        let revisionName = names.count > 2 ? names[2] : ""

        // The categories that know this brand (and model), the folder's category first.
        let candidates = (category.map { [$0] } ?? []) + DeviceCategory.allCases.filter { $0 != category }
        func brand(in category: DeviceCategory) -> (String, [String: [String]])? {
            brands[category]?.first { $0.key.caseInsensitiveCompare(brandName) == .orderedSame }
        }
        func model(_ models: [String: [String]]) -> (String, [String])? {
            models.first { $0.key.caseInsensitiveCompare(modelName) == .orderedSame }
        }
        if !modelName.isEmpty {
            for candidate in candidates {
                guard let (brandSpelling, models) = brand(in: candidate), let (modelSpelling, revisions) = model(models) else { continue }
                let revision = revisions.first { $0.caseInsensitiveCompare(revisionName) == .orderedSame } ?? revisionName
                return GuideLink(category: candidate, brand: brandSpelling, model: modelSpelling, revision: revision)
            }
        }
        for candidate in candidates {
            if let (brandSpelling, _) = brand(in: candidate) {
                return GuideLink(category: category ?? candidate, brand: brandSpelling, model: modelName, revision: revisionName)
            }
        }
        return GuideLink(category: category ?? .other, brand: brandName, model: modelName, revision: revisionName)
    }
}

/// What an import did.
public struct GuideImportResult: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    public init() {}
}

extension Library {
    /// The images a single Markdown note embeds, looked for next to it and in the usual
    /// picture folders beside it (a whole vault goes through `GuideScanner` instead).
    public func markdownImagesBeside(_ note: URL) throws -> [URL] {
        guard GuideFormat(fileName: note.lastPathComponent) == .markdown else { return [] }
        let text = try String(contentsOf: note, encoding: .utf8)
        let folder = note.deletingLastPathComponent()
        let places = [folder] + ["Pictures", "Images", "attachments", "Attachments", "assets"].map { folder.appending(path: $0) }
        return GuideScanner.imageNames(in: text).compactMap { name in
            let candidates = [folder.appending(path: name)] + places.map { $0.appending(path: (name as NSString).lastPathComponent) }
            return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    /// Adds the candidates. A guide imported before from the same path is updated when its
    /// file or images changed (its links stay as they are) and left alone otherwise.
    @discardableResult
    public func importGuides(_ candidates: [GuideCandidate], now: Date = .now) throws -> GuideImportResult {
        var result = GuideImportResult()
        for candidate in candidates {
            if let existing = try guide(sourcePath: candidate.sourcePath) {
                let data = try Data(contentsOf: candidate.file)
                let images = try candidate.images.map { try Data(contentsOf: $0) }
                if Self.hash(data, images) == existing.sourceHash {
                    result.unchanged += 1
                } else {
                    try replaceGuideFile(existing.id, file: candidate.file, images: candidate.images,
                                         title: candidate.title, tags: candidate.tags, now: now)
                    result.updated += 1
                }
            } else {
                try addGuide(file: candidate.file, title: candidate.title, tags: candidate.tags,
                             links: candidate.link.map { [$0] } ?? [], images: candidate.images,
                             sourcePath: candidate.sourcePath, isOverview: candidate.isOverview, now: now)
                result.added += 1
            }
        }
        return result
    }
}
