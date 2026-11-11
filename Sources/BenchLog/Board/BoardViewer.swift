import AppKit
import BenchLogKit
import BoardViewKit
import LogKitUI
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// What a Board window shows: a board file attached to a record, or one on disk.
enum BoardSource: Codable, Hashable {
    case attachment(UUID)
    case file(URL)
}

/// A schematic PDF that can go beside the board.
struct SchematicChoice: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: URL { url }
}

/// One Board window's state: the board, the side shown, the selection, and the schematic.
@MainActor @Observable
final class BoardViewer {
    /// Where a selection came from: a click on the board, the search field, or the schematic.
    enum Origin { case board, search, schematic }

    let source: BoardSource
    private(set) var title = ""
    private(set) var board: Board?
    private(set) var failure: String?
    private(set) var boardURL: URL?
    private(set) var schematics: [SchematicChoice] = []
    /// The schematic PDF in use. Choosing another one shows it.
    var schematic: URL? {
        didSet {
            if oldValue != nil, schematic != oldValue, schematic != nil { showsSchematic = true }
            if schematic != oldValue { readFacts() }
        }
    }
    /// What the schematic says about the board's parts (values, pages); empty until read.
    private(set) var facts = SchematicFacts()
    private(set) var isReadingFacts = false
    /// The reading under way, for the self-test to wait on.
    @ObservationIgnored private(set) var factsTask: Task<Void, Never>?
    @ObservationIgnored private weak var log: LogStore?
    /// The board opens alone; the schematic opens beside it on the first pick.
    var showsSchematic = false {
        didSet {
            guard showsSchematic != oldValue else { return }
            opensSchematicOnPick = false
            if showsSchematic, isFullBoard { leaveFullBoard(restoring: false) }
        }
    }
    @ObservationIgnored private var opensSchematicOnPick = true
    /// The whole board in the whole window: no schematic, zoomed to fit.
    private(set) var isFullBoard = false
    /// What Full Board puts back.
    @ObservationIgnored private var beforeFullBoard: (showsSchematic: Bool, shown: BoardRect?, selection: BoardSelection?)?
    var side: BoardSide = .top
    private(set) var selection: BoardSelection?
    var query = ""
    /// The names the selection can be looked up by in the schematic, and the one in use.
    private(set) var terms: [String] = []
    var termIndex = 0 { didSet { if termIndex != oldValue { findInSchematic(reveal: true) } } }
    /// Matches of the term in the schematic, and which one is shown (1-based, 0 for none).
    private(set) var hits = 0
    private(set) var hitNumber = 0

    /// The schematic page open large, as an index; nil when the panel is closed.
    var enlargedPage: Int? { didSet { if enlargedPage == nil { pageQuery = ""; clearPageSearch() } } }
    /// Find in the large page's panel: the words, their matches in the whole schematic, and
    /// which one is shown (0-based, -1 for none).
    var pageQuery = ""
    private(set) var pageHits: [PDFSelection] = []
    private(set) var pageHit = -1
    /// The words `pageHits` were found for, so Return finds new words or shows the next match.
    private var pageHitsQuery = ""
    /// Return was pressed on these words and they are on no page.
    var pageSearchFoundNothing: Bool {
        pageHits.isEmpty && !pageHitsQuery.isEmpty && pageHitsQuery == pageQuery.trimmingCharacters(in: .whitespaces)
    }
    /// Bumped to put the cursor in the panel's find field (Edit > Find while the panel is open).
    private(set) var pageFindRequest = 0
    @ObservationIgnored weak var canvas: BoardCanvasView?
    @ObservationIgnored weak var largePage: LargePagePDFView?
    @ObservationIgnored let pdf = SchematicController()
    /// The last Board window opened, for snapshots and the self-test.
    static weak var latest: BoardViewer?

    init(source: BoardSource) {
        self.source = source
        pdf.onPick = { [weak self] name in self?.pick(fromSchematic: name) }
        pdf.onLoad = { [weak self] in self?.findInSchematic(reveal: true) }
        pdf.onOpenPage = { [weak self] index in self?.enlargedPage = index }
    }

    var term: String? { terms.indices.contains(termIndex) ? terms[termIndex] : nil }
    var matches: [BoardMatch] { board?.search(query) ?? [] }

    // MARK: Loading

