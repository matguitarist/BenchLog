import Foundation
import Testing
@testable import BoardViewKit

// S-081, S-082, S-083: .fz, GenCAD, and .tvw boards, checked against the sample's .brd.
@Suite struct BoardFormatsTests {
    let board: Board

    init() throws {
        board = try BoardFile.read(BoardSample.data)
    }

    @Test func theNewKindsOpenInTheViewer() {
        for name in ["board.fz", "board.CAD", "board.tvw"] { #expect(BoardFile.canRead(fileName: name)) }
    }

    // MARK: .fz

    @Test func fzTextCompressesAndComesBack() throws {
        let data = FZ.deflate("A!REFDES\r\nS!U1!!X!NO!0\r\n")
        #expect(FZ.isCompressed([UInt8](data)))
        #expect(FZ.inflate([UInt8](data)) == "A!REFDES\r\nS!U1!!X!NO!0\r\n")
    }

    @Test func theSampleAsFZReadsLikeItsBRD() throws {
        let fz = try BoardFile.read(BoardSample.fzData)
        #expect(fz.parts.map(\.name) == board.parts.map(\.name))
        #expect(fz.parts.map(\.side) == board.parts.map(\.side))
        #expect(fz.pins == board.pins)
        #expect(fz.testPoints.map(\.position) == board.testPoints.map(\.position))
        #expect(fz.testPoints.map(\.net) == board.testPoints.map(\.net))
        #expect(fz.outline.count == 4)
    }

    @Test func fzMillimetersBecomeMils() throws {
        let text = "UNIT:millimeters\nA!REFDES\nS!R1!!R!NO!0\nA!NET_NAME\nS!VCC!R1!1!1!2.54!0!!0.1\nS!GND!R1!2!2!5.08!0!!0.1\n"
        let fz = try BoardFile.read(FZ.deflate(text))
        #expect(fz.pins.map(\.position.x).map { $0.rounded() } == [100, 200])
        #expect(fz.pins.map(\.net) == ["VCC", "GND"])
    }

    @Test func aScrambledFZNeedsItsKey() throws {
        let key: [UInt32] = (0..<44).map { UInt32($0) &* 2_654_435_761 }
        // Each byte's mask comes from the 16 scrambled bytes before it, so build the cipher byte by byte.
        let plain = [UInt8](FZ.deflate("A!REFDES\nS!U1!!X!NO!0\nA!NET_NAME\nS!VCC!U1!1!1!0!0!!1\n"))
        var cipher: [UInt8] = []
        for b in plain {
            let next = FZ.unscramble(cipher + [0], key: key).last! ^ b
            cipher.append(next)
        }
        #expect(FZ.unscramble(cipher, key: key) == plain)
        #expect(throws: BoardFileError.needsFZKey) { try BoardFile.read(Data(cipher), fileName: "board.fz") }
        let text = key.map(String.init).joined(separator: " ")
        #expect(FZ.parseKey(text) == key)
        let hex = key.flatMap { w in (0..<4).map { String(format: "%02x", (w >> ($0 * 8)) & 0xFF) } }.joined()
        #expect(FZ.parseKey(hex) == key)
        #expect(FZ.parseKey("1 2 3") == nil)
    }

    // MARK: GenCAD

    @Test func theSampleAsGenCADReadsLikeItsBRD() throws {
        let cad = try BoardFile.read(Data(BoardSample.gencadText.utf8))
        #expect(cad.parts.map(\.name) == board.parts.map(\.name))
        #expect(cad.parts.map(\.side) == board.parts.map(\.side))
        #expect(cad.parts.map(\.isThroughHole) == board.parts.map(\.isThroughHole))
        #expect(cad.pins == board.pins)
        #expect(cad.outline == board.outline)
        let u1 = try #require(cad.part(named: "U1"))
        #expect(cad.parts[u1].outline.count == 5)
        #expect(cad.parts[u1].bounds == board.parts[u1].bounds)
    }

    static let turned = """
        $HEADER
        GENCAD 1.4
        UNITS MM
        $ENDHEADER
        $BOARD
        RECTANGLE 0 0 25.4 12.7
        $ENDBOARD
        $SHAPES
        SHAPE "SOT"
        LINE -1 -1 1 -1
        LINE 1 -1 1 1
        ARC 1 1 -1 1 0 1
        LINE -1 1 -1 -1
        PIN 1 PAD 0.254 0 TOP 0 0
        PIN 2 PAD 0.508 0 TOP 0 0
        $ENDSHAPES
        $COMPONENTS
        COMPONENT Q1
        PLACE 2.54 2.54
        LAYER BOTTOM
        ROTATION 90
        SHAPE "SOT" MIRRORY 0
        COMPONENT Q1
        PLACE 2.54 2.54
        LAYER BOTTOM
        SHAPE "SOT"
        $ENDCOMPONENTS
        $SIGNALS
        SIGNAL "VBUS IN"
        NODE Q1 1
        $ENDSIGNALS
        """

    @Test func genCADPlacesMirrorsAndTurnsAShape() throws {
        let cad = try BoardFile.read(Data(Self.turned.utf8))
        #expect(cad.parts.map(\.name) == ["Q1"], "a second copy at the same place is skipped")
        #expect(cad.parts[0].side == .bottom)
        // Mirrored about y, then turned 90°: (10, 0) mils from the place becomes (0, -10).
        let points = cad.pins.map { BoardPoint(x: $0.position.x.rounded(), y: $0.position.y.rounded()) }
        #expect(points == [BoardPoint(x: 100, y: 90), BoardPoint(x: 100, y: 80)])
        #expect(cad.pins.map(\.net) == ["VBUS IN", ""])
        #expect(cad.outline.count == 5)
        #expect(cad.parts[0].outline.count > 5, "lines and an arc join into one body")
    }

    // MARK: .tvw

    @Test func theSampleAsTVWReadsLikeItsBRD() throws {
        let tvw = try BoardFile.read(BoardSample.tvwData)
        #expect(tvw.parts.map(\.name) == board.parts.map(\.name))
        #expect(tvw.parts.map(\.side) == board.parts.map(\.side))
        #expect(tvw.pins.map(\.position) == board.pins.map(\.position))
        #expect(tvw.pins.map(\.net) == board.pins.map(\.net))
        #expect(tvw.parts.allSatisfy { $0.outline.count == 4 })
    }

    @Test func aTextTVWIsARotatedBRD() throws {
        let data = TVW.rotate(BoardSample.text)
        #expect(TVW.unrotate([UInt8](data)) == Array(BoardSample.text.utf8))
        let tvw = try BoardFile.read(data)
        #expect(tvw.pins == board.pins)
    }
}
