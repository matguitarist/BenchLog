import BenchLogKit
import SwiftUI

// What the Kit's values look like on screen: words (from Localizable.xcstrings),
// SF Symbols, and colors. The Kit itself has no interface strings.

extension RepairStatus {
    var title: String {
        switch self {
        case .intake: String(localized: "Intake")
        case .diagnosing: String(localized: "Diagnosing")
        case .awaitingApproval: String(localized: "Awaiting Approval")
        case .waitingOnParts: String(localized: "Waiting on Parts")
        case .inProgress: String(localized: "In Progress")
        case .ready: String(localized: "Ready")
        case .pickedUp: String(localized: "Picked Up")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var symbol: String {
        switch self {
        case .intake: "tray.and.arrow.down"
        case .diagnosing: "stethoscope"
        case .awaitingApproval: "hand.raised"
        case .waitingOnParts: "shippingbox"
        case .inProgress: "wrench.and.screwdriver"
        case .ready: "checkmark.circle"
        case .pickedUp: "bag"
        case .cancelled: "xmark.circle"
        }
    }

    /// Grey to start, orange while blocked, teal on the bench, green when ready, faded when closed.
    var color: Color {
        switch self {
        case .intake, .diagnosing: .gray
        case .awaitingApproval, .waitingOnParts: .orange
        case .inProgress: .teal
        case .ready: .green
        case .pickedUp, .cancelled: .secondary
        }
    }

    /// ⌘1 … ⌘8 in the Repair menu.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((RepairStatus.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

extension DeviceCategory {
    var title: String {
        switch self {
        case .computer: String(localized: "Computer")
        case .phone: String(localized: "Phone")
        case .tablet: String(localized: "Tablet")
        case .console: String(localized: "Console")
        case .handheld: String(localized: "Handheld")
        case .other: String(localized: "Other")
        }
    }

    /// For lists of guides: "Consoles · Nintendo", "All Consoles".
    var pluralTitle: String {
        switch self {
        case .computer: String(localized: "Computers")
        case .phone: String(localized: "Phones")
        case .tablet: String(localized: "Tablets")
        case .console: String(localized: "Consoles")
        case .handheld: String(localized: "Handhelds")
        case .other: String(localized: "category.other.plural", defaultValue: "Other Devices", comment: "Guides for devices in no other category")
        }
    }

    var symbol: String {
        switch self {
        case .computer: "laptopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .console: "gamecontroller"
        case .handheld: "formfitting.gamecontroller"
        case .other: "cpu"
        }
    }
}

extension AttachmentKind {
    var title: String {
        switch self {
        case .intake: String(localized: "photo.intake", defaultValue: "Intake", comment: "A photo taken when the device came in")
        case .progress: String(localized: "photo.progress", defaultValue: "Progress", comment: "A photo taken during the repair")
        case .final: String(localized: "photo.final", defaultValue: "Final", comment: "A photo of the device as it goes back")
        case .document: String(localized: "photo.document", defaultValue: "Document", comment: "A file that is not a photo")
        }
    }
}

extension PartUseStatus {
    var title: String {
        switch self {
        case .needed: String(localized: "part.needed", defaultValue: "Needed", comment: "Where a part for a repair is (one part)")
        case .ordered: String(localized: "part.ordered", defaultValue: "Ordered", comment: "Where a part for a repair is (one part)")
        case .received: String(localized: "part.received", defaultValue: "Received", comment: "Where a part for a repair is (one part)")
        case .installed: String(localized: "part.installed", defaultValue: "Installed", comment: "Where a part for a repair is (one part)")
        }
    }

    var symbol: String {
        switch self {
        case .needed: "exclamationmark.circle"
        case .ordered: "shippingbox"
        case .received: "tray.and.arrow.down"
        case .installed: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .needed: .gray
        case .ordered: .orange
        case .received: .teal
        case .installed: .green
        }
    }
}

/// Money is integer cents in the library, shown in the business's currency (CAD or USD)
/// in the app's language.
enum Money {
    /// Set from the business's country each time the library reloads.
    nonisolated(unsafe) static var currencyCode = "CAD"

    static func text(_ cents: Int?) -> String {
        guard let cents else { return "—" }
        return (Decimal(cents) / 100).formatted(.currency(code: currencyCode))
    }

    static func decimal(_ cents: Int?) -> Decimal? { cents.map { Decimal($0) / 100 } }

    static func cents(_ value: Decimal?) -> Int? {
        guard let value else { return nil }
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static var format: Decimal.FormatStyle.Currency { .init(code: currencyCode) }
}

extension TaxKind {
    /// The tax's short name in the app's language: GST, QST, HST… or TPS, TVQ, TVH….
    var title: String { name(Locale.current.language.languageCode?.identifier == "fr" ? .french : .english) }
}

extension DocumentsLanguage {
    /// Each language named in itself: the choice is about the printed documents.
    var title: String {
        switch self {
        case .french: "Français"
        case .english: "English"
        }
    }
}

/// The Repairs list's filter.
enum RepairFilter: String, CaseIterable, Identifiable {
    case open, ready, closed, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: String(localized: "filter.open", defaultValue: "Open", comment: "Repairs filter: the repairs not closed (plural)")
        case .ready: String(localized: "filter.ready", defaultValue: "Ready", comment: "Repairs filter: the repairs that are ready (plural)")
        case .closed: String(localized: "Closed")
        case .all: String(localized: "All")
        }
    }

    var statuses: Set<RepairStatus> {
        switch self {
        case .open: Set(RepairStatus.allCases.filter { !$0.isClosed })
        case .ready: [.ready]
        case .closed: [.pickedUp, .cancelled]
        case .all: Set(RepairStatus.allCases)
        }
    }

    var emptyTitle: String {
        switch self {
        case .open: String(localized: "No Open Repairs")
        case .ready: String(localized: "No Repairs Ready")
        case .closed: String(localized: "No Closed Repairs")
        case .all: String(localized: "No Repairs")
        }
    }
}

/// A repair's status as a colored capsule: icon, word, and color, never color alone.
struct StatusPill: View {
    let status: RepairStatus
    /// An internal job's last status reads "Done", not "Picked Up".
    var isInternal = false

    var body: some View {
        Label(status.title(isInternal: isInternal), systemImage: status.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

/// The status pill as a menu that changes it.
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    let repairID: UUID
    let status: RepairStatus
    var isInternal = false

    var body: some View {
        Menu {
            StatusButtons(model: model, repairID: repairID, current: status, shortcuts: false, isInternal: isInternal)
        } label: {
            StatusPill(status: status, isInternal: isInternal)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Change the status (⌘1–⌘8)")
        .accessibilityLabel(Text("Status: \(status.title(isInternal: isInternal))"))
    }
}

/// One button per status, for the pill menu, the context menu, and the Repair menu.
struct StatusButtons: View {
    /// Passed in, not read from the environment: menu bar commands have no environment.
    let model: AppModel
    let repairID: UUID?
    let current: RepairStatus?
    var shortcuts = true
    var isInternal = false

    var body: some View {
        ForEach(RepairStatus.allCases) { status in
            let button = Toggle(isOn: Binding(get: { current == status },
                                              set: { if $0, let repairID { model.setStatus(status, for: repairID) } })) {
                Label(status.title(isInternal: isInternal), systemImage: status.symbol)
            }
            .disabled(repairID == nil)
            if shortcuts {
                button.keyboardShortcut(status.shortcut, modifiers: .command)
            } else {
                button
            }
        }
    }
}

extension PaymentMethod {
    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .debit: String(localized: "Debit")
        case .credit: String(localized: "Credit")
        case .eTransfer: String(localized: "e-Transfer")
        }
    }
}

extension SearchKind {
    /// The heading over this kind's search results.
    var pluralTitle: String {
        switch self {
        case .repair: String(localized: "Repairs")
        case .customer: String(localized: "Customers")
        case .device: String(localized: "Devices")
        case .part: String(localized: "Parts")
        case .guide: String(localized: "Guides")
        case .note: String(localized: "Notes")
        }
    }

    var symbol: String {
        switch self {
        case .repair: "wrench.and.screwdriver"
        case .customer: "person"
        case .device: "laptopcomputer.and.iphone"
        case .part: "shippingbox"
        case .guide: "book.pages"
        case .note: "note.text"
        }
    }
}

extension RepairStatus {
    /// The title, with an internal job's Picked Up read as "Done": nobody picks it up.
    func title(isInternal: Bool) -> String {
        isInternal && self == .pickedUp ? String(localized: "Done") : title
    }
}

/// "Internal": a job on a device the shop owns.
struct InternalBadge: View {
    var body: some View {
        Label("Internal", systemImage: "building.2")
            .font(.caption.weight(.medium))
            .foregroundStyle(.purple)
            .help("A job on a device the shop owns, to resell or keep")
    }
}