    func load(_ model: AppModel) async {
        // SwiftUI makes throwaway viewers; the window's own is the one that loads.
        Self.latest = self
        var pdfs: [SchematicChoice] = []
        switch source {
        case .attachment(let id):
            guard let library = model.library, let file = try? library.attachment(id), file.deletedAt == nil else {
                failure = String(localized: "The board file is no longer in the library.")
                return
            }
            title = file.caption.isEmpty ? file.originalName : file.caption
            boardURL = library.fileURL(for: file)
            // The schematic is a PDF on the same record, or on the repair's device.
            var owners = [(file.ownerType, file.ownerId)]
            if file.ownerType == .repair, let repair = try? library.repair(file.ownerId) {
                owners.append((.device, repair.deviceId))
            }
            for (owner, ownerID) in owners {
                for pdf in (try? library.attachments(for: owner, id: ownerID)) ?? [] where pdf.type?.conforms(to: .pdf) == true {
                    pdfs.append(SchematicChoice(url: library.fileURL(for: pdf), name: pdf.caption.isEmpty ? pdf.originalName : pdf.caption))
                }
            }
        case .file(let url):
            title = url.lastPathComponent
            boardURL = url
            let folder = url.deletingLastPathComponent()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            pdfs = names.filter { $0.lowercased().hasSuffix(".pdf") }.sorted()
                .map { SchematicChoice(url: folder.appending(path: $0), name: $0) }
        }
        schematics = pdfs
        schematic = Schematic.pick(for: title, from: pdfs.map(\.name)).map { pdfs[$0].url }

        guard let url = boardURL else { return }
        do {
            let read = try await Task.detached(priority: .userInitiated) { try BoardFile.read(Data(contentsOf: url)) }.value
            board = read
            log = model.log
            readFacts()
            model.log.post(.info, "Opened the board \(title): \(read.parts.count) parts, \(read.pins.count) pins", source: "Board")
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            model.log.post(.warning, "Unable to open the board \(title): \(failure ?? "")", source: "Board")
        }
    }

    /// Reads each part's value and pages from the schematic, off the main thread.
    func readFacts() {
        factsTask?.cancel()
        facts = SchematicFacts()
        guard let board, let url = schematic else { isReadingFacts = false; return }
        let names = Set(board.parts.map { $0.name.uppercased() })
        isReadingFacts = true
        factsTask = Task { [weak self] in
            let facts = await Task.detached(priority: .utility) { SchematicFacts.read(url, partNames: names) }.value
            guard !Task.isCancelled, let self, self.schematic == url else { return }
            self.facts = facts
            self.isReadingFacts = false
            self.log?.post(.info, "Read \(facts.values.count) part values from the schematic \(url.lastPathComponent)", source: "Board")
        }
    }

    /// What the schematic says about a part, nil when it says nothing.
    func value(ofPart index: Int) -> PartValue? {
        guard let board, let value = facts.values[board.parts[index].name.uppercased()], !value.isEmpty else { return nil }
        return value
    }

    /// Opens the file in the app macOS picks for it (FlexBV, OpenBoardView, …).
    func openInDefaultApp() {
        if let boardURL { NSWorkspace.shared.open(boardURL) }
    }

    // MARK: Selection

    func select(_ selection: BoardSelection?, from origin: Origin) {
        self.selection = selection
        guard let board else { return }
        if selection != nil, opensSchematicOnPick, !isFullBoard { showsSchematic = true }
        var terms = board.schematicTerms(for: selection)
        // A ground net is on most pages: the part says more.
        if case .pin = selection, let net = terms.first, Board.isGround(net) { terms.reverse() }
        self.terms = terms
        termIndex = 0
        if origin != .board { reveal(selection) }
        findInSchematic(reveal: origin != .schematic)
    }

    /// Picks the best match for the search field.
    func submitSearch() {
        guard let match = matches.first else { NSSound.beep(); return }
        select(match.selection, from: .search)
    }

    /// A name double-clicked in the schematic: the part, else the net, on the board.
    func pick(fromSchematic name: String) {
        guard let board else { return }
        if let part = board.part(named: name) {
            select(.part(part), from: .schematic)
        } else if let net = board.net(named: name) {
            select(.net(net), from: .schematic)
        }
    }

