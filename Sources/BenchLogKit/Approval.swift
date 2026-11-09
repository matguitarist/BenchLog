import Foundation
import GRDB

/// What the customer said at check-in about approving the work.
public enum ApprovalRule: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Repair without asking.
    case go
    /// An estimate must be approved before any work.
    case ask
    /// Go ahead while the work costs at most `approvalLimitCents` before taxes.
    case upTo

    public var id: String { rawValue }
}

/// Where a repair stands against its approval rule.
public enum ApprovalState: Hashable, Sendable {
    /// The rule is Go ahead.
    case notNeeded
    /// Under the amount the customer allowed (cents, before taxes).
    case withinLimit(Int)
    /// An approved estimate covers the work.
    case approved
    /// An estimate is required and none is approved yet.
    case needed
    /// The bill passed the amount the customer allowed: subtotal and limit, in cents.
    case overLimit(subtotal: Int, limit: Int)
    /// The customer refused the estimate.
    case refused

    /// True when work should wait for the customer.
    public var blocksWork: Bool {
        switch self {
        case .needed, .overLimit, .refused: true
        case .notNeeded, .withinLimit, .approved: false
        }
    }
}

extension RepairStatus {
    /// The statuses that mean work is happening or done: moving there needs approval first.
    public var isWork: Bool { self == .waitingOnParts || self == .inProgress || self == .ready }
}

extension Library {
    /// The repair's approval state, from its rule, its bill, and its estimates.
    public func approvalState(of repairID: UUID) throws -> ApprovalState {
        guard let repair = try repair(repairID) else { return .notNeeded }
        if repair.approvalRule == .go { return .notNeeded }
        let estimates = try invoices(for: repairID).filter { $0.kind == .estimate }
        let subtotal = try bill(for: repairID).totals.subtotalCents
        // The newest decision counts: a refusal after an approval stops the work again.
        let decided = estimates.filter { $0.decision != nil }.max { ($0.decidedAt ?? .distantPast) < ($1.decidedAt ?? .distantPast) }
        let approvedEstimate = decided?.decision == .approved ? decided : nil

        switch repair.approvalRule {
        case .go:
            return .notNeeded
        case .ask:
            if approvedEstimate != nil { return .approved }
            return decided?.decision == .refused ? .refused : .needed
        case .upTo:
            let limit = repair.approvalLimitCents ?? 0
            if subtotal <= limit { return .withinLimit(limit) }
            // An approved estimate covers the work up to its own subtotal.
            if let approvedEstimate, (approvedEstimate.document?.totals.subtotalCents ?? 0) >= subtotal { return .approved }
            return decided?.decision == .refused ? .refused : .overLimit(subtotal: subtotal, limit: limit)
        }
    }

    /// Sets the repair's approval rule; the limit only counts with `upTo`.
    public func setApproval(_ rule: ApprovalRule, limitCents: Int?, of repairID: UUID, now: Date = .now) throws {
        try db.write { db in
            guard var repair = try Repair.fetchOne(db, key: repairID.stored) else { return }
            repair.approvalRule = rule
            repair.approvalLimitCents = rule == .upTo ? max(limitCents ?? 0, 0) : nil
            repair.updatedAt = now
            try repair.update(db)
        }
    }
}
