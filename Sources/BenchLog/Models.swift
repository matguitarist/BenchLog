import AppKit
import BenchLogKit
import LogKitUI
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The app's state: the open library, the page and record shown, the open sheet,
/// and every change people make (each one logged, and undoable where it says so).
@Observable
final class AppModel {
    let library: Library?
    /// Why the library did not open, in words for the Repairs page.
    let libraryError: String?
    let log: LogStore
    /// The Log page's viewer; kept here so its filters survive moving between pages.
    let logViewer: LogViewerModel

    // MARK: Pages and selection

    var sidebar: SidebarItem? = .repairs
    var settingsTab: SettingsTab = .general
    var selectedRepair: UUID?
    var selectedCustomer: UUID?
    var selectedDevice: UUID?
    var repairFilter: RepairFilter = .open
    var customerSearch = ""
    var deviceSearch = ""
    var sheet: SheetKind?
    /// Set by ⌘⇧K; the note field of the page shown takes focus and clears it.
    var focusNoteField = false
    /// A problem to show in an alert (a failed save).
    var problem: String?
    /// The window's undo manager, so Edit > Undo undoes status changes and trashed notes.
    var undoManager: UndoManager?

    /// Goes up on every change, so pages reload what they show.
    private(set) var dataVersion = 0
    private(set) var openRepairCount = 0
    private(set) var lowStockCount = 0

    private var backStack: [Place] = []
    private var forwardStack: [Place] = []

    var language: AppLanguage = .current {
        didSet { language.apply() }
    }

    var checksForUpdates: Bool {
        get { access(keyPath: \.checksForUpdates); return Updater.shared.automaticallyChecks }
        set { withMutation(keyPath: \.checksForUpdates) { Updater.shared.automaticallyChecks = newValue } }
    }

    init(library: Result<Library, Error>, log: LogStore) {
        switch library {
        case .success(let opened):
            self.library = opened
            libraryError = nil
        case .failure(let error):
            self.library = nil
            libraryError = error.localizedDescription
        }
        self.log = log
        logViewer = LogViewerModel(store: log)
        reload()
    }

    // MARK: Reading

    /// Runs a read; a failure is logged and gives `fallback`.
    func read<T>(_ fallback: T, _ body: (Library) throws -> T) -> T {
        guard let library else { return fallback }
        do { return try body(library) } catch {
            log.post(.error, "Unable to read the library: \(error.localizedDescription)", source: "Library")
            return fallback
        }
    }

    /// Runs a change, logs it, and tells every page to reload. A failure shows an alert.
    @discardableResult
    private func write<T>(_ what: String, _ body: (Library) throws -> T) -> T? {
        guard let library else { return nil }
        do {
            let result = try body(library)
            log.post(.info, what, source: "Library")
            reload()
            return result
        } catch {
            log.post(.error, "\(what) failed: \(error.localizedDescription)", source: "Library")
            problem = error.localizedDescription
            return nil
        }
    }

    /// Tells every page to reload, and recounts the open repairs.
    func reload() {
        dataVersion += 1
        openRepairCount = read(0) { try $0.openRepairCount() }
        lowStockCount = read(0) { try $0.lowStockCount() }
    }

    // MARK: Customers and devices

    /// Adds or updates a customer. A first note typed in the New Customer sheet goes on its timeline.
    @discardableResult
    func save(_ customer: Customer, firstNote: String = "") -> Customer? {
        let isNew = read(nil) { try $0.customer(customer.id) } == nil
        return write(isNew ? "Added customer \(customer.id.stored)" : "Updated customer \(customer.id.stored)") { library in
            let saved = try library.save(customer)
            if isNew { try library.addNote(firstNote, to: .customer, id: saved.id) }
            return saved
        }
    }

    @discardableResult
    func save(_ device: Device) -> Device? {
        let isNew = read(nil) { try $0.device(device.id) } == nil
        return write(isNew ? "Added device \(device.id.stored) (\(device.title))" : "Updated device \(device.id.stored)") {
            try $0.save(device)
        }
    }

    // MARK: Repairs

    func createRepair(deviceID: UUID, complaint: String, promisedAt: Date?) -> Repair? {
        guard let repair = write("Opened a repair for device \(deviceID.stored)", {
            try $0.createRepair(deviceID: deviceID, complaint: complaint, promisedAt: promisedAt)
        }) else { return nil }
        log.post(.info, "Repair \(repair.ticket.text) is in Intake", source: "Repairs")
        return repair
    }

    func update(_ repair: Repair) {
        write("Updated repair \(repair.ticket.text)") { try $0.update(repair) }
    }

