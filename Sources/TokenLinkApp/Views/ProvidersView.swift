import SwiftUI
import TokenLinkCore
import TokenLinkProviders

struct ProvidersView: View {
    @Bindable var model: AppModel
    @State private var replacementKeys: [ProviderID: String] = [:]
    @State private var codexPath = ""
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Providers")
                        .font(.largeTitle.bold())
                    Text("Keys are written to macOS Keychain and are never read back into these fields.")
                        .foregroundStyle(.secondary)
                }

                if model.configurationRestartRequired {
                    Label(
                        "Provider or region changes apply after restarting TokenLink.",
                        systemImage: "arrow.clockwise.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                ForEach(ProviderID.allCases, id: \.self) { provider in
                    providerSection(provider)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .navigationTitle("Providers")
        .task {
            codexPath = model.configuration.codexPath ?? ""
            await model.refreshCredentialStates()
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderMark(provider: provider, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppModel.displayName(for: provider))
                        .font(.headline)
                    Text(subtitle(provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { model.configuration.enabledProviders.contains(provider) },
                    set: { enabled in
                        do { try model.setProvider(provider, enabled: enabled) }
                        catch { message = error.localizedDescription }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            if provider == .codex {
                LabeledContent("Codex executable") {
                    HStack {
                        TextField("Auto-detect from PATH", text: $codexPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            do {
                                try model.setCodexPath(codexPath)
                                message = "Codex path saved."
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .frame(maxWidth: 460)
                }
                Text("Uses the local `codex app-server`; no Codex API key is stored by TokenLink.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Credential") {
                    HStack(spacing: 8) {
                        Image(systemName: model.credentialConfigured[provider] == true
                              ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(model.credentialConfigured[provider] == true
                                             ? .green : .secondary)
                        Text(model.credentialConfigured[provider] == true
                             ? "Configured" : "Not configured")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Replace API key") {
                    HStack {
                        SecureField(
                            "Paste a new key",
                            text: Binding(
                                get: { replacementKeys[provider, default: ""] },
                                set: { replacementKeys[provider] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { saveKey(provider) }
                            .disabled(replacementKeys[provider, default: ""].isEmpty)
                        Button("Delete", role: .destructive) { deleteKey(provider) }
                    }
                    .frame(maxWidth: 460)
                }
                regionPicker(provider)
                if provider == .kimi {
                    Text("If no API key is stored, TokenLink may read the current non-expired Kimi Code CLI access token from its documented credential file. Refresh tokens are never read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }

    @ViewBuilder
    private func regionPicker(_ provider: ProviderID) -> some View {
        if provider == .minimax {
            LabeledContent("Region") {
                Picker("Region", selection: Binding(
                    get: { model.configuration.miniMaxRegion },
                    set: { region in try? model.setMiniMaxRegion(region) })) {
                    Text("Global").tag(MiniMaxRegion.global)
                    Text("China").tag(MiniMaxRegion.china)
                }
                .labelsHidden()
                .frame(width: 180)
            }
        } else if provider == .glm {
            LabeledContent("Region") {
                Picker("Region", selection: Binding(
                    get: { model.configuration.glmRegion },
                    set: { region in try? model.setGLMRegion(region) })) {
                    Text("Global (Z.AI)").tag(GLMRegion.global)
                    Text("China (BigModel)").tag(GLMRegion.china)
                }
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }

    private func saveKey(_ provider: ProviderID) {
        let value = replacementKeys[provider, default: ""]
        Task {
            do {
                try await model.saveAPIKey(value, for: provider)
                replacementKeys[provider] = ""
                message = "\(AppModel.displayName(for: provider)) key saved to Keychain."
            } catch { message = error.localizedDescription }
        }
    }

    private func deleteKey(_ provider: ProviderID) {
        Task {
            do {
                try await model.deleteAPIKey(for: provider)
                replacementKeys[provider] = ""
                message = "\(AppModel.displayName(for: provider)) key deleted."
            } catch { message = error.localizedDescription }
        }
    }

    private func subtitle(_ provider: ProviderID) -> String {
        switch provider {
        case .codex: "Local app-server"
        case .kimi: "Coding Plan usage API or Kimi Code CLI"
        case .minimax: "Token Plan remains API"
        case .glm: "Coding Plan quota monitor"
        }
    }
}