    /// Turns the board to the side the selection is on, and zooms to it.
    private func reveal(_ selection: BoardSelection?) {
        guard let board, let selection else { return }
        let pins = board.highlightedPins(for: selection)
        switch selection {
        case .part(let index):
            if !board.parts[index].isThroughHole { side = board.parts[index].side }
            canvas?.zoom(to: board.parts[index].bounds, minimumSize: 400)
        case .pin, .net, .testPoint:
            let points = board.highlightedTestPoints(for: selection).map { board.testPoints[$0] }
            func isShown(_ s: BoardSide) -> Bool {
                pins.contains { board.shows(pin: $0, on: s) } || points.contains { $0.side == s }
            }
            if !isShown(side), isShown(side.flipped) { side = side.flipped }
            let shown = pins.filter { board.shows(pin: $0, on: side) }.map { board.pins[$0].position }
                + points.filter { $0.side == side }.map(\.position)
            if let rect = BoardRect(around: shown) { canvas?.zoom(to: rect, minimumSize: 400) }
        }
    }

    /// A line about the selection, for the bar under the board.
    var summary: String {
        guard let board else { return "" }
        switch selection {
        case nil:
            return String(localized: "\(board.parts.count) parts, \(board.nets.count) nets. Click a part or a pin.")
        case .part(let index):
            let part = board.parts[index]
            let type = PartType(partName: part.name).map { "\(Self.word(for: $0)), " } ?? ""
            let value = value(ofPart: index).map { "\($0.summary), " } ?? ""
            return "\(part.name): \(type)\(value)" + String(localized: "\(part.pins.count) pins, \(part.side == .top ? String(localized: "top") : String(localized: "bottom"))")
        case .pin(let index):
            let pin = board.pins[index]
            let part = board.parts[pin.part].name
            if pin.net.isEmpty { return String(localized: "\(part) pin \(pin.number), no net") }
            return String(localized: "\(part) pin \(pin.number): \(pin.net)") + Self.netNote(pin.net)
                + String(localized: ", \(board.pins(onNet: pin.net).count) pins on the net") + testPointNote(pin.net, board)
        case .net(let name):
            return name + Self.netNote(name) + String(localized: ": \(board.pins(onNet: name).count) pins on the net") + testPointNote(name, board)
        case .testPoint(let index):
            let point = board.testPoints[index]
            let side = point.side == .top ? String(localized: "top") : String(localized: "bottom")
            if point.net.isEmpty { return String(localized: "Test point \(point.probe), \(side), no net") }
            return String(localized: "Test point \(point.probe), \(side): \(point.net)") + Self.netNote(point.net)
                + String(localized: ", \(board.pins(onNet: point.net).count) pins on the net")
        }
    }

