import Foundation
import GRDB

// MARK: - Business

/// The business details printed on documents, and the rates used to price a repair.
/// Stored as JSON in the meta table. Rates are in millionths: 5 % = 50 000.
public struct BusinessProfile: Codable, Equatable, Sendable {
    public var name = ""
    public var address = ""
    public var phone = ""
    public var email = ""
    public var website = ""
    public var tpsNumber = ""
    public var tvqNumber = ""
    public var warrantyFrench = "Garantie de 90 jours sur les pièces et la main-d’œuvre de cette réparation."
    public var warrantyEnglish = "90-day warranty on the parts and labour of this repair."
    public var termsFrench = "Les appareils non réclamés 90 jours après l’avis de fin de réparation peuvent être recyclés."
    public var termsEnglish = "Devices not picked up 90 days after we tell you the repair is done may be recycled."
    /// The logo file, relative to the library's Files folder; empty for none.
    public var logoPath = ""
    public var tpsRate = 50_000
    public var tvqRate = 99_750
    /// The hourly rate new labour lines start with.
    public var hourlyRateCents = 6_500
    public var estimateValidDays = 30

    public init() {}

    public func warranty(_ language: DocumentsLanguage) -> String { language == .french ? warrantyFrench : warrantyEnglish }
    public func terms(_ language: DocumentsLanguage) -> String { language == .french ? termsFrench : termsEnglish }

    // Decoding keeps the defaults for fields an older profile does not have.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BusinessProfile()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? d.address
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? d.phone
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? d.email
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? d.website
        tpsNumber = try c.decodeIfPresent(String.self, forKey: .tpsNumber) ?? d.tpsNumber
        tvqNumber = try c.decodeIfPresent(String.self, forKey: .tvqNumber) ?? d.tvqNumber
        warrantyFrench = try c.decodeIfPresent(String.self, forKey: .warrantyFrench) ?? d.warrantyFrench
        warrantyEnglish = try c.decodeIfPresent(String.self, forKey: .warrantyEnglish) ?? d.warrantyEnglish
        termsFrench = try c.decodeIfPresent(String.self, forKey: .termsFrench) ?? d.termsFrench
        termsEnglish = try c.decodeIfPresent(String.self, forKey: .termsEnglish) ?? d.termsEnglish
        logoPath = try c.decodeIfPresent(String.self, forKey: .logoPath) ?? d.logoPath
        tpsRate = try c.decodeIfPresent(Int.self, forKey: .tpsRate) ?? d.tpsRate
        tvqRate = try c.decodeIfPresent(Int.self, forKey: .tvqRate) ?? d.tvqRate
        hourlyRateCents = try c.decodeIfPresent(Int.self, forKey: .hourlyRateCents) ?? d.hourlyRateCents
        estimateValidDays = try c.decodeIfPresent(Int.self, forKey: .estimateValidDays) ?? d.estimateValidDays
    }
}

// MARK: - Labour

public enum LabourKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case hourly, flat
    public var id: String { rawValue }
}

/// Work on a repair: hours at a rate, or a flat price.
public struct LabourLine: BenchRecord {
    public static let databaseTableName = "labourLine"

    public var id: UUID
    public var repairId: UUID
    public var description: String
    public var kind: LabourKind
    /// Hours × 100: 1.5 h is 150. Ignored for a flat line.
    public var hundredthHours: Int
    /// The hourly rate, or the flat price.
    public var unitCents: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), repairId: UUID, description: String, kind: LabourKind = .hourly,
                hundredthHours: Int = 100, unitCents: Int, now: Date = .now) {
        self.id = id
        self.repairId = repairId
        self.description = description
        self.kind = kind
        self.hundredthHours = hundredthHours
        self.unitCents = unitCents
        createdAt = now
        updatedAt = now
    }

    public var amountCents: Int {
        kind == .flat ? unitCents : Billing.roundHalfUp(hundredthHours * unitCents, 100)
    }
}

// MARK: - Bills

