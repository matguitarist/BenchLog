import AppKit
import WebKit

/// Prints a document's HTML to a Letter PDF, paginated, without showing anything: an
/// offscreen web view captures the page as one tall PDF page, cut into Letter pages.
/// (NSPrintOperation never finishes for an offscreen window, so it is not used.)
@MainActor
final class DocumentPrinter: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError {
        case notLoaded, notPrinted

        var errorDescription: String? {
            switch self {
            case .notLoaded: String(localized: "Unable to lay out the document.")
            case .notPrinted: String(localized: "Unable to print the document to PDF.")
            }
        }
    }

    private let window: NSWindow
    private let web: WKWebView
    private var loaded: CheckedContinuation<Void, Error>?
    /// The printer keeps itself alive until its job ends.
    private static var running: Set<DocumentPrinter> = []

    private override init() {
        let page = NSRect(x: 0, y: 0, width: 612, height: 792)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: page, configuration: configuration)
        window = NSWindow(contentRect: page, styleMask: [.borderless], backing: .buffered, defer: true)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = web
        web.navigationDelegate = self
    }

    /// The PDF's bytes.
    static func pdf(html: String) async throws -> Data {
        let printer = DocumentPrinter()
        running.insert(printer)
        defer { running.remove(printer) }
        return try await printer.render(html)
    }

    private func render(_ html: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
        // Lay the page out at its full height, capture it as one tall PDF page, then cut it into Letter pages
        // between elements, never through a line of text.
        let height = (try? await web.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().bottom + window.scrollY)") as? Double) ?? 792
        web.frame = NSRect(x: 0, y: 0, width: Self.page.width, height: max(height, 1))
        let blocks = (try? await web.evaluateJavaScript(Self.blocksScript) as? [[Double]]) ?? []
        let configuration = WKPDFConfiguration()
        configuration.rect = web.bounds
        let tall = try await web.pdf(configuration: configuration)
        let spans = blocks.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }.map { (top: CGFloat($0.0), bottom: CGFloat($0.1)) }
        guard let paged = Self.paginate(tall, blocks: spans) else { throw Failure.notPrinted }
        return paged
    }

    /// The top and bottom of every element that must not be cut: lines of text, table rows,
    /// the stamp, the signature. CSS pixels are points here, since the view is 612 wide.
    private static let blocksScript = """
        Array.from(document.querySelectorAll('p, tr, li, h1, h2, h3, pre, img, .stamp, .signature, footer > div, .parties > div > div, .business > div'))
            .map(e => { const r = e.getBoundingClientRect(); return [r.top + window.scrollY, r.bottom + window.scrollY]; })
        """

    /// Where each page's slice ends, from the top of the tall page: as far down as fits, moved
    /// up to the nearest gap between blocks when a block would be cut, unless that wastes over
    /// half the page.
    static func breaks(height: CGFloat, usable: CGFloat, blocks: [(top: CGFloat, bottom: CGFloat)]) -> [CGFloat] {
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

    static let page = CGSize(width: 612, height: 792)
    /// Top and bottom margins; the sides are in the page's CSS.
    static let margin: CGFloat = 36

    /// Cuts one tall page into Letter pages, each with a top and bottom margin. Vector, not pixels.
    static func paginate(_ data: Data, blocks: [(top: CGFloat, bottom: CGFloat)] = []) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let source = CGPDFDocument(provider),
              let tall = source.page(at: 1) else { return nil }
        let box = tall.getBoxRect(.mediaBox)
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: Failure.notLoaded)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: Failure.notLoaded)
        loaded = nil
    }
}
