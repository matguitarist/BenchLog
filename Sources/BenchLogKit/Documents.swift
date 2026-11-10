import Foundation
import GRDB

// Estimates, invoices, credit notes, and sale invoices: what they freeze when issued,
// their numbers, and the payment or refund recorded beside them.

// MARK: - Documents

public enum DocumentKind: String, Codable, Sendable {
    case invoice, estimate, creditNote
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case cash, debit, credit, eTransfer
    public var id: String { rawValue }
}

public enum EstimateDecision: String, Codable, Sendable {
    case approved, refused
}

/// Everything a document prints, frozen when it is issued.
public struct DocumentContent: Codable, Hashable, Sendable {
    public struct Party: Codable, Hashable, Sendable {
        public var name: String
        public var phone: String
        public var email: String
        public var address: String
    }
    public var business: BusinessProfile
    public var customer: Party
    public var deviceTitle: String
    public var serial: String
    public var ticketNumber: Int
    public var complaint: String
    public var diagnosis: String
    public var lines: [BillLine]
    public var totals: Totals
    /// Credit notes only: the invoice credited ("F-0003") and why.
    public var credits: String?
    public var reason: String?
}


/// An issued invoice or estimate. Its content never changes; payment and the estimate's
/// decision are recorded beside it.
public struct Invoice: BenchRecord {
    public static let databaseTableName = "invoice"

    public var id: UUID
    /// The repair billed; nil for the sale of a shop device.
    public var repairId: UUID?
    public var kind: DocumentKind
    /// Invoices only: 1 prints as F-0001.
    public var number: Int?
    public var issuedAt: Date
    /// Estimates only.
    public var validUntil: Date?
    public var language: DocumentsLanguage
    /// `DocumentContent` as JSON.
    public var content: String
    public var totalCents: Int
    public var paidAt: Date?
    public var paymentMethod: PaymentMethod?
    public var decision: EstimateDecision?
    public var decidedAt: Date?
    /// The PDF, an attachment on the repair.
    public var fileId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    /// Credit notes only: 1 prints as NC-0001.
    public var creditNumber: Int? = nil
    /// Credit notes only: the invoice it cancels.
    public var creditsInvoiceId: UUID? = nil
    /// Sale invoices only: the shop device sold.
    public var deviceId: UUID? = nil
    /// Counter sales only: the customer, or the shop for a walk-in.
    public var customerId: UUID? = nil

    /// "F-0001" for an invoice, "NC-0001" for a credit note.
    public var numberText: String? {
        if kind == .creditNote { return creditNumber.map { "NC-" + String(format: "%04d", $0) } }
        return number.map { "F-" + String(format: "%04d", $0) }
    }

    public var document: DocumentContent? {
        try? JSONDecoder().decode(DocumentContent.self, from: Data(content.utf8))
    }
}

public enum BillingError: LocalizedError, Equatable {
    case nothingToBill
    case notAnInvoice
    case alreadyCredited(String)
    case saleNotReady
    case alreadyInvoiced(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToBill: String(localized: "The repair has no labour or priced parts to bill.")
        case .notAnInvoice: String(localized: "Only an invoice can be credited.")
        case .alreadyCredited(let number): String(localized: "This invoice is already credited by \(number).")
        case .saleNotReady: String(localized: "To invoice a sale, mark the device Sold with a price and a buyer.")
        case .alreadyInvoiced(let number): String(localized: "This sale is already invoiced on \(number). Credit that invoice first.")
        }
    }
}

extension Library {
    // MARK: Issuing

    /// Issues an invoice (with the next number) or an estimate (valid for the profile's
    /// days), freezing everything it prints.
    @discardableResult
    public func issue(_ kind: DocumentKind, for repairID: UUID, now: Date = .now) throws -> Invoice {
        guard let row = try repairRow(repairID) else { throw BillingError.nothingToBill }
        guard !row.customer.isShop else { throw ShopError.internalJob }
        let bill = try bill(for: repairID)
        guard !bill.lines.isEmpty else { throw BillingError.nothingToBill }
        let profile = try businessProfile()
        let content = DocumentContent(
            business: profile,
            customer: .init(name: row.customer.name, phone: row.customer.phone, email: row.customer.email, address: row.customer.address),
            deviceTitle: row.device.title, serial: row.device.serial, ticketNumber: row.repair.ticketNumber,
            complaint: row.repair.complaint, diagnosis: row.repair.diagnosis, lines: bill.lines, totals: bill.totals)
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        return try db.write { db in
            let number = kind == .invoice ? try Self.nextNumber("nextInvoiceNumber", db) : nil
            let invoice = Invoice(id: UUID(), repairId: repairID, kind: kind, number: number, issuedAt: now,
                                  validUntil: kind == .estimate ? Calendar.current.date(byAdding: .day, value: profile.estimateValidDays, to: now) : nil,
                                  language: row.customer.documentsLanguage, content: json, totalCents: bill.totals.totalCents,
                                  paidAt: nil, paymentMethod: nil, decision: nil, decidedAt: nil, fileId: nil,
                                  createdAt: now, updatedAt: now, deletedAt: nil)
            try invoice.insert(db)
            return invoice
        }
    }

