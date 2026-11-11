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
        #expect(throws: BoardFileError.unsupported("this kind of board file")) { try BoardFile.read(Data(repeating: 0, count: 64)) }
        #expect(throws: BoardFileError.self) { try BoardFile.read(Data("str_length:\nvar_data:\n1 0 0 0\n".utf8)) }
        #expect(throws: BoardFileError.malformed("no parts")) { try BoardFile.read(Data("BRDOUT: 0 0 0\nNETS: 0\nPARTS: 0\n".utf8)) }
        #expect(BoardFile.canRead(fileName: "820-4924-A.BRD"))
        #expect(BoardFile.canRead(fileName: "board.bdv") && BoardFile.canRead(fileName: "board.brd2"))
        #expect(!BoardFile.canRead(fileName: "board.fz"))
    }

    // S-071
    static let brd2 = """
        BRDOUT: 4 1000 500
        0 0
        1000 0
        1000 500
        0 500
        NETS: 3
        1 PP3V3
        2 GND
        3 UNCONNECTED
        PARTS: 3
        U1 100 100 200 200 0 1
        C1 300 100 340 100 4 2
        J1 500 100 600 100 6 3
        PINS: 8
        100 100 1 1
        200 100 2 1
        200 200 3 1
        100 200 1 1
        300 100 1 2
        340 100 2 2
        500 100 1 3
        600 100 2 3
        NAILS: 1
        7 50 50 1 2
        """

    @Test func readsABRD2Board() throws {
        let board = try BoardFile.read(Data(Self.brd2.utf8))
        #expect(board.outline.count == 4)
        #expect(board.parts.map(\.name) == ["U1", "C1", "J1"])
        #expect(board.parts.map(\.pins.count) == [4, 2, 2])
        #expect(board.parts[1].side == .bottom && !board.parts[1].isThroughHole)
        #expect(board.parts[2].isThroughHole)
        #expect(board.pins(onNet: "PP3V3").count == 4)
        #expect(board.pins[2].net == "")
        #expect(board.testPoints == [BoardTestPoint(position: BoardPoint(x: 50, y: 50), side: .bottom, net: "PP3V3", probe: 7)])
    }

    @Test func aBRD2CountingPinsFromOneReadsTheSame() throws {
        let fromOne = Self.brd2
            .replacingOccurrences(of: "200 200 0 1", with: "200 200 1 1")
            .replacingOccurrences(of: "340 100 4 2", with: "340 100 5 2")
            .replacingOccurrences(of: "600 100 6 3", with: "600 100 7 3")
        let board = try BoardFile.read(Data(fromOne.utf8))
        #expect(board.parts.map(\.pins.count) == [4, 2, 2])
    }

    @Test func bdvDecodersUndoTheirEncoding() {
        let text = "var_data: 0 1 1 0\r\nParts:\nU1 5 1\n"
        for byLine in [false, true] {
            let bytes = [UInt8](BDV.encode(text, byLine: byLine))
            let decoded = byLine ? BDV.decodeByLine(bytes) : BDV.decodeByByte(bytes)
            #expect(String(decoding: decoded, as: UTF8.self) == text)
        }
        // The key wraps from 285 to 159.
        let long = String(repeating: "a", count: 400)
        #expect(String(decoding: BDV.decodeByByte([UInt8](BDV.encode(long, byLine: false))), as: UTF8.self) == long)
        let lines = String(repeating: "a\n", count: 400)
        #expect(String(decoding: BDV.decodeByLine([UInt8](BDV.encode(lines, byLine: true))), as: UTF8.self) == lines)
    }

    @Test func aByteKeyedBDVReadsLikeItsBRD() throws {
        let bdv = try BoardFile.read(BDV.encode(BoardSample.text, byLine: false))
        #expect(bdv.parts.map(\.name) == board.parts.map(\.name))
        #expect(bdv.pins == board.pins)
    }

    @Test func theSampleAsBRD2ReadsLikeItsBRD() throws {
        let brd2 = try BoardFile.read(Data(BoardSample.brd2Text.utf8))
        #expect(brd2.parts.map(\.name) == board.parts.map(\.name))
        #expect(brd2.parts.map(\.side) == board.parts.map(\.side))
        #expect(brd2.parts.map(\.isThroughHole) == board.parts.map(\.isThroughHole))
        #expect(brd2.pins == board.pins)
        #expect(brd2.testPoints == board.testPoints)
    }

    @Test func aLineKeyedBDVReadsItsListing() throws {
        let listing = """
            <<format.asc>>
            0.0 0.0 0.0
            2.0 0.0 0.0
            2.0 1.0 0.0
            <<pins.asc>>
            Part U1 (T)
            1 1 0.100 0.100 1 PP1V8
            2 2 0.200 0.100 1 (NC)
            Part C9 (B)
            1 1 0.500 0.500 2 PP1V8
            2 2 0.500 0.540 2 GND
            $3 1.5 0.5 1 D2 (B) #3 GND
            """
        let data = BDV.encode(listing, byLine: true)
        #expect(data.starts(with: Array("dd:".utf8)))
        let board = try BoardFile.read(data)
        #expect(board.outline == [BoardPoint(x: 0, y: 0), BoardPoint(x: 2000, y: 0), BoardPoint(x: 2000, y: 1000)])
        #expect(board.parts.map(\.name) == ["U1", "C9"])
        #expect(board.parts.map(\.side) == [.top, .bottom])
        #expect(board.pins(onNet: "PP1V8").count == 2)
        #expect(board.pins[1].net == "" && board.pins[1].position == BoardPoint(x: 200, y: 100))
        #expect(board.testPoints.first?.side == .bottom && board.testPoints.first?.net == "GND" && board.testPoints.first?.probe == 3)
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
