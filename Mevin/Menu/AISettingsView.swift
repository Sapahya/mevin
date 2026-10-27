import SwiftUI

/// Menu → AI settings. Keys go to the Keychain, never to
/// `profiles.json`.
struct AISettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            MevinScreenHeader(title: "AI settings") { model.showList() }

            MevinSecondaryText(
                "Add your own API key to turn on the AI features. Keys are stored in your Mac's Keychain and only sent to the provider you chose.",
                style: .caption
            )

            ForEach(AIProvider.allCases) { provider in
                ProviderKeyRow(provider: provider)
            }

            MevinSecondaryText("Reading a screenshot costs a fraction of a cent, billed to your own key.", style: .caption)
        }
    }
}

private struct ProviderKeyRow: View {
    @EnvironmentObject private var model: AppModel
    let provider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.sectionTitleGap) {
            SectionTitle(provider.displayName)

            if let masked = model.maskedKey(for: provider) {
                Text(masked)
                    .font(SessionCardStyles.FontStyle.caption.font.monospaced())
                    .foregroundStyle(SessionCardStyles.textPrimary.opacity(SessionCardStyles.secondaryOpacity))
            }

            SecureField(model.hasSavedKey(provider) ? "Replace key" : "API key", text: draftBinding)
                .mevinField()

            HStack(spacing: SessionCardStyles.headerButtonGap) {
                Button("Save") {
                    Task { await model.saveAPIKey(provider) }
                }
                .buttonStyle(MevinChipButtonStyle())
                .disabled(!model.canSaveKey(provider))

                if model.hasSavedKey(provider) {
                    Button("Remove") {
                        model.removeAPIKey(provider)
                    }
                    .buttonStyle(MevinChipButtonStyle())
                }

                if model.validatingProvider == provider {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            MevinSecondaryText(model.keyStatus(for: provider).line, style: .caption)

            if provider == .deepseek {
                MevinSecondaryText("DeepSeek can't read images. Screenshot reading needs an OpenAI key.", style: .caption)
            }
        }
        .mevinRow()
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.keyDraft(for: provider) },
            set: { model.setKeyDraft($0, for: provider) }
        )
    }
}
