import BenchLogKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts customers and repairs in Spotlight, so typing a name or a ticket number there opens
/// BenchLog on that record. The index is rebuilt a moment after changes stop, and only when
/// what it holds changed. Libraries in /tmp (tests, snapshots, the self-test) are never
/// indexed. Passcodes, notes, and addresses stay out.
@MainActor
final class Spotlight {
    static let shared = Spotlight()

    /// The identifier is "<kind>:<uuid>"; `destination(for:)` reads it back.
    static let domain = "com.mathieuares.benchlog.records"

    private var pending: Task<Void, Never>?
    private var lastFingerprint: Int?

    /// Rebuilds the index two seconds after the last change.
    func schedule(_ model: AppModel) {
        guard !Store.isOverridden, model.library != nil else { return }
        pending?.cancel()
        pending = Task { [weak model] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let model else { return }
            await self.rebuild(model)
        }
    }

    private func rebuild(_ model: AppModel) async {
        let entries = Self.entries(model)
        let fingerprint = entries.hashValue
        guard fingerprint != lastFingerprint else { return }
        let items = entries.map(\.item)
        do {
            let index = CSSearchableIndex.default()
            try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
            try await index.indexSearchableItems(items)
            lastFingerprint = fingerprint
            model.log.post(.info, "Spotlight has \(items.count) customers and repairs", source: "Spotlight")
        } catch {
            model.log.post(.error, "Unable to update Spotlight: \(error.localizedDescription)", source: "Spotlight")
        }
    }

    /// What Spotlight shows for one record.
    struct Entry: Hashable {
        var id: String
        var title: String
        var detail: String
        var keywords: [String]

        var item: CSSearchableItem {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = title
            attributes.contentDescription = detail
            attributes.keywords = keywords
            return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: Spotlight.domain, attributeSet: attributes)
        }
    }

    static func entries(_ model: AppModel) -> [Entry] {
        let customers = model.read([]) { try $0.customers(matching: "") }.map { customer in
            Entry(id: "customer:\(customer.id.stored)", title: customer.name,
                  detail: [customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: " · "),
                  keywords: [customer.phoneDigits, String(customer.phoneDigits.suffix(7))].filter { !$0.isEmpty })
        }
        let repairs = model.read([]) { try $0.repairRows() }.map { row in
            let ticket = row.repair.ticket
            return Entry(id: "repair:\(row.id.stored)", title: "\(ticket.text) \(row.customer.name)",
                         detail: "\(row.device.brand) \(row.device.model) · \(row.repair.status.title) · \(row.repair.complaint)",
                         keywords: [String(row.repair.ticketNumber), ticket.text, row.device.serial].filter { !$0.isEmpty })
        }
        return customers + repairs
    }

    /// Where a Spotlight result leads.
    static func destination(for identifier: String) -> AppModel.Destination? {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "customer": return .customer(id)
        case "repair": return .repair(id)
        default: return nil
        }
    }
}
