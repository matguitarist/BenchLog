import CoreGraphics
import Foundation
import Testing
@testable import BenchLogKit

struct PageLayoutTests {
    @Test func aShortDocumentIsOnePage() {
        #expect(PageLayout.breaks(height: 500, usable: 720, blocks: []) == [500])
    }

    @Test func aLineAcrossTheBreakMovesToTheNextPage() {
        let cuts = PageLayout.breaks(height: 1000, usable: 720, blocks: [.init(top: 700, bottom: 740)])
        #expect(cuts == [700, 1000])
    }

    @Test func aBlockTallerThanHalfAPageIsCut() {
        // Moving the break to 100 would leave most of page 1 empty, so the block is cut.
        let cuts = PageLayout.breaks(height: 1000, usable: 720, blocks: [.init(top: 100, bottom: 800)])
        #expect(cuts == [720, 1000])
    }

    @Test func aLongDocumentGetsAPagePerSlice() {
        let cuts = PageLayout.breaks(height: 2000, usable: 720, blocks: [])
        #expect(cuts == [720, 1440, 2000])
    }

    @Test func paginateMakesLetterPages() throws {
        // A tall blank PDF, 612 × 1600.
        let tall = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 1600)
        let consumer = try #require(CGDataConsumer(data: tall as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.endPDFPage()
        context.closePDF()

        let paged = try #require(PageLayout.paginate(tall as Data))
        let provider = try #require(CGDataProvider(data: paged as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 3)  // 1600 / 720 usable
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == PageLayout.letter)
    }
}
