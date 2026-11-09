import AppKit
import BenchLogKit
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
        web.frame = NSRect(x: 0, y: 0, width: PageLayout.letter.width, height: max(height, 1))
        let blocks = (try? await web.evaluateJavaScript(Self.blocksScript) as? [[Double]]) ?? []
        let configuration = WKPDFConfiguration()
        configuration.rect = web.bounds
        let tall = try await web.pdf(configuration: configuration)
        let spans = blocks.compactMap { $0.count == 2 ? PageLayout.Block(top: $0[0], bottom: $0[1]) : nil }
        guard let paged = PageLayout.paginate(tall, blocks: spans) else { throw Failure.notPrinted }
        return paged
    }

    /// The top and bottom of every element that must not be cut: lines of text, table rows,
    /// the stamp, the signature. CSS pixels are points here, since the view is 612 wide.
    private static let blocksScript = """
        Array.from(document.querySelectorAll('p, tr, li, h1, h2, h3, pre, img, .stamp, .signature, footer > div, .parties > div > div, .business > div'))
            .map(e => { const r = e.getBoundingClientRect(); return [r.top + window.scrollY, r.bottom + window.scrollY]; })
        """

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
