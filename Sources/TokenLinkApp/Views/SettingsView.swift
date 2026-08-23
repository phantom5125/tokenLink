import SwiftUI

struct SettingsView: View {
    let model: AppModel
    private let loginItem: any LoginItemControlling = LoginItemController()

    var body: some View {
        Form {
            Picker("Refresh interval", selection: Binding(
                get: { model.configuration.refreshMinutes },
                set: { model.configuration.refreshMinutes = $0 }
            )) {
                ForEach(RefreshScheduler.allowedMinutes, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            LabeledContent("Launch at login") {
                switch loginItem.status {
                case .enabled: Text("Enabled")
                case .requiresApproval: Text("Requires approval in System Settings")
                case .notRegistered: Text("Off")
                }
            }

            Section("Diagnostics") {
                Button("Export redacted diagnostics…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "tokenlink-diagnostics.json"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let payload: [String: Any] = [
                        "configuration": [
                            "refreshMinutes": model.configuration.refreshMinutes,
                            "enabledProviders": model.configuration.enabledProviders.map(\.rawValue),
                        ],
                        "events": model.events,
                    ]
                    try? DiagnosticExporter().export(payload, to: url)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
