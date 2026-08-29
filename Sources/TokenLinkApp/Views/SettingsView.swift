import AppKit
import SwiftUI
import TokenLinkCore
import TokenLinkProviders

private struct CostMetricOption: Identifiable {
  let metric: MenuBarCostMetric
  let label: String
  var id: MenuBarCostMetric { metric }
}

struct SettingsView: View {
  @Bindable var model: AppModel
  @State private var message: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 6) {
          Text(model.text(.settingsTitle))
            .font(.largeTitle.bold())
          Text(model.text(.settingsSubtitle))
            .foregroundStyle(.secondary)
        }
        generalCard
        betaCard
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
    .navigationTitle(model.text(.settingsTitle))
    .task { await model.loadCostsIfNeeded() }
  }

  private var generalCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.text(.settingsGeneral))
        .font(.headline)
      LabeledContent(model.text(.settingsLanguage)) {
        Picker(
          model.text(.settingsLanguage),
          selection: Binding(
            get: { model.configuration.appLanguage ?? "" },
            set: { preference in
              do {
                try model.setAppLanguage(preference.isEmpty ? nil : preference)
              } catch { message = error.localizedDescription }
            })
        ) {
          Text(model.text(.languageSystem)).tag("")
          Text(model.text(.languageEnglish)).tag(AppLanguage.english.rawValue)
          Text(model.text(.languageChinese)).tag(AppLanguage.simplifiedChinese.rawValue)
          Text(model.text(.languageJapanese)).tag(AppLanguage.japanese.rawValue)
        }
        .labelsHidden()
        .frame(width: 160)
      }
      LabeledContent(model.text(.settingsRefreshInterval)) {
        Picker(
          model.text(.settingsRefreshInterval),
          selection: Binding(
            get: { model.configuration.refreshMinutes },
            set: { minutes in
              do { try model.setRefreshMinutes(minutes) } catch {
                message = error.localizedDescription
              }
            })
        ) {
          ForEach([1, 2, 5, 15, 30], id: \.self) { minutes in
            Text(String(format: model.text(.settingsMinutes), minutes)).tag(minutes)
          }
        }
        .labelsHidden()
        .frame(width: 140)
      }
      LabeledContent(model.text(.settingsNotifications)) {
        Toggle(
          model.text(.settingsNotifications),
          isOn: Binding(
            get: { model.configuration.notificationsEnabled },
            set: { enabled in
              do { try model.setNotificationsEnabled(enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }
      LabeledContent(model.text(.settingsFairPace)) {
        Toggle(
          model.text(.settingsFairPace),
          isOn: Binding(
            get: { model.configuration.fairPaceEnabled },
            set: { enabled in
              do { try model.setFairPaceEnabled(enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }
      Text(model.text(.settingsFairPaceHint))
        .font(.caption)
        .foregroundStyle(.secondary)
      LabeledContent(model.text(.settingsLaunchAtLogin)) {
        Toggle(
          model.text(.settingsLaunchAtLogin),
          isOn: Binding(
            get: { model.loginItemState == .enabled },
            set: { enabled in
              do { try model.setLoginItemEnabled(enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }
      if model.loginItemState == .requiresApproval {
        Label(
          model.text(.settingsLoginApproval),
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
    .settingsCard()
  }

  private var betaCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.text(.settingsBetaTitle))
        .font(.headline)
      LabeledContent(model.text(.betaLocalUsage)) {
        Toggle(
          model.text(.betaLocalUsage),
          isOn: Binding(
            get: { model.configuration.betaLocalUsageEnabled },
            set: { enabled in
              do { try model.setBetaLocalUsageEnabled(enabled) } catch {
                message = error.localizedDescription
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }
      Text(model.text(.betaLocalUsageHint))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if model.configuration.betaLocalUsageEnabled {
        if model.localUsageSummaries.isEmpty && !model.isScanningLocalUsage {
          Text(model.text(.betaNoTranscripts))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(model.localUsageSummaries, id: \.provider) { summary in
          HStack {
            ProviderMark(provider: summary.provider, size: 22)
            Text(AppModel.displayName(for: summary.provider))
              .font(.subheadline)
            Spacer()
            Text(tokenText(summary))
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
        Button {
          Task { await model.scanLocalUsage() }
        } label: {
          Label(
            model.isScanningLocalUsage
              ? model.text(.betaScanning) : model.text(.betaScanNow),
            systemImage: "arrow.clockwise")
        }
        .disabled(model.isScanningLocalUsage)
      }

      Divider()

      LabeledContent(model.text(.betaCosts)) {
        Toggle(
          model.text(.betaCosts),
          isOn: Binding(
            get: { model.configuration.betaCostsEnabled },
            set: { enabled in
              Task { @MainActor in
                do {
                  try await model.setBetaCostsEnabled(enabled)
                  if enabled { await model.loadCostsIfNeeded() }
                } catch {
                  message = error.localizedDescription
                }
              }
            })
        )
        .toggleStyle(.switch)
        .labelsHidden()
      }
      Text(model.text(.betaCostsHint))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if model.configuration.betaCostsEnabled {
        LabeledContent(model.text(.betaCostsMetric)) {
          Picker(
            model.text(.betaCostsMetric),
            selection: Binding(
              get: { model.configuration.menuBarCostMetric },
              set: { metric in
                do { try model.setMenuBarCostMetric(metric) } catch {
                  message = error.localizedDescription
                }
              })
          ) {
            ForEach(costMetricOptions) { option in
              Text(option.label).tag(option.metric)
            }
          }
          .labelsHidden()
          .frame(width: 250)
        }
        Text(model.text(.betaCostsMetricHint))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .settingsCard()
  }

  private func tokenText(_ summary: LocalUsageSummary) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let total = formatter.string(from: NSNumber(value: summary.totalTokens)) ?? "0"
    let cached = formatter.string(from: NSNumber(value: summary.cachedInputTokens)) ?? "0"
    return "\(total) tok (\(cached) cached)"
  }

  private var costMetricOptions: [CostMetricOption] {
    var options = [
      CostMetricOption(metric: .none, label: model.text(.costMetricNone))
    ]
    options += ProviderRegistry.localCostEstimateProviderIDs.map { provider in
      CostMetricOption(
        metric: .localEstimate(provider),
        label: String(
          format: model.text(.costMetricLocalFormat),
          AppModel.displayName(for: provider)))
    }
    for row in model.costDashboard.authoritativeRows {
      let providerName = AppModel.displayName(for: row.source.provider)
      let currencies = row.state.snapshot?.balances.map(\.available.currency) ?? []
      for currency in currencies {
        options.append(
          CostMetricOption(
            metric: .authoritativeBalance(
              accountID: row.source.accountID, currency: currency),
            label: String(
              format: model.text(.costMetricBalanceFormat), providerName, currency)))
      }
    }
    let selected = model.configuration.menuBarCostMetric
    if !options.contains(where: { $0.metric == selected }),
      case .authoritativeBalance(let accountID, let currency) = selected
    {
      let provider = model.configuration.accounts.first(where: { $0.id == accountID })?.provider
      options.append(
        CostMetricOption(
          metric: selected,
          label: String(
            format: model.text(.costMetricBalanceFormat),
            provider.map(AppModel.displayName(for:)) ?? model.text(.costsAuthoritative),
            currency)))
    }
    return options
  }

  private var privacyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(model.text(.settingsPrivacyTitle), systemImage: "lock.shield")
        .font(.headline)
      Text(model.text(.settingsPrivacyBody))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .settingsCard()
  }

  private var diagnosticsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.text(.settingsDiagnostics))
        .font(.headline)
      Text(model.text(.settingsDiagnosticsBody))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button {
        exportDiagnostics()
      } label: {
        Label(model.text(.settingsExportDiagnostics), systemImage: "square.and.arrow.up")
      }
    }
    .settingsCard()
  }

  private var eventCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.text(.settingsRecentEvents))
        .font(.headline)
      if model.events.isEmpty {
        Text(model.text(.settingsNoEvents))
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
    panel.title = model.text(.settingsExportPanelTitle)
    panel.nameFieldStringValue = "tokenlink-diagnostics.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try model.exportDiagnostics(to: url)
      message = String(format: model.text(.settingsExported), url.lastPathComponent)
    } catch {
      message = error.localizedDescription
    }
  }
}

extension View {
  fileprivate func settingsCard() -> some View {
    self
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background, in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
  }
}
