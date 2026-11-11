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
    /// People clicked a page once: open it large (its index).
    var onOpenPage: ((Int) -> Void)?
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

    var document: PDFDocument? { view?.document }

    /// The page shown in the pane, as an index.
    var currentPage: Int? {
        guard let view, let document = view.document, let page = view.currentPage else { return nil }
        return document.index(for: page)
    }

    /// The highlighted matches on a page, for the large view.
    func matches(onPage index: Int) -> [PDFSelection] {
        guard let page = document?.page(at: index) else { return [] }
        return results.filter { $0.pages.contains(page) }
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

    private var downAt: NSPoint?
    private var pendingPage: Task<Void, Never>?

    override func mouseDown(with event: NSEvent) {
        pendingPage?.cancel()
        downAt = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if !isSelectingForSearch { controller?.selectionEnded() }
        // One click that didn't move or select text opens the page large, once it's clear no
        // second click (a double-click on a name) follows.
        guard event.clickCount == 1, let downAt,
              hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y) < 4,
              (currentSelection?.string ?? "").isEmpty,
              let document, let page = page(for: convert(event.locationInWindow, from: nil), nearest: false)
        else { return }
        let index = document.index(for: page)
        pendingPage = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled else { return }
            self?.controller?.onOpenPage?(index)
        }
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

// MARK: Large page

/// One schematic page, large: the panel people open by clicking a page.
final class LargePagePDFView: PDFView {
    /// A name double-clicked or selected on the page.
    var onPick: ((String) -> Void)?
    /// The page in view changed (the scroll wheel, a swipe, or the arrows): its index.
    var onPageChange: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pageChanged() {
        guard let document, let page = currentPage else { return }
        onPageChange?(document.index(for: page))
    }

    /// Selects a find match and scrolls to it.
    func show(_ match: PDFSelection) {
        setCurrentSelection(match, animate: true)
        go(to: match)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if let text = currentSelection?.string, let name = Schematic.name(fromSelection: text) { onPick?(name) }
    }
}

struct LargePagePDF: NSViewRepresentable {
    let document: PDFDocument
    let page: Int
    let highlights: [PDFSelection]
    let onPick: (String) -> Void
    let onPageChange: (Int) -> Void
    let onMake: (LargePagePDFView) -> Void

    func makeNSView(context: Context) -> LargePagePDFView {
        let view = LargePagePDFView()
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .underPageBackgroundColor
        view.document = document
        view.autoScales = true
        onMake(view)
        return view
    }

    func updateNSView(_ view: LargePagePDFView, context: Context) {
        view.onPick = onPick
        view.onPageChange = onPageChange
        if let target = document.page(at: page), view.currentPage != target {
            view.go(to: target)
            view.autoScales = true
        }
        view.highlightedSelections = highlights.isEmpty ? nil : highlights
    }
}
