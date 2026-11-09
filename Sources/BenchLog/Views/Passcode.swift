import SwiftUI

/// A device's passcode, shown as dots until people click the eye. It hides again
/// when the page goes away or after 30 seconds. It never prints on documents.
struct PasscodeView: View {
    let passcode: String
    let isPattern: Bool
    @State private var shown = false

    var body: some View {
        LabeledContent("Passcode") {
            HStack(spacing: Space.sm) {
                if passcode.isEmpty {
                    Text("No passcode").foregroundStyle(.secondary)
                } else {
                    Group {
                        if shown {
                            Text(isPattern ? String(localized: "Pattern \(passcode)") : passcode)
                                .textSelection(.enabled)
                        } else {
                            Text(verbatim: String(repeating: "•", count: 6))
                        }
                    }
                    .monospaced()
                    .accessibilityLabel(shown ? Text(passcode) : Text("Passcode, hidden"))
                    Button(shown ? "Hide Passcode" : "Show Passcode", systemImage: shown ? "eye.slash" : "eye") {
                        shown.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .help(shown ? String(localized: "Hide the passcode (⌥⌘P)") : String(localized: "Show the passcode (⌥⌘P)"))
                }
            }
        }
        .onDisappear { shown = false }
        .task(id: shown) {
            guard shown else { return }
            try? await Task.sleep(for: .seconds(30))
            shown = false
        }
    }
}

/// Entering a passcode: a code typed in a secure field, or an Android pattern
/// drawn by clicking the dots in order (saved as "1-5-9-6").
struct PasscodeField: View {
    @Binding var passcode: String
    @Binding var isPattern: Bool
    @State private var shown = false

    var body: some View {
        Toggle("Pattern", isOn: $isPattern)
            .onChange(of: isPattern) { passcode = "" }
        if isPattern {
            LabeledContent("Pattern") {
                PatternPad(pattern: $passcode)
            }
        } else {
            LabeledContent("Passcode") {
                HStack(spacing: Space.sm) {
                    Group {
                        if shown {
                            TextField("Passcode", text: $passcode, prompt: Text("No passcode"))
                        } else {
                            SecureField("Passcode", text: $passcode, prompt: Text("No passcode"))
                        }
                    }
                    .labelsHidden()
                    Button(shown ? "Hide Passcode" : "Show Passcode", systemImage: shown ? "eye.slash" : "eye") {
                        shown.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(shown ? String(localized: "Hide the passcode") : String(localized: "Show the passcode"))
                }
            }
        }
    }
}

/// A 3×3 grid of dots. Clicking a dot adds it to the pattern; each chosen dot shows its order.
struct PatternPad: View {
    @Binding var pattern: String

    private var dots: [Int] { pattern.split(separator: "-").compactMap { Int($0) } }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.md) {
            Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(1...3, id: \.self) { column in
                            dot(row * 3 + column)
                        }
                    }
                }
            }
            Button("Clear") { pattern = "" }
                .disabled(pattern.isEmpty)
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pattern"))
        .accessibilityValue(pattern.isEmpty ? Text("Empty") : Text(pattern))
    }

    private func dot(_ number: Int) -> some View {
        let order = dots.firstIndex(of: number).map { $0 + 1 }
        return Button {
            guard order == nil else { return }
            pattern = (dots + [number]).map(String.init).joined(separator: "-")
        } label: {
            ZStack {
                Circle()
                    .fill(order == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint))
                if let order {
                    Text(verbatim: "\(order)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Dot \(number)"))
    }
}
