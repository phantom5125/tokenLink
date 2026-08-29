import SwiftUI

enum ControlRoute: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case providers = "Providers"
  case stopwatch = "StopWatch"
  case settings = "Settings & Diagnostics"
  var id: Self { self }

  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .providers: "bolt.horizontal.circle"
    case .stopwatch: "stopwatch"
    case .settings: "gearshape.2"
    }
  }

  var l10nKey: L10n.Key {
    switch self {
    case .overview: .routeOverview
    case .providers: .routeProviders
    case .stopwatch: .routeStopwatch
    case .settings: .routeSettings
    }
  }
}

struct ControlCenterView: View {
  @Bindable var model: AppModel
  @State private var selection: ControlRoute? = .overview

  var body: some View {
    NavigationSplitView {
      List(ControlRoute.allCases, selection: $selection) { route in
        Label(model.text(route.l10nKey), systemImage: route.symbol)
          .tag(route)
          .padding(.vertical, 4)
      }
      .navigationTitle("TokenLink")
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      Group {
        switch selection ?? .overview {
        case .overview:
          OverviewView(model: model)
        case .providers:
          ProvidersView(model: model)
        case .stopwatch:
          StopWatchView(model: model)
        case .settings:
          SettingsView(model: model)
        }
      }
      .environment(\.appLanguage, model.currentLanguage)
      .toolbar {
        ToolbarItem {
          Button {
            Task { await model.refreshManually() }
          } label: {
            Label(model.text(.actionRefresh), systemImage: "arrow.clockwise")
          }
          .disabled(model.isRefreshing)
        }
      }
    }
  }
}
