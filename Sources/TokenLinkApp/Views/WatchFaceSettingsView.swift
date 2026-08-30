import SwiftUI
import TokenLinkCore
import TokenLinkDevice

struct WatchFaceSettingsView: View {
  @Bindable var model: AppModel
  @State private var draftNames: [String: String] = [:]
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(model.text(.watchFaceTitle))
          .font(.headline)
        Text(model.text(.watchFaceHint))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      protocolSummary
      providerSelection
      facePreferences
      workItemEditor
      payloadPreview

      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
  }

  private var protocolSummary: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(String(format: model.text(.watchNegotiated), negotiatedProtocolText))
        .font(.subheadline.weight(.medium))
      if model.negotiatedWatchProtocol == .v1 {
        Text(model.text(.watchV1Note))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var providerSelection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(model.text(.watchSyncProviders))
        .font(.subheadline.weight(.semibold))
      ForEach(enabledProviders, id: \.self) { provider in
        Toggle(
          isOn: Binding(
            get: { model.configuration.watchSettings.syncedProviders.contains(provider) },
            set: { enabled in
              do {
                try model.setWatchSyncedProvider(provider, enabled: enabled)
                message = nil
              } catch {
                message = error.localizedDescription
              }
            })
        ) {
          HStack(spacing: 9) {
            ProviderMark(provider: provider, size: 24)
            Text(AppModel.displayName(for: provider))
          }
        }
        .toggleStyle(.switch)
      }
    }
  }

  private var facePreferences: some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent(model.text(.watchTheme)) {
        Picker(
          model.text(.watchTheme),
          selection: Binding(
            get: { model.configuration.watchSettings.faceTheme },
            set: { theme in
              persist { try model.setWatchFaceTheme(theme) }
            })
        ) {
          Text(model.text(.watchThemeData)).tag(WatchFaceTheme.data)
          Text(model.text(.watchThemePet)).tag(WatchFaceTheme.pet)
        }
        .labelsHidden()
        .frame(width: 170)
      }

      LabeledContent(model.text(.watchWake)) {
        Picker(
          model.text(.watchWake),
          selection: Binding(
            get: { model.configuration.watchSettings.wakeMode },
            set: { mode in
              persist { try model.setWatchWakeMode(mode) }
            })
        ) {
          Text(model.text(.watchWakeRaise)).tag(WatchWakeMode.raise)
          Text(model.text(.watchWakeTap)).tag(WatchWakeMode.tap)
        }
        .labelsHidden()
        .frame(width: 170)
      }

      LabeledContent(model.text(.watchHourFormat)) {
        Picker(
          model.text(.watchHourFormat),
          selection: Binding(
            get: { model.configuration.watchSettings.hourFormat },
            set: { format in
              persist { try model.setWatchHourFormat(format) }
            })
        ) {
          Text(model.text(.watchHourSystem)).tag(WatchHourFormat.system)
          Text(model.text(.watchHour12)).tag(WatchHourFormat.h12)
          Text(model.text(.watchHour24)).tag(WatchHourFormat.h24)
        }
        .labelsHidden()
        .frame(width: 170)
      }
    }
  }

  private var workItemEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(model.text(.watchWorkItems))
        .font(.subheadline.weight(.semibold))
      if model.workItems.isEmpty {
        Text(model.text(.watchNoWorkItems))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.workItems) { item in
          HStack(spacing: 10) {
            Text("\(item.slot + 1)")
              .font(.system(.caption, design: .monospaced).weight(.semibold))
              .frame(width: 22, height: 22)
              .background(.secondary.opacity(0.12), in: Circle())
            TextField(
              model.text(.watchWorkItemName),
              text: Binding(
                get: { draftNames[item.id] ?? item.name },
                set: { draftNames[item.id] = $0 })
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveName(for: item) }
            Text(item.state.rawValue.replacingOccurrences(of: "_", with: " "))
              .font(.caption)
              .foregroundStyle(.secondary)
            Button(model.text(.actionSave)) {
              saveName(for: item)
            }
            .disabled(draftNames[item.id] == nil)
            if item.source == .codex {
              Button {
                Task { await model.focusWorkItemOnMac(slot: item.slot) }
              } label: {
                Image(systemName: "arrow.up.forward.app")
              }
              .help(
                localized("Test task focus on this Mac", "在这台 Mac 上测试任务聚焦", "この Mac でタスクフォーカスをテスト"))
            }
          }
        }
        Text(model.text(.watchFocusNote))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let outcome = model.lastWatchFocusOutcome {
          focusOutcome(outcome)
        }
      }
    }
  }

  private func focusOutcome(_ outcome: WatchFocusOutcome) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(
        systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(outcome.succeeded ? Color.green : Color.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(focusOutcomeText(outcome))
          .font(.caption.weight(.medium))
        if let date = model.lastWatchFocusAt {
          Text(date.formatted(date: .omitted, time: .standard))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      (outcome.succeeded ? Color.green : Color.orange).opacity(0.09),
      in: RoundedRectangle(cornerRadius: 9))
  }

  private func focusOutcomeText(_ outcome: WatchFocusOutcome) -> String {
    switch outcome {
    case .openedThread:
      localized(
        "The matching task link was delivered to Codex Desktop.",
        "对应任务链接已发送到 Codex Desktop。",
        "対応するタスクリンクを Codex Desktop に渡しました。")
    case .activatedFallback:
      localized(
        "Codex Desktop came forward, but the installed build did not accept the task link.",
        "Codex Desktop 已切到前台，但当前安装版本未接受任务链接。",
        "Codex Desktop を前面に出しましたが、インストール済みビルドはタスクリンクを受け付けませんでした。")
    case .noWorkItem:
      localized(
        "That watch slot no longer maps to a current task. Refresh and retry.",
        "该手表槽位已不再对应当前任务，请刷新后重试。",
        "そのウォッチスロットは現在のタスクに対応していません。更新して再試行してください。")
    case .unsupportedProvider:
      localized(
        "Only Codex tasks can be focused on the Mac.",
        "只有 Codex 任务可以在 Mac 上聚焦。",
        "Mac でフォーカスできるのは Codex タスクだけです。")
    case .desktopUnavailable:
      localized(
        "Codex Desktop is not running or could not be activated.",
        "Codex Desktop 未运行或无法激活。",
        "Codex Desktop が起動していないか、アクティブにできませんでした。")
    }
  }

  private var payloadPreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.text(.watchPayloadPreview))
        .font(.subheadline.weight(.semibold))
      Group {
        if let payload = model.lastWatchPayloadSummary {
          Text(payload)
        } else {
          Text(model.text(.watchNoPayload))
            .foregroundStyle(.secondary)
        }
      }
      .font(.system(.caption, design: .monospaced))
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
  }

  private var enabledProviders: [ProviderID] {
    model.watchEligibleProviders
  }

  private var negotiatedProtocolText: String {
    switch model.negotiatedWatchProtocol {
    case nil:
      model.text(.watchNotNegotiated)
    case .v1:
      "v1"
    case .v2(let capabilities):
      if let firmware = capabilities.firmware, !firmware.isEmpty {
        "v2 · \(firmware)"
      } else {
        "v2"
      }
    }
  }

  private func persist(_ operation: () throws -> Void) {
    do {
      try operation()
      message = nil
    } catch {
      message = error.localizedDescription
    }
  }

  private func saveName(for item: WorkItem) {
    guard let name = draftNames[item.id] else { return }
    draftNames[item.id] = nil
    Task { await model.renameWorkItem(id: item.id, to: name) }
  }

  private func localized(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch model.currentLanguage {
    case .english: english
    case .simplifiedChinese: chinese
    case .japanese: japanese
    }
  }
}
