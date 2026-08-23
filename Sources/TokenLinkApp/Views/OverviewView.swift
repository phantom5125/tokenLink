import SwiftUI

struct OverviewView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let highlight = model.highlight {
                    GroupBox("Most constrained") {
                        HStack {
                            Text(highlight.provider.rawValue.capitalized)
                                .font(.title2)
                            Spacer()
                            Text("\(Int(highlight.window.remainingPercent))%")
                                .font(.system(size: 44, weight: .bold))
                                .monospacedDigit()
                        }
                        Text(highlight.window.label)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "No quota yet",
                        systemImage: "gauge.with.dots.needle.33percent",
                        description: Text("Refresh to fetch provider quota."))
                }

                GroupBox("Recent events") {
                    if model.events.isEmpty {
                        Text("Nothing yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.events, id: \.self) { event in
                            Text(event).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
