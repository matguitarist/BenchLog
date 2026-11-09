import CoreGraphics
import Foundation

/// Cuts one tall PDF page (a whole document laid out at Letter width) into Letter pages,
/// breaking between blocks so no line of text is split. Plain Core Graphics, for the iOS
/// app too; the app measures the blocks and makes the tall page.
public enum PageLayout {
    public static let letter = CGSize(width: 612, height: 792)
    /// Top and bottom margins; the sides are in the page's CSS.
    public static let margin: CGFloat = 36

    /// Something that must not be cut, measured from the top of the tall page, in points.
    public struct Block: Equatable, Sendable {
        public var top: CGFloat
        public var bottom: CGFloat
        public init(top: CGFloat, bottom: CGFloat) {
            self.top = top
            self.bottom = bottom
        }
    }

    /// Where each page's slice ends, from the top of the tall page: as far down as fits, moved
    /// up to the top of a block that would be cut, unless that wastes over half the page.
    public static func breaks(height: CGFloat, usable: CGFloat, blocks: [Block]) -> [CGFloat] {
        var cuts: [CGFloat] = []
        var start: CGFloat = 0
        while height - start > usable + 0.5 {
            var cut = start + usable
            while let block = blocks.first(where: { $0.top < cut - 0.5 && $0.bottom > cut + 0.5 && $0.top > start + 0.5 }),
                  block.top - start >= usable / 2 {
                cut = block.top
            }
            cuts.append(cut)
            start = cut
        }
        cuts.append(height)
        return cuts
    }

    /// Letter pages from one tall page, each with a top and bottom margin. Vector, not pixels.
    public static func paginate(_ data: Data, blocks: [Block] = []) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let source = CGPDFDocument(provider),
              let tall = source.page(at: 1) else { return nil }
        let box = tall.getBoxRect(.mediaBox)
        let page = letter
        let usable = page.height - 2 * margin
        let output = NSMutableData()
        var media = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        var start: CGFloat = 0
        for cut in breaks(height: box.height, usable: usable, blocks: blocks) {
            context.beginPDFPage(nil)
            context.saveGState()
            // Show only this slice, from `start` to `cut` measured from the top, below the top margin.
            context.clip(to: CGRect(x: 0, y: page.height - margin - (cut - start), width: page.width, height: cut - start))
            // PDF space grows upward: the slice's top lands at the top margin.
            context.translateBy(x: 0, y: page.height - margin - (box.height - start))
            context.drawPDFPage(tall)
            context.restoreGState()
            context.endPDFPage()
            start = cut
        }
        context.closePDF()
        return output as Data
    }
}
