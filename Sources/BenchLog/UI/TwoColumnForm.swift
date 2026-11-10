import SwiftUI

/// A grouped form for a detail page. In a wide pane (full screen) it splits into two
/// columns, `main` beside `side`, so the page fills the space; narrower, it is one column
/// with `side` under `main`. `main` gets `true` when the columns are side by side: its
/// first section then takes a header, so both columns start level.
struct TwoColumnForm<Main: View, Side: View>: View {
    @ViewBuilder var main: (_ wide: Bool) -> Main
    @ViewBuilder var side: () -> Side
    @State private var wide = false

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    Form { main(true) }.formStyle(.grouped)
                    Form { side() }.formStyle(.grouped)
                }
            } else {
                Form {
                    main(false)
                    side()
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width >= twoColumnWidth } action: { wide = $0 }
    }
}

/// From this width a detail page has two columns.
private nonisolated let twoColumnWidth: CGFloat = 880
