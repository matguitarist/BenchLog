import BenchLogKit
import PDFKit
import SwiftUI

/// Reads a guide: a PDF with page thumbnails, find, and zoom, or a rendered Markdown note
/// with its table of contents.
struct GuideReader: View {
    @Environment(AppModel.self) private var model
    let guide: Guide

    var body: some View {
        if let file = model.read(nil, { try $0.guideFile(guide) }), let library = model.library {
            switch guide.format {
            case .pdf:
                PDFGuideReader(url: library.fileURL(for: file), guideID: guide.id, startPage: guide.lastPage)
            case .markdown:
                MarkdownGuideReader(guide: guide)
            }
        } else {
            ContentUnavailableView("Guide File Missing", systemImage: "doc.questionmark",
                                   description: Text("The guide's file is not in the library. Add the guide again."))
        }
    }
}

// MARK: PDF

/// Talks to the PDFView for the find bar and the zoom buttons.
@MainActor
final class PDFController {
    weak var view: PDFView?
    private var results: [PDFSelection] = []
    private(set) var current = -1

    /// Finds every match, highlights them, and shows the first. Returns how many there are.
    func find(_ text: String) -> Int {
        guard let view, let document = view.document else { return 0 }
        results = text.isEmpty ? [] : document.findString(text, withOptions: [.caseInsensitive])
        view.highlightedSelections = results
        current = -1
        if !results.isEmpty { step(1) }
        return results.count
    }

    func step(_ delta: Int) {
        guard let view, !results.isEmpty else { return }
        current = (current + delta + results.count) % results.count
        let selection = results[current]
        selection.color = .findHighlightColor
        view.setCurrentSelection(selection, animate: true)
        view.go(to: selection)
    }

    func zoom(_ direction: Int) {
        guard let view else { return }
        switch direction {
        case 1: view.zoomIn(nil)
        case -1: view.zoomOut(nil)
        default: view.autoScales = true
        }
    }
}

struct PDFGuideReader: View {
    let url: URL
    let guideID: UUID
    let startPage: Int
    @Environment(AppModel.self) private var model
    @State private var controller = PDFController()
    @State private var finding = false
    @State private var query = ""
    @State private var matches: Int?
    @State private var current = 0
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            PDFKitView(url: url, startPage: startPage, controller: controller) { page in
                model.rememberPage(page, of: guideID)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: Space.sm) {
            if finding {
                TextField("Find in Guide", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .focused($findFocused)
                    .onSubmit { search() }
                    .onKeyPress(.escape) { closeFind(); return .handled }
                if let matches {
                    Text(matches == 0 ? String(localized: "Not found") : String(localized: "\(current) of \(matches)"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ControlGroup {
                    Button("Previous", systemImage: "chevron.left") { move(-1) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                        .help("Show the previous match (⇧⌘G)")
                    Button("Next", systemImage: "chevron.right") { move(1) }
                        .keyboardShortcut("g")
                        .help("Show the next match (⌘G)")
                }
                .disabled((matches ?? 0) == 0)
                .fixedSize()
                Button("Done") { closeFind() }
            } else {
                Button("Find", systemImage: "magnifyingglass") {
                    finding = true
                    findFocused = true
                }
                .keyboardShortcut("f")
                .help("Find text in this guide (⌘F)")
            }
            Spacer()
            ControlGroup {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { controller.zoom(-1) }
                    .keyboardShortcut("-")
                    .help("Make the page smaller (⌘−)")
                Button("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { controller.zoom(0) }
                    .keyboardShortcut("0")
                    .help("Fit the page to the window (⌘0)")
                Button("Zoom In", systemImage: "plus.magnifyingglass") { controller.zoom(1) }
                    .keyboardShortcut("+")
                    .help("Make the page bigger (⌘+)")
            }
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }

    private func search() {
        matches = controller.find(query)
        current = controller.current + 1
    }

    private func move(_ delta: Int) {
        controller.step(delta)
        current = controller.current + 1
    }

    private func closeFind() {
        finding = false
        query = ""
        matches = nil
        _ = controller.find("")
    }
}

/// Lays out the thumbnails, a hairline, and the PDF by hand. With Auto Layout inside,
/// SwiftUI sizes the view to its constraints' fitting size, which is next to nothing.
final class PDFContainer: NSView {
    let thumbnails: NSView
    let separator: NSView
    let pdf: NSView
    static let thumbnailWidth: CGFloat = 120

    init(thumbnails: NSView, separator: NSView, pdf: NSView) {
        self.thumbnails = thumbnails
        self.separator = separator
        self.pdf = pdf
        super.init(frame: .zero)
        for view in [thumbnails, separator, pdf] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = Self.thumbnailWidth
        thumbnails.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        separator.frame = NSRect(x: width, y: 0, width: 1, height: bounds.height)
        pdf.frame = NSRect(x: width + 1, y: 0, width: max(bounds.width - width - 1, 0), height: bounds.height)
    }
}

/// PDFKit's view with a column of page thumbnails on its left.
struct PDFKitView: NSViewRepresentable {
    let url: URL
    let startPage: Int
    let controller: PDFController
    let pageChanged: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let pdf = PDFView()
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displaysPageBreaks = true
        pdf.backgroundColor = .underPageBackgroundColor
        let thumbnails = PDFThumbnailView()
        thumbnails.pdfView = pdf
        thumbnails.thumbnailSize = NSSize(width: 88, height: 116)
        thumbnails.backgroundColor = .clear
        let separator = NSBox()
        separator.boxType = .separator

        let container = PDFContainer(thumbnails: thumbnails, separator: separator, pdf: pdf)
        controller.view = pdf
        context.coordinator.observe(pdf)
        load(pdf, context: context)
        return container
    }

    /// Fill what SwiftUI offers: the container's constraints alone would fit it to zero.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 480, height: 480))
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.pageChanged = pageChanged
        if let pdf = controller.view, context.coordinator.url != url { load(pdf, context: context) }
    }

    private func load(_ pdf: PDFView, context: Context) {
        context.coordinator.url = url
        context.coordinator.loading = true
        pdf.document = PDFDocument(url: url)
        if let page = pdf.document?.page(at: min(startPage, max((pdf.document?.pageCount ?? 1) - 1, 0))) {
            pdf.go(to: page)
        }
        context.coordinator.loading = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(pageChanged: pageChanged) }

    @MainActor
    final class Coordinator: NSObject {
        var pageChanged: (Int) -> Void
        var url: URL?
        var loading = false
        private var lastPage = -1

        init(pageChanged: @escaping (Int) -> Void) {
            self.pageChanged = pageChanged
        }

        func observe(_ pdf: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .PDFViewPageChanged, object: pdf)
        }

        @objc private func changed(_ note: Notification) {
            guard !loading, let pdf = note.object as? PDFView, let page = pdf.currentPage, let document = pdf.document else { return }
            let index = document.index(for: page)
            guard index != lastPage else { return }
            lastPage = index
            pageChanged(index)
        }
    }
}
