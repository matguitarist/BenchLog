import BenchLogKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkdownGuideReader: View {
    @Environment(AppModel.self) private var model
    let guide: Guide
    @State private var rendered: MarkdownHTML.Result?
    @State private var web = WebController()

    var body: some View {
        HStack(spacing: 0) {
            let contents = rendered?.headings.filter { $0.level >= 2 } ?? []
            if contents.count >= 2 {
                List(contents) { heading in
                    Button {
                        web.scroll(to: heading.anchor)
                    } label: {
                        Text(heading.text)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(heading.level - 2) * Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(heading.level == 2 ? .primary : .secondary)
                    .help("Go to “\(heading.text)”")
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                .accessibilityLabel(Text("Contents"))
                Divider()
            }
            WebHTMLView(html: rendered.map { MarkdownHTML.page(body: $0.body) } ?? "", controller: web) { target in
                model.openGuide(wikiTarget: target)
            }
        }
        .task(id: "\(guide.id) \(guide.updatedAt.timeIntervalSince1970)") {
            rendered = render()
        }
    }

    private func render() -> MarkdownHTML.Result {
        guard let library = model.library else { return MarkdownHTML.Result(body: "", headings: []) }
        let text = (try? library.guideText(guide)) ?? ""
        let images = ((try? library.attachments(for: .guide, id: guide.id)) ?? []).filter(\.isImage)
        var byName: [String: Attachment] = [:]
        for image in images { byName[image.originalName.lowercased()] = image }
        return MarkdownHTML { name in
            guard let image = byName[(name as NSString).lastPathComponent.lowercased()],
                  let data = try? Data(contentsOf: library.fileURL(for: image)) else { return nil }
            let mime = image.type?.preferredMIMEType ?? "image/png"
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }.render(text)
    }
}

@MainActor
final class WebController {
    weak var view: WKWebView?

    func scroll(to anchor: String) {
        let escaped = anchor.replacingOccurrences(of: "'", with: "\\'")
        view?.evaluateJavaScript("document.getElementById('\(escaped)')?.scrollIntoView({behavior: 'smooth', block: 'start'})")
    }
}

/// A web view for rendered guides. Links to other guides open them in BenchLog; web
/// links open in the browser; nothing else loads.
struct WebHTMLView: NSViewRepresentable {
    let html: String
    let controller: WebController
    let openGuide: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        controller.view = view
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 480, height: 480))
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.openGuide = openGuide
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(openGuide: openGuide) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var openGuide: (String) -> Void
        var html = ""

        init(openGuide: @escaping (String) -> Void) {
            self.openGuide = openGuide
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.scheme == MarkdownHTML.guideScheme {
                let target = String(url.absoluteString.dropFirst(MarkdownHTML.guideScheme.count + 1))
                openGuide(target.removingPercentEncoding ?? target)
                return .cancel
            }
            if ["http", "https", "mailto"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            // The page itself, and jumps to a heading in it.
            return action.navigationType == .other || url.fragment != nil ? .allow : .cancel
        }
    }
}
