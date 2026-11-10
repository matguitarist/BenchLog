import Foundation
import Testing
@testable import BenchLogKit

/// S-067 Dashboard.
@Suite struct DashboardTests {
    let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 10, hour: 12).date!
    let day: TimeInterval = 86_400

    @Test func anEmptyLibraryHasAnEmptyDashboard() throws {
        let dashboard = try Library().dashboard(now: now)
        #expect(dashboard.isEmpty && dashboard.openCount == 0 && dashboard.attention.isEmpty)
    }

    @Test func countsOpenRepairsAndListsTheOnesThatNeedAttention() throws {
        let library = try Library()
        let customer = try library.save(Customer(name: "Roy, Marc"))
        let device = try library.save(Device(customerId: customer.id, category: .console, brand: "Sony", model: "PS5"))
        func repair(daysAgo: Double, promisedIn: Double? = nil, _ status: RepairStatus? = nil) throws -> Repair {
            let received = now.addingTimeInterval(-daysAgo * day)
            let repair = try library.createRepair(deviceID: device.id, complaint: "HDMI",
                                                  promisedAt: promisedIn.map { now.addingTimeInterval($0 * day) }, now: received)
            if let status { try library.setStatus(status, of: repair.id, now: received.addingTimeInterval(3_600)) }
            return repair
        }
        let long = try repair(daysAgo: 20, .diagnosing)
        let late = try repair(daysAgo: 5, promisedIn: -2, .inProgress)
        let ready = try repair(daysAgo: 4, promisedIn: -1, .ready)       // Ready is never late
        let waiting = try repair(daysAgo: 3, .awaitingApproval)
        let today = try repair(daysAgo: 1, promisedIn: 0)
        _ = try repair(daysAgo: 1, promisedIn: 3)                         // nothing to do yet
        _ = try repair(daysAgo: 30, promisedIn: -10, .pickedUp)           // closed

        // A paid counter sale (an invoice with no repair) changes nothing about To Collect.
        let sale = try library.issueCounterSale(to: nil, items: [CounterSaleItem(description: "Cable", unitCents: 1_000)], now: now.addingTimeInterval(-40 * day))
        try library.setPaid(sale.id, method: .cash, now: now.addingTimeInterval(-40 * day))

        let dashboard = try library.dashboard(now: now)
        #expect(!dashboard.isEmpty)
        #expect(dashboard.openCount == 6)
        #expect(dashboard.count(.intake) == 2 && dashboard.count(.ready) == 1 && dashboard.count(.pickedUp) == 0)
        #expect(dashboard.attention.map(\.id) == [late.id, today.id, ready.id, waiting.id, long.id])
        #expect(dashboard.attention.map(\.reason) == [.overdue(days: 2), .promisedToday, .toCollect, .awaitingApproval, .longOnBench(days: 20)])
        #expect(dashboard.overdueCount == 1 && dashboard.toCollectCount == 1)

        // A paid invoice takes the Ready repair off the list and into the month's sales.
        try library.save(LabourLine(repairId: ready.id, description: "Pose", kind: .flat, unitCents: 10_000))
        let invoice = try library.issue(.invoice, for: ready.id, now: now)
        try library.setPaid(invoice.id, method: .cash, now: now)
        let paid = try library.dashboard(now: now)
        #expect(paid.toCollectCount == 0 && paid.month.salesCents == 10_000 && paid.month.owedCents == 0)
    }

    @Test func countsThePartsToDealWith() throws {
        let library = try Library()
        let customer = try library.save(Customer(name: "Roy, Marc"))
        let device = try library.save(Device(customerId: customer.id, category: .console, brand: "Sony", model: "PS5"))
        let repair = try library.createRepair(deviceID: device.id, complaint: "HDMI", now: now)
        let needed = try library.useFreePart("HDMI port", on: repair.id, now: now)
        let ordered = try library.useFreePart("Fan", on: repair.id, now: now)
        try library.setStatus(.needed, ofUse: needed.id, now: now)
        try library.setStatus(.ordered, ofUse: ordered.id, now: now)
        let dashboard = try library.dashboard(now: now)
        #expect(dashboard.toOrder == 1 && dashboard.incoming == 1 && dashboard.lowStock == 0)
    }
}
