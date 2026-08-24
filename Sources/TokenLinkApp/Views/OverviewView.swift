import SwiftUI
import TokenLinkCore

struct OverviewView: View {
  @Bindable var model: AppModel
  private let columns = [
    GridItem(.adaptive(minimum: 260), spacing: 16)
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        pageHeader
        if let highlight = model.highlight {
          highlightCard(highlight)
        }
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(model.orderedProviderRows) { row in
            ProviderOverviewCard(
              row: row,
              language: model.currentLanguage,
              estimate: model.burnEstimate(for: row.id))
          }
        }
        watchCard
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .navigationTitle(model.text(.routeOverview))
  }

  private var pageHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text(model.text(.overviewTitle))
          .font(.largeTitle.bold())
        Text(model.text(.overviewSubtitle))
          .foregroundStyle(.secondary)
      }
      Spacer()
      if model.isRefreshing {
        ProgressView(model.text(.phaseRefreshing))
          .controlSize(.small)
      }
    }
  }

  private func highlightCard(_ highlight: ProviderHighlight) -> some View {
    HStack(spacing: 18) {
      ProviderMark(provider: highlight.provider, size: 54)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.text(.overviewMostConstrained))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
        Text("\(AppModel.displayName(for: highlight.provider)) · \(highlight.window.label)")
          .font(.title2.weight(.semibold))
        Text(model.text(.overviewMostConstrainedHint))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(Int(highlight.window.remainingPercent.rounded()))%")
        .font(.system(size: 42, weight: .bold, design: .rounded))
        .monospacedDigit()
      Text(model.text(.quotaLeft))
        .foregroundStyle(.secondary)
    }
    .padding(22)
    .background(
      LinearGradient(
        colors: [
          ProviderPresentation.color(for: highlight.provider).opacity(0.18),
          Color(nsColor: .windowBackgroundColor),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(ProviderPresentation.color(for: highlight.provider).opacity(0.22))
    }
  }

  private var watchCard: some View {
    HStack(spacing: 16) {
      Image(systemName: "stopwatch.fill")
        .font(.title2)
        .foregroundStyle(.white)
        .frame(width: 46, height: 46)
        .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text("M5Stack StopWatch")
          .font(.headline)
        Text(model.text(.overviewWatchSubtitle))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(model.deviceStatusText)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.1), in: Capsule())
    }
    .padding(18)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct ProviderOverviewCard: View {
  let row: ProviderRow
  let language: AppLanguage
  var estimate: BurnRateEstimate?

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        ProviderMark(provider: row.id, size: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(row.displayName)
            .font(.headline)
          PhaseBadge(phase: row.state.phase)
        }
        Spacer()
      }
      if let snapshot = row.state.snapshot,
        let window = snapshot.mostConstrainedWindow
      {
        HStack(alignment: .lastTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text(window.label)
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(Int(window.remainingPercent.rounded()))%")
              .font(.system(size: 32, weight: .bold, design: .rounded))
              .monospacedDigit()
          }
          Spacer()
          Text(L10n.text(.quotaRemaining, language: language))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ProgressView(value: window.remainingPercent, total: 100)
          .tint(ProviderPresentation.color(for: row.id))
        Text(detail(snapshot: snapshot, window: window))
          .font(.caption)
          .foregroundStyle(row.state.phase == .error ? .red : .secondary)
      } else {
        Spacer(minLength: 8)
        Text(row.state.error?.message ?? L10n.text(.quotaNoSnapshot, language: language))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private func detail(snapshot: QuotaSnapshot, window: QuotaWindow) -> String {
    let base: String
    if row.state.phase == .error {
      base = String(
        format: L10n.text(.quotaExpiredCacheFrom, language: language),
        snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
    } else if row.state.phase == .stale {
      base = String(
        format: L10n.text(.quotaStaleFetched, language: language),
        snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
    } else {
      base =
        window.resetsAt.map {
          String(
            format: L10n.text(.quotaResetsAt, language: language),
            ProviderPresentation.relative($0))
        } ?? L10n.text(.quotaResetUnavailable, language: language)
    }
    guard let estimate, estimate.windowID == window.id, row.state.phase == .healthy
    else { return base }
    let burn = String(
      format: L10n.text(.quotaBurnEta, language: language),
      ProviderPresentation.relative(estimate.depletesAt))
    return "\(base) · \(burn)"
  }
}
