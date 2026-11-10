import SwiftUI

/// A grouped form for a detail page. In a wide pane (full screen) it splits into two
/// columns, `main` beside `side`, so the page fills the space; narrower, it is one column
/// with `side` under `main`. `main` gets `true` when the columns are side by side: its
/// first section then takes a header, so both columns start level. `side` gets it too, for a
/// page whose sections sit in another order when they share one column.
struct TwoColumnForm<Main: View, Side: View>: View {
    @ViewBuilder var main: (_ wide: Bool) -> Main
    @ViewBuilder var side: (_ wide: Bool) -> Side
    @State private var wide = false

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    Form { main(true) }.formStyle(.grouped)
                    Form { side(true) }.formStyle(.grouped)
                }
            } else {
                Form {
                    main(false)
                    side(false)
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width >= twoColumnWidth } action: { wide = $0 }
    }
}

extension TwoColumnForm {
    /// A side column that is the same in one column and in two.
    init(@ViewBuilder main: @escaping (_ wide: Bool) -> Main, @ViewBuilder side: @escaping () -> Side) {
        self.init(main: main, side: { _ in side() })
    }
}

/// From this width a detail page has two columns.
private nonisolated let twoColumnWidth: CGFloat = 820
