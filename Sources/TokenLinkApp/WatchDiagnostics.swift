import Foundation
import TokenLinkDevice

public enum WatchDiagnosticLevel: String, Equatable, Sendable {
  case ready
  case attention
  case blocked
  case inactive
}

public struct WatchDiagnosticItem: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let detail: String
  public let level: WatchDiagnosticLevel
}

extension AppModel {
  public var watchDiagnosticItems: [WatchDiagnosticItem] {
    var items = [permissionDiagnostic, adapterDiagnostic, bindingDiagnostic]
    items.append(connectionDiagnostic)
    items.append(commandChannelDiagnostic)
    items.append(syncDiagnostic)
    if let lastWatchSyncFailure {
      items.append(
        WatchDiagnosticItem(
          id: "lastFailure",
          title: localized("Last failure", "最近失败", "直近の失敗"),
          detail: failureGuidance(lastWatchSyncFailure),
          level: .blocked))
    }
    return items
  }

  private var permissionDiagnostic: WatchDiagnosticItem {
    let title = localized("Bluetooth permission", "蓝牙权限", "Bluetooth 権限")
    switch bluetoothDiagnostics.authorization {
    case .allowed:
      return .init(
        id: "permission", title: title,
        detail: localized(
          "Allowed for nearby-device discovery, connection, quota sync, and watch commands.",
          "已允许附近设备发现、连接、额度同步和手表命令。",
          "周辺デバイスの検出、接続、クォータ同期、ウォッチコマンドが許可されています。"),
        level: .ready)
    case .notDetermined:
      return .init(
        id: "permission", title: title,
        detail: localized(
          "Not requested. TokenLink asks only after you press Scan or Sync.",
          "尚未请求；TokenLink 只会在你点击“扫描”或“同步”后请求。",
          "未要求です。TokenLink は「スキャン」または「同期」を押した後にのみ要求します。"),
        level: .inactive)
    case .denied, .restricted:
      return .init(
        id: "permission", title: title,
        detail: localized(
          "Blocked. Open System Settings → Privacy & Security → Bluetooth and allow TokenLink.",
          "已阻止。请打开“系统设置 → 隐私与安全性 → 蓝牙”并允许 TokenLink。",
          "ブロックされています。「システム設定 → プライバシーとセキュリティ → Bluetooth」で TokenLink を許可してください。"),
        level: .blocked)
    case .unavailable:
      return .init(
        id: "permission", title: title,
        detail: localized(
          "Permission state is unavailable until Bluetooth initializes.",
          "蓝牙初始化前无法读取权限状态。",
          "Bluetooth が初期化されるまで権限状態を取得できません。"),
        level: .inactive)
    }
  }

  private var adapterDiagnostic: WatchDiagnosticItem {
    let title = localized("Bluetooth adapter", "蓝牙适配器", "Bluetooth アダプタ")
    switch bluetoothDiagnostics.centralState {
    case .poweredOn:
      return .init(
        id: "adapter", title: title,
        detail: localized("Powered on and available.", "已开启且可用。", "オンで利用可能です。"),
        level: .ready)
    case .notInitialized:
      return .init(
        id: "adapter", title: title,
        detail: localized(
          "Idle; it initializes after an explicit Scan or Sync.",
          "尚未启动；会在你明确点击“扫描”或“同步”后初始化。",
          "待機中です。明示的な「スキャン」または「同期」の後に初期化します。"),
        level: .inactive)
    case .poweredOff:
      return .init(
        id: "adapter", title: title,
        detail: localized("Bluetooth is off.", "蓝牙已关闭。", "Bluetooth がオフです。"),
        level: .blocked)
    case .unauthorized:
      return .init(
        id: "adapter", title: title,
        detail: localized(
          "macOS has not authorized TokenLink.", "macOS 未授权 TokenLink。",
          "macOS が TokenLink を許可していません。"),
        level: .blocked)
    case .unsupported:
      return .init(
        id: "adapter", title: title,
        detail: localized(
          "Bluetooth Low Energy is unavailable on this Mac.", "这台 Mac 不支持蓝牙低功耗。",
          "この Mac では Bluetooth Low Energy を利用できません。"),
        level: .blocked)
    case .unknown, .resetting:
      return .init(
        id: "adapter", title: title,
        detail: localized(
          "macOS is preparing Bluetooth.", "macOS 正在准备蓝牙。", "macOS が Bluetooth を準備しています。"),
        level: .attention)
    }
  }

