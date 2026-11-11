import AppKit
import BenchLogKit
import BoardViewKit
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
        didSet { if oldValue != nil, schematic != oldValue, schematic != nil { showsSchematic = true } }
    }
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

    @ObservationIgnored weak var canvas: BoardCanvasView?
    @ObservationIgnored let pdf = SchematicController()
    /// The last Board window opened, for snapshots and the self-test.
    static weak var latest: BoardViewer?

    init(source: BoardSource) {
        self.source = source
        pdf.onPick = { [weak self] name in self?.pick(fromSchematic: name) }
        pdf.onLoad = { [weak self] in self?.findInSchematic(reveal: true) }
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
            model.log.post(.info, "Opened the board \(title): \(read.parts.count) parts, \(read.pins.count) pins", source: "Board")
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            model.log.post(.warning, "Unable to open the board \(title): \(failure ?? "")", source: "Board")
        }
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
        case .pin, .net:
            if !pins.contains(where: { board.shows(pin: $0, on: side) }) { side = side.flipped }
            let shown = pins.filter { board.shows(pin: $0, on: side) }.map { board.pins[$0].position }
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
            return String(localized: "\(part.name): \(part.pins.count) pins, \(part.side == .top ? String(localized: "top") : String(localized: "bottom"))")
        case .pin(let index):
            let pin = board.pins[index]
            let part = board.parts[pin.part].name
            if pin.net.isEmpty { return String(localized: "\(part) pin \(pin.number), no net") }
            return String(localized: "\(part) pin \(pin.number): \(pin.net), \(board.pins(onNet: pin.net).count) pins on the net")
        case .net(let name):
            return String(localized: "\(name): \(board.pins(onNet: name).count) pins on the net")
        }
    }

    // MARK: Schematic

    func findInSchematic(reveal: Bool) {
        hits = pdf.find(term ?? "", reveal: reveal)
        hitNumber = pdf.current + 1
    }

    func stepSchematic(_ delta: Int) {
        pdf.step(delta)
        hitNumber = pdf.current + 1
    }

    // MARK: View

    func flip() { side = side.flipped }
    func zoom(_ direction: Int) { canvas?.zoom(direction) }

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

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                BoardCanvas(viewer: viewer)
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
        .focusedSceneValue(\.boardViewer, viewer)
        .focusedSceneValue(\.boardFind, BoardFindAction(id: ObjectIdentifier(viewer)) { searchFocused = true })
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
                    .disabled((viewer?.hits ?? 0) == 0)
                Button("Previous in Schematic") { viewer?.stepSchematic(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled((viewer?.hits ?? 0) == 0)
                Button(viewer?.showsSchematic == false ? "Show Schematic" : "Hide Schematic") { viewer?.showsSchematic.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
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