    /// ", 3.3 V in S0", ", 12 V, always on", ", always on", or nothing when the name says nothing.
    static func netNote(_ net: String) -> String {
        let info = NetInfo(netName: net)
        let volts = info.volts.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " V" }
        let state: String? = switch info.state {
        case nil: nil
        case _ where info.isAlwaysOn: String(localized: "always on")
        case let code?: String(localized: "in \(code)")
        }
        switch (volts, state) {
        case let (v?, s?): return info.isAlwaysOn ? ", \(v), \(s)" : ", \(v) \(s)"
        case let (v?, nil): return ", \(v)"
        case let (nil, s?): return info.isAlwaysOn ? ", \(s)" : ""
        case (nil, nil): return ""
        }
    }

    /// The type of a part on a board, lowercase, for the bar under it.
    static func word(for type: PartType) -> String {
        switch type {
        case .capacitor: String(localized: "capacitor")
        case .resistor: String(localized: "resistor")
        case .resistorNetwork: String(localized: "resistor network")
        case .inductor: String(localized: "inductor")
        case .ferriteBead: String(localized: "ferrite bead")
        case .chip: String(localized: "chip")
        case .transistor: String(localized: "transistor")
        case .diode: String(localized: "diode")
        case .led: String(localized: "LED")
        case .fuse: String(localized: "fuse")
        case .connector: String(localized: "connector")
        case .crystal: String(localized: "crystal")
        case .oscillator: String(localized: "oscillator")
        case .switchPart: String(localized: "switch")
        case .testPoint: String(localized: "test point")
        case .jumper: String(localized: "jumper")
        case .transformer: String(localized: "transformer")
        }
    }

    /// ", 2 test points" after a net's pin count, when it has any.
    private func testPointNote(_ net: String, _ board: Board) -> String {
        let count = board.testPoints(onNet: net).count
        switch count {
        case 0: return ""
        case 1: return String(localized: ", 1 test point")
        default: return String(localized: ", \(count) test points")
        }
    }

    // MARK: Schematic

    func findInSchematic(reveal: Bool) {
        hits = pdf.find(term ?? "", reveal: reveal)
        hitNumber = pdf.current + 1
    }

    /// Next or previous match: of the panel's find field while the large page is open, else of the selection.
    var canStepSchematic: Bool { enlargedPage != nil && !pageHits.isEmpty || hits > 0 }

    func stepSchematic(_ delta: Int) {
        if enlargedPage != nil, !pageHits.isEmpty { stepPageSearch(delta); return }
        pdf.step(delta)
        hitNumber = pdf.current + 1
    }

    // MARK: View

    func flip() { side = side.flipped }

    /// Zooms the board, or the large page while it is open.
    func zoom(_ direction: Int) {
        guard enlargedPage != nil, let largePage else { canvas?.zoom(direction); return }
        switch direction {
        case 0: largePage.autoScales = true
        case 1: largePage.zoomIn(nil)
        default: largePage.zoomOut(nil)
        }
    }

    // MARK: Large page

    var canEnlargePage: Bool { showsSchematic && pdf.document != nil }
    var pageCount: Int { pdf.document?.pageCount ?? 0 }

    /// Opens the schematic page shown in the pane, large.
    func enlargePage() {
        guard canEnlargePage else { return }
        enlargedPage = pdf.currentPage ?? 0
    }

    /// The previous (-1) or next (1) page in the large panel.
    func turnPage(_ delta: Int) {
        guard let page = enlargedPage else { return }
        enlargedPage = min(max(page + delta, 0), max(pageCount - 1, 0))
    }

    /// Edit > Find while the large page is open: the panel's find field.
    func focusPageSearch() { pageFindRequest += 1 }

    /// Return in the panel's find field: finds new words from the page in view, or shows the next match.
    func submitPageSearch() {
        let words = pageQuery.trimmingCharacters(in: .whitespaces)
        if words == pageHitsQuery, !pageHits.isEmpty { stepPageSearch(1); return }
        clearPageSearch()
        guard !words.isEmpty, let document = pdf.document else { return }
        pageHitsQuery = words
        pageHits = document.findString(words, withOptions: [.caseInsensitive])
        guard !pageHits.isEmpty else { NSSound.beep(); return }
        for hit in pageHits { hit.color = .findHighlightColor }
        // Start at the page in view.
        let here = enlargedPage ?? 0
        let first = pageHits.firstIndex { hit in hit.pages.first.map { document.index(for: $0) >= here } ?? false } ?? 0
        pageHit = first - 1
        stepPageSearch(1)
    }

    /// The next (1) or previous (-1) match of the panel's find field, turning the page to it.
    func stepPageSearch(_ delta: Int) {
        guard !pageHits.isEmpty, let document = pdf.document else { return }
        pageHit = (pageHit + delta + pageHits.count) % pageHits.count
        let hit = pageHits[pageHit]
        if let page = hit.pages.first { enlargedPage = document.index(for: page) }
        largePage?.show(hit)
    }

    func clearPageSearch() {
        pageHits = []
        pageHit = -1
        pageHitsQuery = ""
    }

    /// What the large page highlights: the find field's matches, else the selection's.
    func largePageHighlights(onPage index: Int) -> [PDFSelection] {
        guard !pageHits.isEmpty else { return pdf.matches(onPage: index) }
        guard let page = pdf.document?.page(at: index) else { return [] }
        return pageHits.filter { $0.pages.contains(page) }
    }

    /// A name double-clicked on the large page: closes the panel and picks it on the board.
    func pickFromLargePage(_ name: String) {
        guard let board, board.part(named: name) != nil || board.net(named: name) != nil else { return }
        enlargedPage = nil
        pick(fromSchematic: name)
    }

    /// Back to how the window opens: the top, the whole board, no selection, no schematic.
    func reset() {
        if isFullBoard { leaveFullBoard(restoring: false) }
        select(nil, from: .board)
        side = .top
        showsSchematic = false
        opensSchematicOnPick = true
        zoom(0)
    }

    /// Full Board on: hides the schematic and fits the board; off: puts both back as they were.
    func toggleFullBoard() {
        if isFullBoard {
            leaveFullBoard(restoring: true)
            return
        }
        beforeFullBoard = (showsSchematic, canvas?.shownRect, selection)
        isFullBoard = true
        let opens = opensSchematicOnPick
        showsSchematic = false
        opensSchematicOnPick = opens
        canvas?.zoom(0)
    }

    private func leaveFullBoard(restoring: Bool) {
        isFullBoard = false
        guard let before = beforeFullBoard else { return }
        beforeFullBoard = nil
        guard restoring else { return }
        let opens = opensSchematicOnPick
        // A part picked while the board was full opens the schematic now, the first time.
        showsSchematic = before.showsSchematic || (opens && selection != nil)
        if !showsSchematic { opensSchematicOnPick = opens }
        // Back to what was in view, unless something was picked since.
        if selection == before.selection, let shown = before.shown { canvas?.show(shown) }
    }
}

