import Foundation
import GRDB

/// One line of a counter sale: a part from stock, or an item typed in.
public struct CounterSaleItem: Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// A stocked part; it leaves stock as Sold. Nil for a typed item.
    public var partId: UUID?
    public var description: String
    public var quantity: Int
    public var unitCents: Int

    public init(partId: UUID? = nil, description: String, quantity: Int = 1, unitCents: Int) {
        self.partId = partId
        self.description = description
        self.quantity = quantity
        self.unitCents = unitCents
    }

    public var amountCents: Int { quantity * unitCents }

    var billLine: BillLine {
        BillLine(kind: partId == nil ? .item : .part, description: description, hundredths: quantity * 100,
                 unitCents: unitCents, amountCents: amountCents)
    }
}

extension Library {
    /// The lines and totals a counter sale would have, at the region's taxes.
    public func counterSaleTotals(_ items: [CounterSaleItem]) throws -> Totals {
        let profile = try businessProfile()
        return Billing.totals(items.filter { $0.quantity > 0 }.map(\.billLine), discountCents: 0,
                              taxes: profile.chargedTaxes, taxesLabour: profile.taxesLabour)
    }

    /// Invoices a sale over the counter, with no repair: the next invoice number, the lines,
    /// and the region's taxes. Stocked parts leave stock as Sold. With no customer, the sale
    /// is to a walk-in and the invoice sits with the shop.
    @discardableResult
    public func issueCounterSale(to customerID: UUID?, items: [CounterSaleItem], now: Date = .now) throws -> Invoice {
        let items = items.filter { $0.quantity > 0 && !$0.description.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { throw BillingError.nothingToBill }
        let profile = try businessProfile()
        let buyer: Customer
        if let customerID, let customer = try customer(customerID), !customer.isShop {
            buyer = customer
        } else {
            buyer = try shop(named: profile.name, now: now)
        }
        let lines = items.map(\.billLine)
        let content = DocumentContent(
            business: profile,
            customer: buyer.isShop ? .init(name: "", phone: "", email: "", address: "")
                                   : .init(name: buyer.name, phone: buyer.phone, email: buyer.email, address: buyer.address),
            deviceTitle: "", serial: "", ticketNumber: 0, complaint: "", diagnosis: "",
            lines: lines, totals: Billing.totals(lines, discountCents: 0, taxes: profile.chargedTaxes, taxesLabour: profile.taxesLabour))
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        let language = buyer.isShop ? profile.defaultDocumentsLanguage : buyer.documentsLanguage
        return try db.write { db in
            var invoice = Invoice(id: UUID(), repairId: nil, kind: .invoice, number: try Self.nextNumber("nextInvoiceNumber", db),
                                  issuedAt: now, validUntil: nil, language: language, content: json,
                                  totalCents: content.totals.totalCents, paidAt: nil, paymentMethod: nil, decision: nil, decidedAt: nil,
                                  fileId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
            invoice.customerId = buyer.id
            try invoice.insert(db)
            for item in items {
                guard let partID = item.partId else { continue }
                try Self.moveStock(db, partID: partID, by: -item.quantity, reason: .sold,
                                   from: StockSource(invoice: invoice.id), now: now)
            }
            return invoice
        }
    }

    /// Puts back the parts an invoice sold, as Returned, when a credit note cancels it.
    static func returnSoldParts(_ db: Database, invoice invoiceID: UUID, credit creditID: UUID, now: Date) throws {
        let sold = try StockMove.filter(Column("invoiceId") == invoiceID.stored && Column("reason") == StockReason.sold.rawValue
                                        && Column("deletedAt") == nil).fetchAll(db)
        for move in sold {
            try moveStock(db, partID: move.partId, by: -move.delta, reason: .returned, from: StockSource(invoice: creditID), now: now)
        }
    }

    /// A customer's counter sales and their credit notes, newest first. For the shop, the
    /// walk-in sales.
    public func counterSales(of customerID: UUID) throws -> [Invoice] {
        try db.read { db in
            try Invoice.filter(Column("customerId") == customerID.stored && Column("deletedAt") == nil)
                .order(Column("issuedAt").desc, Column("rowid").desc).fetchAll(db)
        }
    }
}
