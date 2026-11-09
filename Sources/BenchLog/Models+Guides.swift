import BenchLogKit
import Foundation

/// Guides: adding, editing, importing, and reading.
extension AppModel {
    /// Adds PDF and Markdown files as guides with no links yet, and selects the last one.
    /// A folder opens the import review instead. Returns the guides added.
    @discardableResult
    func addGuides(_ urls: [URL]) -> [Guide] {
        if let folder = urls.first(where: { $0.hasDirectoryPath }) {
            sheet = .importGuides(folder)
            return []
        }
        let files = urls.filter { GuideFormat(fileName: $0.lastPathComponent) != nil }
        guard !files.isEmpty else {
            problem = String(localized: "Guides are PDF or Markdown files.")
            return []
        }
        let added = files.compactMap { url in
            write("Added guide “\(url.lastPathComponent)”") { library in
                // A Markdown note's images beside it come along.
                let images = try library.markdownImagesBeside(url)
                return try library.addGuide(file: url, images: images)
            }
        }
        if let last = added.last {
            selectedGuide = last.id
            if added.count == 1 { sheet = .editGuide(last.id) }
        }
        return added
    }

    @discardableResult
    func save(_ guide: Guide, links: [GuideLink]) -> Guide? {
        write("Saved guide \(guide.id.stored) (\(guide.title))") { try $0.save(guide, links: links) }
    }

    @discardableResult
    func importGuides(_ candidates: [GuideCandidate]) -> GuideImportResult? {
        write("Imported \(candidates.count) guides") { try $0.importGuides(candidates) }
    }

    /// Remembers the page without reloading anything: turning a page must not redraw the app.
    func rememberPage(_ page: Int, of guideID: UUID) {
        try? library?.setLastPage(page, of: guideID)
    }

    /// Opens the guide a wiki link in a Markdown guide points to.
    func openGuide(wikiTarget: String) {
        if let guide = read(nil, { try $0.guide(wikiTarget: wikiTarget) }) {
            open(.guide(guide.id))
        } else {
            problem = String(localized: "No guide named “\(wikiTarget)”. Import the note it links to, then try again.")
        }
    }
}
