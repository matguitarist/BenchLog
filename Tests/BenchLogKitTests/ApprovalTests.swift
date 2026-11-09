import Foundation
import Testing
@testable import BenchLogKit

/// S-034 Approval before work.
@Suite struct ApprovalTests {
    let library: Library
    let customer: Customer
    let device: Device

    init() throws {
        library = try Library()
        customer = try library.save(Customer(name: "Julie Gagnon"))
        device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13 Pro"))
    }

    /// A repair with `hours` of labour at 65 $ an hour.
    private func repair(_ rule: ApprovalRule, limit: Int? = nil, hours: Int = 1) throws -> Repair {
        let repair = try library.createRepair(deviceID: device.id, complaint: "Cracked screen", approval: rule, approvalLimitCents: limit)
        var line = LabourLine(repairId: repair.id, description: "Screen", kind: .hourly, hundredthHours: hours * 100, unitCents: 6500)
        line = try library.save(line)
        return repair
    }

    @Test func goAheadNeedsNothing() throws {
        let made = try repair(.go)
        #expect(try library.approvalState(of: made.id) == .notNeeded)
        #expect(try library.repair(made.id)?.approvalLimitCents == nil)
    }

    @Test func askFirstNeedsAnApprovedEstimate() throws {
        let made = try repair(.ask)
        #expect(try library.approvalState(of: made.id) == .needed)
        #expect(try library.approvalState(of: made.id).blocksWork)
        let estimate = try library.issue(.estimate, for: made.id)
        #expect(try library.approvalState(of: made.id) == .needed)
        _ = try library.decide(estimate.id, approved: true)
        #expect(try library.approvalState(of: made.id) == .approved)
    }

    @Test func aRefusedEstimateStopsTheWork() throws {
        let made = try repair(.ask)
        let estimate = try library.issue(.estimate, for: made.id)
        _ = try library.decide(estimate.id, approved: false)
        #expect(try library.approvalState(of: made.id) == .refused)
    }

    @Test func upToAnAmountAllowsWorkBelowIt() throws {
        let made = try repair(.upTo, limit: 15_000, hours: 2)  // 130 $ of 150 $
        #expect(try library.approvalState(of: made.id) == .withinLimit(15_000))
    }

    @Test func passingTheAmountNeedsAnEstimateThatCoversIt() throws {
        let made = try repair(.upTo, limit: 10_000, hours: 2)  // 130 $ over 100 $
        #expect(try library.approvalState(of: made.id) == .overLimit(subtotal: 13_000, limit: 10_000))
        let estimate = try library.issue(.estimate, for: made.id)
        _ = try library.decide(estimate.id, approved: true)
        #expect(try library.approvalState(of: made.id) == .approved)
        // More work than the approved estimate: ask again.
        _ = try library.save(LabourLine(repairId: made.id, description: "Battery", kind: .flat, hundredthHours: 100, unitCents: 4000))
        #expect(try library.approvalState(of: made.id) == .overLimit(subtotal: 17_000, limit: 10_000))
    }

    @Test func theRuleCanChange() throws {
        let made = try repair(.go)
        try library.setApproval(.upTo, limitCents: 20_000, of: made.id)
        #expect(try library.repair(made.id)?.approvalLimitCents == 20_000)
        try library.setApproval(.ask, limitCents: 20_000, of: made.id)
        #expect(try library.repair(made.id)?.approvalLimitCents == nil)
    }

    @Test func theIntakeSlipPrintsTheRule() throws {
        let made = try repair(.upTo, limit: 15_000)
        let html = DocumentHTML(language: .french).intakeSlip(business: BusinessProfile(), customer: customer, device: device,
                                                              repair: try #require(try library.repair(made.id)))
        #expect(html.contains("Réparation autorisée jusqu’à 150,00\u{00A0}$, taxes en sus."))
        let asked = try repair(.ask)
        let english = DocumentHTML(language: .english).intakeSlip(business: BusinessProfile(), customer: customer, device: device,
                                                                  repair: try #require(try library.repair(asked.id)))
        #expect(english.contains("Estimate required before any repair."))
        let plain = try repair(.go)
        let none = DocumentHTML(language: .french).intakeSlip(business: BusinessProfile(), customer: customer, device: device,
                                                              repair: try #require(try library.repair(plain.id)))
        #expect(!none.contains("class=\"approval\""))
    }
}
