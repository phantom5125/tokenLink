import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case japanese = "ja"

  /// Resolves the effective language: an explicit preference wins; otherwise
  /// the system preferred languages decide, falling back to English for
  /// anything that is not Chinese or Japanese.
  public static func resolve(
    preference: String?,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> AppLanguage {
    if let preference, let language = AppLanguage(rawValue: preference) {
      return language
    }
    for preferred in preferredLanguages {
      let lowercased = preferred.lowercased()
      if lowercased.hasPrefix("zh") { return .simplifiedChinese }
      if lowercased.hasPrefix("ja") { return .japanese }
    }
    return .english
  }
}

/// Lightweight in-code string catalog. Every key must provide a translation
/// for every `AppLanguage`; `LocalizationTests` enforces completeness.
public enum L10n {
  public enum Key: String, CaseIterable, Sendable {
    // Routes and chrome
    case routeOverview = "route.overview"
    case routeProviders = "route.providers"
    case routeCosts = "route.costs"
    case routeStopwatch = "route.stopwatch"
    case routeSettings = "route.settings"
    case actionRefresh = "action.refresh"
    case actionRefreshCosts = "action.refreshCosts"
    case actionControlCenter = "action.controlCenter"
    case actionQuit = "action.quit"
    case actionSave = "action.save"
    case actionDelete = "action.delete"
    case actionCancel = "action.cancel"
    case actionContinue = "action.continue"
    // Menu bar
    case menubarNoProviders = "menubar.noProviders"
    case menubarEnableHint = "menubar.enableHint"
    case menubarQuotaAccessibilityFormat = "menubar.quotaAccessibilityFormat"
    case menubarEstimateAccessibilityFormat = "menubar.estimateAccessibilityFormat"
    case menubarBalanceAccessibilityFormat = "menubar.balanceAccessibilityFormat"
    case menubarCostFresh = "menubar.costFresh"
    case menubarCostStale = "menubar.costStale"
    case menubarCostRefreshing = "menubar.costRefreshing"
    case menubarEstimateCompactFormat = "menubar.estimateCompactFormat"
    case menubarBalanceCompactFormat = "menubar.balanceCompactFormat"
    // Costs
    case costsTitle = "costs.title"
    case costsBetaBadge = "costs.betaBadge"
    case costsSubtitle = "costs.subtitle"
    case costsBetaOffTitle = "costs.betaOffTitle"
    case costsBetaOffBody = "costs.betaOffBody"
    case costsEnable = "costs.enable"
    case costsAuthoritative = "costs.authoritative"
    case costsAuthoritativeHint = "costs.authoritativeHint"
    case costsNoAuthoritative = "costs.noAuthoritative"
    case costsEstimated = "costs.estimated"
    case costsEstimatedHint = "costs.estimatedHint"
    case costsNoEstimates = "costs.noEstimates"
    case costsSourceOfficialAPI = "costs.sourceOfficialAPI"
    case costsSourceLocalTranscripts = "costs.sourceLocalTranscripts"
    case costsEstimatedLabel = "costs.estimatedLabel"
    case costsAvailable = "costs.available"
    case costsPurchased = "costs.purchased"
    case costsUsed = "costs.used"
    case costsProviderUnavailable = "costs.providerUnavailable"
    case costsUpdatedFormat = "costs.updatedFormat"
    case costsPeriodFormat = "costs.periodFormat"
    case costsCatalogFormat = "costs.catalogFormat"
    case costsUnknownModelsFormat = "costs.unknownModelsFormat"
    case costsDailySpend = "costs.dailySpend"
    case costsWeeklySpend = "costs.weeklySpend"
    case costsMonthlySpend = "costs.monthlySpend"
    case costsLifetimeSpend = "costs.lifetimeSpend"
    case costsNoData = "costs.noData"
    case costsAssumedCache = "costs.assumedCache"
    case costsPartialScanFormat = "costs.partialScanFormat"
    case costsPartialSource = "costs.partialSource"
    case costsUnpricedModel = "costs.unpricedModel"
    case costsInvalidTokenCount = "costs.invalidTokenCount"
    case costsCalculationDetails = "costs.calculationDetails"
    case costsCalculationIntro = "costs.calculationIntro"
    case costsNoPricedModels = "costs.noPricedModels"
    case costsPricedRecordsFormat = "costs.pricedRecordsFormat"
    case costsEffectiveRateFormat = "costs.effectiveRateFormat"
    case costsCatalogRates = "costs.catalogRates"
    case costsRatePerMillionFormat = "costs.ratePerMillionFormat"
    case costsUncachedInput = "costs.uncachedInput"
    case costsCacheRead = "costs.cacheRead"
    case costsCacheWrite = "costs.cacheWrite"
    case costsCacheWriteFiveMinute = "costs.cacheWriteFiveMinute"
    case costsCacheWriteOneHour = "costs.cacheWriteOneHour"
    case costsOutput = "costs.output"
    case costsLongContextRuleFormat = "costs.longContextRuleFormat"
    case costsPricingSource = "costs.pricingSource"
    case costsExcludedModels = "costs.excludedModels"
    case costsExcludedModelsHint = "costs.excludedModelsHint"
    // Quota rows and cards
    case quotaLeft = "quota.left"
    case quotaRemaining = "quota.remaining"
    case quotaWaitingFirst = "quota.waitingFirst"
    case quotaNoSnapshot = "quota.noSnapshot"
    case quotaExpiredCacheFetched = "quota.expiredCacheFetched"
    case quotaExpiredCacheFrom = "quota.expiredCacheFrom"
    case quotaStaleFetched = "quota.staleFetched"
    case quotaResetsAt = "quota.resetsAt"
    case quotaUpdatedAt = "quota.updatedAt"
    case quotaResetUnavailable = "quota.resetUnavailable"
    case quotaBurnEta = "quota.burnEta"
    // Phases
    case phaseDisabled = "phase.disabled"
    case phaseMissingCredential = "phase.missingCredential"
    case phaseRefreshing = "phase.refreshing"
    case phaseHealthy = "phase.healthy"
    case phaseStale = "phase.stale"
    case phaseError = "phase.error"
    // Device states
    case deviceUnbound = "device.unbound"
    case deviceDisconnected = "device.disconnected"
    case deviceScanning = "device.scanning"
    case deviceConnecting = "device.connecting"
    case deviceConnected = "device.connected"
    case deviceSyncing = "device.syncing"
    case deviceSynced = "device.synced"
    case deviceStale = "device.stale"
    // Overview
    case overviewTitle = "overview.title"
    case overviewSubtitle = "overview.subtitle"
    case overviewMostConstrained = "overview.mostConstrained"
    case overviewMostConstrainedHint = "overview.mostConstrainedHint"
    case overviewWatchSubtitle = "overview.watchSubtitle"
    // StopWatch
    case watchSubtitle = "watch.subtitle"
    case watchCompatTitle = "watch.compatTitle"
    case watchCompatBody = "watch.compatBody"
    case watchBoundDevice = "watch.boundDevice"
    case watchNoBoundDevice = "watch.noBoundDevice"
    case watchRebindTitle = "watch.rebindTitle"
    case watchRebindBody = "watch.rebindBody"
    case watchSyncNow = "watch.syncNow"
    case watchUnbind = "watch.unbind"
    case watchUnboundMessage = "watch.unboundMessage"
    case watchBoundMessage = "watch.boundMessage"
    case watchDiscoverTitle = "watch.discoverTitle"
    case watchDiscoverNote = "watch.discoverNote"
    case watchScanning = "watch.scanning"
    case watchScan = "watch.scan"
    case watchBindSelected = "watch.bindSelected"
    // Settings
    case settingsTitle = "settings.title"
    case settingsSubtitle = "settings.subtitle"
    case settingsGeneral = "settings.general"
    case settingsRefreshInterval = "settings.refreshInterval"
    case settingsMinutes = "settings.minutes"
    case settingsLaunchAtLogin = "settings.launchAtLogin"
    case settingsLoginApproval = "settings.loginApproval"
    case settingsPrivacyTitle = "settings.privacyTitle"
    case settingsPrivacyBody = "settings.privacyBody"
    case settingsDiagnostics = "settings.diagnostics"
    case settingsDiagnosticsBody = "settings.diagnosticsBody"
    case settingsExportDiagnostics = "settings.exportDiagnostics"
    case settingsExportPanelTitle = "settings.exportPanelTitle"
    case settingsExported = "settings.exported"
    case settingsRecentEvents = "settings.recentEvents"
    case settingsNoEvents = "settings.noEvents"
    case settingsLanguage = "settings.language"
    case settingsNotifications = "settings.notifications"
    case settingsFairPace = "settings.fairPace"
    case settingsFairPaceHint = "settings.fairPaceHint"
    case settingsBetaTitle = "settings.betaTitle"
    case betaLocalUsage = "beta.localUsage"
    case betaLocalUsageHint = "beta.localUsageHint"
    case betaScanNow = "beta.scanNow"
    case betaScanning = "beta.scanning"
    case betaNoTranscripts = "beta.noTranscripts"
    case betaCosts = "beta.costs"
    case betaCostsHint = "beta.costsHint"
    case betaCostsMetric = "beta.costsMetric"
    case betaCostsMetricHint = "beta.costsMetricHint"
    case costMetricNone = "costMetric.none"
    case costMetricLocalFormat = "costMetric.localFormat"
    case costMetricBalanceFormat = "costMetric.balanceFormat"
    case watchFaceTitle = "watch.faceTitle"
    case watchSyncProviders = "watch.syncProviders"
    case watchTheme = "watch.theme"
    case watchThemeData = "watch.themeData"
    case watchThemePet = "watch.themePet"
    case watchWake = "watch.wake"
    case watchWakeRaise = "watch.wakeRaise"
    case watchWakeTap = "watch.wakeTap"
    case watchHourFormat = "watch.hourFormat"
    case watchHourSystem = "watch.hourSystem"
    case watchWorkItems = "watch.workItems"
    case watchNoWorkItems = "watch.noWorkItems"
    case watchPayloadPreview = "watch.payloadPreview"
    case watchNegotiated = "watch.negotiated"
    case watchV1Note = "watch.v1Note"
    case watchFaceHint = "watch.faceHint"
    case watchHour12 = "watch.hour12"
    case watchHour24 = "watch.hour24"
    case watchWorkItemName = "watch.workItemName"
    case watchFocusNote = "watch.focusNote"
    case watchNoPayload = "watch.noPayload"
    case watchNotNegotiated = "watch.notNegotiated"
    case notifyLowQuotaTitle = "notify.lowQuotaTitle"
    case notifyLowQuotaBody = "notify.lowQuotaBody"
    case notifyAuthFailureTitle = "notify.authFailureTitle"
    case notifyAuthFailureBody = "notify.authFailureBody"
    case notifyResetTitle = "notify.resetTitle"
    case notifyResetBody = "notify.resetBody"
    case languageSystem = "language.system"
    case languageEnglish = "language.en"
    case languageChinese = "language.zhHans"
    case languageJapanese = "language.ja"
    // Providers
    case providersTitle = "providers.title"
    case providersSubtitle = "providers.subtitle"
    case providersRestartBanner = "providers.restartBanner"
    case providersLegacyMigrationTitle = "providers.legacyMigrationTitle"
    case providersLegacyMigrationNote = "providers.legacyMigrationNote"
    case providersLegacyMigrationAction = "providers.legacyMigrationAction"
    case providersLegacyMigrationDismiss = "providers.legacyMigrationDismiss"
    case providersLegacyMigrationAuthorizationTitle =
      "providers.legacyMigrationAuthorizationTitle"
    case providersLegacyMigrationAuthorizationExplanation =
      "providers.legacyMigrationAuthorizationExplanation"
    case providersLegacyMigrationSucceeded = "providers.legacyMigrationSucceeded"
    case providersLegacyMigrationNone = "providers.legacyMigrationNone"
    case providersEnabled = "providers.enabled"
    case providersCodexExecutable = "providers.codexExecutable"
    case providersCodexPathPlaceholder = "providers.codexPathPlaceholder"
    case providersCodexNote = "providers.codexNote"
    case providersCredential = "providers.credential"
    case providersConfigured = "providers.configured"
    case providersNotConfigured = "providers.notConfigured"
    case providersReplaceKey = "providers.replaceKey"
    case providersKeyPlaceholder = "providers.keyPlaceholder"
    case providersRegion = "providers.region"
    case regionGlobal = "region.global"
    case regionChina = "region.china"
    case regionGlobalZAI = "region.globalZAI"
    case regionChinaBigModel = "region.chinaBigModel"
    case providersKimiCLINote = "providers.kimiCLINote"
    case providersKeySaved = "providers.keySaved"
    case providersKeyDeleted = "providers.keyDeleted"
    case providersGetKey = "providers.getKey"
    case providersDefaultBadge = "providers.defaultBadge"
    case providersAddAccount = "providers.addAccount"
    case providersAddAccountNote = "providers.addAccountNote"
    case providersAccountLabel = "providers.accountLabel"
    case providersAccountLabelPlaceholder = "providers.accountLabelPlaceholder"
    case providersDeleteAccount = "providers.deleteAccount"
    case providersAccountAdded = "providers.accountAdded"
    case providersAccountRemoved = "providers.accountRemoved"
    case providersCostTitle = "providers.costTitle"
    case providersCostSubtitle = "providers.costSubtitle"
    case providersCostBadge = "providers.costBadge"
    case providersOpenRouterCostNote = "providers.openRouterCostNote"
    case providersDeepSeekCostNote = "providers.deepSeekCostNote"
    case sourceKeychain = "source.keychain"
    case sourceCLI = "source.cli"
    case sourceEnvironment = "source.environment"
    // Provider subtitles
    case subtitleCodex = "subtitle.codex"
    case subtitleKimi = "subtitle.kimi"
    case subtitleMinimax = "subtitle.minimax"
    case subtitleGLM = "subtitle.glm"
    case subtitleClaude = "subtitle.claude"
    case providersClaudeNote = "providers.claudeNote"
    case providersClaudeAuthorize = "providers.claudeAuthorize"
    case providersClaudeAuthorizationTitle = "providers.claudeAuthorizationTitle"
    case providersClaudeAuthorizationExplanation = "providers.claudeAuthorizationExplanation"
    case providersClaudeAuthorized = "providers.claudeAuthorized"
    case providersClaudeAuthorizationSucceeded = "providers.claudeAuthorizationSucceeded"
    case providersClaudeStopUsing = "providers.claudeStopUsing"
    case providersClaudeStopped = "providers.claudeStopped"
    case providersClaudeEnableFirst = "providers.claudeEnableFirst"
    case providersClaudeCredentialUnavailable = "providers.claudeCredentialUnavailable"
    case providersClaudeAuthorizationDenied = "providers.claudeAuthorizationDenied"
  }