// MARK: Window

/// The Board window: the board on the left, its schematic on the right.
struct BoardWindow: View {
    @Environment(AppModel.self) private var model
    @State private var viewer: BoardViewer

    init(source: BoardSource) {
        _viewer = State(initialValue: BoardViewer(source: source))
    }

    var body: some View {
        Group {
            if viewer.board != nil {
                BoardViewerView(viewer: viewer)
            } else if let failure = viewer.failure {
                ContentUnavailableView {
                    Label("Can't Open Board", systemImage: "cpu")
                } description: {
                    Text(failure)
                } actions: {
                    if viewer.boardURL != nil {
                        Button("Open in Default App") { viewer.openInDefaultApp() }
                    }
                }
            } else {
                ProgressView("Reading the board…")
            }
        }
        .navigationTitle(viewer.title)
        .frame(minWidth: 760, minHeight: 480)
        .noInitialFocus()
        .task { await viewer.load(model) }
    }
}

private struct BoardViewerView: View {
    @Bindable var viewer: BoardViewer
    @FocusState private var searchFocused: Bool
    @State private var windowSize = CGSize(width: 1200, height: 800)

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                BoardCanvas(viewer: viewer, colors: ThemeStore.shared.boardColors)
                Divider()
                Text(viewer.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .gridArea("board-bar", inset: Space.sm)
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            if viewer.showsSchematic {
                SchematicPane(viewer: viewer)
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Side", selection: $viewer.side) {
                    Text("Top").tag(BoardSide.top)
                    Text("Bottom").tag(BoardSide.bottom)
                }
                .pickerStyle(.segmented)
                .help("Show the top or the bottom of the board (⌘1, ⌘2, or Space)")
            }
            ToolbarItem {
                ControlGroup {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { viewer.zoom(-1) }
                        .help("Zoom out (⌘−)")
                    Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { viewer.zoom(0) }
                        .help("Show the whole board (⌘0)")
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { viewer.zoom(1) }
                        .help("Zoom in (⌘+)")
                }
            }
            ToolbarItem {
                Toggle(isOn: Binding(get: { viewer.isFullBoard }, set: { _ in viewer.toggleFullBoard() })) {
                    Label("Full Board", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help(viewer.isFullBoard ? "Put the schematic and the view back (⇧⌘F)" : "Show the whole board in the whole window (⇧⌘F)")
            }
            ToolbarItem {
                Toggle(isOn: $viewer.showsSchematic) {
                    Label("Schematic", systemImage: "sidebar.right")
                }
                .help(viewer.showsSchematic ? "Hide the schematic (⌥⌘S)" : "Show the schematic (⌥⌘S)")
            }
        }
        .searchable(text: $viewer.query, placement: .toolbar, prompt: Text("Part or Net"))
        .searchFocused($searchFocused)
        .searchSuggestions {
            ForEach(viewer.matches.prefix(12)) { match in
                switch match {
                case .part(_, let name):
                    Label(name, systemImage: "cpu").searchCompletion(name)
                case .net(let name, let pins):
                    Label("\(name) (\(pins) pins)", systemImage: "point.3.connected.trianglepath.dotted").searchCompletion(name)
                }
            }
        }
        .onSubmit(of: .search) { viewer.submitSearch() }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .sheet(item: Binding(get: { viewer.enlargedPage.map(PageNumber.init) }, set: { viewer.enlargedPage = $0?.index })) { _ in
            LargePagePanel(viewer: viewer)
                .frame(width: max(windowSize.width - 2 * Space.xl, 560), height: max(windowSize.height - 2 * Space.xl, 400))
        }
        .focusedSceneValue(\.boardViewer, viewer)
        .focusedSceneValue(\.boardFind, BoardFindAction(id: ObjectIdentifier(viewer)) {
            if viewer.enlargedPage != nil { viewer.focusPageSearch() } else { searchFocused = true }
        })
    }
}

