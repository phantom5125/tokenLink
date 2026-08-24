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
    case routeStopwatch = "route.stopwatch"
    case routeSettings = "route.settings"
    case actionRefresh = "action.refresh"
    case actionControlCenter = "action.controlCenter"
    case actionQuit = "action.quit"
    case actionSave = "action.save"
    case actionDelete = "action.delete"
    // Menu bar
    case menubarNoProviders = "menubar.noProviders"
    case menubarEnableHint = "menubar.enableHint"
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
  }

  public static func text(_ key: Key, language: AppLanguage) -> String {
    table[key]?[language] ?? table[key]?[.english] ?? key.rawValue
  }

  private static let table: [Key: [AppLanguage: String]] = [
    .routeOverview: [.english: "Overview", .simplifiedChinese: "概览", .japanese: "概要"],
    .routeProviders: [
      .english: "Providers", .simplifiedChinese: "额度源", .japanese: "プロバイダー",
    ],
    .routeStopwatch: [
      .english: "StopWatch", .simplifiedChinese: "StopWatch", .japanese: "StopWatch",
    ],
    .routeSettings: [
      .english: "Settings & Diagnostics", .simplifiedChinese: "设置与诊断",
      .japanese: "設定と診断",
    ],
    .actionRefresh: [.english: "Refresh", .simplifiedChinese: "刷新", .japanese: "更新"],
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
    .menubarNoProviders: [
      .english: "No providers enabled", .simplifiedChinese: "未启用任何额度源",
      .japanese: "有効なプロバイダーがありません",
    ],
    .menubarEnableHint: [
      .english: "Enable a provider in Control Center.",
      .simplifiedChinese: "请在控制中心里启用一个额度源。",
      .japanese: "コントロールセンターでプロバイダーを有効にしてください。",
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
        "Bind one M5Stack device and sync the Codex primary quota window over the existing private GATT service.",
      .simplifiedChinese: "绑定一台 M5Stack 设备，并通过现有的私有 GATT 服务同步 Codex 主额度窗口。",
      .japanese: "M5Stack デバイスを 1 台バインドし、既存のプライベート GATT サービスで Codex プライマリクォータを同期します。",
    ],
    .watchCompatTitle: [
      .english: "Firmware v1 compatibility mode",
      .simplifiedChinese: "固件 v1 兼容模式",
      .japanese: "ファームウェア v1 互換モード",
    ],
    .watchCompatBody: [
      .english:
        "The current face remains unchanged. TokenLink sends only Codex using `remaining_percent` and `reset_in_seconds`; Kimi, MiniMax, and GLM stay on the Mac until protocol v2.",
      .simplifiedChinese:
        "现有表盘保持不变。TokenLink 只用 `remaining_percent` 和 `reset_in_seconds` 发送 Codex 额度；Kimi、MiniMax 和 GLM 在协议 v2 之前只显示在 Mac 上。",
      .japanese:
        "現在のウォッチフェイスは変更されません。TokenLink は `remaining_percent` と `reset_in_seconds` で Codex のみを送信します。Kimi、MiniMax、GLM はプロトコル v2 まで Mac 側に留まります。",
    ],
    .watchBoundDevice: [
      .english: "Bound device", .simplifiedChinese: "已绑定设备",
      .japanese: "バインド済みデバイス",
    ],
    .watchNoBoundDevice: [
      .english: "No StopWatch bound", .simplifiedChinese: "未绑定 StopWatch",
      .japanese: "StopWatch はバインドされていません",
    ],
    .watchSyncNow: [
      .english: "Sync Codex now", .simplifiedChinese: "立即同步 Codex",
      .japanese: "Codex を今すぐ同期",
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
        "Uses the local Claude Code CLI sign-in (OAuth usage endpoint). Anthropic pay-as-you-go keys do not report subscription quota, so TokenLink does not store one.",
      .simplifiedChinese:
        "使用本机 Claude Code CLI 登录态（OAuth 用量接口）。Anthropic 按量付费 key 查询不到订阅额度，因此 TokenLink 不保存 key。",
      .japanese:
        "ローカルの Claude Code CLI ログイン状態（OAuth 使用量エンドポイント）を使用します。従量課金キーではサブスクリプションのクォータを取得できないため、TokenLink はキーを保存しません。",
    ],
  ]
}
