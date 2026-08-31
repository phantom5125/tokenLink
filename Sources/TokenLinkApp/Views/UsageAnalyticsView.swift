import Charts
import SwiftUI

struct UsageAnalyticsView: View {
  @Bindable var model: AppModel
  @Bindable var analytics: UsageAnalyticsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      rangeControls

      if analytics.errorMessage != nil {
        Label(
          localized(
            "Local analytics history could not be refreshed.",
            "无法刷新本地分析历史。",
            "ローカル分析履歴を更新できませんでした。"),
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }

      if analytics.isRefreshing, analytics.dataset == nil {
        ProgressView(localized("Building local history…", "正在构建本地历史…", "ローカル履歴を作成中…"))
          .frame(maxWidth: .infinity, minHeight: 220)
      } else if analytics.snapshot.current.totalTokens == 0 {
        emptyState
      } else {
        switch analytics.selectedSection {
        case .overview:
          overview
        case .trends:
          trends
        case .attribution:
          attribution
        case .costs:
          EmptyView()
        }
      }
    }
  }

  private var rangeControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        ForEach(UsageAnalyticsRangePreset.allCases) { preset in
          Button(presetText(preset)) {
            analytics.selectPreset(preset)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(analytics.selectedPreset == preset ? .accentColor : .secondary)
        }
        Spacer()
        metricPicker
      }

      if analytics.selectedPreset == .custom {
        HStack(spacing: 10) {
          DatePicker(
            localized("From", "开始", "開始"),
            selection: Binding(
              get: { analytics.startDate },
              set: { analytics.setCustomRange(start: $0, end: analytics.endDate) }),
            in: analytics.minimumSelectableDate...analytics.endDate,
            displayedComponents: .date)
          DatePicker(
            localized("To", "结束", "終了"),
            selection: Binding(
              get: { analytics.endDate },
              set: { analytics.setCustomRange(start: analytics.startDate, end: $0) }),
            in: analytics.startDate...analytics.maximumSelectableDate,
            displayedComponents: .date)
          Spacer()
          Text(localized("Maximum 400 days", "最多 400 天", "最大400日"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private var metricPicker: some View {
    Picker(
      localized("Metric", "指标", "指標"),
      selection: $analytics.selectedMetric
    ) {
      ForEach(UsageAnalyticsMetric.allCases) { metric in
        Text(metricText(metric)).tag(metric)
      }
    }
    .pickerStyle(.segmented)
    .frame(width: 260)
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 18) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
        metricCard(
          title: localized("Total tokens", "总 Token", "合計トークン"),
          value: tokenText(analytics.snapshot.current.totalTokens),
          current: Double(analytics.snapshot.current.totalTokens),
          previous: Double(analytics.snapshot.previous.totalTokens),
          symbol: "sum")
        metricCard(
          title: localized("Input", "输入", "入力"),
          value: tokenText(analytics.snapshot.current.totalInputTokens),
          current: Double(analytics.snapshot.current.totalInputTokens),
          previous: Double(analytics.snapshot.previous.totalInputTokens),
          symbol: "arrow.down.left")
        metricCard(
          title: localized("Output", "输出", "出力"),
          value: tokenText(analytics.snapshot.current.outputTokens),
          current: Double(analytics.snapshot.current.outputTokens),
          previous: Double(analytics.snapshot.previous.outputTokens),
          symbol: "arrow.up.right")
        metricCard(
          title: localized("Cache reuse · token", "缓存复用率 · Token", "キャッシュ再利用率・トークン"),
          value: percentText(analytics.snapshot.current.cacheReuseRatio),
          current: analytics.snapshot.current.cacheReuseRatio ?? 0,
          previous: analytics.snapshot.previous.cacheReuseRatio ?? 0,
          symbol: "bolt.horizontal.fill")
        metricCard(
          title: localized("Estimated active time", "估算活跃时长", "推定アクティブ時間"),
          value: durationText(analytics.snapshot.current.activeSeconds),
          current: Double(analytics.snapshot.current.activeSeconds),
          previous: Double(analytics.snapshot.previous.activeSeconds),
          symbol: "timer")
        metricCard(
          title: String(
            format: localized(
              "API-equivalent · %@ priced",
              "API 等价成本 · %@ 已定价",
              "API相当コスト・%@価格対応"),
            percentText(analytics.snapshot.current.pricingCoverage)),
          value: costText(analytics.snapshot.current.costUSD),
          current: analytics.snapshot.current.costUSD,
          previous: analytics.snapshot.previous.costUSD,
          symbol: "dollarsign")
      }

      calendarCard
      overviewBreakdowns
      provenanceCard
    }
  }

  private var trends: some View {
    VStack(alignment: .leading, spacing: 18) {
      chartCard(
        title: localized("Usage over time", "用量趋势", "使用量の推移"),
        subtitle: localized(
          "Current period compared with the immediately preceding equal-length period.",
          "当前周期与紧邻的等长上一周期对比。",
          "現在期間と直前の同じ長さの期間を比較します。"
        )
      ) {
        Chart {
          ForEach(analytics.snapshot.timeline) { point in
            LineMark(
              x: .value("Time", point.date),
              y: .value("Current", metricValue(point.totals))
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2.2))
          }
          ForEach(analytics.snapshot.comparisonTimeline) { point in
            LineMark(
              x: .value("Time", point.date),
              y: .value("Previous", metricValue(point.totals))
            )
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
          }
        }
        .chartLegend(.hidden)
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 7))
        }
        .frame(height: 260)
      }

      chartCard(
        title: localized("Time-of-day distribution", "一天内的分时分布", "時間帯別の分布"),
        subtitle: localized(
          "Local clock hours; bars are current and the dashed line is the previous period.",
          "按本地时间统计；柱形为当前周期，虚线为上一周期。",
          "ローカル時刻。棒は現在期間、破線は前期間です。"
        )
      ) {
        Chart(analytics.snapshot.hourlyDistribution) { point in
          BarMark(
            x: .value("Hour", point.hour),
            y: .value("Current", metricValue(point.current))
          )
          .foregroundStyle(Color.accentColor.opacity(0.72))
          LineMark(
            x: .value("Hour", point.hour),
            y: .value("Previous", metricValue(point.previous))
          )
          .foregroundStyle(Color.secondary)
          .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
        }
        .chartXAxis {
          AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
            AxisValueLabel {
              if let hour = value.as(Int.self) {
                Text(String(format: "%02d", hour))
              }
            }
          }
        }
        .chartLegend(.hidden)
        .frame(height: 240)
      }

      comparisonCard
    }
  }

  private var attribution: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker(
        localized("Break down by", "归因维度", "内訳"),
        selection: $analytics.selectedDimension
      ) {
        ForEach(UsageAttributionDimension.allCases) { dimension in
          Text(dimensionText(dimension)).tag(dimension)
        }
      }
      .pickerStyle(.segmented)

      let rows = sortedAttributionRows
      chartCard(
        title: String(
          format: localized("By %@", "按%@", "%@別"),
          dimensionText(analytics.selectedDimension)),
        subtitle: localized(
          "Top categories for the selected metric; exact Token, cost, and active-time values remain visible below.",
          "按所选指标显示主要类别；下方同时保留精确的 Token、成本和活跃时长。",
          "選択した指標の上位カテゴリ。正確なトークン、コスト、アクティブ時間は下に表示します。"
        )
      ) {
        Chart(Array(rows.prefix(12))) { row in
          BarMark(
            x: .value("Value", metricValue(row.totals)),
            y: .value("Category", row.label)
          )
          .foregroundStyle(Color.accentColor)
          .annotation(position: .trailing, alignment: .leading) {
            Text(metricFormatted(row.totals))
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        .chartXAxis {
          AxisMarks(position: .bottom)
        }
        .chartLegend(.hidden)
        .frame(height: max(260, CGFloat(min(rows.count, 12)) * 34))
      }

      VStack(spacing: 0) {
        ForEach(Array(rows.prefix(40))) { row in
          HStack(spacing: 12) {
            Text(row.label)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(tokenText(row.totals.totalTokens))
              .frame(width: 90, alignment: .trailing)
            Text(costText(row.totals.costUSD))
              .frame(width: 80, alignment: .trailing)
            Text(durationText(row.totals.activeSeconds))
              .frame(width: 90, alignment: .trailing)
          }
          .font(.caption)
          .padding(.vertical, 8)
          if row.id != rows.prefix(40).last?.id { Divider() }
        }
      }
      .padding(.horizontal, 14)
      .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(.quaternary)
      }
    }
  }

  private var calendarCard: some View {
    chartCard(
      title: localized("Activity calendar", "用量日历", "アクティビティカレンダー"),
      subtitle: localized(
        "Each square is one local calendar day. Color intensity follows the selected metric.",
        "每个方格代表一个本地自然日，颜色深浅对应当前所选指标。",
        "各マスはローカル暦の1日です。色の濃さは選択した指標を表します。"
      )
    ) {
      UsageCalendarHeatmap(
        days: analytics.snapshot.calendarDays,
        value: metricValue,
        valueText: metricFormatted)
    }
  }

  private var overviewBreakdowns: some View {
    let projects = analytics.snapshot.attribution[.project] ?? []
    let models = analytics.snapshot.attribution[.model] ?? []
    return HStack(alignment: .top, spacing: 14) {
      compactRanking(
        title: localized("Top projects", "主要项目", "上位プロジェクト"),
        rows: Array(projects.prefix(5)))
      compactRanking(
        title: localized("Top models", "主要模型", "上位モデル"),
        rows: Array(models.prefix(5)))
    }
  }

  private var comparisonCard: some View {
    HStack(spacing: 20) {
      comparisonItem(
        localized("Tokens", "Token", "トークン"),
        current: Double(analytics.snapshot.current.totalTokens),
        previous: Double(analytics.snapshot.previous.totalTokens))
      Divider().frame(height: 42)
      comparisonItem(
        localized("API-equivalent", "API 等价成本", "API 相当コスト"),
        current: analytics.snapshot.current.costUSD,
        previous: analytics.snapshot.previous.costUSD)
      Divider().frame(height: 42)
      comparisonItem(
        localized("Active time", "活跃时长", "アクティブ時間"),
        current: Double(analytics.snapshot.current.activeSeconds),
        previous: Double(analytics.snapshot.previous.activeSeconds))
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private var provenanceCard: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(
        localized("Local analytics history", "本地分析历史", "ローカル分析履歴"), systemImage: "externaldrive"
      )
      .font(.headline)
      if let metadata = analytics.snapshot.metadata {
        Text(
          String(
            format: localized(
              "%lld events · %lld files reused · %lld reparsed · %@ on disk",
              "%lld 条事件 · 复用 %lld 个文件 · 重解析 %lld 个 · 本地占用 %@",
              "%lldイベント・%lldファイル再利用・%lld再解析・ディスク上%@"
            ),
            metadata.retainedEventCount,
            metadata.reusedFileCount,
            metadata.reparsedFileCount,
            ByteCountFormatter.string(
              fromByteCount: Int64(metadata.storageBytes), countStyle: .file))
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        Text(
          localized(
            "Only token counters and privacy-safe attribution are persisted. Prompts, replies, tool output, and full paths are never stored.",
            "仅持久化 Token 计数和隐私安全的归因字段；不保存 prompt、回复、工具输出或完整路径。",
            "トークン数とプライバシー保護された属性のみ保存し、プロンプト、返信、ツール出力、フルパスは保存しません。"
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Text(
        localized(
          "Active time is an estimate: gaps within five minutes are counted per Session; isolated activity contributes one minute. Concurrent Sessions can overlap.",
          "活跃时长为估算值：同一 Session 内不超过 5 分钟的间隔计入活跃时间，孤立事件按 1 分钟计；并发 Session 可能重叠。",
          "アクティブ時間は推定値です。同一Session内の5分以内の間隔を数え、単独イベントは1分とします。並行Sessionは重複する場合があります。"
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "chart.xyaxis.line")
        .font(.system(size: 32))
        .foregroundStyle(.secondary)
      Text(localized("No local usage in this range", "这个时间范围内没有本地用量", "この期間のローカル使用量はありません"))
        .font(.headline)
      Text(
        localized(
          "Choose another range or refresh after Codex, Claude, or Kimi has written local usage records.",
          "请选择其他时间范围，或在 Codex、Claude、Kimi 写入本地用量记录后刷新。",
          "別の期間を選ぶか、Codex、Claude、Kimi がローカル使用記録を書き込んだ後に更新してください。")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 260)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
  }

  private func metricCard(
    title: String,
    value: String,
    current: Double,
    previous: Double,
    symbol: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.weight(.semibold))
        .monospacedDigit()
      Text(deltaText(current: current, previous: previous))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private func chartCard<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      content()
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.quaternary)
    }
  }

  private func compactRanking(title: String, rows: [UsageAttributionRow]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      ForEach(rows) { row in
        HStack {
          Text(row.label).lineLimit(1)
          Spacer()
          Text(tokenText(row.totals.totalTokens))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary)
    }
  }

  private func comparisonItem(_ title: String, current: Double, previous: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(deltaText(current: current, previous: previous))
        .font(.headline.monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sortedAttributionRows: [UsageAttributionRow] {
    let rows = analytics.snapshot.attribution[analytics.selectedDimension] ?? []
    return rows.sorted {
      let lhs = metricValue($0.totals)
      let rhs = metricValue($1.totals)
      if lhs != rhs { return lhs > rhs }
      return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
    }
  }

  private func metricValue(_ totals: UsageAnalyticsTotals) -> Double {
    switch analytics.selectedMetric {
    case .tokens: Double(totals.totalTokens)
    case .cost: totals.costUSD
    case .activeTime: Double(totals.activeSeconds) / 3_600
    }
  }

  private func metricFormatted(_ totals: UsageAnalyticsTotals) -> String {
    switch analytics.selectedMetric {
    case .tokens: tokenText(totals.totalTokens)
    case .cost: costText(totals.costUSD)
    case .activeTime: durationText(totals.activeSeconds)
    }
  }

  private func tokenText(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName))
  }

  private func costText(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(value < 1 ? 3 : 2)))
  }

  private func percentText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(.percent.precision(.fractionLength(1)))
  }

  private func durationText(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: TimeInterval(seconds)) ?? "0m"
  }

  private func deltaText(current: Double, previous: Double) -> String {
    guard previous > 0 else {
      return localized("No prior baseline", "无上一周期基线", "前期間の基準なし")
    }
    let delta = (current - previous) / previous
    let formatted = delta.formatted(
      .percent
        .sign(strategy: .always())
        .precision(.fractionLength(1)))
    return String(
      format: localized("%@ vs prior period", "较上一周期 %@", "前期間比 %@"),
      formatted)
  }

  private func presetText(_ preset: UsageAnalyticsRangePreset) -> String {
    switch preset {
    case .sevenDays: localized("7D", "7 天", "7日")
    case .thirtyDays: localized("30D", "30 天", "30日")
    case .ninetyDays: localized("90D", "90 天", "90日")
    case .year: localized("1Y", "1 年", "1年")
    case .custom: localized("Custom", "自定义", "カスタム")
    }
  }

  private func metricText(_ metric: UsageAnalyticsMetric) -> String {
    switch metric {
    case .tokens: "Token"
    case .cost: localized("Cost", "成本", "コスト")
    case .activeTime: localized("Active", "活跃时长", "アクティブ")
    }
  }

  private func dimensionText(_ dimension: UsageAttributionDimension) -> String {
    switch dimension {
    case .project: localized("Project", "项目", "プロジェクト")
    case .model: localized("Model", "模型", "モデル")
    case .effort: localized("Effort", "强度", "推論強度")
    case .session: "Session"
    }
  }

  private func localized(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch model.currentLanguage {
    case .english: english
    case .simplifiedChinese: chinese
    case .japanese: japanese
    }
  }
}

