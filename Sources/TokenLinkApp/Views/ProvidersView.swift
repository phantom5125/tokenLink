import SwiftUI
import TokenLinkCore

struct ProvidersView: View {
  let model: AppModel

  var body: some View {
    List {
      ForEach(model.rows) { row in
        ProviderSettingsRow(model: model, row: row)
      }
    }
  }
}

private struct ProviderSettingsRow: View {
  let model: AppModel
  let row: AppModel.ProviderRow
  @State private var draftKey = ""
  @State private var saved = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(row.provider.rawValue.capitalized).font(.headline)
        Spacer()
        // 只展示“已配置/未配置”，绝不从 Keychain 回填明文
        Text(statusLabel)
          .font(.caption)
          .foregroundStyle(statusColor)
      }
      HStack {
        SecureField("Paste new API key", text: $draftKey)
          .textFieldStyle(.roundedBorder)
        Button("Save") {
          let key = draftKey
          guard !key.isEmpty else { return }
          Task {
            try? await model.saveAPIKey(key, for: row.provider)
            draftKey = ""
            saved = true
          }
        }
        .disabled(draftKey.isEmpty)
        Button("Delete") {
          Task {
            try? await model.deleteAPIKey(for: row.provider)
            saved = false
          }
        }
      }
      if saved {
        Text("Key saved to Keychain.")
          .font(.caption)
          .foregroundStyle(.green)
      }
    }
    .padding(.vertical, 4)
  }

  private var statusLabel: String {
    switch row.phase {
    case .missingCredential: return "Not configured"
    case .healthy, .stale, .refreshing: return "Configured"
    default: return "Unknown"
    }
  }

  private var statusColor: Color {
    statusLabel == "Configured" ? .green : .secondary
  }
}
