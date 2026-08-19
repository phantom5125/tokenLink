import SwiftUI
import TokenLinkCore

enum ProviderPresentation {
    static func symbol(for provider: ProviderID) -> String {
        switch provider {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .kimi: "moon.stars.fill"
        case .minimax: "sparkles"
        case .glm: "cube.transparent.fill"
        }
    }

    static func color(for provider: ProviderID) -> Color {
        switch provider {
        case .codex: Color(red: 0.20, green: 0.75, blue: 0.62)
        case .kimi: Color(red: 0.48, green: 0.55, blue: 0.98)
        case .minimax: Color(red: 0.95, green: 0.49, blue: 0.32)
        case .glm: Color(red: 0.30, green: 0.66, blue: 0.95)
        }
    }

    static func phaseColor(_ phase: ProviderPhase) -> Color {
        switch phase {
        case .healthy: .green
        case .refreshing: .blue
        case .stale: .orange
        case .error, .missingCredential: .red
        case .disabled: .secondary
        }
    }

    static func phaseText(_ phase: ProviderPhase) -> String {
        switch phase {
        case .disabled: "Disabled"
        case .missingCredential: "Credential needed"
        case .refreshing: "Refreshing"
        case .healthy: "Live"
        case .stale: "Stale"
        case .error: "Unavailable"
        }
    }

    static func relative(_ date: Date, relativeTo now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: ProviderPresentation.symbol(for: provider))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [
                        ProviderPresentation.color(for: provider),
                        ProviderPresentation.color(for: provider).opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct PhaseBadge: View {
    let phase: ProviderPhase

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ProviderPresentation.phaseColor(phase))
                .frame(width: 7, height: 7)
            Text(ProviderPresentation.phaseText(phase))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