    /// Issues a credit note that cancels an invoice: the next credit number, the invoice's
    /// lines and each tax reversed. The invoice keeps its number; to correct it, issue a new
    /// invoice after the credit note.
    @discardableResult
    public func issueCreditNote(for invoiceID: UUID, reason: String = "", now: Date = .now) throws -> Invoice {
        guard let invoice = try invoice(invoiceID), invoice.kind == .invoice, var content = invoice.document else {
            throw BillingError.notAnInvoice
        }
        if let credit = try creditNote(of: invoiceID) { throw BillingError.alreadyCredited(credit.numberText ?? "") }
        content.lines = content.lines.map { line in
            var line = line
            line.unitCents = -line.unitCents
            line.amountCents = -line.amountCents
            return line
        }
        let t = content.totals
        content.totals = Totals(labourCents: -t.labourCents, partsCents: -t.partsCents, discountCents: -t.discountCents,
                                subtotalCents: -t.subtotalCents, taxableCents: -t.taxableCents,
                                taxes: t.taxes.map { TaxLine(kind: $0.kind, rate: $0.rate, cents: -$0.cents) },
                                totalCents: -t.totalCents)
        content.credits = invoice.numberText
        content.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        return try db.write { db in
            let next = try Self.nextNumber("nextCreditNumber", db)
            let credit = Invoice(id: UUID(), repairId: invoice.repairId, kind: .creditNote, number: nil, issuedAt: now, validUntil: nil,
                                 language: invoice.language, content: json, totalCents: -invoice.totalCents,
                                 paidAt: nil, paymentMethod: nil, decision: nil, decidedAt: nil, fileId: nil,
                                 createdAt: now, updatedAt: now, deletedAt: nil, creditNumber: next, creditsInvoiceId: invoice.id,
                                 deviceId: invoice.deviceId, customerId: invoice.customerId)
            try credit.insert(db)
            try Self.returnSoldParts(db, invoice: invoice.id, credit: credit.id, now: now)
            return credit
        }
    }

