import SwiftUI

enum ControlRoute: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case providers = "Providers"
    case stopwatch = "StopWatch"
    case settings = "Settings & Diagnostics"
    var id: Self { self }
}

struct ControlCenterView: View {
    let model: AppModel
    @State private var route: ControlRoute = .overview

    var body: some View {
        NavigationSplitView {
            List(ControlRoute.allCases, selection: $route) { route in
                Text(route.rawValue).tag(route)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch route {
            case .overview: OverviewView(model: model)
            case .providers: ProvidersView(model: model)
            case .stopwatch: StopWatchView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
    }
}
