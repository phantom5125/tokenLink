import SwiftUI

struct StopWatchView: View {
  @Bindable var model: AppModel
  @State private var selection: UUID?
  @State private var message: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 6) {
          Text("StopWatch")
            .font(.largeTitle.bold())
          Text(model.text(.watchSubtitle))
            .foregroundStyle(.secondary)
        }

        compatibilityNotice
        if model.configuration.requiresBluetoothRebinding {
          bluetoothIdentityNotice
        }
        bindingCard
        diagnosticsCard
        WatchFaceSettingsView(model: model)
        discoveryCard

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
    .navigationTitle("StopWatch")
    .task {
      await model.refreshBluetoothDiagnostics()
    }
  }

  private var diagnosticsCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(localized("Connection diagnostics", "连接诊断", "接続診断"))
            .font(.headline)
          Text(
            localized(
              "This checklist contains no credentials, token values, or watch payload contents.",
              "该检查表不包含凭据、token 数值或手表 payload 内容。",
              "このチェックリストには認証情報、トークン値、ウォッチのペイロード内容は含まれません。")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await model.refreshBluetoothDiagnostics() }
        } label: {
          Label(
            localized("Refresh status", "刷新状态", "状態を更新"),
            systemImage: "arrow.clockwise")
        }
      }

      VStack(spacing: 0) {
        ForEach(Array(model.watchDiagnosticItems.enumerated()), id: \.element.id) {
          index, item in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: diagnosticSymbol(item.level))
              .foregroundStyle(diagnosticColor(item.level))
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.title)
                .font(.subheadline.weight(.medium))
              Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 10)
          if index < model.watchDiagnosticItems.count - 1 {
            Divider().padding(.leading, 30)
          }
        }
      }
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
  }

  private func diagnosticSymbol(_ level: WatchDiagnosticLevel) -> String {
    switch level {
    case .ready: "checkmark.circle.fill"
    case .attention: "exclamationmark.triangle.fill"
    case .blocked: "xmark.octagon.fill"
    case .inactive: "circle.dotted"
    }
  }

  private func diagnosticColor(_ level: WatchDiagnosticLevel) -> Color {
    switch level {
    case .ready: .green
    case .attention: .orange
    case .blocked: .red
    case .inactive: .secondary
    }
  }

  private func localized(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch model.currentLanguage {
    case .english: english
    case .simplifiedChinese: chinese
    case .japanese: japanese
    }
  }

  private var bluetoothIdentityNotice: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: "bolt.horizontal.circle.fill")
        .font(.title2)
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.text(.watchRebindTitle))
          .font(.headline)
        Text(model.text(.watchRebindBody))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
  }

  private var compatibilityNotice: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: "checkmark.shield.fill")
        .font(.title2)
        .foregroundStyle(.blue)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.text(.watchCompatTitle))
          .font(.headline)
        Text(model.text(.watchCompatBody))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
  }

  private var bindingCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(model.text(.watchBoundDevice))
            .font(.headline)
          Text(
            model.configuration.boundDeviceIdentifier?.uuidString
              ?? model.text(.watchNoBoundDevice)
          )
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        }
        Spacer()
        Text(model.deviceStatusText)
          .font(.caption.weight(.medium))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.secondary.opacity(0.1), in: Capsule())
      }
      HStack {
        Button {
          Task { await model.syncCodexNow() }
        } label: {
          Label(model.text(.watchSyncNow), systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.configuration.boundDeviceIdentifier == nil)

        if model.configuration.boundDeviceIdentifier != nil {
          Button(model.text(.watchUnbind), role: .destructive) {
            Task {
              do {
                try await model.unbindDevice()
                message = model.text(.watchUnboundMessage)
              } catch { message = error.localizedDescription }
            }
          }
        }
      }
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
  }

  private var discoveryCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(model.text(.watchDiscoverTitle))
            .font(.headline)
          Text(model.text(.watchDiscoverNote))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          selection = nil
          Task { await model.discoverDevices() }
        } label: {
          Label(
            model.isDiscovering ? model.text(.watchScanning) : model.text(.watchScan),
            systemImage: "dot.radiowaves.left.and.right"
          )
        }
        .disabled(model.isDiscovering)
      }

      if model.isDiscovering {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      } else if !model.discoveredDeviceIdentifiers.isEmpty {
        VStack(spacing: 8) {
          ForEach(model.discoveredDeviceIdentifiers, id: \.self) { identifier in
            let isSelected = selection == identifier
            Button {
              selection = identifier
            } label: {
              HStack {
                Image(
                  systemName: isSelected
                    ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(identifier.uuidString)
                  .font(.system(.caption, design: .monospaced))
                Spacer()
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
          }
        }
        Button(model.text(.watchBindSelected)) {
          guard let selection else { return }
          Task {
            do {
              try await model.bindDevice(selection)
              self.selection = nil
              message = model.text(.watchBoundMessage)
            } catch { message = error.localizedDescription }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selection == nil)
      }
    }
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary) }
  }
}
