import BenchLogKit
import AppKit
import UniformTypeIdentifiers

/// What people do to their library, by feature. Every action goes through `write`,
/// which logs it and bumps `dataVersion` so pages reload.
extension AppModel {
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

    func createRepair(deviceID: UUID, complaint: String, promisedAt: Date?,
                      approval: ApprovalRule = .go, approvalLimitCents: Int? = nil) -> Repair? {
        guard let repair = write("Opened a repair for device \(deviceID.stored)", {
            try $0.createRepair(deviceID: deviceID, complaint: complaint, promisedAt: promisedAt,
                                approval: approval, approvalLimitCents: approvalLimitCents)
        }) else { return nil }
        log.post(.info, "Repair \(repair.ticket.text) is in Intake", source: "Repairs")
        return repair
    }

    func setApproval(_ rule: ApprovalRule, limitCents: Int?, of repairID: UUID) {
        write("Repair \(repairID.stored) approval: \(rule.rawValue) \(limitCents.map(String.init) ?? "")") {
            try $0.setApproval(rule, limitCents: limitCents, of: repairID)
        }
    }

    func update(_ repair: Repair) {
        write("Updated repair \(repair.ticket.text)") { try $0.update(repair) }
    }

    /// Changes the status; Edit > Undo puts the old one back.
    /// Changes a repair's status. Starting work the customer has not approved asks first
    /// (`pendingStart`), unless `force` is set.
    func setStatus(_ status: RepairStatus, for repairID: UUID, force: Bool = false) {
        guard let old = read(nil, { try $0.repair(repairID) }), old.status != status else { return }
        if !force, status.isWork, !old.status.isWork,
           let state = read(nil, { try $0.approvalState(of: repairID) }), state.blocksWork {
            pendingStart = PendingStart(repairID: repairID, status: status, state: state)
            return
        }
        write("Repair \(old.ticket.text): \(old.status.rawValue) → \(status.rawValue)") { try $0.setStatus(status, of: repairID) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.setStatus(old.status, for: repairID, force: true) }
        }
        undoManager?.setActionName(String(localized: "Change Status"))
    }

    /// The record that File > Add Note and Add Photo or File act on: the repair, customer,
    /// or device shown on its page.
    var focusedRecord: (owner: NoteOwner, id: UUID)? {
        switch sidebar {
        case .repairs: selectedRepair.map { (.repair, $0) }
        case .customers: selectedCustomer.map { (.customer, $0) }
        case .devices: selectedDevice.map { (.device, $0) }
        default: nil
        }
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
}
