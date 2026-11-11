import BoardViewKit
import Foundation
import PDFKit

/// What the schematic says about each part on the board: its value and ratings, and the pages it is on.
struct SchematicFacts: Sendable {
    var values: [String: PartValue] = [:]
    /// Each part's pages, from 0, in order.
    var pages: [String: [Int]] = [:]

    /// Reads a schematic PDF for the board's part names. Slow (about 2 s for 80 pages): call it off the main thread.
    nonisolated static func read(_ url: URL, partNames: Set<String>) -> SchematicFacts {
        guard let document = PDFDocument(url: url) else { return SchematicFacts() }
        let words = words(in: document)
        var facts = SchematicFacts()
        facts.values = SchematicValues.read(words, partNames: partNames)
        var pages: [String: Set<Int>] = [:]
        for word in words {
            if let name = SchematicValues.partName(word.text, in: partNames) { pages[name, default: []].insert(word.page) }
        }
        facts.pages = pages.mapValues { $0.sorted() }
        return facts
    }

    /// Every word of every page, with where it is.
    nonisolated static func words(in document: PDFDocument) -> [SchematicWord] {
        var words: [SchematicWord] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string.map({ $0 as NSString }) else { continue }
            var start = -1
            func flush(_ end: Int) {
                defer { start = -1 }
                guard start >= 0, let selection = page.selection(for: NSRange(location: start, length: end - start)) else { return }
                let box = selection.bounds(for: page)
                guard !box.isNull, !box.isEmpty else { return }
                words.append(SchematicWord(text: text.substring(with: NSRange(location: start, length: end - start)), page: index,
                                           minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY))
            }
            for i in 0..<text.length {
                switch text.character(at: i) {
                case 9, 10, 13, 32: flush(i)
                default: if start < 0 { start = i }
                }
            }
            flush(text.length)
        }
        return words
    }
}