  private var bindingDiagnostic: WatchDiagnosticItem {
    let title = localized("Device binding", "设备绑定", "デバイスのバインド")
    if configuration.requiresBluetoothRebinding {
      return .init(
        id: "binding", title: title,
        detail: localized(
          "The old app identity was cleared. Scan and bind this C152 once.",
          "旧应用身份的绑定已清除，请扫描并重新绑定这台 C152 一次。",
          "以前のアプリ ID のバインドは消去されました。この C152 を一度スキャンして再バインドしてください。"),
        level: .attention)
    }
    guard configuration.boundDeviceIdentifier != nil else {
      return .init(
        id: "binding", title: title,
        detail: localized("No StopWatch is bound.", "尚未绑定 StopWatch。", "StopWatch はバインドされていません。"),
        level: .inactive)
    }
    return .init(
      id: "binding", title: title,
      detail: localized(
        "One StopWatch is bound.", "已绑定一台 StopWatch。", "1 台の StopWatch がバインドされています。"),
      level: .ready)
  }

  private var connectionDiagnostic: WatchDiagnosticItem {
    let title = localized("Connection", "连接", "接続")
    let isBoundDevice =
      bluetoothDiagnostics.connectedIdentifier != nil
      && bluetoothDiagnostics.connectedIdentifier == configuration.boundDeviceIdentifier
    if isBoundDevice, bluetoothDiagnostics.connectionStep == .ready {
      return .init(
        id: "connection", title: title,
        detail: localized(
          "Connected; services and characteristics are ready.",
          "已连接，服务与特征已就绪。",
          "接続済みで、サービスとキャラクタリスティックの準備ができています。"),
        level: .ready)
    }
    let step = bluetoothDiagnostics.connectionStep
    if ![.idle, .ready].contains(step) {
      return .init(
        id: "connection", title: title,
        detail: localized(
          "In progress: \(connectionStepName(step, language: .english)).",
          "进行中：\(connectionStepName(step, language: .simplifiedChinese))。",
          "処理中：\(connectionStepName(step, language: .japanese))。"),
        level: .attention)
    }
    return .init(
      id: "connection", title: title,
      detail: localized("Not connected.", "尚未连接。", "未接続です。"),
      level: configuration.boundDeviceIdentifier == nil ? .inactive : .attention)
  }

  private var commandChannelDiagnostic: WatchDiagnosticItem {
    let title = localized("Watch command channel", "手表命令通道", "ウォッチコマンドチャネル")
    if bluetoothDiagnostics.commandNotificationsActive {
      return .init(
        id: "commands", title: title,
        detail: localized(
          "C04 notifications are active; Session focus and watch refresh commands can reach the Mac.",
          "C04 通知已启用；Session 聚焦与手表刷新命令可到达 Mac。",
          "C04 通知が有効です。Session フォーカスと更新コマンドを Mac に送れます。"),
        level: .ready)
    }
    if case .v1 = negotiatedWatchProtocol {
      return .init(
        id: "commands", title: title,
        detail: localized(
          "Protocol v1 can sync quota but does not support Session focus commands.",
          "协议 v1 可以同步额度，但不支持 Session 聚焦命令。",
          "プロトコル v1 はクォータ同期に対応しますが、Session フォーカスコマンドには対応しません。"),
        level: .attention)
    }
    return .init(
      id: "commands", title: title,
      detail: localized(
        "Available after a protocol-v2 connection confirms C04 notifications.",
        "协议 v2 连接并确认 C04 通知后可用。",
        "プロトコル v2 接続で C04 通知を確認した後に利用できます。"),
      level: .inactive)
  }

