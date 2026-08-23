import SwiftUI

@main
struct TokenLinkApplication: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(model.menuBarLabel, systemImage: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)

        Window("TokenLink", id: "control-center") {
            ControlCenterView(model: model)
                .frame(minWidth: 860, minHeight: 590)
        }
        .defaultSize(width: 980, height: 680)
    }
}
