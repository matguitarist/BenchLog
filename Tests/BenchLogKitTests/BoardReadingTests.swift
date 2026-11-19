import Foundation
import Testing
@testable import BenchLogKit

/// S-084 Board notes and readings.
@Suite struct BoardReadingTests {
    let library: Library
    let device: Device
    let repair: Repair

    init() throws {
        library = try Library()
        let customer = try library.save(Customer(name: "Léa Tremblay", phone: "514 555-0142"))
        device = try library.save(Device(customerId: customer.id, category: .computer, brand: "Apple", model: "MacBook Pro"))
        repair = try library.createRepair(deviceID: device.id, complaint: "Ne démarre pas")
    }

    @Test(arguments: [
        (ReadingMode.diode, "0.452", 0.452), (.diode, "452", 0.452), (.diode, "452 mV", 0.452), (.diode, "0,45 V", 0.45),
        (.voltage, "3.3", 3.3), (.voltage, "3.3V", 3.3), (.voltage, "12.6 v", 12.6), (.voltage, "850m", 0.85),
        (.resistance, "12k", 12_000), (.resistance, "1.2 MΩ", 1_200_000), (.resistance, "4.7 ohms", 4.7), (.resistance, "330Ω", 330),
    ])
    func aTypedReadingIsRead(mode: ReadingMode, text: String, value: Double) throws {
        let read = try #require(mode.parse(text))
        #expect(abs((read ?? -1) - value) < 1e-9)
    }

    @Test func openLoopAndNonsense() {
        #expect(ReadingMode.diode.parse("OL") == .some(nil))
        #expect(ReadingMode.resistance.parse("o.l") == .some(nil))
        #expect(ReadingMode.voltage.parse("high") == nil)
        #expect(ReadingMode.voltage.parse("") == nil)
    }

    @Test func readingsAreWrittenAsAMeterShowsThem() {
        #expect(ReadingMode.diode.format(0.452).hasSuffix(" V"))
        #expect(ReadingMode.diode.format(nil) == "OL")
        #expect(ReadingMode.resistance.format(12_000).hasSuffix(" kΩ"))
        #expect(ReadingMode.resistance.format(1_200_000).hasSuffix(" MΩ"))
        #expect(ReadingMode.resistance.format(330).hasSuffix(" Ω"))
    }

    @Test func readingsAreKeptOnTheRepairAndItsBoard() throws {
        try library.addBoardReading(BoardReading(repairId: repair.id, board: "820-4924.brd", target: "PPBUS_G3H", isPin: false,
                                                 mode: .diode, value: 0.38, note: "  low  "))
        try library.addBoardReading(BoardReading(repairId: repair.id, board: "820-4924.brd", target: "U7100.3", isPin: true,
                                                 mode: .voltage, value: nil))
        try library.addBoardReading(BoardReading(repairId: repair.id, board: "other.brd", target: "GND", isPin: false,
                                                 mode: .resistance, value: 0))
        let readings = try library.boardReadings(repair: repair.id, board: "820-4924.brd")
        #expect(readings.map(\.target) == ["PPBUS_G3H", "U7100.3"])
        #expect(readings[0].note == "low")
        #expect(readings[1].value == nil)
        #expect(try library.boardReadings(repair: repair.id).count == 3)
        try library.trash(BoardReading.self, id: readings[0].id)
        #expect(try library.boardReadings(repair: repair.id).count == 2)
    }

    @Test func aBoardOnTheDeviceUsesItsOpenRepair() throws {
        let onRepair = try library.addAttachment(data: Data("b".utf8), originalName: "a.brd", to: .repair, id: repair.id)
        let onDevice = try library.addAttachment(data: Data("b".utf8), originalName: "b.brd", to: .device, id: device.id)
        #expect(try library.readingRepair(forAttachment: onRepair.id) == repair.id)
        #expect(try library.readingRepair(forAttachment: onDevice.id) == repair.id)
    }

    @Test func emptyTrashTakesARepairsReadings() throws {
        try library.addBoardReading(BoardReading(repairId: repair.id, board: "b.brd", target: "GND", isPin: false, mode: .diode, value: 0))
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try library.moveToTrash(.repair(repair.id), now: day)
        try library.emptyTrash(now: day.addingTimeInterval(40 * 86_400))
        #expect(try library.boardReadings(repair: repair.id).isEmpty)
    }
}