    /// Changes the status; Edit > Undo puts the old one back.
    func setStatus(_ status: RepairStatus, for repairID: UUID) {
        guard let old = read(nil, { try $0.repair(repairID) }), old.status != status else { return }
        write("Repair \(old.ticket.text): \(old.status.rawValue) → \(status.rawValue)") { try $0.setStatus(status, of: repairID) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.setStatus(old.status, for: repairID) }
        }
        undoManager?.setActionName(String(localized: "Change Status"))
    }

    /// The repair the Repair menu acts on: the one shown on the Repairs page.
    var focusedRepairID: UUID? { sidebar == .repairs ? selectedRepair : nil }

    var focusedRepairStatus: RepairStatus? {
        guard let id = focusedRepairID else { return nil }
        return read(nil) { try $0.repair(id)?.status }
    }

    // MARK: Notes

    func addNote(_ text: String, to owner: NoteOwner, id: UUID) {
        write("Added a note to \(owner.rawValue) \(id.stored)") { try $0.addNote(text, to: owner, id: id) }
    }

    func editNote(_ id: UUID, text: String) {
        write("Edited note \(id.stored)") { try $0.editNote(id, text: text) }
    }

    /// Moves a note to the trash; Edit > Undo brings it back.
    func trashNote(_ id: UUID) {
        write("Moved note \(id.stored) to the trash") { try $0.trash(Note.self, id: id) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.write("Restored note \(id.stored)") { try $0.restore(Note.self, id: id) } }
        }
        undoManager?.setActionName(String(localized: "Move to Trash"))
    }

    // MARK: Photos and files

    /// Copies files from the Mac into the library and attaches them.
    func addFiles(_ urls: [URL], to owner: NoteOwner, id: UUID) {
        guard !urls.isEmpty else { return }
        write("Added \(urls.count) file(s) to \(owner.rawValue) \(id.stored)") { library in
            for url in urls { try library.addAttachment(copying: url, to: owner, id: id) }
        }
    }

    /// Pasted or imported items (Continuity Camera, a copied image or file): file URLs are
    /// copied; images and PDFs arrive as data.
    func addItems(_ providers: [NSItemProvider], to owner: NoteOwner, id: UUID) async {
        var files: [URL] = []
        var items: [(Data, String)] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let data = await Self.load(provider, .fileURL),
               let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                files.append(url)
            } else if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) || $0.conforms(to: .pdf) }),
                      let data = await Self.load(provider, type) {
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                    .replacingOccurrences(of: ":", with: "-")
                items.append((data, "\(provider.suggestedName ?? "Photo \(stamp)").\(type.preferredFilenameExtension ?? "jpg")"))
            }
        }
        addFiles(files, to: owner, id: id)
        guard !items.isEmpty else { return }
        write("Added \(items.count) imported item(s) to \(owner.rawValue) \(id.stored)") { library in
            for (data, name) in items { try library.addAttachment(data: data, originalName: name, to: owner, id: id) }
        }
    }

    private static func load(_ provider: NSItemProvider, _ type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    func setKind(_ kind: AttachmentKind, of id: UUID) {
        write("Marked attachment \(id.stored) as \(kind.rawValue)") { try $0.setKind(kind, of: id) }
    }

    func setCaption(_ caption: String, of id: UUID) {
        write("Captioned attachment \(id.stored)") { try $0.setCaption(caption, of: id) }
    }

    /// Moves a photo or file to the trash; Edit > Undo brings it back. The file stays on disk.
    func trashAttachment(_ id: UUID) {
        write("Moved attachment \(id.stored) to the trash") { try $0.trash(Attachment.self, id: id) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.write("Restored attachment \(id.stored)") { try $0.restore(Attachment.self, id: id) } }
        }
        undoManager?.setActionName(String(localized: "Move to Trash"))
    }

    // MARK: Parts

    var partsTab: PartsTab = .inventory
    var partSearch = ""
    var selectedPart: UUID?

    @discardableResult
    func save(_ part: Part, fits: [PartFit]) -> Part? {
        write("Saved part \(part.id.stored) (\(part.name))") { try $0.save(part, fits: fits) }
    }

    func adjustStock(of partID: UUID, by delta: Int) {
        write("Stock of part \(partID.stored) \(delta > 0 ? "+" : "")\(delta)") { try $0.adjustStock(of: partID, by: delta) }
    }

    func usePart(_ partID: UUID, on repairID: UUID) {
        write("Added part \(partID.stored) to repair \(repairID.stored)") { try $0.usePart(partID, on: repairID) }
    }

    func useFreePart(_ name: String, on repairID: UUID) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        write("Added part “\(name)” to repair \(repairID.stored)") { try $0.useFreePart(name, on: repairID) }
    }

    func setStatus(_ status: PartUseStatus, ofUse useID: UUID) {
        write("Part use \(useID.stored) → \(status.rawValue)") { try $0.setStatus(status, ofUse: useID) }
    }

    func update(_ use: PartUse) {
        write("Updated part use \(use.id.stored)") { try $0.update(use) }
    }

    func removeUse(_ useID: UUID) {
        write("Removed part use \(useID.stored)") { try $0.removeUse(useID) }
    }

    // MARK: Catalog

    func renameCatalog(_ path: CatalogPath, to name: String) {
        write("Renamed catalog “\(path.name)” to “\(name)”") { try $0.renameCatalog(path, to: name) }
    }

    func deleteFromCatalog(_ path: CatalogPath) {
        write("Deleted “\(path.name)” from the catalog") { try $0.deleteFromCatalog(path) }
    }

    // MARK: Navigation

    /// Where people are: a page and the record selected on it.
    struct Place: Equatable {
        var sidebar: SidebarItem?
        var selection: UUID?
    }

    enum Destination {
        case repair(UUID), customer(UUID), device(UUID)
    }

    private var here: Place {
        let selection: UUID? = switch sidebar {
        case .repairs: selectedRepair
        case .customers: selectedCustomer
        case .devices: selectedDevice
        default: nil
        }
        return Place(sidebar: sidebar, selection: selection)
    }

    private func go(to place: Place) {
        sidebar = place.sidebar
        switch place.sidebar {
        case .repairs: selectedRepair = place.selection
        case .customers: selectedCustomer = place.selection
        case .devices: selectedDevice = place.selection
        default: break
        }
    }

    /// Opens a record on its page; Go > Back returns here.
    func open(_ destination: Destination) {
        backStack.append(here)
        forwardStack.removeAll()
        switch destination {
        case .repair(let id):
            // A closed repair is hidden by the Open filter.
            if let status = read(nil, { try $0.repair(id)?.status }), !repairFilter.statuses.contains(status) { repairFilter = .all }
            go(to: Place(sidebar: .repairs, selection: id))
        case .customer(let id):
            customerSearch = ""
            go(to: Place(sidebar: .customers, selection: id))
        case .device(let id):
            deviceSearch = ""
            go(to: Place(sidebar: .devices, selection: id))
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let place = backStack.popLast() else { return }
        forwardStack.append(here)
        go(to: place)
    }

    func goForward() {
        guard let place = forwardStack.popLast() else { return }
        backStack.append(here)
        go(to: place)
    }

    // MARK: Commands

    /// File > New Repair: for the customer or device on screen, if any.
    func newRepair() {
        switch sidebar {
        case .customers: sheet = .newRepair(customer: selectedCustomer, device: nil)
        case .devices:
            let device = selectedDevice.flatMap { id in read(nil) { try $0.device(id) } }
            sheet = .newRepair(customer: device?.customerId, device: device?.id)
        default: sheet = .newRepair(customer: nil, device: nil)
        }
    }

    /// The customer File > Add Device adds to.
    var customerForNewDevice: UUID? { sidebar == .customers ? selectedCustomer : nil }
}

/// The sheets the main window shows, one at a time.
enum SheetKind: Identifiable, Hashable {
    case newCustomer
    case editCustomer(UUID)
    case addDevice(customer: UUID)
    case editDevice(UUID)
    case newRepair(customer: UUID?, device: UUID?)
    case newPart
    case editPart(UUID)

    var id: Self { self }
}

/// The Parts page's tabs.
enum PartsTab: String, CaseIterable, Identifiable {
    case inventory, low, toOrder, incoming
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inventory: String(localized: "Inventory")
        case .low: String(localized: "Low Stock")
        case .toOrder: String(localized: "To Order")
        case .incoming: String(localized: "Incoming")
        }
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case repairs, customers, devices, parts, guides, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repairs: String(localized: "Repairs")
        case .customers: String(localized: "Customers")
        case .devices: String(localized: "Devices")
        case .parts: String(localized: "Parts")
        case .guides: String(localized: "Guides")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .repairs: "wrench.and.screwdriver"
        case .customers: "person.2"
        case .devices: "laptopcomputer.and.iphone"
        case .parts: "shippingbox"
        case .guides: "book.pages"
        case .log: "list.bullet.rectangle"
        }
    }
}