/// One printed line.
public struct BillLine: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case labour, part }
    public var kind: Kind
    public var description: String
    /// Hours × 100 for hourly labour, quantity × 100 for parts; nil for a flat price.
    public var hundredths: Int?
    public var unitCents: Int
    public var amountCents: Int
    public var isHourly: Bool

    public init(kind: Kind, description: String, hundredths: Int?, unitCents: Int, amountCents: Int, isHourly: Bool = false) {
        self.kind = kind
        self.description = description
        self.hundredths = hundredths
        self.unitCents = unitCents
        self.amountCents = amountCents
        self.isHourly = isHourly
    }
}

public struct Totals: Codable, Hashable, Sendable {
    public var labourCents: Int
    public var partsCents: Int
    public var discountCents: Int
    public var subtotalCents: Int
    public var tpsRate: Int
    public var tvqRate: Int
    public var tpsCents: Int
    public var tvqCents: Int
    public var totalCents: Int
}

public enum Billing {
    /// a ÷ b rounded half up, for amounts that are never negative.
    public static func roundHalfUp(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? (a + b / 2) / b : -((-a + b / 2) / b)
    }

    /// Subtotal = labour + parts − discount (never below zero). TPS and TVQ are each a
    /// share of the subtotal, rounded half up to the cent.
    public static func totals(_ lines: [BillLine], discountCents: Int, tpsRate: Int, tvqRate: Int) -> Totals {
        let labour = lines.filter { $0.kind == .labour }.reduce(0) { $0 + $1.amountCents }
        let parts = lines.filter { $0.kind == .part }.reduce(0) { $0 + $1.amountCents }
        let discount = min(max(discountCents, 0), labour + parts)
        let subtotal = labour + parts - discount
        let tps = roundHalfUp(subtotal * tpsRate, 1_000_000)
        let tvq = roundHalfUp(subtotal * tvqRate, 1_000_000)
        return Totals(labourCents: labour, partsCents: parts, discountCents: discount, subtotalCents: subtotal,
                      tpsRate: tpsRate, tvqRate: tvqRate, tpsCents: tps, tvqCents: tvq, totalCents: subtotal + tps + tvq)
    }
}

/// What a repair costs right now, at the current rates.
public struct Bill: Hashable, Sendable {
    public var lines: [BillLine]
    public var totals: Totals
    /// Parts on the repair with no price yet: they are left off.
    public var unpricedParts: [String]
}

// MARK: - Documents

public enum DocumentKind: String, Codable, Sendable {
    case invoice, estimate
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
}

extension BusinessProfile: Hashable {}

/// An issued invoice or estimate. Its content never changes; payment and the estimate's
/// decision are recorded beside it.
public struct Invoice: BenchRecord {
    public static let databaseTableName = "invoice"

    public var id: UUID
    public var repairId: UUID
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

    public var numberText: String? { number.map { "F-" + String(format: "%04d", $0) } }

    public var document: DocumentContent? {
        try? JSONDecoder().decode(DocumentContent.self, from: Data(content.utf8))
    }
}

public enum BillingError: LocalizedError {
    case nothingToBill

    public var errorDescription: String? {
        switch self {
        case .nothingToBill: "The repair has no labour or priced parts to bill."
        }
    }
}

extension Library {
    // MARK: Business

    public func businessProfile() throws -> BusinessProfile {
        guard let json = try metaValue("business") else { return BusinessProfile() }
        return (try? JSONDecoder().decode(BusinessProfile.self, from: Data(json.utf8))) ?? BusinessProfile()
    }

