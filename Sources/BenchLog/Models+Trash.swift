import AppKit
import BenchLogKit

/// A customer about to go to the Trash with repairs still open: asked first.
struct PendingTrash: Identifiable {
    let item: TrashItem
    let name: String
    let openRepairs: Int
    var id: String { "\(item)" }
}

extension AppModel {
    /// The record Edit > Move to Trash acts on: the one selected on the page in front.
    var focusedTrashItem: TrashItem? {
        switch sidebar {
        case .repairs: selectedRepair.map(TrashItem.repair)
        case .customers: selectedCustomer.map(TrashItem.customer)
        case .devices: selectedDevice.map(TrashItem.device)
        case .parts: selectedPart.map(TrashItem.part)
        case .guides: selectedGuide.map(TrashItem.guide)
        default: nil
        }
    }

    /// Edit > Move to Trash (⌘⌫). In a text field, ⌘⌫ keeps its usual meaning.
    func trashFocused() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            text.deleteToBeginningOfLine(nil)
            return
        }
        if let item = focusedTrashItem { moveToTrash(item) }
    }

    /// Moves a record and what goes with it to the Trash; Edit > Undo brings it all back.
    /// A customer with open repairs asks first.
    func moveToTrash(_ item: TrashItem, confirmed: Bool = false) {
        if !confirmed, case .customer(let id) = item {
            let open = read(0) { try $0.openRepairCount(ofCustomer: id) }
            if open > 0 {
                pendingTrash = PendingTrash(item: item, name: read(nil) { try $0.customer(id) }?.name ?? "", openRepairs: open)
                return
            }
        }
        let selection = (selectedRepair, selectedCustomer, selectedDevice, selectedPart, selectedGuide)
        guard let stamp = write("Moved \(item) to the trash", { try $0.moveToTrash(item) }) else { return }
        switch item {
        case .repair(let id): if selectedRepair == id { selectedRepair = nil }
        case .customer(let id): if selectedCustomer == id { selectedCustomer = nil }
        case .device(let id): if selectedDevice == id { selectedDevice = nil }
        case .part(let id): if selectedPart == id { selectedPart = nil }
        case .guide(let id): if selectedGuide == id { selectedGuide = nil }
        }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.write("Put back \(item)") { try $0.putBack(item, trashedAt: stamp) }
                (model.selectedRepair, model.selectedCustomer, model.selectedDevice, model.selectedPart, model.selectedGuide) = selection
            }
        }
        undoManager?.setActionName(String(localized: "Move to Trash"))
    }

    /// Settings → Backup → Empty Trash: what has been in the Trash for 30 days goes for good.
    func emptyTrash() {
        if let removed = write("Emptied the trash", { try $0.emptyTrash() }) {
            log.post(.info, "Deleted \(removed) row(s) from the trash", source: "Library")
        }
    }
}
