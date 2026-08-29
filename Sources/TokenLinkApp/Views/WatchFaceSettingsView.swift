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
          }
        }
        Text(model.text(.watchFocusNote))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
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
    ProviderID.allCases.filter { provider in
      model.configuration.accounts.contains { $0.provider == provider && $0.enabled }
    }
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
}
