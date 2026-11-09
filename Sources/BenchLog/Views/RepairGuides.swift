import BenchLogKit
import SwiftUI

/// The guides that cover a repair's device, most specific first. A click opens one on the
/// Guides page; the button beside it opens it in its own window.
struct RepairGuides: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let device: Device
    @State private var matches: [GuideMatch] = []

    var body: some View {
        Group {
            if matches.isEmpty {
                Text("No guides cover this device yet.").foregroundStyle(.secondary)
            }
            ForEach(matches) { match in
                HStack(spacing: Space.sm) {
                    Button {
                        model.open(.guide(match.guide.id))
                    } label: {
                        Label(match.guide.title, systemImage: match.guide.format == .pdf ? "doc.text" : "doc.richtext")
                            .lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .help("Open “\(match.guide.title)” on the Guides page")
                    Spacer()
                    Text(scope(match.link)).foregroundStyle(.secondary).lineLimit(1)
                    Button("Open in Window", systemImage: "macwindow") { openWindow(id: "guide", value: match.guide.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open this guide in its own window, beside the repair")
                }
            }
        }
        .task(id: "\(model.dataVersion) \(device.id)") {
            matches = model.read([]) { try $0.guides(for: device) }
        }
    }

    /// How closely the guide fits: "This revision", "This model", "Nintendo", "Consoles".
    private func scope(_ link: GuideLink) -> String {
        switch link.specificity {
        case 3: String(localized: "This revision")
        case 2: String(localized: "This model")
        case 1: link.brand
        default: link.category.pluralTitle
        }
    }
}
