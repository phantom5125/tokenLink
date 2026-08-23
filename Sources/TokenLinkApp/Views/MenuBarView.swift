import SwiftUI
import TokenLinkCore

struct MenuBarView: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("StopWatch")
          .font(.headline)
        Spacer()
        Text(deviceLabel)
          .font(.caption)
          .foregroundStyle(deviceColor)
      }

      ForEach(model.rows) { row in
        ProviderQuotaRow(row: row)
      }

      Divider()

      HStack {
        Button("Refresh") {
          Task { await model.refreshManually() }
        }
        Spacer()
        Button("Control Center…") {
          openWindow(id: "control-center")
        }
      }
    }
    .padding()
    .frame(width: 300)
  }

  private var deviceLabel: String {
    switch model.devicePhase {
    case .unbound: return "Unbound"
    case .disconnected: return "Disconnected"
    case .scanning: return "Scanning…"
    case .connecting: return "Connecting…"
    case .connected: return "Connected"
    case .syncing: return "Syncing…"
    case .synced(let date): return "Synced \(date.formatted(date: .omitted, time: .shortened))"
    case .stale: return "Stale"
    }
  }

  private var deviceColor: Color {
    switch model.devicePhase {
    case .connected, .syncing, .synced: return .green
    case .scanning, .connecting: return .orange
    default: return .secondary
    }
  }
}

struct ProviderQuotaRow: View {
  let row: AppModel.ProviderRow

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Circle()
          .fill(indicatorColor)
          .frame(width: 8, height: 8)
        Text(row.provider.rawValue.capitalized)
        Spacer()
        if let window = row.snapshot?.mostConstrainedWindow {
          Text("\(Int(window.remainingPercent))%")
            .monospacedDigit()
        } else {
          Text(row.phase.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if let window = row.snapshot?.mostConstrainedWindow {
        ProgressView(value: window.remainingPercent, total: 100)
        HStack {
          Text(window.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
          Spacer()
          if let resetsAt = window.resetsAt {
            Text("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        // 陈旧行展示原始抓取时间，绝不假装是最新数据
        if row.phase == .stale, let snapshot = row.snapshot {
          Text(
            "Stale · fetched \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
          )
          .font(.caption2)
          .foregroundStyle(.orange)
        }
      }
    }
  }

  private var indicatorColor: Color {
    switch row.phase {
    case .healthy: return .green
    case .stale: return .orange
    case .refreshing: return .blue
    default: return .gray
    }
  }
}
