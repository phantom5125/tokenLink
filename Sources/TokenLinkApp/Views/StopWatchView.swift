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
          Text(
            "Bind one M5Stack device and sync the Codex primary quota window over the existing private GATT service."
          )
          .foregroundStyle(.secondary)
        }

        compatibilityNotice
        bindingCard
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
  }

  private var compatibilityNotice: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: "checkmark.shield.fill")
        .font(.title2)
        .foregroundStyle(.blue)
      VStack(alignment: .leading, spacing: 4) {
        Text("Firmware v1 compatibility mode")
          .font(.headline)
        Text(
          "The current face remains unchanged. TokenLink sends only Codex using `remaining_percent` and `reset_in_seconds`; Kimi, MiniMax, and GLM stay on the Mac until protocol v2."
        )
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
          Text("Bound device")
            .font(.headline)
          Text(model.configuration.boundDeviceIdentifier?.uuidString ?? "No StopWatch bound")
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
          Label("Sync Codex now", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.configuration.boundDeviceIdentifier == nil)

        if model.configuration.boundDeviceIdentifier != nil {
          Button("Unbind", role: .destructive) {
            Task {
              do {
                try await model.unbindDevice()
                message = "StopWatch unbound."
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
          Text("Discover nearby devices")
            .font(.headline)
          Text("Discovery starts only when you press Scan. Results are not retained after binding.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          selection = nil
          Task { await model.discoverDevices() }
        } label: {
          Label(
            model.isDiscovering ? "Scanning…" : "Scan", systemImage: "dot.radiowaves.left.and.right"
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
        Button("Bind selected device") {
          guard let selection else { return }
          Task {
            do {
              try await model.bindDevice(selection)
              self.selection = nil
              message = "StopWatch bound."
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
