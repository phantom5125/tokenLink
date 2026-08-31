import AppKit
import SwiftUI

@MainActor
private final class TokenLinkApplicationDelegate: NSObject, NSApplicationDelegate {
  static var onDidFinishLaunching: (() -> Void)?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.onDidFinishLaunching?()
    Self.onDidFinishLaunching = nil
  }
}

@main
@MainActor
struct TokenLinkApplication: App {
  @NSApplicationDelegateAdaptor(TokenLinkApplicationDelegate.self)
  private var applicationDelegate
  @State private var model: AppModel

  init() {
    let liveModel = AppModel.live()
    _model = State(initialValue: liveModel)
    // MenuBarExtra scenes are lazy. AppKit's finished-launching callback is the
    // deterministic point for starting the long-lived refresh/BLE model.
    TokenLinkApplicationDelegate.onDidFinishLaunching = {
      Task { @MainActor in await liveModel.start() }
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(model: model)
        .task { await model.start() }
    } label: {
      HStack(spacing: 4) {
        TokenLinkMark(pointSize: 18)
        Text(model.menuBarLabel)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(model.menuBarAccessibilityLabel)
      // MenuBarExtra content is lazy. Starting from the always-present label
      // guarantees the first refresh/BLE sync without requiring a click.
      .task { await model.start() }
    }
    .menuBarExtraStyle(.window)

    Window("TokenLink", id: "control-center") {
      ControlCenterView(model: model)
        .frame(minWidth: 860, minHeight: 590)
        .task { await model.start() }
    }
    .defaultSize(width: 980, height: 680)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
