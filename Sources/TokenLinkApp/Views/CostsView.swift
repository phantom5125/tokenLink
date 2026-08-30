import SwiftUI
import TokenLinkCore

struct CostsView: View {
  @Bindable var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 9) {
            Text(model.text(.costsTitle))
              .font(.largeTitle.bold())
            Text(model.text(.costsBetaBadge))
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.orange.opacity(0.14), in: Capsule())
              .foregroundStyle(.orange)
          }
          Text(model.text(.costsSubtitle))
            .foregroundStyle(.secondary)
        }

        if model.configuration.betaCostsEnabled {
          authoritativeSection
          estimateSection
        } else {
          betaDisabledCard
        }
      }
      .padding(28)
      .frame(maxWidth: 880, alignment: .leading)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .navigationTitle(model.text(.costsTitle))
    .task { await model.loadCostsIfNeeded() }
  }

  private var betaDisabledCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(model.text(.costsBetaOffTitle), systemImage: "flask")
        .font(.headline)
      Text(model.text(.costsBetaOffBody))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(model.text(.costsEnable)) {
        Task {
          try? await model.setBetaCostsEnabled(true)
          await model.loadCostsIfNeeded()
        }
      }
    }
    .costCard()
  }

  private var authoritativeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(
        title: model.text(.costsAuthoritative),
        subtitle: model.text(.costsAuthoritativeHint),
        symbol: "building.columns")
      if model.costDashboard.authoritativeRows.isEmpty {
        Text(model.text(.costsNoAuthoritative))
          .foregroundStyle(.secondary)
          .costCard()
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)], spacing: 14) {
          ForEach(model.costDashboard.authoritativeRows) { row in
            authoritativeCard(row)
          }
        }
      }
    }
  }

  private var estimateSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(
        title: model.text(.costsEstimated),
        subtitle: model.text(.costsEstimatedHint),
        symbol: "function")
      if model.costDashboard.estimateRows.isEmpty {
        Text(model.text(.costsNoEstimates))
          .foregroundStyle(.secondary)
          .costCard()
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)], spacing: 14) {
          ForEach(model.costDashboard.estimateRows) { row in
            estimateCard(row)
          }
        }
      }
    }
  }

  private func sectionHeader(title: String, subtitle: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Label(title, systemImage: symbol)
        .font(.title2.bold())
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func authoritativeCard(_ row: AuthoritativeCostRow) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ProviderMark(provider: row.source.provider, size: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text(accountLabel(row.source.accountID, provider: row.source.provider))
            .font(.headline)
          Text(model.text(.costsSourceOfficialAPI))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        PhaseBadge(phase: row.state.phase)
      }

      if let snapshot = row.state.snapshot {
        ForEach(Array(snapshot.balances.enumerated()), id: \.offset) { _, balance in
          VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
              Text(model.text(.costsAvailable))
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Text(CostFormatting.amount(balance.available, language: model.currentLanguage))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            }
            if let purchased = balance.purchased {
              amountDetail(model.text(.costsPurchased), amount: purchased)
            }
            if let used = balance.used {
              amountDetail(model.text(.costsUsed), amount: used)
            }
          }
        }
        ForEach(Array(snapshot.periodSpend.enumerated()), id: \.offset) { _, spend in
          LabeledContent(periodText(spend.period)) {
            Text(CostFormatting.amount(spend.amount, language: model.currentLanguage))
              .monospacedDigit()
          }
          .font(.caption)
        }
        metadataLine(
          String(
            format: model.text(.costsUpdatedFormat),
            snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
        if snapshot.isAvailable == false {
          warningLine(model.text(.costsProviderUnavailable))
        }
        warningList(snapshot.warnings)
        if let error = row.state.error {
          warningLine(error.message)
        }
      } else {
        emptyState(row.state.error)
      }
    }
    .costCard()
  }

  private func estimateCard(_ row: EstimatedCostRow) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ProviderMark(provider: row.provider, size: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text(AppModel.displayName(for: row.provider))
            .font(.headline)
          Text(model.text(.costsEstimatedLabel))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
        Spacer()
        PhaseBadge(phase: row.state.phase)
      }

      if let snapshot = row.state.snapshot {
        ForEach(Array(snapshot.totals.enumerated()), id: \.offset) { _, total in
          Text("≈\(CostFormatting.amount(total, language: model.currentLanguage))")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }
        metadataLine(model.text(.costsSourceLocalTranscripts))
        metadataLine(
          String(
            format: model.text(.costsPeriodFormat),
            snapshot.period.start.formatted(date: .abbreviated, time: .omitted),
            snapshot.period.end.formatted(date: .abbreviated, time: .omitted)))
        metadataLine(
          String(
            format: model.text(.costsCatalogFormat),
            snapshot.catalogVersion,
            snapshot.catalogEffectiveDate.formatted(date: .abbreviated, time: .omitted)))
        metadataLine(
          String(
            format: model.text(.costsUpdatedFormat),
            snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened)))
        CostExplanationView(model: model, snapshot: snapshot)
        if !snapshot.unknownModelIDs.isEmpty {
          warningLine(
            String(
              format: model.text(.costsUnknownModelsFormat),
              snapshot.unknownModelIDs.count))
        }
        warningList(snapshot.warnings)
        if let error = row.state.error {
          warningLine(error.message)
        }
      } else {
        emptyState(row.state.error)
      }
    }
    .costCard()
  }

  private func accountLabel(_ accountID: UUID, provider: ProviderID) -> String {
    model.configuration.accounts.first(where: { $0.id == accountID })?.label
      ?? AppModel.displayName(for: provider)
  }

  private func periodText(_ period: ProviderSpendPeriod) -> String {
    switch period {
    case .daily: model.text(.costsDailySpend)
    case .weekly: model.text(.costsWeeklySpend)
    case .monthly: model.text(.costsMonthlySpend)
    case .lifetime: model.text(.costsLifetimeSpend)
    }
  }

  @ViewBuilder
  private func emptyState(_ error: ProviderFailure?) -> some View {
    Text(error?.message ?? model.text(.costsNoData))
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func metadataLine(_ value: String) -> some View {
    Text(value)
      .font(.caption2)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func amountDetail(_ label: String, amount: CurrencyAmount) -> some View {
    LabeledContent(label) {
      Text(CostFormatting.amount(amount, language: model.currentLanguage)).monospacedDigit()
    }
    .font(.caption)
  }

  private func warningLine(_ value: String) -> some View {
    Label(value, systemImage: "exclamationmark.triangle")
      .font(.caption2)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func warningList(_ warnings: [CostWarning]) -> some View {
    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
      warningLine(warningText(warning))
    }
  }

  private func warningText(_ warning: CostWarning) -> String {
    switch warning {
    case .assumedFiveMinuteCacheWrite:
      model.text(.costsAssumedCache)
    case .partialLocalScan(let fileCount, let recordCount):
      String(format: model.text(.costsPartialScanFormat), fileCount, recordCount)
    case .partialSource:
      model.text(.costsPartialSource)
    case .unpricedModel:
      model.text(.costsUnpricedModel)
    case .invalidTokenCount:
      model.text(.costsInvalidTokenCount)
    }
  }
}

extension View {
  fileprivate func costCard() -> some View {
    self
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.quaternary)
      }
  }
}
