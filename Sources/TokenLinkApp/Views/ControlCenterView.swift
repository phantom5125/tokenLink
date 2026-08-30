import SwiftUI

enum ControlRoute: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case providers = "Providers"
  case costs = "Costs"
  case stopwatch = "StopWatch"
  case settings = "Settings & Diagnostics"
  var id: Self { self }

  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .providers: "bolt.horizontal.circle"
    case .costs: "chart.bar.xaxis"
    case .stopwatch: "stopwatch"
    case .settings: "gearshape.2"
    }
  }

  var l10nKey: L10n.Key {
    switch self {
    case .overview: .routeOverview
    case .providers: .routeProviders
    case .costs: .routeCosts
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
        case .costs:
          CostsView(model: model)
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
            Task {
              if selection == .costs {
                await model.refreshCosts(force: true)
              } else {
                await model.refreshManually()
              }
            }
          } label: {
            Label(
              model.text(selection == .costs ? .actionRefreshCosts : .actionRefresh),
              systemImage: "arrow.clockwise")
          }
          .disabled(selection == .costs ? model.costDashboard.isRefreshing : model.isRefreshing)
        }
      }
    }
  }
}