    public func save(_ profile: BusinessProfile) throws {
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        try db.write { try $0.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('business', ?)", arguments: [json]) }
    }

    /// Copies a logo into the library and saves its path in the profile.
    public func setLogo(data: Data, fileExtension: String) throws {
        var profile = try businessProfile()
        let relative = "business/logo-\(UUID().uuidString.prefix(8).lowercased()).\(fileExtension.lowercased())"
        let url = filesURL.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        profile.logoPath = relative
        try save(profile)
    }

    // MARK: Labour

    public func labourLines(on repairID: UUID) throws -> [LabourLine] {
        try db.read { db in
            try LabourLine.filter(Column("repairId") == repairID.stored && Column("deletedAt") == nil)
                .order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
    }

    @discardableResult
    public func save(_ line: LabourLine, now: Date = .now) throws -> LabourLine {
        var line = line
        line.updatedAt = now
        try db.write { try line.save($0) }
        return line
    }

    public func setDiscount(_ cents: Int, of repairID: UUID, now: Date = .now) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE repair SET discountCents = ?, updatedAt = ? WHERE id = ?",
                           arguments: [max(cents, 0), now, repairID.stored])
        }
    }

    // MARK: Pricing

    /// Labour lines, then priced parts, with the totals at the current rates.
    public func bill(for repairID: UUID) throws -> Bill {
        guard let repair = try repair(repairID) else {
            return Bill(lines: [], totals: Billing.totals([], discountCents: 0, tpsRate: 0, tvqRate: 0), unpricedParts: [])
        }
        let profile = try businessProfile()
        var lines = try labourLines(on: repairID).map { line in
            BillLine(kind: .labour, description: line.description, hundredths: line.kind == .hourly ? line.hundredthHours : nil,
                     unitCents: line.unitCents, amountCents: line.amountCents, isHourly: line.kind == .hourly)
        }
        let uses = try partUses(on: repairID)
        lines += uses.compactMap { use in
            guard let price = use.priceCents else { return nil }
            return BillLine(kind: .part, description: use.name, hundredths: use.quantity * 100, unitCents: price,
                            amountCents: price * use.quantity)
        }
        return Bill(lines: lines,
                    totals: Billing.totals(lines, discountCents: repair.discountCents, tpsRate: profile.tpsRate, tvqRate: profile.tvqRate),
                    unpricedParts: uses.filter { $0.priceCents == nil }.map(\.name))
    }

    // MARK: Issuing

    /// Issues an invoice (with the next number) or an estimate (valid for the profile's
    /// days), freezing everything it prints.
    @discardableResult
    public func issue(_ kind: DocumentKind, for repairID: UUID, now: Date = .now) throws -> Invoice {
        guard let row = try repairRow(repairID) else { throw BillingError.nothingToBill }
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
            var number: Int?
            if kind == .invoice {
                let next = try Int.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'nextInvoiceNumber'") ?? 1
                try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('nextInvoiceNumber', ?)", arguments: ["\(next + 1)"])
                number = next
            }
            let invoice = Invoice(id: UUID(), repairId: repairID, kind: kind, number: number, issuedAt: now,
                                  validUntil: kind == .estimate ? Calendar.current.date(byAdding: .day, value: profile.estimateValidDays, to: now) : nil,
                                  language: row.customer.documentsLanguage, content: json, totalCents: bill.totals.totalCents,
                                  paidAt: nil, paymentMethod: nil, decision: nil, decidedAt: nil, fileId: nil,
                                  createdAt: now, updatedAt: now, deletedAt: nil)
            try invoice.insert(db)
            return invoice
        }
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
            try Note(owner: .repair, ownerId: estimate.repairId, kind: .estimate, text: decision.rawValue, now: now).insert(db)
        }
        guard approved, let repair = try repair(estimate.repairId),
              [.intake, .diagnosing, .awaitingApproval].contains(repair.status) else { return try repair(estimate.repairId) }
        let next: RepairStatus = try isWaitingOnParts(repair.id) ? .waitingOnParts : .inProgress
        return try setStatus(next, of: repair.id, now: now.addingTimeInterval(1))
    }

    /// Ready repairs with no paid invoice: the money still to collect.
    public func toCollectRepairIDs() throws -> Set<UUID> {
        try db.read { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT id FROM repair WHERE status = 'ready' AND deletedAt IS NULL AND id NOT IN (
                    SELECT repairId FROM invoice WHERE kind = 'invoice' AND paidAt IS NOT NULL AND deletedAt IS NULL)
                """)
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }
}
