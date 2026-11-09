import BenchLogKit
import SwiftUI

extension ApprovalRule {
    var title: String {
        switch self {
        case .go: String(localized: "Go ahead")
        case .ask: String(localized: "Ask for an estimate first")
        case .upTo: String(localized: "Go ahead up to an amount")
        }
    }
}

/// The approval rule and, for "up to", the amount before taxes. Used in New Repair and on
/// the repair.
struct ApprovalPicker: View {
    @Binding var rule: ApprovalRule
    @Binding var limit: Decimal?

    var body: some View {
        Picker("Before repairing", selection: $rule) {
            ForEach(ApprovalRule.allCases) { Text($0.title).tag($0) }
        }
        .help("What the customer said about approving the work; it prints on the intake slip")
        if rule == .upTo {
            LabeledContent("Up to, before taxes") {
                TextField("Up to, before taxes", value: $limit, format: Money.format, prompt: Text(Money.text(15_000)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        }
    }
}

/// The repair's approval rule, saved as it changes.
struct RepairApprovalRow: View {
    @Environment(AppModel.self) private var model
    let repair: Repair
    @State private var rule: ApprovalRule = .go
    @State private var limit: Decimal?

    var body: some View {
        ApprovalPicker(rule: $rule, limit: $limit)
            .onAppear {
                rule = repair.approvalRule
                limit = Money.decimal(repair.approvalLimitCents)
            }
            .onChange(of: rule) { save() }
            .onSubmit(save)
    }

    private func save() {
        let cents = Money.cents(limit)
        guard rule != repair.approvalRule || (rule == .upTo && cents != repair.approvalLimitCents) else { return }
        model.setApproval(rule, limitCents: cents, of: repair.id)
    }
}

/// Where the repair stands against its rule, beside its status: words and a symbol, never
/// color alone.
struct ApprovalBadge: View {
    let state: ApprovalState

    var body: some View {
        if let text {
            Label(text, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(color)
                .help(help)
        }
    }

    private var text: String? {
        switch state {
        case .notNeeded: nil
        case .withinLimit(let limit): String(localized: "Approved up to \(Money.text(limit))")
        case .approved: String(localized: "Estimate approved")
        case .needed: String(localized: "Estimate required")
        case .overLimit(_, let limit): String(localized: "Over the approved \(Money.text(limit))")
        case .refused: String(localized: "Estimate refused")
        }
    }

    private var symbol: String {
        switch state {
        case .notNeeded, .withinLimit, .approved: "checkmark.seal"
        case .needed, .overLimit: "hand.raised"
        case .refused: "hand.thumbsdown"
        }
    }

    private var color: Color {
        switch state {
        case .notNeeded, .withinLimit: .secondary
        case .approved: .green
        case .needed, .overLimit: .orange
        case .refused: .red
        }
    }

    private var help: String {
        state.blocksWork ? String(localized: "Print an estimate and record the customer's answer before you start")
                         : String(localized: "The customer allowed this work")
    }
}

/// A status change that would start work without the customer's approval.
struct PendingStart: Identifiable {
    let repairID: UUID
    let status: RepairStatus
    let state: ApprovalState
    var id: UUID { repairID }

    var message: String {
        switch state {
        case .overLimit(let subtotal, let limit):
            String(localized: "The work comes to \(Money.text(subtotal)) before taxes, over the \(Money.text(limit)) the customer allowed.")
        case .refused:
            String(localized: "The customer refused the estimate.")
        default:
            String(localized: "The customer asked for an estimate before any repair.")
        }
    }
}
