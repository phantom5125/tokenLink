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
          model.text(.menubarNoProviders),
          systemImage: "gauge.open.with.lines.needle.33percent",
          description: Text(model.text(.menubarEnableHint))
        )
        .frame(height: 170)
      } else {
        VStack(spacing: 0) {
          ForEach(model.orderedProviderRows) { row in
            ProviderQuotaRow(
              row: row,
              language: model.currentLanguage,
              estimate: model.burnEstimate(for: row.id)
            )
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
          Label(model.text(.actionRefresh), systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshing)

        Spacer()

        Button(model.text(.actionControlCenter)) {
          openWindow(id: "control-center")
          NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Menu {
          Button(model.text(.actionQuit)) {
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
    .environment(\.appLanguage, model.currentLanguage)
  }
}

struct ProviderQuotaRow: View {
  let row: ProviderRow
  let language: AppLanguage
  var estimate: BurnRateEstimate?

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
            Text(
              "\(Int(window.remainingPercent.rounded()))% \(L10n.text(.quotaLeft, language: language))"
            )
            .font(.caption.weight(.semibold))
            .monospacedDigit()
          }
          ProgressView(value: window.remainingPercent, total: 100)
            .tint(ProviderPresentation.color(for: row.id))
          Text(detailText(snapshot: snapshot, window: window))
            .font(.caption2)
            .foregroundStyle(row.state.phase == .stale ? .orange : .secondary)
          if let estimate, estimate.windowID == window.id, row.state.phase == .healthy {
            Text(burnText(estimate))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(row.state.error?.message ?? L10n.text(.quotaWaitingFirst, language: language))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func burnText(_ estimate: BurnRateEstimate) -> String {
    String(
      format: L10n.text(.quotaBurnEta, language: language),
      ProviderPresentation.relative(estimate.depletesAt))
  }

  private func detailText(snapshot: QuotaSnapshot, window: QuotaWindow) -> String {
    if row.state.phase == .error {
      return String(
        format: L10n.text(.quotaExpiredCacheFetched, language: language),
        snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
    }
    if row.state.phase == .stale {
      return String(
        format: L10n.text(.quotaStaleFetched, language: language),
        snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
    }
    if let resetsAt = window.resetsAt {
      return String(
        format: L10n.text(.quotaResetsAt, language: language),
        ProviderPresentation.relative(resetsAt))
    }
    return String(
      format: L10n.text(.quotaUpdatedAt, language: language),
      snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
  }
}
