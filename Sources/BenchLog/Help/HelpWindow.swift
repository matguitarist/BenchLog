import AppKit
import BenchLogKit
import Observation
import SwiftUI

/// One page of BenchLog Help. Its text is Help/<language>/<id>.md, in the app's language.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted = "getting-started"
    case repairs, billing
    case counterSales = "counter-sales"
    case inventory
    case shopDevices = "shop-devices"
    case guides, reports, backups, sync, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .repairs: String(localized: "Repairs")
        case .billing: String(localized: "Estimates and Invoices")
        case .counterSales: String(localized: "Counter Sales")
        case .inventory: String(localized: "Parts and Inventory")
        case .shopDevices: String(localized: "Shop Devices")
        case .guides: String(localized: "Guides")
        case .reports: String(localized: "Reports")
        case .backups: String(localized: "Backups and Trash")
        case .sync: String(localized: "Sync and the Shop Server")
        case .shortcuts: String(localized: "Keyboard Shortcuts")
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "star"
        case .repairs: "wrench.and.screwdriver"
        case .billing: "doc.text"
        case .counterSales: "cart"
        case .inventory: "shippingbox"
        case .shopDevices: "laptopcomputer.and.iphone"
        case .guides: "book.pages"
        case .reports: "chart.bar.doc.horizontal"
        case .backups: "externaldrive"
        case .sync: "server.rack"
        case .shortcuts: "keyboard"
        }
    }

    /// The topic’s Markdown (Help/en or Help/fr, copied to en/ and fr/ in the bundle), in French when the app runs in French.
    var text: String {
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "fr" : "en"
        for lang in [language, "en"] {
            if let url = Bundle.module.url(forResource: rawValue, withExtension: "md", subdirectory: lang),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "# \(title)"
    }
}

/// The topic the Help window shows; the Help menu sets it before opening the window.
@MainActor
@Observable
final class HelpCenter {
    static let shared = HelpCenter()
    var topic: HelpTopic? = .gettingStarted
}

/// The Help window: topics in a sidebar, the topic beside them, and a search that narrows the topics.
struct HelpWindow: View {
    @State private var search = ""
    private var help: HelpCenter { .shared }

    private var matches: [HelpTopic] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return HelpTopic.allCases }
        return HelpTopic.allCases.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    var body: some View {
        @Bindable var help = help
        NavigationSplitView {
            List(matches, selection: $help.topic) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let topic = help.topic {
                HelpPage(topic: topic)
                    .navigationTitle(topic.title)
            } else {
                ContentUnavailableView("Choose a Topic", systemImage: "questionmark.circle")
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search Help"))
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// One topic, rendered like a Markdown guide. Links to another topic (`[[sync|…]]`) open it.
private struct HelpPage: View {
    let topic: HelpTopic
    @State private var web = WebController()

    var body: some View {
        WebHTMLView(html: MarkdownHTML.page(body: MarkdownHTML().render(topic.text).body), controller: web) { target in
            if let other = HelpTopic(rawValue: target) { HelpCenter.shared.topic = other }
        }
    }
}

/// BenchLog's own Help items, under BenchLog Help. The rest of the Help menu is the shared
/// StandardCommands (UI/AppCommands.swift).
struct HelpTopicItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Keyboard Shortcuts") { open(.shortcuts) }
        Button("Set Up the Shop Server") { open(.sync) }
        #if DEBUG
        Divider()
        Button("Load Sample Data") { SeedData.load(into: model) }
            .disabled(model.library == nil || !SeedData.isEmpty(model))
        #endif
    }

    private func open(_ topic: HelpTopic) {
        HelpCenter.shared.topic = topic
        openWindow(id: "help")
    }
}
