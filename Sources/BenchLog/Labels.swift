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
        case .open: String(localized: "Open")
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

    var body: some View {
        Label(status.title, systemImage: status.symbol)
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

    var body: some View {
        Menu {
            StatusButtons(model: model, repairID: repairID, current: status, shortcuts: false)
        } label: {
            StatusPill(status: status)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Change the status (⌘1–⌘8)")
        .accessibilityLabel(Text("Status: \(status.title)"))
    }
}

/// One button per status, for the pill menu, the context menu, and the Repair menu.
struct StatusButtons: View {
    /// Passed in, not read from the environment: menu bar commands have no environment.
    let model: AppModel
    let repairID: UUID?
    let current: RepairStatus?
    var shortcuts = true

    var body: some View {
        ForEach(RepairStatus.allCases) { status in
            let button = Toggle(isOn: Binding(get: { current == status },
                                              set: { if $0, let repairID { model.setStatus(status, for: repairID) } })) {
                Label(status.title, systemImage: status.symbol)
            }
            if shortcuts {
                button.keyboardShortcut(status.shortcut, modifiers: .command)
            } else {
                button
            }
        }
    }
}
