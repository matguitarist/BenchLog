import Foundation
import GRDB

/// Customers. Every write sets `updatedAt`.
extension Library {
    // MARK: Customers

    /// Customers sorted by name. `search` matches the name, the email, or the phone's digits.
    public func customers(matching search: String = "") throws -> [Customer] {
        try db.read { db in
            var request = Customer.filter(Column("deletedAt") == nil)
            let text = search.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                let digits = Customer.digits(text)
                var condition = Column("name").like("%\(text)%") || Column("email").like("%\(text)%")
                if digits.count >= 3 { condition = condition || Column("phoneDigits").like("%\(digits)%") }
                request = request.filter(condition)
            }
            return try request.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }
    }

    public func customer(_ id: UUID) throws -> Customer? {
        try db.read { try Customer.fetchOne($0, key: id.stored) }
    }

    /// Adds or updates a customer. Returns it as stored.
    @discardableResult
    public func save(_ customer: Customer, now: Date = .now) throws -> Customer {
        var customer = customer
        customer.phoneDigits = Customer.digits(customer.phone)
        customer.updatedAt = now
        try db.write { try customer.save($0) }
        return customer
    }
}
