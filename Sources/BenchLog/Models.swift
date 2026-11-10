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
    private(set) var library: Library?
    /// Why the library did not open, in words for the Repairs page.
    let libraryError: String?
    let log: LogStore
    /// The Log page's viewer; kept here so its filters survive moving between pages.
    let logViewer: LogViewerModel

    // MARK: Pages and selection

    var partsTab: PartsTab = .inventory
    var partSearch = ""
    /// The Inventory's kind filter; nil shows every kind.
    var partKind: PartKind?
    var selectedPart: UUID?
    var guideSearch = ""
    /// Ready repairs with no paid invoice.
    var toCollect: Set<UUID> = []
    var selectedGuide: UUID?

    var sidebar: SidebarItem? = .repairs
    var settingsTab: SettingsTab = .general
    var selectedRepair: UUID?
    var selectedCustomer: UUID?
    var selectedDevice: UUID?
    var repairFilter: RepairFilter = .open
    var customerSearch = ""
    var deviceSearch = ""
    var deviceScope: DeviceScope = .all
    var sheet: SheetKind?
    /// Search BenchLog (⌘F) is open over the main window.
    var searching = false
    /// A status change waiting for "Start Anyway" or "Ask for Approval".
    var pendingStart: PendingStart?
    var pendingTrash: PendingTrash?
    /// Reports: the month, quarter, or year shown.
    var reportPeriod = ReportPeriod(.month, containing: .now)
    var searchText = ""
    /// Set by ⌘⇧K; the note field of the page shown takes focus and clears it.
    var focusNoteField = false
    /// Set by ⌘⇧P to the record whose Photos and Files section should open the file picker.
    var choosingFilesFor: UUID?
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
    /// Every change goes through here: it logs, reloads, and shows a problem on failure.
    /// Internal so the feature actions in Models+Actions.swift can use it; views never call it.
    func write<T>(_ what: String, _ body: (Library) throws -> T) -> T? {
        guard let library else { return nil }
        do {
            let result = try body(library)
            log.post(.info, what, source: "Library")
            reload()
            SyncController.shared.changed(self)
            return result
        } catch {
            log.post(.error, "\(what) failed: \(error.localizedDescription)", source: "Library")
            problem = error.localizedDescription
            return nil
        }
    }

    /// Swaps the open library (restore), and forgets what was selected in the old one.
    func replaceLibrary(_ library: Library?) {
        self.library = library
        selectedRepair = nil
        selectedCustomer = nil
        selectedDevice = nil
        selectedPart = nil
        selectedGuide = nil
        backStack.removeAll()
        forwardStack.removeAll()
        reload()
        SyncController.shared.load(self)
    }

    /// Tells every page to reload, and recounts the open repairs.
    func reload() {
        dataVersion += 1
        openRepairCount = read(0) { try $0.openRepairCount() }
        lowStockCount = read(0) { try $0.lowStockCount() }
        toCollect = read([]) { try $0.toCollectRepairIDs() }
        let profile = read(BusinessProfile()) { try $0.businessProfile() }
        Money.currencyCode = profile.country.currencyCode
        CustomerDraft.defaultLanguage = profile.defaultDocumentsLanguage
        Spotlight.shared.schedule(self)
    }

    // MARK: Navigation

    /// Where people are: a page and the record selected on it.
    struct Place: Equatable {
        var sidebar: SidebarItem?
        var selection: UUID?
    }

    enum Destination {
        case repair(UUID), customer(UUID), device(UUID), guide(UUID), part(UUID)
    }

    private var here: Place {
        let selection: UUID? = switch sidebar {
        case .repairs: selectedRepair
        case .customers: selectedCustomer
        case .devices: selectedDevice
        case .guides: selectedGuide
        case .parts: selectedPart
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
        case .guides: selectedGuide = place.selection
        case .parts: selectedPart = place.selection
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
        case .guide(let id):
            guideSearch = ""
            go(to: Place(sidebar: .guides, selection: id))
        case .part(let id):
            partSearch = ""
            partsTab = .inventory
            go(to: Place(sidebar: .parts, selection: id))
        }
    }

    /// Opens what a search result points at, and closes the search.
    func open(_ hit: SearchHit) {
        searching = false
        let id = hit.target.id
        switch hit.target.kind {
        case .repair: open(.repair(id))
        case .customer: open(.customer(id))
        case .device: open(.device(id))
        case .guide: open(.guide(id))
        case .part: open(.part(id))
        case .note: break
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
    case editGuide(UUID)
    case importGuides(URL)
    /// `items` start the sale filled in (snapshots).
    case newCounterSale(customer: UUID?, items: [CounterSaleItem] = [])

    var id: Self { self }
}

/// The Parts page's tabs.
enum PartsTab: String, CaseIterable, Identifiable {
    case inventory, low, toOrder, incoming, restock
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inventory: String(localized: "Inventory")
        case .low: String(localized: "Low Stock")
        case .toOrder: String(localized: "To Order")
        case .incoming: String(localized: "Incoming")
        case .restock: String(localized: "Restock")
        }
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case repairs, customers, devices, parts, guides, reports, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repairs: String(localized: "Repairs")
        case .customers: String(localized: "Customers")
        case .devices: String(localized: "Devices")
        case .parts: String(localized: "Parts")
        case .guides: String(localized: "Guides")
        case .reports: String(localized: "Reports")
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
        case .reports: "chart.bar.doc.horizontal"
        case .log: "list.bullet.rectangle"
        }
    }
}
