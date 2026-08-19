import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings & Diagnostics")
                        .font(.largeTitle.bold())
                    Text("Tune refresh behavior and export a redacted support snapshot.")
                        .foregroundStyle(.secondary)
                }
                generalCard
                privacyCard
                diagnosticsCard
                eventCard
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
        .navigationTitle("Settings & Diagnostics")
    }

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)
            LabeledContent("Refresh interval") {
                Picker("Refresh interval", selection: Binding(
                    get: { model.configuration.refreshMinutes },
                    set: { minutes in
                        do { try model.setRefreshMinutes(minutes) }
                        catch { message = error.localizedDescription }
                    })) {
                    ForEach([1, 2, 5, 15, 30], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            LabeledContent("Launch at login") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginItemState == .enabled },
                    set: { enabled in
                        do { try model.setLoginItemEnabled(enabled) }
                        catch { message = error.localizedDescription }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if model.loginItemState == .requiresApproval {
                Label("Approval is required in System Settings → General → Login Items.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .settingsCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy boundary", systemImage: "lock.shield")
                .font(.headline)
            Text("API keys live in macOS Keychain. TokenLink may reuse the current Kimi Code CLI access token from its documented file, but never reads browser cookies, refresh tokens, or unrelated credential stores. Full Disk Access is not required.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsCard()
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.headline)
            Text("Exports provider phases, percentages, timestamps, device state, and recent events. Paths, usernames, account labels, UUIDs, and secret-like fields are redacted before writing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                exportDiagnostics()
            } label: {
                Label("Export redacted diagnostics…", systemImage: "square.and.arrow.up")
            }
        }
        .settingsCard()
    }

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent events")
                .font(.headline)
            if model.events.isEmpty {
                Text("No events recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.events.prefix(8)) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.date.formatted(date: .omitted, time: .standard))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(event.message)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .settingsCard()
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export TokenLink Diagnostics"
        panel.nameFieldStringValue = "tokenlink-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportDiagnostics(to: url)
            message = "Diagnostics exported to \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
    }
}