  public static func text(_ key: Key, language: AppLanguage) -> String {
    table[key]?[language] ?? table[key]?[.english] ?? key.rawValue
  }

  private static let table: [Key: [AppLanguage: String]] = [
    .routeOverview: [.english: "Overview", .simplifiedChinese: "概览", .japanese: "概要"],
    .routeProviders: [
      .english: "Providers", .simplifiedChinese: "额度源", .japanese: "プロバイダー",
    ],
    .routeCosts: [.english: "Costs β", .simplifiedChinese: "成本 β", .japanese: "コスト β"],
    .routeStopwatch: [
      .english: "StopWatch", .simplifiedChinese: "StopWatch", .japanese: "StopWatch",
    ],
    .routeSettings: [
      .english: "Settings & Diagnostics", .simplifiedChinese: "设置与诊断",
      .japanese: "設定と診断",
    ],
    .actionRefresh: [.english: "Refresh", .simplifiedChinese: "刷新", .japanese: "更新"],
    .actionRefreshCosts: [
      .english: "Refresh costs", .simplifiedChinese: "刷新成本", .japanese: "コストを更新",
    ],
    .actionControlCenter: [
      .english: "Control Center…", .simplifiedChinese: "控制中心…",
      .japanese: "コントロールセンター…",
    ],
    .actionQuit: [
      .english: "Quit TokenLink", .simplifiedChinese: "退出 TokenLink",
      .japanese: "TokenLink を終了",
    ],
    .actionSave: [.english: "Save", .simplifiedChinese: "保存", .japanese: "保存"],
    .actionDelete: [.english: "Delete", .simplifiedChinese: "删除", .japanese: "削除"],
    .actionCancel: [.english: "Cancel", .simplifiedChinese: "取消", .japanese: "キャンセル"],
    .actionContinue: [
      .english: "Continue", .simplifiedChinese: "继续", .japanese: "続ける",
    ],
    .menubarNoProviders: [
      .english: "No providers enabled", .simplifiedChinese: "未启用任何额度源",
      .japanese: "有効なプロバイダーがありません",
    ],
    .menubarEnableHint: [
      .english: "Enable a provider in Control Center.",
      .simplifiedChinese: "请在控制中心里启用一个额度源。",
      .japanese: "コントロールセンターでプロバイダーを有効にしてください。",
    ],
    .menubarQuotaAccessibilityFormat: [
      .english: "%@ quota, %lld percent remaining",
      .simplifiedChinese: "%@ 额度剩余百分之 %lld",
      .japanese: "%@ クォータ、残り %lld パーセント",
    ],
    .menubarEstimateAccessibilityFormat: [
      .english: "%@; %@ local Estimated/API-equivalent cost %@ for the last 7 days; %@",
      .simplifiedChinese: "%@；%@ 本地 Estimated/API-equivalent 成本 %@，近 7 天；%@",
      .japanese: "%@、%@ のローカル Estimated/API-equivalent コスト %@、直近7日間、%@",
    ],
    .menubarBalanceAccessibilityFormat: [
      .english: "%@; %@ authoritative balance %@ remaining; %@",
      .simplifiedChinese: "%@；%@ 权威余额剩余 %@；%@",
      .japanese: "%@、%@ の正式残高は残り %@、%@",
    ],
    .menubarCostFresh: [
      .english: "fresh", .simplifiedChinese: "数据新鲜", .japanese: "最新",
    ],
    .menubarCostStale: [
      .english: "stale", .simplifiedChinese: "数据已过期", .japanese: "古いデータ",
    ],
    .menubarCostRefreshing: [
      .english: "refreshing with last known data",
      .simplifiedChinese: "正在刷新，显示上次数据",
      .japanese: "更新中、前回のデータを表示",
    ],
    .menubarEstimateCompactFormat: [
      .english: "≈%@/7d", .simplifiedChinese: "≈%@/7天", .japanese: "≈%@/7日",
    ],
    .menubarBalanceCompactFormat: [
      .english: "%@ %@ left", .simplifiedChinese: "%@ 剩余 %@", .japanese: "%@ 残り %@",
    ],
    .costsTitle: [
      .english: "Costs", .simplifiedChinese: "成本", .japanese: "コスト",
    ],
    .costsBetaBadge: [
      .english: "Beta", .simplifiedChinese: "Beta", .japanese: "ベータ",
    ],
    .costsSubtitle: [
      .english:
        "Official balances and local estimates stay separate from coding-plan quota.",
      .simplifiedChinese: "官方余额与本地估算独立于编程套餐额度。",
      .japanese: "正式残高とローカル推定値は、コーディングプランのクォータとは別に扱われます。",
    ],
    .costsBetaOffTitle: [
      .english: "Costs beta is off", .simplifiedChinese: "成本 Beta 尚未启用",
      .japanese: "コストのベータ機能はオフです",
    ],
    .costsBetaOffBody: [
      .english:
        "Enable it to fetch opt-in official balances and estimate the API-equivalent cost of local CLI usage. Quota behavior will not change.",
      .simplifiedChinese:
        "启用后可获取主动配置的官方余额，并估算本地 CLI 用量的 API 等价成本；额度行为不会改变。",
      .japanese:
        "有効にすると、明示的に設定した正式残高を取得し、ローカル CLI 使用量の API 相当コストを推定します。クォータの動作は変わりません。",
    ],
    .costsEnable: [
      .english: "Enable Costs beta", .simplifiedChinese: "启用成本 Beta",
      .japanese: "コストのベータ機能を有効にする",
    ],
    .costsAuthoritative: [
      .english: "Authoritative balances", .simplifiedChinese: "权威余额",
      .japanese: "正式残高",
    ],
    .costsAuthoritativeHint: [
      .english: "Reported by the provider's official account API.",
      .simplifiedChinese: "由服务商官方账户 API 返回。",
      .japanese: "プロバイダーの正式なアカウント API が返す値です。",
    ],
    .costsNoAuthoritative: [
      .english: "No authoritative cost provider is enabled.",
      .simplifiedChinese: "尚未启用权威成本源。",
      .japanese: "有効な正式コストプロバイダーがありません。",
    ],
    .costsEstimated: [
      .english: "Local estimates", .simplifiedChinese: "本地估算",
      .japanese: "ローカル推定",
    ],
    .costsEstimatedHint: [
      .english: "Seven-day, read-only pricing of supported local CLI transcripts.",
      .simplifiedChinese: "只读扫描支持的本地 CLI 会话，并按近 7 天计价。",
      .japanese: "対応するローカル CLI 履歴を読み取り専用で走査し、直近7日間を価格換算します。",
    ],
    .costsNoEstimates: [
      .english: "No supported local estimate source is available.",
      .simplifiedChinese: "没有可用的本地估算源。",
      .japanese: "利用可能なローカル推定ソースがありません。",
    ],
    .costsSourceOfficialAPI: [
      .english: "Official provider API", .simplifiedChinese: "服务商官方 API",
      .japanese: "プロバイダー正式 API",
    ],
    .costsSourceLocalTranscripts: [
      .english: "Source: local CLI transcripts (read-only)",
      .simplifiedChinese: "来源：本地 CLI 会话（只读）",
      .japanese: "ソース：ローカル CLI 履歴（読み取り専用）",
    ],
    .costsEstimatedLabel: [
      .english: "Estimated/API-equivalent", .simplifiedChinese: "Estimated/API-equivalent",
      .japanese: "Estimated/API-equivalent",
    ],
    .costsAvailable: [
      .english: "Available", .simplifiedChinese: "可用余额", .japanese: "利用可能",
    ],
    .costsPurchased: [
      .english: "Purchased / credited", .simplifiedChinese: "已购买 / 已入账",
      .japanese: "購入・付与済み",
    ],
    .costsUsed: [
      .english: "Authoritative usage", .simplifiedChinese: "权威累计用量",
      .japanese: "正式な累計使用額",
    ],
    .costsProviderUnavailable: [
      .english: "The provider reports that this balance is currently unavailable.",
      .simplifiedChinese: "服务商报告当前余额不可用。",
      .japanese: "プロバイダーは、この残高が現在利用できないと報告しています。",
    ],
    .costsUpdatedFormat: [
      .english: "Updated %@", .simplifiedChinese: "更新于 %@", .japanese: "%@ に更新",
    ],
    .costsPeriodFormat: [
      .english: "Period: %@ – %@", .simplifiedChinese: "周期：%@ 至 %@",
      .japanese: "期間：%@〜%@",
    ],
    .costsCatalogFormat: [
      .english: "Pricing catalog %@ · effective %@",
      .simplifiedChinese: "价格目录 %@ · 生效于 %@",
      .japanese: "価格カタログ %@・発効 %@",
    ],
    .costsUnknownModelsFormat: [
      .english: "%lld unpriced model(s) excluded",
      .simplifiedChinese: "已排除 %lld 个未定价模型",
      .japanese: "価格未設定のモデル %lld 件を除外",
    ],
    .costsDailySpend: [
      .english: "Daily spend", .simplifiedChinese: "当日支出", .japanese: "日次支出",
    ],
    .costsWeeklySpend: [
      .english: "Weekly spend", .simplifiedChinese: "每周支出", .japanese: "週次支出",
    ],
    .costsMonthlySpend: [
      .english: "Monthly spend", .simplifiedChinese: "每月支出", .japanese: "月次支出",
    ],
    .costsLifetimeSpend: [
      .english: "Lifetime spend", .simplifiedChinese: "累计支出", .japanese: "累計支出",
    ],
    .costsNoData: [
      .english: "No cost snapshot yet.", .simplifiedChinese: "还没有成本快照。",
      .japanese: "コストスナップショットはまだありません。",
    ],
    .costsAssumedCache: [
      .english: "Cache writes without a duration use the five-minute rate.",
      .simplifiedChinese: "未标注时长的缓存写入按 5 分钟价格估算。",
      .japanese: "期間が不明なキャッシュ書き込みには5分料金を使用しています。",
    ],
    .costsPartialScanFormat: [
      .english: "Partial local scan: %lld file(s), %lld record(s) skipped.",
      .simplifiedChinese: "本地扫描不完整：跳过 %lld 个文件、%lld 条记录。",
      .japanese: "ローカル走査は一部のみ：%lld ファイル、%lld レコードをスキップ。",
    ],
    .costsPartialSource: [
      .english: "The provider returned only part of the authoritative cost data.",
      .simplifiedChinese: "服务商仅返回了部分权威成本数据。",
      .japanese: "プロバイダーから正式コストデータの一部だけが返されました。",
    ],
    .costsUnpricedModel: [
      .english: "An unpriced model was excluded from the estimate.",
      .simplifiedChinese: "估算中排除了未定价模型。",
      .japanese: "価格未設定のモデルを推定から除外しました。",
    ],
    .costsInvalidTokenCount: [
      .english: "A record with an invalid token count was excluded from the estimate.",
      .simplifiedChinese: "估算中排除了一条令 Token 计数溢出的记录。",
      .japanese: "トークン数が不正なレコードを推定から除外しました。",
    ],
    .costsCalculationDetails: [
      .english: "How this estimate is calculated",
      .simplifiedChinese: "此估算的计算方式",
      .japanese: "この推定の計算方法",
    ],
    .costsCalculationIntro: [
      .english:
        "Each supported record is priced before aggregation. Category amounts below include any request-level long-context multiplier.",
      .simplifiedChinese: "每条受支持的记录会先计价再汇总；下方各类别金额已包含适用的单次请求长上下文倍率。",
      .japanese:
        "対応する各レコードを集計前に価格換算します。以下のカテゴリ金額には、該当するリクエスト単位の長文コンテキスト倍率が含まれます。",
    ],
    .costsNoPricedModels: [
      .english: "No priced model records are included in this total.",
      .simplifiedChinese: "此合计中没有已定价的模型记录。",
      .japanese: "この合計には価格設定済みモデルのレコードがありません。",
    ],
    .costsPricedRecordsFormat: [
      .english: "%lld priced record(s) · %lld used long-context pricing",
      .simplifiedChinese: "%lld 条已计价记录 · %lld 条使用长上下文价格",
      .japanese: "%lld 件を価格換算・%lld 件に長文コンテキスト料金を適用",
    ],
    .costsEffectiveRateFormat: [
      .english: "%@ tokens · effective %@ / 1M",
      .simplifiedChinese: "%@ tokens · 有效价格 %@ / 1M",
      .japanese: "%@ tokens・実効料金 %@ / 1M",
    ],
    .costsCatalogRates: [
      .english: "Reviewed catalog rates", .simplifiedChinese: "已审核的目录价格",
      .japanese: "レビュー済みカタログ料金",
    ],
    .costsRatePerMillionFormat: [
      .english: "%@ / 1M tokens", .simplifiedChinese: "%@ / 1M tokens",
      .japanese: "%@ / 1M tokens",
    ],
    .costsUncachedInput: [
      .english: "Uncached input", .simplifiedChinese: "未缓存输入", .japanese: "未キャッシュ入力",
    ],
    .costsCacheRead: [
      .english: "Cache read", .simplifiedChinese: "缓存读取", .japanese: "キャッシュ読み取り",
    ],
    .costsCacheWrite: [
      .english: "Cache write", .simplifiedChinese: "缓存写入", .japanese: "キャッシュ書き込み",
    ],
    .costsCacheWriteFiveMinute: [
      .english: "Cache write (5 min)", .simplifiedChinese: "缓存写入（5 分钟）",
      .japanese: "キャッシュ書き込み（5分）",
    ],
    .costsCacheWriteOneHour: [
      .english: "Cache write (1 hour)", .simplifiedChinese: "缓存写入（1 小时）",
      .japanese: "キャッシュ書き込み（1時間）",
    ],
    .costsOutput: [
      .english: "Output", .simplifiedChinese: "输出", .japanese: "出力",
    ],
    .costsLongContextRuleFormat: [
      .english: "Above %@ input tokens: input × %@ · output × %@",
      .simplifiedChinese: "输入超过 %@ tokens：输入 × %@ · 输出 × %@",
      .japanese: "入力が %@ tokens を超える場合：入力 × %@・出力 × %@",
    ],
    .costsPricingSource: [
      .english: "Open reviewed pricing source", .simplifiedChinese: "打开已审核价格来源",
      .japanese: "レビュー済み料金ソースを開く",
    ],
    .costsExcludedModels: [
      .english: "Excluded unpriced models", .simplifiedChinese: "已排除的未定价模型",
      .japanese: "除外した価格未設定モデル",
    ],
    .costsExcludedModelsHint: [
      .english: "These locally observed model IDs are not included in the displayed total.",
      .simplifiedChinese: "这些在本地观察到的模型 ID 未计入显示的合计。",
      .japanese: "ローカルで検出した以下のモデル ID は、表示中の合計に含まれません。",
    ],
    .quotaLeft: [.english: "left", .simplifiedChinese: "剩余", .japanese: "残り"],
    .quotaRemaining: [
      .english: "remaining", .simplifiedChinese: "剩余", .japanese: "残り",
    ],
    .quotaWaitingFirst: [
      .english: "Waiting for the first quota snapshot.",
      .simplifiedChinese: "正在等待第一次额度快照。",
      .japanese: "最初のクォータスナップショットを待っています。",
    ],
    .quotaNoSnapshot: [
      .english: "No quota snapshot yet", .simplifiedChinese: "还没有额度快照",
      .japanese: "クォータスナップショットはまだありません",
    ],
    .quotaExpiredCacheFetched: [
      .english: "Expired cache · fetched %@",
      .simplifiedChinese: "缓存已过期 · 抓取于 %@",
      .japanese: "期限切れのキャッシュ・%@ に取得",
    ],
    .quotaExpiredCacheFrom: [
      .english: "Expired cache from %@",
      .simplifiedChinese: "缓存已过期，抓取于 %@",
      .japanese: "%@ に取得した期限切れのキャッシュ",
    ],
    .quotaStaleFetched: [
      .english: "Stale · fetched %@", .simplifiedChinese: "已过期 · 抓取于 %@",
      .japanese: "古いデータ・%@ に取得",
    ],
    .quotaResetsAt: [
      .english: "Resets %@", .simplifiedChinese: "重置时间：%@",
      .japanese: "リセット：%@",
    ],
    .quotaUpdatedAt: [
      .english: "Updated %@", .simplifiedChinese: "更新于 %@", .japanese: "%@ に更新",
    ],
    .quotaResetUnavailable: [
      .english: "Reset time unavailable", .simplifiedChinese: "重置时间未知",
      .japanese: "リセット時刻は不明です",
    ],
    .quotaBurnEta: [
      .english: "Runs out in ~%@ at this pace",
      .simplifiedChinese: "按当前速度约 %@ 后耗尽",
      .japanese: "このペースではあと約 %@ で枯渇",
    ],
    .phaseDisabled: [.english: "Disabled", .simplifiedChinese: "已停用", .japanese: "無効"],
    .phaseMissingCredential: [
      .english: "Credential needed", .simplifiedChinese: "需要凭据",
      .japanese: "認証情報が必要です",
    ],
    .phaseRefreshing: [
      .english: "Refreshing", .simplifiedChinese: "刷新中", .japanese: "更新中",
    ],
    .phaseHealthy: [.english: "Live", .simplifiedChinese: "正常", .japanese: "最新"],
    .phaseStale: [.english: "Stale", .simplifiedChinese: "已过期", .japanese: "古い"],
    .phaseError: [
      .english: "Unavailable", .simplifiedChinese: "不可用", .japanese: "利用不可",
    ],
    .deviceUnbound: [
      .english: "Not bound", .simplifiedChinese: "未绑定", .japanese: "未バインド",
    ],
    .deviceDisconnected: [
      .english: "Disconnected", .simplifiedChinese: "已断开", .japanese: "切断",
    ],
    .deviceScanning: [
      .english: "Scanning", .simplifiedChinese: "扫描中", .japanese: "スキャン中",
    ],
    .deviceConnecting: [
      .english: "Connecting", .simplifiedChinese: "连接中", .japanese: "接続中",
    ],
    .deviceConnected: [
      .english: "Connected", .simplifiedChinese: "已连接", .japanese: "接続済み",
    ],
    .deviceSyncing: [.english: "Syncing", .simplifiedChinese: "同步中", .japanese: "同期中"],
    .deviceSynced: [
      .english: "Synced", .simplifiedChinese: "已同步", .japanese: "同期済み",
    ],
    .deviceStale: [
      .english: "Sync stale", .simplifiedChinese: "同步过期", .japanese: "同期が古い",
    ],
    .overviewTitle: [
      .english: "Coding quota, at a glance",
      .simplifiedChinese: "编程额度，一目了然",
      .japanese: "コーディングクォータを一目で",
    ],
    .overviewSubtitle: [
      .english: "A local control plane for your coding plans and M5Stack StopWatch.",
      .simplifiedChinese: "为你的编程套餐和 M5Stack StopWatch 提供本地管控中枢。",
      .japanese: "コーディングプランと M5Stack StopWatch のローカルコントロールプレーン。",
    ],
    .overviewMostConstrained: [
      .english: "Most constrained window",
      .simplifiedChinese: "最紧张的额度窗口",
      .japanese: "最も厳しいウィンドウ",
    ],
    .overviewMostConstrainedHint: [
      .english: "Plan work around the quota with the least headroom.",
      .simplifiedChinese: "请围绕余量最小的额度安排工作。",
      .japanese: "余裕の最も少ないクォータに合わせて作業を計画しましょう。",
    ],
    .overviewWatchSubtitle: [
      .english: "Firmware v1 compatibility · Codex primary window only",
      .simplifiedChinese: "固件 v1 兼容模式 · 仅同步 Codex 主窗口",
      .japanese: "ファームウェア v1 互換・Codex プライマリウィンドウのみ",
    ],
    .watchSubtitle: [
      .english:
        "Bind one M5Stack device, negotiate protocol v1 or v2, and sync selected coding-plan quota.",
      .simplifiedChinese: "绑定一台 M5Stack 设备，协商协议 v1 或 v2，并同步所选编程套餐额度。",
      .japanese: "M5Stack デバイスを 1 台バインドし、プロトコル v1 / v2 をネゴシエートして選択したクォータを同期します。",
    ],
    .watchCompatTitle: [
      .english: "Versioned protocol with v1 fallback",
      .simplifiedChinese: "版本化协议与 v1 回退",
      .japanese: "バージョン付きプロトコルと v1 フォールバック",
    ],
    .watchCompatBody: [
      .english:
        "Protocol v2 adds selected-provider rotation, settings, and work items. Existing v1 firmware still receives only the unchanged Codex payload.",
      .simplifiedChinese:
        "协议 v2 增加所选额度源轮转、表盘设置和工作单元；现有 v1 固件仍只接收完全不变的 Codex payload。",
      .japanese:
        "プロトコル v2 は選択プロバイダーのローテーション、設定、作業ユニットを追加します。既存の v1 ファームウェアは従来どおり Codex ペイロードのみを受信します。",
    ],
    .watchBoundDevice: [
      .english: "Bound device", .simplifiedChinese: "已绑定设备",
      .japanese: "バインド済みデバイス",
    ],
    .watchNoBoundDevice: [
      .english: "No StopWatch bound", .simplifiedChinese: "未绑定 StopWatch",
      .japanese: "StopWatch はバインドされていません",
    ],
    .watchRebindTitle: [
      .english: "Bind the StopWatch once for the new TokenLink identity",
      .simplifiedChinese: "请为新的 TokenLink 身份重新绑定一次 StopWatch",
      .japanese: "新しい TokenLink ID で StopWatch を一度再バインドしてください",
    ],
    .watchRebindBody: [
      .english:
        "TokenLink 0.2.1 now uses app.tokenlink. The previous app identity's Bluetooth device identifier was cleared because macOS may scope it to that identity. Press Scan, review the Bluetooth prompt, allow nearby-device access, then bind this C152 again. This permission covers Bluetooth discovery, connection, quota sync, and watch commands; it does not grant Keychain access.",
      .simplifiedChinese:
        "TokenLink 0.2.1 现在统一使用 app.tokenlink。由于 macOS 可能按应用身份隔离蓝牙设备标识，旧身份保存的标识已被清除。请按“扫描”，阅读蓝牙弹窗并允许附近设备访问，然后重新绑定这台 C152。该权限仅用于蓝牙发现、连接、额度同步和手表命令，不包含钥匙串访问。",
      .japanese:
        "TokenLink 0.2.1 は app.tokenlink に統一されました。macOS は Bluetooth デバイス識別子をアプリ ID ごとに分離する場合があるため、以前の ID で保存した識別子を消去しました。「スキャン」を押して Bluetooth の説明を確認し、周辺デバイスへのアクセスを許可してから、この C152 を再度バインドしてください。この権限は Bluetooth の検出、接続、クォータ同期、ウォッチコマンドにのみ使用され、キーチェーンへのアクセスは含みません。",
    ],
    .watchSyncNow: [
      .english: "Sync watch now", .simplifiedChinese: "立即同步手表",
      .japanese: "ウォッチを今すぐ同期",
    ],
    .watchUnbind: [.english: "Unbind", .simplifiedChinese: "解绑", .japanese: "バインド解除"],
    .watchUnboundMessage: [
      .english: "StopWatch unbound.", .simplifiedChinese: "已解绑 StopWatch。",
      .japanese: "StopWatch のバインドを解除しました。",
    ],
    .watchBoundMessage: [
      .english: "StopWatch bound.", .simplifiedChinese: "已绑定 StopWatch。",
      .japanese: "StopWatch をバインドしました。",
    ],
    .watchDiscoverTitle: [
      .english: "Discover nearby devices", .simplifiedChinese: "发现附近的设备",
      .japanese: "近くのデバイスを検出",
    ],
    .watchDiscoverNote: [
      .english:
        "Discovery starts only when you press Scan. Results are not retained after binding.",
      .simplifiedChinese: "只有按下“扫描”才会开始发现设备，绑定后不保留结果。",
      .japanese: "検出は「スキャン」を押したときだけ開始されます。結果はバインド後に保持されません。",
    ],
    .watchScanning: [
      .english: "Scanning…", .simplifiedChinese: "扫描中…", .japanese: "スキャン中…",
    ],
    .watchScan: [.english: "Scan", .simplifiedChinese: "扫描", .japanese: "スキャン"],
    .watchBindSelected: [
      .english: "Bind selected device", .simplifiedChinese: "绑定所选设备",
      .japanese: "選択したデバイスをバインド",
    ],
    .settingsTitle: [
      .english: "Settings & Diagnostics", .simplifiedChinese: "设置与诊断",
      .japanese: "設定と診断",
    ],
    .settingsSubtitle: [
      .english: "Tune refresh behavior and export a redacted support snapshot.",
      .simplifiedChinese: "调整刷新行为，并导出脱敏后的诊断快照。",
      .japanese: "更新動作を調整し、マスク済みのサポートスナップショットを書き出します。",
    ],
    .settingsGeneral: [.english: "General", .simplifiedChinese: "通用", .japanese: "一般"],
    .settingsRefreshInterval: [
      .english: "Refresh interval", .simplifiedChinese: "刷新间隔",
      .japanese: "更新間隔",
    ],
    .settingsMinutes: [
      .english: "%lld min", .simplifiedChinese: "%lld 分钟", .japanese: "%lld 分",
    ],
    .settingsLaunchAtLogin: [
      .english: "Launch at login", .simplifiedChinese: "登录时启动",
      .japanese: "ログイン時に起動",
    ],
    .settingsLoginApproval: [
      .english: "Approval is required in System Settings → General → Login Items.",
      .simplifiedChinese: "需要在“系统设置 → 通用 → 登录项”中批准。",
      .japanese: "「システム設定 → 一般 → ログイン項目」での承認が必要です。",
    ],
    .settingsPrivacyTitle: [
      .english: "Privacy boundary", .simplifiedChinese: "隐私边界",
      .japanese: "プライバシー境界",
    ],
    .settingsPrivacyBody: [
      .english:
        "API keys live in macOS Keychain. TokenLink may reuse the current Kimi Code CLI access token from its documented file, but never reads browser cookies, refresh tokens, or unrelated credential stores. Full Disk Access is not required.",
      .simplifiedChinese:
        "API key 只存放在 macOS 钥匙串中。TokenLink 可能会复用 Kimi Code CLI 官方文件中当前有效的访问令牌，但绝不读取浏览器 Cookie、刷新令牌或任何无关的凭据存储，也不需要完全磁盘访问权限。",
      .japanese:
        "API キーは macOS キーチェーンにのみ保存されます。TokenLink は Kimi Code CLI の正式なファイルから現在有効なアクセストークンを再利用できますが、ブラウザの Cookie、リフレッシュトークン、無関係な認証情報ストアは一切読み取りません。フルディスクアクセスも不要です。",
    ],
    .settingsDiagnostics: [
      .english: "Diagnostics", .simplifiedChinese: "诊断", .japanese: "診断",
    ],
    .settingsDiagnosticsBody: [
      .english:
        "Exports provider phases, percentages, timestamps, device state, and recent events. Paths, usernames, account labels, UUIDs, and secret-like fields are redacted before writing.",
      .simplifiedChinese:
        "导出各额度源状态、百分比、时间戳、设备状态和最近事件。写入前会脱敏路径、用户名、账户标签、UUID 和疑似密钥的字段。",
      .japanese:
        "プロバイダーの状態、割合、タイムスタンプ、デバイス状態、最近のイベントを書き出します。パス、ユーザー名、アカウントラベル、UUID、秘密情報らしきフィールドは書き出し前にマスクされます。",
    ],
    .settingsExportDiagnostics: [
      .english: "Export redacted diagnostics…",
      .simplifiedChinese: "导出脱敏诊断…",
      .japanese: "マスク済み診断を書き出す…",
    ],
    .settingsExportPanelTitle: [
      .english: "Export TokenLink Diagnostics",
      .simplifiedChinese: "导出 TokenLink 诊断",
      .japanese: "TokenLink 診断を書き出す",
    ],
    .settingsExported: [
      .english: "Diagnostics exported to %@.",
      .simplifiedChinese: "诊断已导出到 %@。",
      .japanese: "診断を %@ に書き出しました。",
    ],
    .settingsRecentEvents: [
      .english: "Recent events", .simplifiedChinese: "最近事件", .japanese: "最近のイベント",
    ],
    .settingsNoEvents: [
      .english: "No events recorded yet.", .simplifiedChinese: "还没有事件记录。",
      .japanese: "記録されたイベントはまだありません。",
    ],
    .settingsLanguage: [.english: "Language", .simplifiedChinese: "语言", .japanese: "言語"],
    .settingsNotifications: [
      .english: "Notifications", .simplifiedChinese: "系统通知",
      .japanese: "通知",
    ],
    .settingsFairPace: [
      .english: "Fair-pace reference", .simplifiedChinese: "合理用量参考线",
      .japanese: "適正ペースの目安",
    ],
    .settingsBetaTitle: [
      .english: "Beta", .simplifiedChinese: "Beta 功能", .japanese: "ベータ機能",
    ],
    .betaLocalUsage: [
      .english: "Local usage observation",
      .simplifiedChinese: "本地用量观测",
      .japanese: "ローカル使用量の観測",
    ],
    .betaLocalUsageHint: [
      .english:
        "Read-only scan of local CLI transcripts (Codex / Claude / Kimi) to estimate token consumption for the last 7 days — useful for cross-checking provider-reported quota. Data never leaves this Mac.",
      .simplifiedChinese:
        "只读扫描本机 CLI 会话记录（Codex / Claude / Kimi），估算近 7 天的 token 消耗，用于和上游额度对账。数据不出本机。",
      .japanese:
        "ローカル CLI のセッション記録（Codex / Claude / Kimi）を読み取り専用でスキャンし、直近7日間のトークン消費量を推定します。プロバイダー報告のクォータとの照合に使えます。データはこの Mac から出ません。",
    ],
    .betaScanNow: [
      .english: "Scan now", .simplifiedChinese: "立即扫描", .japanese: "今すぐスキャン",
    ],
    .betaScanning: [
      .english: "Scanning…", .simplifiedChinese: "扫描中…", .japanese: "スキャン中…",
    ],
    .betaNoTranscripts: [
      .english: "No local transcripts found for the supported CLIs.",
      .simplifiedChinese: "没有找到支持的 CLI 本地会话记录。",
      .japanese: "対応する CLI のローカルセッション記録が見つかりません。",
    ],
    .betaCosts: [
      .english: "Costs", .simplifiedChinese: "成本", .japanese: "コスト",
    ],
    .betaCostsHint: [
      .english:
        "Fetch official balances only for explicitly configured cost providers and estimate local API-equivalent cost separately. Quota remains the primary feature.",
      .simplifiedChinese:
        "仅为明确配置的成本源获取官方余额，并独立估算本地 API 等价成本；额度始终是首要能力。",
      .japanese:
        "明示的に設定したコストプロバイダーだけ正式残高を取得し、ローカルの API 相当コストは別に推定します。クォータが常に主機能です。",
    ],
    .betaCostsMetric: [
      .english: "Menu bar cost metric", .simplifiedChinese: "菜单栏成本指标",
      .japanese: "メニューバーのコスト指標",
    ],
    .betaCostsMetricHint: [
      .english:
        "One fixed metric appears after the primary quota; missing data falls back to quota only.",
      .simplifiedChinese: "固定选择一个指标显示在主额度之后；数据缺失时仅显示额度。",
      .japanese: "固定した1つの指標を主クォータの後に表示し、データがない場合はクォータだけに戻ります。",
    ],
    .costMetricNone: [
      .english: "Quota only", .simplifiedChinese: "仅显示额度", .japanese: "クォータのみ",
    ],
    .costMetricLocalFormat: [
      .english: "%@ · Estimated 7d", .simplifiedChinese: "%@ · 近 7 天估算",
      .japanese: "%@・7日間推定",
    ],
    .costMetricBalanceFormat: [
      .english: "%@ · %@ balance", .simplifiedChinese: "%@ · %@ 余额",
      .japanese: "%@・%@ 残高",
    ],
    .watchFaceTitle: [
      .english: "Watch face (protocol v2)", .simplifiedChinese: "表盘（协议 v2）",
      .japanese: "ウォッチフェイス（プロトコル v2）",
    ],
    .watchSyncProviders: [
      .english: "Providers synced to the watch",
      .simplifiedChinese: "同步到手表的额度源",
      .japanese: "ウォッチに同期するプロバイダー",
    ],
    .watchTheme: [
      .english: "Face theme", .simplifiedChinese: "表盘主题", .japanese: "テーマ",
    ],
    .watchThemeData: [
      .english: "Data", .simplifiedChinese: "数据", .japanese: "データ",
    ],
    .watchThemePet: [
      .english: "Pet", .simplifiedChinese: "宠物", .japanese: "ペット",
    ],
    .watchWake: [
      .english: "Wake", .simplifiedChinese: "唤醒方式", .japanese: "起動方法",
    ],
    .watchWakeRaise: [
      .english: "Raise to wake", .simplifiedChinese: "抬腕唤醒",
      .japanese: "手首を上げて起動",
    ],
    .watchWakeTap: [
      .english: "Tap only", .simplifiedChinese: "仅点按唤醒",
      .japanese: "タップのみ",
    ],
    .watchHourFormat: [
      .english: "Hour format", .simplifiedChinese: "时间格式", .japanese: "時刻形式",
    ],
    .watchHourSystem: [
      .english: "System", .simplifiedChinese: "跟随系统", .japanese: "システムに従う",
    ],
    .watchWorkItems: [
      .english: "Work items", .simplifiedChinese: "工作单元", .japanese: "作業ユニット",
    ],
    .watchNoWorkItems: [
      .english: "No active sessions yet.",
      .simplifiedChinese: "暂无活跃会话。",
      .japanese: "アクティブなセッションはまだありません。",
    ],
    .watchPayloadPreview: [
      .english: "Last payload sent",
      .simplifiedChinese: "最近发送的 payload",
      .japanese: "最後に送信したペイロード",
    ],
    .watchNegotiated: [
      .english: "Negotiated protocol: %@",
      .simplifiedChinese: "协商协议：%@",
      .japanese: "ネゴシエート済みプロトコル：%@",
    ],
    .watchV1Note: [
      .english: "The bound firmware speaks protocol v1 and only receives Codex.",
      .simplifiedChinese: "当前绑定固件为协议 v1，只接收 Codex 额度。",
      .japanese: "バインドされたファームウェアはプロトコル v1 で、Codex のみを受信します。",
    ],
    .watchFaceHint: [
      .english:
        "Settings are stored on this Mac and included in the next v2 payload. When a compatible watch is connected, changes are sent immediately.",
      .simplifiedChinese: "设置保存在本机并写入下一条 v2 payload；兼容手表已连接时会立即下发。",
      .japanese:
        "設定はこの Mac に保存され、次の v2 ペイロードに含まれます。対応ウォッチの接続中は変更がすぐ送信されます。",
    ],
    .watchHour12: [
      .english: "12-hour", .simplifiedChinese: "12 小时制", .japanese: "12 時間表示",
    ],
    .watchHour24: [
      .english: "24-hour", .simplifiedChinese: "24 小时制", .japanese: "24 時間表示",
    ],
    .watchWorkItemName: [
      .english: "Short name", .simplifiedChinese: "短名称", .japanese: "短い名前",
    ],
    .watchFocusNote: [
      .english:
        "Selecting a Codex item on the watch sends its matching task link over the protocol-v2 C04 channel. Use the arrow button to test the same link directly on this Mac; TokenLink shows the last outcome below.",
      .simplifiedChinese:
        "在手表选择 Codex 工作单元会通过协议 v2 的 C04 通道发送对应任务链接。可点击箭头按钮直接在这台 Mac 上测试同一链接；TokenLink 会在下方显示最近结果。",
      .japanese:
        "ウォッチで Codex の作業ユニットを選ぶと、プロトコル v2 の C04 チャネルで対応するタスクリンクを送ります。矢印ボタンで同じリンクをこの Mac から直接テストでき、直近の結果が下に表示されます。",
    ],
    .watchNoPayload: [
      .english: "No payload has been sent in this session.",
      .simplifiedChinese: "本次运行尚未发送 payload。",
      .japanese: "このセッションではまだペイロードを送信していません。",
    ],
    .watchNotNegotiated: [
      .english: "not connected", .simplifiedChinese: "尚未连接", .japanese: "未接続",
    ],
    .settingsFairPaceHint: [
      .english:
        "Marks where each window would be at an even pace (e.g. 6/7 left one day into a weekly window).",
      .simplifiedChinese: "在额度条上标出均匀消耗的参考位置（例如 7 天窗口过 1 天时应剩 6/7）。",
      .japanese: "均等に消費した場合の基準位置をバーに表示します（例：週次ウィンドウ1日目で残り6/7）。",
    ],
    .notifyLowQuotaTitle: [
      .english: "Quota running low", .simplifiedChinese: "额度即将耗尽",
      .japanese: "クォータが残りわずか",
    ],
    .notifyLowQuotaBody: [
      .english: "%@ has %d%% remaining in its most constrained window.",
      .simplifiedChinese: "%@ 最紧张的窗口只剩 %d%%。",
      .japanese: "%@ の最も厳しいウィンドウの残りは %d%% です。",
    ],
    .notifyAuthFailureTitle: [
      .english: "Credential rejected", .simplifiedChinese: "凭据失效",
      .japanese: "認証情報が拒否されました",
    ],
    .notifyAuthFailureBody: [
      .english: "%@ rejected its stored credential. Update it in Control Center.",
      .simplifiedChinese: "%@ 拒绝了已保存的凭据，请在控制中心更新。",
      .japanese: "%@ が保存済みの認証情報を拒否しました。コントロールセンターで更新してください。",
    ],
    .notifyResetTitle: [
      .english: "Quota window reset", .simplifiedChinese: "额度窗口已重置",
      .japanese: "クォータウィンドウがリセットされました",
    ],
    .notifyResetBody: [
      .english: "%@ · %@ has reset.", .simplifiedChinese: "%@ 的 %@ 已重置。",
      .japanese: "%@ の %@ がリセットされました。",
    ],
    .languageSystem: [
      .english: "System", .simplifiedChinese: "跟随系统", .japanese: "システムに従う",
    ],
    .languageEnglish: [
      .english: "English", .simplifiedChinese: "English", .japanese: "English",
    ],
    .languageChinese: [
      .english: "中文（简体）", .simplifiedChinese: "中文（简体）", .japanese: "中文（简体）",
    ],
    .languageJapanese: [
      .english: "日本語", .simplifiedChinese: "日本語", .japanese: "日本語",
    ],
    .providersTitle: [
      .english: "Providers", .simplifiedChinese: "额度源", .japanese: "プロバイダー",
    ],
    .providersSubtitle: [
      .english: "Keys are written to macOS Keychain and are never read back into these fields.",
      .simplifiedChinese: "密钥只会写入 macOS 钥匙串，绝不会再回显到输入框中。",
      .japanese: "キーは macOS キーチェーンに書き込まれ、これらのフィールドに再表示されることはありません。",
    ],
    .providersRestartBanner: [
      .english: "Provider enablement and Codex path changes apply after restarting TokenLink.",
      .simplifiedChinese: "额度源启用状态和 Codex 路径的修改将在重启 TokenLink 后生效。",
      .japanese: "プロバイダーの有効化と Codex パスの変更は TokenLink の再起動後に適用されます。",
    ],
    .providersLegacyMigrationTitle: [
      .english: "Upgrade from TokenLink 0.2.0?",
      .simplifiedChinese: "从 TokenLink 0.2.0 升级？",
      .japanese: "TokenLink 0.2.0 からアップグレードしますか？",
    ],
    .providersLegacyMigrationNote: [
      .english:
        "TokenLink no longer reads its old Keychain service automatically. Review the scope before copying any saved provider keys, or dismiss this if you are not upgrading.",
      .simplifiedChinese:
        "TokenLink 不再自动读取旧钥匙串 service。复制已有 provider key 前请先确认授权范围；如果不是升级安装，可以忽略。",
      .japanese:
        "TokenLink は旧キーチェーンサービスを自動では読み取りません。保存済みプロバイダーキーをコピーする前に範囲を確認してください。新規インストールの場合は閉じられます。",
    ],
    .providersLegacyMigrationAction: [
      .english: "Review and migrate…", .simplifiedChinese: "查看说明并迁移…",
      .japanese: "確認して移行…",
    ],
    .providersLegacyMigrationDismiss: [
      .english: "Don't migrate", .simplifiedChinese: "不迁移", .japanese: "移行しない",
    ],
    .providersLegacyMigrationAuthorizationTitle: [
      .english: "Allow one-time access to old TokenLink credentials?",
      .simplifiedChinese: "允许一次性访问旧 TokenLink 凭据？",
      .japanese: "旧 TokenLink 認証情報への一時アクセスを許可しますか？",
    ],
    .providersLegacyMigrationAuthorizationExplanation: [
      .english:
        "The next step checks only configured Kimi, MiniMax, and GLM items under the old internal service ‘io.github.phantom5125.tokenlink.provider’, which belonged to TokenLink 0.2.0. macOS may ask separately for each stored item. TokenLink copies found keys into its new service and keeps the old items as a safety fallback; it does not access Claude Code or any unrelated Keychain item. This is a one-time migration, so Allow is sufficient—Always Allow is unnecessary.",
      .simplifiedChinese:
        "下一步只会检查旧内部 service“io.github.phantom5125.tokenlink.provider”下已配置的 Kimi、MiniMax 和 GLM 条目；这个名称来自 TokenLink 0.2.0。macOS 可能会针对每个已有条目分别询问。TokenLink 会把找到的 key 复制到新 service，并保留旧条目作为安全备份；不会访问 Claude Code 或任何无关钥匙串条目。这是一次性迁移，点“允许”即可，无需点“始终允许”。",
      .japanese:
        "次の操作では、TokenLink 0.2.0 が使用していた旧内部サービス ‘io.github.phantom5125.tokenlink.provider’ にある設定済み Kimi、MiniMax、GLM 項目だけを確認します。保存項目ごとに macOS が許可を求める場合があります。見つかったキーは新サービスへコピーし、安全のため旧項目も残します。Claude Code や無関係なキーチェーン項目にはアクセスしません。1 回限りの移行なので「許可」で十分で、「常に許可」は不要です。",
    ],
    .providersLegacyMigrationSucceeded: [
      .english: "Migrated %ld legacy credential item(s).",
      .simplifiedChinese: "已迁移 %ld 个旧凭据条目。",
      .japanese: "%ld 件の旧認証情報を移行しました。",
    ],
    .providersLegacyMigrationNone: [
      .english: "No legacy TokenLink credentials were found.",
      .simplifiedChinese: "未找到旧 TokenLink 凭据。",
      .japanese: "旧 TokenLink 認証情報は見つかりませんでした。",
    ],
    .providersEnabled: [.english: "Enabled", .simplifiedChinese: "启用", .japanese: "有効"],
    .providersCodexExecutable: [
      .english: "Codex executable", .simplifiedChinese: "Codex 可执行文件",
      .japanese: "Codex 実行ファイル",
    ],
    .providersCodexPathPlaceholder: [
      .english: "Auto-detect from PATH", .simplifiedChinese: "从 PATH 自动检测",
      .japanese: "PATH から自動検出",
    ],
    .providersCodexNote: [
      .english: "Uses the local `codex app-server`; no Codex API key is stored by TokenLink.",
      .simplifiedChinese: "使用本机 Codex CLI 登录态（`codex app-server`），TokenLink 不保存 Codex API key。",
      .japanese:
        "ローカルの Codex CLI ログイン状態（`codex app-server`）を使用します。TokenLink は Codex API キーを保存しません。",
    ],
    .providersCredential: [.english: "Credential", .simplifiedChinese: "凭据", .japanese: "認証情報"],
    .providersConfigured: [
      .english: "Configured", .simplifiedChinese: "已配置", .japanese: "設定済み",
    ],
    .providersNotConfigured: [
      .english: "Not configured", .simplifiedChinese: "未配置", .japanese: "未設定",
    ],
    .providersReplaceKey: [
      .english: "Replace API key", .simplifiedChinese: "更换 API key",
      .japanese: "API キーを更新",
    ],
    .providersKeyPlaceholder: [
      .english: "Paste a new key", .simplifiedChinese: "粘贴新密钥",
      .japanese: "新しいキーを貼り付け",
    ],
    .providersRegion: [.english: "Region", .simplifiedChinese: "区域", .japanese: "リージョン"],
    .regionGlobal: [.english: "Global", .simplifiedChinese: "国际版", .japanese: "グローバル"],
    .regionChina: [.english: "China", .simplifiedChinese: "中国版", .japanese: "中国"],
    .regionGlobalZAI: [
      .english: "Global (Z.AI)", .simplifiedChinese: "国际版（Z.AI）",
      .japanese: "グローバル（Z.AI）",
    ],
    .regionChinaBigModel: [
      .english: "China (BigModel)", .simplifiedChinese: "中国版（BigModel）",
      .japanese: "中国（BigModel）",
    ],
    .providersKimiCLINote: [
      .english:
        "If no API key is stored, TokenLink may read the current non-expired Kimi Code CLI access token from its documented credential file. Refresh tokens are never read.",
      .simplifiedChinese:
        "如果没有保存 API key，TokenLink 可以从 Kimi Code CLI 的官方凭据文件读取当前未过期的访问令牌，绝不读取刷新令牌。",
      .japanese:
        "API キーが保存されていない場合、TokenLink は Kimi Code CLI の正式な認証情報ファイルから現在有効なアクセストークンを読み取れます。リフレッシュトークンは一切読み取りません。",
    ],
    .providersKeySaved: [
      .english: "%@ key saved to Keychain.",
      .simplifiedChinese: "%@ 密钥已存入钥匙串。",
      .japanese: "%@ のキーをキーチェーンに保存しました。",
    ],
    .providersKeyDeleted: [
      .english: "%@ key deleted.", .simplifiedChinese: "%@ 密钥已删除。",
      .japanese: "%@ のキーを削除しました。",
    ],
    .providersGetKey: [
      .english: "Get an API key →", .simplifiedChinese: "获取 API Key →",
      .japanese: "API キーを取得 →",
    ],
    .providersDefaultBadge: [
      .english: "Default", .simplifiedChinese: "默认", .japanese: "デフォルト",
    ],
    .providersAddAccount: [
      .english: "Add account (advanced)", .simplifiedChinese: "添加账户（进阶）",
      .japanese: "アカウントを追加（上級者向け）",
    ],
    .providersAddAccountNote: [
      .english:
        "Most users need only one account. Multiple accounts are for running several plans at once; keep track of which quota belongs to which account.",
      .simplifiedChinese: "大多数用户只需一个账户。多账户用于同时挂多个套餐，请注意区分额度归属。",
      .japanese:
        "ほとんどのユーザーは 1 つのアカウントで十分です。複数アカウントは複数プランを同時に運用するためのものです。どのクォータがどのアカウントのものか管理してください。",
    ],
    .providersAccountLabel: [
      .english: "Account label", .simplifiedChinese: "账户名称",
      .japanese: "アカウント名",
    ],
    .providersAccountLabelPlaceholder: [
      .english: "e.g. Work", .simplifiedChinese: "例如：工作",
      .japanese: "例：仕事",
    ],
    .providersDeleteAccount: [
      .english: "Delete account", .simplifiedChinese: "删除账户",
      .japanese: "アカウントを削除",
    ],
    .providersAccountAdded: [
      .english: "%@ account added.", .simplifiedChinese: "已添加 %@ 账户。",
      .japanese: "%@ アカウントを追加しました。",
    ],
    .providersAccountRemoved: [
      .english: "%@ account removed.", .simplifiedChinese: "已删除 %@ 账户。",
      .japanese: "%@ アカウントを削除しました。",
    ],
    .providersCostTitle: [
      .english: "Authoritative cost providers (Beta)",
      .simplifiedChinese: "权威成本源（Beta）",
      .japanese: "正式コストプロバイダー（ベータ）",
    ],
    .providersCostSubtitle: [
      .english: "Opt-in provider balances. Cost refresh remains separate from quota refresh.",
      .simplifiedChinese: "主动配置的服务商余额；成本刷新与额度刷新相互独立。",
      .japanese: "オプトインのプロバイダー残高です。コスト更新はクォータ更新とは別に行われます。",
    ],
    .providersCostBadge: [
      .english: "Authoritative balance · Beta", .simplifiedChinese: "权威余额 · Beta",
      .japanese: "正式残高・ベータ",
    ],
    .providersOpenRouterCostNote: [
      .english:
        "Use an explicit Management Key for account credits; a regular API key may provide only current-key spend.",
      .simplifiedChinese:
        "请显式配置 Management Key 以读取账户余额；普通 API key 可能只能返回当前 key 的支出。",
      .japanese:
        "アカウント残高には Management Key を明示的に設定してください。通常の API キーでは現在のキーの支出しか取得できない場合があります。",
    ],
    .providersDeepSeekCostNote: [
      .english: "Use an explicit DeepSeek API key for authoritative multi-currency balances.",
      .simplifiedChinese: "请显式配置 DeepSeek API key，以读取权威的多币种余额。",
      .japanese: "正式な複数通貨残高には DeepSeek API キーを明示的に設定してください。",
    ],
    .sourceKeychain: [
      .english: "Keychain", .simplifiedChinese: "钥匙串", .japanese: "キーチェーン",
    ],
    .sourceCLI: [.english: "CLI", .simplifiedChinese: "CLI", .japanese: "CLI"],
    .sourceEnvironment: [
      .english: "Environment", .simplifiedChinese: "环境变量", .japanese: "環境変数",
    ],
    .subtitleCodex: [
      .english: "Local app-server", .simplifiedChinese: "本地 app-server",
      .japanese: "ローカル app-server",
    ],
    .subtitleKimi: [
      .english: "Coding Plan usage API or Kimi Code CLI",
      .simplifiedChinese: "Coding Plan 用量 API 或 Kimi Code CLI",
      .japanese: "Coding Plan 使用量 API または Kimi Code CLI",
    ],
    .subtitleMinimax: [
      .english: "Token Plan remains API", .simplifiedChinese: "Token Plan 余量 API",
      .japanese: "Token Plan 残量 API",
    ],
    .subtitleGLM: [
      .english: "Coding Plan quota monitor", .simplifiedChinese: "Coding Plan 额度监控",
      .japanese: "Coding Plan クォータモニター",
    ],
    .subtitleClaude: [
      .english: "Claude Code CLI sign-in",
      .simplifiedChinese: "Claude Code CLI 登录态",
      .japanese: "Claude Code CLI ログイン状態",
    ],
    .providersClaudeNote: [
      .english:
        "TokenLink does not access Claude Code credentials at launch. Enable Claude, then authorize this read explicitly. Anthropic pay-as-you-go keys do not report subscription quota, so there is no API-key field here.",
      .simplifiedChinese:
        "TokenLink 启动时不会访问 Claude Code 凭据。请先启用 Claude，再明确授权读取。Anthropic 按量付费 key 查询不到订阅额度，因此这里不提供 API key 输入框。",
      .japanese:
        "TokenLink は起動時に Claude Code の認証情報へアクセスしません。Claude を有効にしてから、読み取りを明示的に許可してください。従量課金キーではサブスクリプションのクォータを取得できないため、API キー入力欄はありません。",
    ],
    .providersClaudeAuthorize: [
      .english: "Authorize Claude Code…", .simplifiedChinese: "授权 Claude Code…",
      .japanese: "Claude Code を許可…",
    ],
    .providersClaudeAuthorizationTitle: [
      .english: "Allow TokenLink to read Claude Code credentials?",
      .simplifiedChinese: "允许 TokenLink 读取 Claude Code 凭据？",
      .japanese: "TokenLink に Claude Code 認証情報の読み取りを許可しますか？",
    ],
    .providersClaudeAuthorizationExplanation: [
      .english:
        "The next step asks macOS for the entire ‘Claude Code-credentials’ Keychain item—not your whole Keychain. TokenLink uses the access token and expiry for Claude quota; the raw item may also contain a refresh token, which TokenLink does not decode or use. Your Mac password is verified by macOS and is never given to TokenLink. Choose Always Allow only for a TokenLink build you trust and if you want automatic background refresh; Allow Once asks again later.",
      .simplifiedChinese:
        "下一步会请求 macOS 开放完整的“Claude Code-credentials”钥匙串条目，而不是整个钥匙串。TokenLink 使用其中的 access token 和有效期查询 Claude 额度；原始条目可能还含 refresh token，但 TokenLink 不解析也不使用它。Mac 密码只由 macOS 验证，不会交给 TokenLink。只有在你信任当前 TokenLink 构建并希望后台自动刷新时，才建议点“始终允许”；点“允许一次”以后仍会再次询问。",
      .japanese:
        "次の操作では、キーチェーン全体ではなく ‘Claude Code-credentials’ 項目全体へのアクセスを macOS に要求します。TokenLink は Claude クォータ取得にアクセストークンと有効期限を使用します。元の項目にリフレッシュトークンが含まれる場合でも、TokenLink は解析も使用もしません。Mac のパスワードは macOS だけが検証し、TokenLink には渡りません。信頼できる TokenLink ビルドで自動バックグラウンド更新を使う場合のみ「常に許可」を選んでください。「1回だけ許可」では後で再確認されます。",
    ],
    .providersClaudeAuthorized: [
      .english: "TokenLink is set to use the Claude Code credential",
      .simplifiedChinese: "TokenLink 已设为使用 Claude Code 凭据",
      .japanese: "TokenLink は Claude Code 認証情報を使用する設定です",
    ],
    .providersClaudeAuthorizationSucceeded: [
      .english: "Claude Code access authorized. TokenLink can now refresh Claude quota.",
      .simplifiedChinese: "Claude Code 已授权，TokenLink 现在可以刷新 Claude 额度。",
      .japanese: "Claude Code のアクセスを許可しました。Claude クォータを更新できます。",
    ],
    .providersClaudeStopUsing: [
      .english: "Stop using credential", .simplifiedChinese: "停止使用此凭据",
      .japanese: "認証情報の使用を停止",
    ],
    .providersClaudeStopped: [
      .english: "TokenLink will no longer read the Claude Code Keychain item.",
      .simplifiedChinese: "TokenLink 将不再读取 Claude Code 钥匙串条目。",
      .japanese: "TokenLink は Claude Code のキーチェーン項目を読み取らなくなります。",
    ],
    .providersClaudeEnableFirst: [
      .english: "Enable Claude before authorizing its credential.",
      .simplifiedChinese: "请先启用 Claude，再授权凭据。",
      .japanese: "認証情報を許可する前に Claude を有効にしてください。",
    ],
    .providersClaudeCredentialUnavailable: [
      .english:
        "No valid Claude Code Keychain credential was found. Sign in with Claude Code first.",
      .simplifiedChinese: "未找到有效的 Claude Code 钥匙串凭据，请先登录 Claude Code。",
      .japanese: "有効な Claude Code キーチェーン認証情報が見つかりません。先に Claude Code へログインしてください。",
    ],
    .providersClaudeAuthorizationDenied: [
      .english: "macOS did not grant access to the Claude Code credential.",
      .simplifiedChinese: "macOS 未授予 Claude Code 凭据访问权限。",
      .japanese: "macOS から Claude Code 認証情報へのアクセスが許可されませんでした。",
    ],
  ]
}
