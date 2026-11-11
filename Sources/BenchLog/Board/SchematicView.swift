import AppKit
import BoardViewKit
import PDFKit
import SwiftUI

/// Finds part and net names in the schematic, and reports names people double-click.
@MainActor
final class SchematicController {
    weak var view: SchematicPDFView?
    /// A name double-clicked (or selected) in the schematic.
    var onPick: ((String) -> Void)?
    /// A schematic finished loading.
    var onLoad: (() -> Void)?
    private var results: [PDFSelection] = []
    private(set) var current = -1

    /// Highlights every whole-name match of `term`. With `reveal`, shows the first; without, keeps
    /// the page where it is and counts the match under the selection people made as the current one.
    func find(_ term: String, reveal: Bool) -> Int {
        guard let view, let document = view.document else { return 0 }
        let previous = view.currentSelection
        results = term.isEmpty ? [] : document.findString(term, withOptions: []).filter { isWholeName($0, term: term) }
        for result in results { result.color = .findHighlightColor }
        view.highlightedSelections = results.isEmpty ? nil : results
        current = -1
        if reveal {
            if !results.isEmpty { step(1) } else { view.clearSelection() }
        } else if let previous, let page = previous.pages.first {
            let bounds = previous.bounds(for: page)
            current = results.firstIndex { $0.pages.first == page && $0.bounds(for: page).intersects(bounds) } ?? -1
        }
        return results.count
    }

    func step(_ delta: Int) {
        guard let view, !results.isEmpty else { return }
        current = (current + delta + results.count) % results.count
        let selection = results[current]
        view.isSelectingForSearch = true
        view.setCurrentSelection(selection, animate: true)
        view.isSelectingForSearch = false
        view.go(to: selection)
    }

    /// "C713" is not a match inside "C7130".
    private func isWholeName(_ selection: PDFSelection, term: String) -> Bool {
        guard let wider = selection.copy() as? PDFSelection else { return true }
        wider.extend(atStart: 1)
        wider.extend(atEnd: 1)
        let text = wider.string ?? term
        guard let range = text.range(of: term) else { return true }
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return Schematic.isWholeName(before: before, after: after)
    }

    /// People finished a click or a drag in the schematic.
    func selectionEnded() {
        guard let text = view?.currentSelection?.string, let name = Schematic.name(fromSelection: text) else { return }
        onPick?(name)
    }
}

/// PDFKit's view, telling the controller when people finish selecting text.
final class SchematicPDFView: PDFView {
    weak var controller: SchematicController?
    /// True while the controller selects a match, so it isn't taken for a person's pick.
    var isSelectingForSearch = false

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if !isSelectingForSearch { controller?.selectionEnded() }
    }
}

/// The schematic PDF, fitted to the pane.
struct SchematicPDF: NSViewRepresentable {
    let url: URL
    let controller: SchematicController

    func makeNSView(context: Context) -> SchematicPDFView {
        let view = SchematicPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .underPageBackgroundColor
        view.controller = controller
        controller.view = view
        return view
    }

    func updateNSView(_ view: SchematicPDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
        view.autoScales = true
        // After this update: the search it runs changes what SwiftUI shows.
        Task { @MainActor in controller.onLoad?() }
    }
}
