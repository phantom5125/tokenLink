import AppKit
import SwiftUI
import TokenLinkCore

struct MenuBarView: View {
  @Bindable var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "gauge.with.dots.needle.33percent")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.tint)
          .frame(width: 38, height: 38)
          .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 2) {
          Text("TokenLink")
            .font(.headline)
          Text("StopWatch · \(model.deviceStatusText)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if model.isRefreshing {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding(16)

      Divider()

      if model.orderedProviderRows.isEmpty {
        ContentUnavailableView(
          "No providers enabled",
          systemImage: "gauge.open.with.lines.needle.33percent",
          description: Text("Enable a provider in Control Center.")
        )
        .frame(height: 170)
      } else {
        VStack(spacing: 0) {
          ForEach(model.orderedProviderRows) { row in
            ProviderQuotaRow(row: row)
              .padding(.horizontal, 16)
              .padding(.vertical, 11)
            if row.id != model.orderedProviderRows.last?.id {
              Divider().padding(.leading, 64)
            }
          }
        }
      }

      Divider()

      HStack(spacing: 8) {
        Button {
          Task { await model.refreshManually() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshing)

        Spacer()

        Button("Control Center…") {
          openWindow(id: "control-center")
          NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Menu {
          Button("Quit TokenLink") {
            NSApplication.shared.terminate(nil)
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }
      .padding(12)
    }
    .frame(width: 350)
  }
}

struct ProviderQuotaRow: View {
  let row: ProviderRow

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ProviderMark(provider: row.id, size: 36)
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(row.displayName)
            .font(.subheadline.weight(.semibold))
          Spacer()
          PhaseBadge(phase: row.state.phase)
        }
        if let snapshot = row.state.snapshot,
          let window = snapshot.mostConstrainedWindow
        {
          HStack(alignment: .firstTextBaseline) {
            Text(window.label)
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(window.remainingPercent.rounded()))% left")
              .font(.caption.weight(.semibold))
              .monospacedDigit()
          }
          ProgressView(value: window.remainingPercent, total: 100)
            .tint(ProviderPresentation.color(for: row.id))
          Text(detailText(snapshot: snapshot, window: window))
            .font(.caption2)
            .foregroundStyle(row.state.phase == .stale ? .orange : .secondary)
        } else {
          Text(row.state.error?.message ?? "Waiting for the first quota snapshot.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func detailText(snapshot: QuotaSnapshot, window: QuotaWindow) -> String {
    if row.state.phase == .stale {
      return "Stale · fetched \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
    if let resetsAt = window.resetsAt {
      return "Resets \(ProviderPresentation.relative(resetsAt))"
    }
    return "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
  }
}
