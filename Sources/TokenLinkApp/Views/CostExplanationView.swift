import SwiftUI
import TokenLinkCore

struct CostExplanationView: View {
  @Bindable var model: AppModel
  let snapshot: EstimatedCostSnapshot

  var body: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.text(.costsCalculationIntro))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if snapshot.lineItems.isEmpty {
          Text(model.text(.costsNoPricedModels))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(snapshot.lineItems.enumerated()), id: \.offset) { _, item in
            modelExplanation(item)
          }
        }

        if !snapshot.unknownModelIDs.isEmpty {
          excludedModels
        }
      }
      .padding(.top, 10)
    } label: {
      Label(model.text(.costsCalculationDetails), systemImage: "sum")
        .font(.caption.weight(.semibold))
    }
  }

  private func modelExplanation(_ item: ModelCostLineItem) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text(item.usage.modelID)
          .font(.caption.weight(.semibold).monospaced())
          .textSelection(.enabled)
        Spacer(minLength: 12)
        Text(CostFormatting.preciseAmount(item.amount, language: model.currentLanguage))
          .font(.caption.weight(.semibold))
          .monospacedDigit()
      }

      if item.requestCount > 0 {
        Text(
          String(
            format: model.text(.costsPricedRecordsFormat),
            item.requestCount,
            item.longContextRequestCount,
            item.fastRequestCount)
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      ForEach(Array(item.components.enumerated()), id: \.offset) { _, component in
        componentRow(component)
      }

      if let price = item.price {
        Divider()
        Text(model.text(.costsCatalogRates))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
        catalogRates(price)
        if let rule = price.longContext {
          Text(
            String(
              format: model.text(.costsLongContextRuleFormat),
              CostFormatting.tokenCount(
                rule.thresholdInputTokens,
                language: model.currentLanguage),
              CostFormatting.decimal(rule.inputMultiplier, language: model.currentLanguage),
              CostFormatting.decimal(rule.outputMultiplier, language: model.currentLanguage))
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        if let fastMultiplier = price.fastMultiplier {
          Text(
            String(
              format: model.text(.costsFastMultiplierFormat),
              CostFormatting.decimal(fastMultiplier, language: model.currentLanguage))
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        Link(destination: price.sourceURL) {
          Label(model.text(.costsPricingSource), systemImage: "arrow.up.right.square")
        }
        .font(.caption2)
      }
    }
    .padding(11)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
  }

  private func componentRow(_ component: ModelCostComponent) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 1) {
        Text(CostFormatting.preciseAmount(component.amount, language: model.currentLanguage))
          .monospacedDigit()
        if let rate = component.effectiveRatePerMillion {
          Text(
            String(
              format: model.text(.costsEffectiveRateFormat),
              CostFormatting.tokenCount(component.tokens, language: model.currentLanguage),
              CostFormatting.preciseAmount(
                CurrencyAmount(value: rate, currency: component.amount.currency),
                language: model.currentLanguage))
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
    } label: {
      Text(componentLabel(component.category))
    }
    .font(.caption)
  }

  @ViewBuilder
  private func catalogRates(_ price: ModelPrice) -> some View {
    if let value = price.uncachedInputPerMillion {
      catalogRate(model.text(.costsUncachedInput), value: value, currency: price.currency)
    }
    if let value = price.cacheReadPerMillion {
      catalogRate(model.text(.costsCacheRead), value: value, currency: price.currency)
    }
    if let value = price.cacheWritePerMillion {
      catalogRate(model.text(.costsCacheWrite), value: value, currency: price.currency)
    }
    if let value = price.cacheWriteFiveMinutePerMillion {
      catalogRate(model.text(.costsCacheWriteFiveMinute), value: value, currency: price.currency)
    }
    if let value = price.cacheWriteOneHourPerMillion {
      catalogRate(model.text(.costsCacheWriteOneHour), value: value, currency: price.currency)
    }
    if let value = price.outputPerMillion {
      catalogRate(model.text(.costsOutput), value: value, currency: price.currency)
    }
  }

  private func catalogRate(_ label: String, value: Decimal, currency: String) -> some View {
    LabeledContent(label) {
      Text(
        String(
          format: model.text(.costsRatePerMillionFormat),
          CostFormatting.preciseAmount(
            CurrencyAmount(value: value, currency: currency),
            language: model.currentLanguage))
      )
      .monospacedDigit()
    }
    .font(.caption2)
  }

  private var excludedModels: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(model.text(.costsExcludedModels), systemImage: "exclamationmark.triangle")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
      Text(model.text(.costsExcludedModelsHint))
        .font(.caption2)
        .foregroundStyle(.secondary)
      ForEach(snapshot.unknownModelIDs, id: \.self) { modelID in
        Text(modelID)
          .font(.caption2.monospaced())
          .textSelection(.enabled)
      }
    }
  }

  private func componentLabel(_ category: CostComponentCategory) -> String {
    switch category {
    case .uncachedInput: model.text(.costsUncachedInput)
    case .cacheRead: model.text(.costsCacheRead)
    case .cacheWrite: model.text(.costsCacheWrite)
    case .output: model.text(.costsOutput)
    }
  }
}