private struct UsageCalendarHeatmap: View {
  let days: [UsageAnalyticsDay]
  let value: (UsageAnalyticsTotals) -> Double
  let valueText: (UsageAnalyticsTotals) -> String

  private var weeks: [[UsageAnalyticsDay?]] {
    guard let first = days.first else { return [] }
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: first.date)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    var padded: [UsageAnalyticsDay?] = Array(repeating: nil, count: leading)
    padded.append(contentsOf: days.map(Optional.some))
    while padded.count % 7 != 0 { padded.append(nil) }
    return stride(from: 0, to: padded.count, by: 7).map {
      Array(padded[$0..<min($0 + 7, padded.count)])
    }
  }

  private var maximum: Double {
    max(weeks.flatMap { $0 }.compactMap { $0 }.map { value($0.totals) }.max() ?? 0, 1)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 3) {
        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
          VStack(spacing: 3) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
              if let day {
                RoundedRectangle(cornerRadius: 2.5)
                  .fill(fill(for: day))
                  .frame(width: 12, height: 12)
                  .overlay {
                    RoundedRectangle(cornerRadius: 2.5)
                      .strokeBorder(Color.primary.opacity(0.08))
                  }
                  .help(
                    "\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(valueText(day.totals))"
                  )
                  .accessibilityLabel(
                    "\(day.date.formatted(date: .complete, time: .omitted)), \(valueText(day.totals))"
                  )
              } else {
                Color.clear.frame(width: 12, height: 12)
              }
            }
          }
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func fill(for day: UsageAnalyticsDay) -> Color {
    let amount = value(day.totals)
    guard amount > 0 else { return Color.secondary.opacity(0.10) }
    let intensity = 0.22 + 0.78 * min(1, amount / maximum)
    return Color.accentColor.opacity(intensity)
  }
}
