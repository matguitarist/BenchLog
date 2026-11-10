import Foundation
import Testing
@testable import BenchLogKit

// S-064
@Suite struct BarcodeTests {
    @Test func aBarcodeIsItsDigitsWithARightCheckDigit() {
        #expect(BarcodeLookup.normalized(" 045496-590420 ") == "045496590420")
        #expect(BarcodeLookup.normalized("0045496590420") == "045496590420")
        #expect(BarcodeLookup.normalized("5030917181771") == "5030917181771")
        #expect(BarcodeLookup.normalized("045496590421") == nil)
        #expect(BarcodeLookup.normalized("12345") == nil)
        #expect(BarcodeLookup.normalized("JC-STICK") == nil)
    }

    @Test func aLookupAnswerBecomesAProduct() {
        let answer = Data(#"{"code":"OK","total":1,"items":[{"ean":"0045496590420","title":" The Legend of Zelda: Breath of the Wild - Nintendo Switch ","brand":"Nintendo","category":"Electronics > Video Game Consoles","offers":[]}]}"#.utf8)
        let product = BarcodeLookup.parse(answer, barcode: "045496590420")
        #expect(product?.title == "The Legend of Zelda: Breath of the Wild - Nintendo Switch")
        #expect(product?.brand == "Nintendo")
        #expect(product?.suggestedKind == .game)
        #expect(BarcodeLookup.parse(Data(#"{"code":"OK","total":0,"items":[]}"#.utf8), barcode: "1") == nil)
        #expect(BarcodeLookup.parse(Data("oops".utf8), barcode: "1") == nil)
        #expect(BarcodeLookup.request(for: "045496590420").url?.absoluteString == "https://api.upcitemdb.com/prod/trial/lookup?upc=045496590420")
    }

    @Test func theKindIsGuessedFromTheTitle() {
        #expect(ProductInfo(barcode: "", title: "Xbox Wireless Controller", category: "Video Game Accessories").suggestedKind == .controller)
        #expect(ProductInfo(barcode: "", title: "PS2 Component AV Cable").suggestedKind == .cable)
        #expect(ProductInfo(barcode: "", title: "Thermal paste").suggestedKind == .part)
    }

    @Test func aScannedPartIsFoundByEitherSpellingAndReceived() throws {
        let library = try Library()
        let game = try library.save(Part(name: "Zelda", kind: .game), fits: [])
        #expect(try library.part(barcode: "045496590420") == nil)
        var edited = game
        edited.barcode = "0 45496 59042 0"
        try library.save(edited, fits: [])
        #expect(try library.part(game.id)?.barcode == "045496590420")
        #expect(try library.part(barcode: "0045496590420")?.id == game.id)
        #expect(try library.parts(matching: "0454965").map(\.id) == [game.id])
        try library.receiveScanned(game.id)
        #expect(try library.part(game.id)?.quantity == 1)
        #expect(try library.stockHistory(of: game.id).first?.move.reason == .received)
    }
}
