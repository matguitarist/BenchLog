import Foundation
import Testing
@testable import BoardViewKit

// S-070
@Suite struct BoardTests {
    let board: Board

    init() throws {
        board = try BoardFile.read(BoardSample.data)
    }

    @Test func encodingRoundTrips() {
        let text = "Parts:\nU7100 5 3\r\n"
        let encoded = BoardFile.encode(text)
        #expect(String(decoding: BoardFile.decode([UInt8](encoded)), as: UTF8.self) == text)
    }

    @Test func anEncodedFileStartsWithTheMagicBytes() {
        #expect([UInt8](BoardSample.data.prefix(4)) == [0x23, 0xE2, 0x63, 0x28])
    }

    @Test func encodedAndPlainFilesReadTheSame() throws {
        let plain = try BoardFile.read(Data(BoardSample.text.utf8))
        #expect(plain.parts.map(\.name) == board.parts.map(\.name))
        #expect(plain.pins == board.pins)
    }

    @Test func readsPartsPinsOutlineAndTestPoints() throws {
        #expect(board.parts.count == 16)
        #expect(board.outline.count == 6)
        #expect(board.testPoints.count == 2)
        let u1 = try #require(board.part(named: "u1"))
        #expect(board.parts[u1].pins.count == 64)
        #expect(board.parts[u1].side == .top)
        #expect(!board.parts[u1].isThroughHole)
        #expect(board.pins[board.parts[u1].pins.lowerBound].number == 1)
    }

    @Test func partTypesGiveTheSide() throws {
        let j1 = try #require(board.part(named: "J1"))
        #expect(board.parts[j1].side == .bottom)
        let cn1 = try #require(board.part(named: "CN1"))
        #expect(board.parts[cn1].isThroughHole)
        let firstPin = board.parts[cn1].pins.lowerBound
        #expect(board.shows(pin: firstPin, on: .top) && board.shows(pin: firstPin, on: .bottom))
        let j1Pin = board.parts[j1].pins.lowerBound
        #expect(!board.shows(pin: j1Pin, on: .top))
    }

    @Test func aNetListsItsPinsOnEverySide() throws {
        let pins = board.pins(onNet: "USBC_VBUS")
        #expect(pins.count == 5)
        let sides = Set(pins.map { board.parts[board.pins[$0].part].side })
        #expect(sides == [.bottom])
        #expect(board.net(named: "usbc_vbus") == "USBC_VBUS")
        #expect(Board.isGround("GND") && Board.isGround("GND_AUDIO") && !Board.isGround("PPBUS_MAIN"))
    }

    @Test func aPinHighlightsItsNetAndAPartItsPins() throws {
        let l1 = try #require(board.part(named: "L1"))
        let pin = board.parts[l1].pins.lowerBound
        #expect(Set(board.highlightedPins(for: .pin(pin))) == Set(board.pins(onNet: "PPBUS_MAIN")))
        #expect(board.highlightedPins(for: .part(l1)) == Array(board.parts[l1].pins))
        #expect(board.schematicTerms(for: .pin(pin)) == ["PPBUS_MAIN", "L1"])
    }

    @Test func searchPutsExactNamesFirst() {
        let found = board.search("c1")
        #expect(found.first == .part(board.part(named: "C1")!, name: "C1"))
        #expect(board.search("i2c").map(\.name) == ["I2C_SCL", "I2C_SDA"])
        #expect(board.search("  ").isEmpty)
    }

    @Test func hitTestFindsAPinThenAPart() throws {
        let c1 = try #require(board.part(named: "C1"))
        let pin = board.parts[c1].pins.lowerBound
        #expect(board.hitTest(board.pins[pin].position, side: .top, tolerance: 1) == .pin(pin))
        let u1 = try #require(board.part(named: "U1"))
        let between = BoardPoint(x: 580, y: 440)
        #expect(board.hitTest(between, side: .top, tolerance: 0) == .part(u1))
        #expect(board.hitTest(BoardPoint(x: 1900, y: 100), side: .top, tolerance: 4) == nil)
        // J1 is on the bottom: not there from the top.
        let j1Pin = board.parts[board.part(named: "J1")!].pins.lowerBound
        #expect(board.hitTest(board.pins[j1Pin].position, side: .top, tolerance: 1) == nil)
        #expect(board.hitTest(board.pins[j1Pin].position, side: .bottom, tolerance: 1) == .pin(j1Pin))
    }

    @Test func pinRadiusFollowsThePitch() throws {
        let u1 = try #require(board.part(named: "U1"))
        #expect(board.parts[u1].pinRadius == 12)
        #expect(board.parts[u1].bounds.width == 280 + 24)
    }

    @Test func otherFormatsAreRefused() {
        #expect(throws: BoardFileError.unsupported("BRD2")) { try BoardFile.read(Data("BRDOUT: 1 2 3".utf8)) }
        #expect(throws: BoardFileError.self) { try BoardFile.read(Data(repeating: 0, count: 64)) }
        #expect(throws: BoardFileError.self) { try BoardFile.read(Data("str_length:\nvar_data:\n1 0 0 0\n".utf8)) }
        #expect(BoardFile.canRead(fileName: "820-4924-A.BRD"))
        #expect(!BoardFile.canRead(fileName: "board.fz"))
    }

    @Test func aNameIsWholeOnlyBetweenSeparators() {
        #expect(Schematic.isWholeName(before: nil, after: nil))
        #expect(Schematic.isWholeName(before: " ", after: "\n"))
        #expect(!Schematic.isWholeName(before: nil, after: "0"))
        #expect(!Schematic.isWholeName(before: "_", after: nil))
        #expect(Schematic.isWholeName(before: "(", after: ","))
    }

    @Test func theSchematicIsPickedByName() {
        #expect(Schematic.pick(for: "820-4924-A.brd", from: ["Invoice.pdf", "Schematic 820-4924_a_a1502.pdf"]) == 1)
        #expect(Schematic.pick(for: "820-4924-A.brd", from: ["Guide.pdf", "820-4924 notes.pdf"]) == 1)
        #expect(Schematic.pick(for: "board.brd", from: ["a.pdf", "b.pdf"]) == 0)
        #expect(Schematic.pick(for: "board.brd", from: []) == nil)
    }

    @Test func aSelectionInTheSchematicBecomesAName() {
        #expect(Schematic.name(fromSelection: " U7100, ") == "U7100")
        #expect(Schematic.name(fromSelection: "PPBUS_G3H") == "PPBUS_G3H")
        #expect(Schematic.name(fromSelection: "two words") == nil)
        #expect(Schematic.name(fromSelection: "  ") == nil)
    }
}
