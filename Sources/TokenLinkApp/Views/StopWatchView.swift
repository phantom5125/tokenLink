import SwiftUI

struct StopWatchView: View {
  let model: AppModel
  @State private var isDiscovering = false
  @State private var discovered: [UUID] = []
  @State private var selected: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Bound device")
        Spacer()
        Text(model.configuration.boundDeviceIdentifier?.uuidString ?? "None")
          .foregroundStyle(.secondary)
          .monospaced()
      }

      // 只在显式发现会话中列出设备；必须先选择才能绑定
      if isDiscovering {
        List(discovered, id: \.self, selection: $selected) { uuid in
          Text(uuid.uuidString).tag(uuid)
        }
        .frame(minHeight: 160)
      }

      HStack {
        Button(isDiscovering ? "Stop discovery" : "Discover…") {
          isDiscovering.toggle()
          if !isDiscovering { discovered = [] }
        }
        Button("Bind") {
          if let selected { model.bindDevice(selected) }
          isDiscovering = false
        }
        .disabled(selected == nil)
        Spacer()
        Button("Sync Codex now") {
          Task { await model.syncCodexNow() }
        }
        .disabled(model.configuration.boundDeviceIdentifier == nil)
      }
      Spacer()
    }
    .padding()
  }
}