    /// Takes the next number of a sequence kept in meta (invoices and credit notes).
    static func nextNumber(_ key: String, _ db: Database) throws -> Int {
        let next = try Int.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = ?", arguments: [key]) ?? 1
        try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, "\(next + 1)"])
        return next
    }

    /// Invoices the sale of a shop device to its buyer: the next invoice number, one line at
    /// the sale price, and the region's taxes. A sale is invoiced once, unless credited.
    @discardableResult
    public func issueSaleInvoice(for deviceID: UUID, now: Date = .now) throws -> Invoice {
        guard let device = try device(deviceID), device.disposition == .sold, let price = device.salePriceCents,
              let buyer = try customer(device.customerId), !buyer.isShop else { throw BillingError.saleNotReady }
        let credited = Set(try saleInvoices(of: deviceID).compactMap(\.creditsInvoiceId))
        if let live = try saleInvoices(of: deviceID).first(where: { $0.kind == .invoice && !credited.contains($0.id) }) {
            throw BillingError.alreadyInvoiced(live.numberText ?? "")
        }
        let profile = try businessProfile()
        let lines = [BillLine(kind: .item, description: device.title, hundredths: 100, unitCents: price, amountCents: price)]
        let content = DocumentContent(
            business: profile,
            customer: .init(name: buyer.name, phone: buyer.phone, email: buyer.email, address: buyer.address),
            deviceTitle: device.title, serial: device.serial, ticketNumber: 0, complaint: "", diagnosis: "",
            lines: lines, totals: Billing.totals(lines, discountCents: 0, taxes: profile.chargedTaxes, taxesLabour: profile.taxesLabour))
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        return try db.write { db in
            let invoice = Invoice(id: UUID(), repairId: nil, kind: .invoice, number: try Self.nextNumber("nextInvoiceNumber", db),
                                  issuedAt: now, validUntil: nil, language: buyer.documentsLanguage, content: json,
                                  totalCents: content.totals.totalCents, paidAt: nil, paymentMethod: nil, decision: nil, decidedAt: nil,
                                  fileId: nil, createdAt: now, updatedAt: now, deletedAt: nil, deviceId: deviceID)
            try invoice.insert(db)
            return invoice
        }
    }

    /// A shop device's sale invoices and their credit notes, newest first.
    public func saleInvoices(of deviceID: UUID) throws -> [Invoice] {
        try db.read { db in
            try Invoice.filter(Column("deviceId") == deviceID.stored && Column("deletedAt") == nil)
                .order(Column("issuedAt").desc, Column("rowid").desc).fetchAll(db)
        }
    }

    /// The credit note that cancels an invoice, if any.
    public func creditNote(of invoiceID: UUID) throws -> Invoice? {
        try db.read { try Invoice.filter(Column("creditsInvoiceId") == invoiceID.stored && Column("deletedAt") == nil).fetchOne($0) }
    }

    public func invoice(_ id: UUID) throws -> Invoice? {
        try db.read { try Invoice.fetchOne($0, key: id.stored) }
    }

    /// A repair's documents, newest first.
    public func invoices(for repairID: UUID) throws -> [Invoice] {
        try db.read { db in
            try Invoice.filter(Column("repairId") == repairID.stored && Column("deletedAt") == nil)
                .order(Column("issuedAt").desc, Column("rowid").desc).fetchAll(db)
        }
    }

    public func setFile(_ attachmentID: UUID, of invoiceID: UUID) throws {
        try db.write { try $0.execute(sql: "UPDATE invoice SET fileId = ? WHERE id = ?", arguments: [attachmentID.stored, invoiceID.stored]) }
    }

    /// Records a payment; nil method clears it.
    public func setPaid(_ invoiceID: UUID, method: PaymentMethod?, now: Date = .now) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE invoice SET paidAt = ?, paymentMethod = ?, updatedAt = ? WHERE id = ?",
                           arguments: [method == nil ? nil : now, method?.rawValue, now, invoiceID.stored])
        }
    }

    /// Approving an estimate moves an early repair on: to Waiting on Parts when a part is
    /// missing, else In Progress. Either way a note records the decision.
    @discardableResult
    public func decide(_ estimateID: UUID, approved: Bool, now: Date = .now) throws -> Repair? {
        guard let estimate = try invoice(estimateID), estimate.kind == .estimate else { return nil }
        let decision: EstimateDecision = approved ? .approved : .refused
        try db.write { db in
            try db.execute(sql: "UPDATE invoice SET decision = ?, decidedAt = ?, updatedAt = ? WHERE id = ?",
                           arguments: [decision.rawValue, now, now, estimateID.stored])
            if let repairID = estimate.repairId {
                try Note(owner: .repair, ownerId: repairID, kind: .estimate, text: decision.rawValue, now: now).insert(db)
            }
        }
        guard approved, let repairID = estimate.repairId, let repair = try repair(repairID),
              [.intake, .diagnosing, .awaitingApproval].contains(repair.status) else { return try estimate.repairId.flatMap { try self.repair($0) } }
        let next: RepairStatus = try isWaitingOnParts(repair.id) ? .waitingOnParts : .inProgress
        return try setStatus(next, of: repair.id, now: now.addingTimeInterval(1))
    }

    /// Ready repairs with no paid invoice (a credited one does not count): the money still to collect.
    public func toCollectRepairIDs() throws -> Set<UUID> {
        try db.read { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT id FROM repair WHERE status = 'ready' AND deletedAt IS NULL AND id NOT IN (
                    SELECT repairId FROM invoice WHERE kind = 'invoice' AND paidAt IS NOT NULL AND deletedAt IS NULL
                    AND id NOT IN (SELECT creditsInvoiceId FROM invoice WHERE creditsInvoiceId IS NOT NULL AND deletedAt IS NULL))
                AND deviceId NOT IN (
                    SELECT d.id FROM device d JOIN customer c ON c.id = d.customerId WHERE c.isShop = 1)
                """)
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }
}