/// The page open large, for `sheet(item:)`.
private struct PageNumber: Identifiable {
    let index: Int
    var id: Int { 0 } // one panel: turning the page keeps it open
}

/// A schematic page, large, over the Board window: Previous/Next page, find, zoom, Done.
private struct LargePagePanel: View {
    @Bindable var viewer: BoardViewer
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                ControlGroup {
                    Button("Previous Page", systemImage: "chevron.left") { viewer.turnPage(-1) }
                        // ← and → move the cursor while it is in the find field.
                        .keyboardShortcut(findFocused ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
                        .disabled((viewer.enlargedPage ?? 0) == 0)
                        .help("Show the previous page (←)")
                    Button("Next Page", systemImage: "chevron.right") { viewer.turnPage(1) }
                        .keyboardShortcut(findFocused ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
                        .disabled((viewer.enlargedPage ?? 0) >= viewer.pageCount - 1)
                        .help("Show the next page (→)")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                Text("Page \((viewer.enlargedPage ?? 0) + 1) of \(viewer.pageCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                Spacer(minLength: Space.md)
                find
                Spacer(minLength: Space.md)
                ControlGroup {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { viewer.zoom(-1) }
                        .help("Zoom out (⌘−)")
                    Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { viewer.zoom(0) }
                        .help("Fit the page (⌘0)")
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { viewer.zoom(1) }
                        .help("Zoom in (⌘+)")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                Button("Done") { viewer.enlargedPage = nil }
                    // Esc in the find field clears it first.
                    .keyboardShortcut(findFocused && !viewer.pageQuery.isEmpty ? nil : .cancelAction)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 48)
            .gridArea("page-bar", inset: Space.sm)
            Divider()
            if let document = viewer.pdf.document, let page = viewer.enlargedPage {
                LargePagePDF(document: document, page: page, highlights: viewer.largePageHighlights(onPage: page),
                             onPick: { viewer.pickFromLargePage($0) },
                             onPageChange: { if let shown = viewer.enlargedPage, shown != $0 { viewer.enlargedPage = $0 } },
                             onMake: { viewer.largePage = $0 })
                    .help("Double-click a name to find it on the board.")
            }
        }
        .noInitialFocus()
        .onChange(of: viewer.pageFindRequest) { findFocused = true }
    }

    /// The find field, the match count, and the arrows to the previous and next match.
    private var find: some View {
        HStack(spacing: Space.sm) {
            TextField("Find in Schematic", text: $viewer.pageQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 220, maxWidth: 240)
                .focused($findFocused)
                .onSubmit { viewer.submitPageSearch() }
                .onExitCommand { viewer.pageQuery = ""; viewer.clearPageSearch() }
                .onChange(of: viewer.pageQuery) { if viewer.pageQuery.isEmpty { viewer.clearPageSearch() } }
                .help("Find words on every page. Return shows the next match (⌘F)")
            if !viewer.pageHits.isEmpty {
                Text("\(viewer.pageHit + 1) of \(viewer.pageHits.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                ControlGroup {
                    Button("Previous Match", systemImage: "chevron.up") { viewer.stepPageSearch(-1) }
                        .help("Show the previous match (⇧⌘G)")
                    Button("Next Match", systemImage: "chevron.down") { viewer.stepPageSearch(1) }
                        .help("Show the next match (⌘G)")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            } else if viewer.pageSearchFoundNothing {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

/// The schematic beside the board: the match bar and the PDF.
private struct SchematicPane: View {
    @Bindable var viewer: BoardViewer

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            if let url = viewer.schematic {
                SchematicPDF(url: url, controller: viewer.pdf)
                    .help("Click a page to see it large. Double-click a name to find it on the board.")
            } else {
                ContentUnavailableView {
                    Label("No Schematic", systemImage: "doc.text.magnifyingglass")
                } description: {
                    if case .file = viewer.source {
                        Text("Put the schematic PDF in the board's folder, then open the board again.")
                    } else {
                        Text("Add the schematic PDF to this repair or its device, then open the board again.")
                    }
                }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: Space.sm) {
            if viewer.terms.count > 1 {
                Picker("Find", selection: $viewer.termIndex) {
                    ForEach(Array(viewer.terms.enumerated()), id: \.offset) { index, term in
                        Text(term).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Look for the net or the part in the schematic")
            } else if let term = viewer.term {
                Text(term).font(.headline).lineLimit(1)
            } else {
                Text("Select a part or a net to find it here.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if viewer.term != nil, viewer.schematic != nil {
                Text(viewer.hits == 0 ? String(localized: "Not found")
                     : viewer.hitNumber == 0 ? String(localized: "\(viewer.hits) matches")
                     : String(localized: "\(viewer.hitNumber) of \(viewer.hits)"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                ControlGroup {
                    Button("Previous", systemImage: "chevron.left") { viewer.stepSchematic(-1) }
                        .help("Show the previous match (⇧⌘G)")
                    Button("Next", systemImage: "chevron.right") { viewer.stepSchematic(1) }
                        .help("Show the next match (⌘G)")
                }
                .disabled(viewer.hits == 0)
                .fixedSize()
            }
            Spacer(minLength: 0)
            if viewer.schematics.count > 1 {
                Picker("Schematic", selection: $viewer.schematic) {
                    ForEach(viewer.schematics) { Text($0.name).tag(Optional($0.url)) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Choose the schematic PDF")
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, Space.md)
        .frame(height: 40)
        .gridArea("schematic-bar", inset: Space.sm)
    }
}

// MARK: Menus

struct BoardFindAction: Equatable {
    let id: ObjectIdentifier
    let open: () -> Void

    func callAsFunction() { open() }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

extension FocusedValues {
    /// The Board menu acts on it.
    @Entry var boardViewer: BoardViewer?
    /// Edit > Find Part or Net… uses it.
    @Entry var boardFind: BoardFindAction?
}

/// The Board menu: sides, zoom, the schematic's matches. Enabled in a Board window.
struct BoardCommands: Commands {
    @FocusedValue(\.boardViewer) private var viewer
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Board…") { openBoard() }
                .keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandMenu("Board") {
            Group {
                Button("Show Top") { viewer?.side = .top }
                    .keyboardShortcut("1")
                Button("Show Bottom") { viewer?.side = .bottom }
                    .keyboardShortcut("2")
                Divider()
                Button("Zoom In") { viewer?.zoom(1) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { viewer?.zoom(-1) }
                    .keyboardShortcut("-")
                Button("Zoom to Fit") { viewer?.zoom(0) }
                    .keyboardShortcut("0")
                Button(viewer?.isFullBoard == true ? "Exit Full Board" : "Full Board") { viewer?.toggleFullBoard() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Next in Schematic") { viewer?.stepSchematic(1) }
                    .keyboardShortcut("g")
                    .disabled(viewer?.canStepSchematic != true)
                Button("Previous in Schematic") { viewer?.stepSchematic(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(viewer?.canStepSchematic != true)
                Button(viewer?.showsSchematic == false ? "Show Schematic" : "Hide Schematic") { viewer?.showsSchematic.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Enlarge Page") { viewer?.enlargePage() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(viewer?.canEnlargePage != true)
                Divider()
                Picker("Board Colors", selection: Bindable(ThemeStore.shared).boardColorsID) {
                    ForEach(BoardColors.all) { Text($0.name).tag($0.id) }
                }
                Divider()
                Button("Clear Selection") { viewer?.select(nil, from: .board) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(viewer?.selection == nil)
            }
            .disabled(viewer == nil)
        }
    }

    /// File > Open Board…: a board file from the Mac, with the PDFs in its folder.
    private func openBoard() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = BoardFile.readableExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Choose a board file. A schematic PDF in the same folder opens beside it.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(id: "board", value: BoardSource.file(url))
    }
}
