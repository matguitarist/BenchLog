import BenchLogKit
import Foundation

/// Everything an agent can do in benchlog. Add a command here and the CLI, `help`, and the
/// MCP tools all get it. Each `run` is on the main actor with the app's model, through the
/// same functions as the window's buttons, so the window updates and Undo works.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the open page and the counts on the Dashboard: open repairs by status, low stock.",
                     example: "benchlog status --json", readOnly: true) { _, model in
            let rows = try library(model).repairRows()
            var byStatus: JSONObject = [:]
            for status in RepairStatus.allCases where !status.isClosed {
                byStatus[status.rawValue] = rows.filter { $0.repair.status == status }.count
            }
            return ["running": true, "page": model.sidebar?.rawValue ?? "none",
                    "openRepairs": rows.filter { !$0.repair.status.isClosed }.count, "byStatus": byStatus,
                    "lowStockParts": try library(model).lowStockCount()]
        },

        // MARK: Repairs

        AgentCommand(name: "repair list", summary: "List repairs, newest first: ticket, status, customer, device, complaint.",
                     params: [.init(name: "open", kind: .boolean, help: "only repairs not Picked Up or Cancelled"),
                              .init(name: "status", help: "only this status: " + statusNames),
                              .init(name: "search", help: "only repairs whose customer, device, complaint, or diagnosis contains this"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "benchlog repair list --open --json", readOnly: true) { args, model in
            var statuses = Set(RepairStatus.allCases)
            if try args.bool("open") == true { statuses = statuses.filter { !$0.isClosed } }
            if let name = args.string("status") { statuses = statuses.intersection([try status(name)]) }
            var rows = try library(model).repairRows(statuses: statuses)
                .sorted { ($0.repair.receivedAt, $0.repair.ticketNumber) > ($1.repair.receivedAt, $1.repair.ticketNumber) }
            if let text = args.string("search"), !text.isEmpty {
                rows = rows.filter { row in
                    [row.customer.name, row.device.title, row.repair.complaint, row.repair.diagnosis]
                        .contains { $0.localizedStandardContains(text) }
                }
            }
            return try page(rows.map { json($0) }, args)
        },
        AgentCommand(name: "repair show", summary: "Show one repair with its notes and parts.",
                     params: [ticketParam],
                     example: "benchlog repair show 42 --json", readOnly: true) { args, model in
            let row = try findRepair(try args.required("ticket"), model)
            let library = try library(model)
            var result = json(row)
            result["diagnosis"] = row.repair.diagnosis
            result["promisedAt"] = row.repair.promisedAt.map(JSON.date)
            result["pickedUpAt"] = row.repair.pickedUpAt.map(JSON.date)
            if let first = row.repair.warrantyOfId, let earlier = try library.repair(first) {
                result["warrantyOf"] = earlier.ticket.text
            }
            result["notes"] = try library.notes(for: .repair, id: row.id).map { note in
                ["at": JSON.date(note.createdAt), "kind": note.kind.rawValue, "text": note.text]
            }
            result["parts"] = try library.partUses(on: row.id).map { use in
                ["name": use.name, "quantity": use.quantity, "status": use.status.rawValue]
            }
            return result.compactMapValues { $0 }
        },
        AgentCommand(name: "repair add", summary: "Open a repair for a device and show it in the window.",
                     params: [.init(name: "device", required: true, help: "the device's id (from `benchlog device list`)"),
                              .init(name: "complaint", required: true, help: "what the customer says is wrong"),
                              .init(name: "warranty-of", help: "the ticket of an earlier, finished repair of this device")],
                     example: "benchlog repair add --device 3f2a9c1e --complaint \"No power\" --json") { args, model in
            let device = try findDevice(try args.required("device"), model)
            let complaint = try args.required("complaint").trimmingCharacters(in: .whitespacesAndNewlines)
            var warrantyOf: UUID?
            if let ticket = args.string("warranty-of") {
                let earlier = try findRepair(ticket, model)
                guard earlier.device.id == device.id, [.ready, .pickedUp].contains(earlier.repair.status) else {
                    throw AgentError.invalid("\(earlier.repair.ticket.text) is not a finished repair of this device")
                }
                warrantyOf = earlier.id
            }
            guard let repair = model.createRepair(deviceID: device.id, complaint: complaint, promisedAt: nil, warrantyOf: warrantyOf),
                  let row = try library(model).repairRow(repair.id) else {
                // The agent gets the problem; the window doesn't show it as an alert.
                defer { model.problem = nil }
                throw AgentError.invalid(model.problem ?? "the repair could not be opened")
            }
            model.open(.repair(repair.id))
            return json(row)
        },
        AgentCommand(name: "repair status", summary: "Move a repair to another status, as the status menu does.",
                     params: [ticketParam,
                              .init(name: "to", required: true, help: statusNames),
                              .init(name: "force", kind: .boolean, help: "start work the customer hasn't approved")],
                     example: "benchlog repair status 42 --to ready --json") { args, model in
            let row = try findRepair(try args.required("ticket"), model)
            let target = try status(try args.required("to"))
            guard row.repair.status != target else { return ["ticket": row.repair.ticket.text, "status": target.rawValue, "changed": false] }
            model.setStatus(target, for: row.id, force: try args.bool("force") ?? false)
            if model.pendingStart?.repairID == row.id {
                model.pendingStart = nil
                throw AgentError.invalid("the customer hasn't approved the work on \(row.repair.ticket.text). Add --force to start anyway")
            }
            let now = try library(model).repair(row.id)?.status ?? row.repair.status
            return ["ticket": row.repair.ticket.text, "status": now.rawValue, "changed": now != row.repair.status]
        },
        AgentCommand(name: "repair note", summary: "Add a note to a repair's timeline.",
                     params: [ticketParam, .init(name: "text", required: true, help: "the note")],
                     example: "benchlog repair note 42 --text \"Ordered the HDMI port\" --json") { args, model in
            let row = try findRepair(try args.required("ticket"), model)
            let text = try args.required("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AgentError.usage("--text cannot be empty") }
            model.addNote(text, to: .repair, id: row.id)
            return ["ticket": row.repair.ticket.text, "added": true]
        },

        // MARK: Customers, devices, parts

        AgentCommand(name: "customer list", summary: "List customers by name, with their phone and email.",
                     params: [.init(name: "search", help: "only customers whose name, phone, or email matches"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "benchlog customer list --search tremblay --json", readOnly: true) { args, model in
            let customers = try library(model).customers(matching: args.string("search") ?? "")
            return try page(customers.map { ["id": short($0.id), "name": $0.name, "phone": $0.phone, "email": $0.email] }, args)
        },
        AgentCommand(name: "device list", summary: "List devices with their customer.",
                     params: [.init(name: "search", help: "only devices whose model, brand, serial, or customer matches"),
                              .init(name: "customer", help: "only this customer's devices (their id)"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "benchlog device list --search switch --json", readOnly: true) { args, model in
            var rows = try library(model).deviceRows(matching: args.string("search") ?? "")
            if let customer = args.string("customer") {
                let id = try findCustomer(customer, model).id
                rows = rows.filter { $0.device.customerId == id }
            }
            return try page(rows.map { row in
                ["id": short(row.device.id), "device": row.device.title, "category": row.device.category.rawValue,
                 "serial": row.device.serial, "customer": row.customer.name, "customerId": short(row.customer.id)]
            }, args)
        },
        AgentCommand(name: "part list", summary: "List parts in inventory with their stock and price.",
                     params: [.init(name: "search", help: "only parts whose name, SKU, vendor, or barcode matches"),
                              .init(name: "low", kind: .boolean, help: "only parts at or under their low-stock threshold"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "benchlog part list --low --json", readOnly: true) { args, model in
            let parts = try library(model).parts(matching: args.string("search") ?? "", lowOnly: try args.bool("low") ?? false)
            return try page(parts.map { part in
                ["id": short(part.id), "name": part.name, "sku": part.sku, "vendor": part.vendor, "quantity": part.quantity,
                 "lowStockThreshold": part.lowStockThreshold, "priceCents": part.priceCents as Any]
            }, args)
        },
        AgentCommand(name: "search", summary: "Search everything, as the search field does: repairs, customers, devices, parts, guides, notes.",
                     params: [.init(name: "text", required: true, positional: true, help: "words, a ticket number, or phone digits")],
                     example: "benchlog search \"hdmi\" --json", readOnly: true) { args, model in
            let hits = try library(model).search(try args.required("text"))
            return ["hits": hits.map { ["kind": $0.kind.rawValue, "id": short($0.target.id), "title": $0.title, "subtitle": $0.subtitle] },
                    "total": hits.count]
        },
        AgentCommand(name: "open", summary: "Show a sidebar page, or a repair by its ticket, in the window.",
                     params: [.init(name: "page", required: true, positional: true,
                                    help: SidebarItem.allCases.map(\.rawValue).joined(separator: ", ") + ", or a ticket like 42")],
                     example: "benchlog open repairs") { args, model in
            let name = try args.required("page")
            if let page = SidebarItem(rawValue: name) {
                model.sidebar = page
                return ["page": page.rawValue]
            }
            guard let row = try? findRepair(name, model) else {
                throw AgentError.usage("no page or ticket \"\(name)\". Pages: \(SidebarItem.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            model.open(.repair(row.id))
            return ["repair": row.repair.ticket.text]
        },
    ]

    // MARK: Helpers

    static let ticketParam = AgentCommand.Param(name: "ticket", required: true, positional: true,
                                                help: "the repair's ticket: 42, 0042, or #0042")
    static var statusNames: String { RepairStatus.allCases.map(\.rawValue).joined(separator: ", ") }

    static func library(_ model: AppModel) throws -> Library {
        guard let library = model.library else { throw AgentError.unavailable("the library isn't open. Look at the BenchLog window") }
        return library
    }

    static func status(_ name: String) throws -> RepairStatus {
        guard let status = RepairStatus.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw AgentError.usage("no status \"\(name)\". Statuses: \(statusNames)")
        }
        return status
    }

    /// The first 8 characters of an id, without dashes.
    static func short(_ id: UUID) -> String { String(id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)) }

    /// One record by any unique start of its id.
    static func unique<T>(_ id: String, in items: [T], key: (T) -> UUID, noun: String, list: String) throws -> T {
        let wanted = id.lowercased().replacingOccurrences(of: "-", with: "")
        let matches = items.filter { key($0).uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(wanted) }
        guard !wanted.isEmpty, let first = matches.first else { throw AgentError.notFound("no \(noun) with id \(id). Run `benchlog \(list)`") }
        guard matches.count == 1 else { throw AgentError.usage("\(matches.count) \(noun)s start with \(id). Give more characters") }
        return first
    }

    /// A repair by its ticket ("42", "#0042"), or by the start of its id.
    static func findRepair(_ text: String, _ model: AppModel) throws -> RepairRow {
        let rows = try library(model).repairRows()
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if let number = Int(digits) {
            if let row = rows.first(where: { $0.repair.ticketNumber == number }) { return row }
            if digits.count < 8 { throw AgentError.notFound("no repair #\(String(format: "%04d", number)). Run `benchlog repair list`") }
        }
        return try unique(text, in: rows, key: \.id, noun: "repair", list: "repair list")
    }

    static func findDevice(_ id: String, _ model: AppModel) throws -> Device {
        try unique(id, in: try library(model).deviceRows().map(\.device), key: \.id, noun: "device", list: "device list")
    }

    static func findCustomer(_ id: String, _ model: AppModel) throws -> Customer {
        try unique(id, in: try library(model).customers(), key: \.id, noun: "customer", list: "customer list")
    }

    static func json(_ row: RepairRow) -> JSONObject {
        ["ticket": row.repair.ticket.text, "id": short(row.id), "status": row.repair.status.rawValue,
         "customer": row.customer.isShop ? "(the shop)" : row.customer.name, "device": row.device.title,
         "deviceId": short(row.device.id), "complaint": row.repair.complaint,
         "receivedAt": JSON.date(row.repair.receivedAt), "warranty": row.repair.warrantyOfId != nil]
    }

    /// A page of a list, with `total` and `nextOffset` when more remain.
    static func page(_ items: [JSONObject], _ args: Args) throws -> JSONObject {
        let limit = try args.int("limit", default: 50)
        let offset = try args.int("offset", default: 0)
        guard limit > 0, offset >= 0 else { throw AgentError.usage("--limit must be above 0 and --offset 0 or more") }
        let slice = Array(items.dropFirst(offset).prefix(limit))
        var result: JSONObject = ["items": slice, "total": items.count]
        if offset + slice.count < items.count { result["nextOffset"] = offset + slice.count }
        return result
    }
}
