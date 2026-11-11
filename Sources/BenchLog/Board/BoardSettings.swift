import SwiftUI

/// Settings > Board: the Claude API key for Explain This Part.
struct BoardSettings: View {
    @State private var key = ""
    @State private var hasKey = PartExplainer.apiKey != nil

    var body: some View {
        Section {
            if hasKey {
                LabeledContent("Claude API key") {
                    HStack(spacing: Space.sm) {
                        Text("Saved in the Keychain").foregroundStyle(.secondary)
                        Button("Remove") {
                            PartExplainer.saveKey(nil)
                            hasKey = false
                        }
                    }
                }
            } else {
                SecureField("Claude API key", text: $key, prompt: Text("sk-ant-…"))
                    .onSubmit(save)
                LabeledContent {
                    Button("Save Key", action: save)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                } label: {
                    Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
            }
        } header: {
            Text("Explain This Part")
        } footer: {
            Text("""
                In Part Info, Explain This Part asks Claude what a part does. Only that part's schematic page, \
                its value, and its pin nets are sent to Anthropic, never a customer or a repair. Each answer is \
                kept with the schematic and costs a few cents on your Anthropic account.
                """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        PartExplainer.saveKey(key)
        key = ""
        hasKey = PartExplainer.apiKey != nil
    }
}