  private var syncDiagnostic: WatchDiagnosticItem {
    let title = localized("Last watch sync", "最近手表同步", "最後のウォッチ同期")
    switch devicePhase {
    case .synced(let date):
      return .init(
        id: "sync", title: title,
        detail: localized("Succeeded at ", "成功于 ", "成功：")
          + date.formatted(date: .omitted, time: .standard),
        level: .ready)
    case .syncing:
      return .init(
        id: "sync", title: title,
        detail: localized("Syncing now.", "正在同步。", "同期中です。"), level: .attention)
    case .stale:
      return .init(
        id: "sync", title: title,
        detail: localized(
          "The previous payload is stale; retry Sync.", "上次 payload 已过期，请重试同步。",
          "以前のペイロードが古くなっています。同期を再試行してください。"),
        level: .attention)
    default:
      return .init(
        id: "sync", title: title,
        detail: localized(
          "No successful sync in this app session.", "本次应用会话中尚未成功同步。", "このアプリセッションではまだ同期に成功していません。"),
        level: .inactive)
    }
  }

  private func failureGuidance(_ failure: String) -> String {
    switch failure {
    case "bluetooth unavailable":
      return localized(
        "Bluetooth is off, unsupported, or denied. Check the permission and adapter rows above.",
        "蓝牙已关闭、不受支持或被拒绝，请检查上方权限与适配器状态。",
        "Bluetooth がオフ、非対応、または拒否されています。上の権限とアダプタ状態を確認してください。")
    case "bound device not found":
      return localized(
        "The saved device is no longer visible to this app identity. Scan and bind it again.",
        "当前应用身份无法再看到已保存设备，请重新扫描并绑定。",
        "保存済みデバイスが現在のアプリ ID から見えません。再スキャンしてバインドしてください。")
    case "watch command notifications unavailable":
      return localized(
        "C04 notification setup failed. Reconnect, then confirm the watch runs protocol-v2 firmware.",
        "C04 通知设置失败，请重新连接并确认手表运行协议 v2 固件。",
        "C04 通知の設定に失敗しました。再接続し、ウォッチがプロトコル v2 ファームウェアか確認してください。")
    case "timeout":
      return localized(
        "The watch did not finish the Bluetooth operation in time. Keep it awake and nearby, then retry.",
        "手表未能及时完成蓝牙操作，请保持唤醒并靠近 Mac 后重试。",
        "Bluetooth 操作が時間内に完了しませんでした。ウォッチを起動したまま近くに置いて再試行してください。")
    default:
      return localized(
        "The last operation failed (\(failure)). Retry once; export redacted diagnostics if it repeats.",
        "上次操作失败（\(failure)）。请重试一次；若重复出现，请导出脱敏诊断。",
        "直前の操作に失敗しました（\(failure)）。一度再試行し、繰り返す場合はマスク済み診断を書き出してください。")
    }
  }

  private func localized(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch currentLanguage {
    case .english: english
    case .simplifiedChinese: chinese
    case .japanese: japanese
    }
  }

  private func connectionStepName(
    _ step: BluetoothConnectionStep,
    language: AppLanguage
  ) -> String {
    let values: (String, String, String) =
      switch step {
      case .idle: ("idle", "空闲", "待機")
      case .scanning: ("scanning", "扫描", "スキャン")
      case .waitingForPower: ("waiting for Bluetooth", "等待蓝牙", "Bluetooth を待機")
      case .connecting: ("connecting", "正在连接", "接続")
      case .discoveringServices: ("discovering services", "发现服务", "サービス検出")
      case .discoveringCharacteristics: ("discovering characteristics", "发现特征", "キャラクタリスティック検出")
      case .subscribingCommands: ("enabling C04 notifications", "启用 C04 通知", "C04 通知を有効化")
      case .ready: ("ready", "就绪", "準備完了")
      }
    return switch language {
    case .english: values.0
    case .simplifiedChinese: values.1
    case .japanese: values.2
    }
  }
}
