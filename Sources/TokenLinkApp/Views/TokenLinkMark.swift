import SwiftUI

/// Compact TokenLink mark used where the full macOS app icon is too detailed.
/// The menu-bar variant stays monochrome so macOS can adapt it to light, dark,
/// highlighted, and accessibility appearances.
struct TokenLinkMark: View {
  enum Appearance {
    case template
    case brand
  }

  var appearance: Appearance = .brand

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let strokeWidth = max(2, side * 0.15)
      let ringInset = side * 0.08

      ZStack {
        Circle()
          .trim(from: 0.08, to: 0.92)
          .stroke(
            ringStyle,
            style: StrokeStyle(
              lineWidth: strokeWidth,
              lineCap: .round,
              lineJoin: .round)
          )
          .rotationEffect(.degrees(90))
          .padding(ringInset)

        Text("∞")
          .font(.system(size: side * 0.49, weight: .bold, design: .rounded))
          .foregroundStyle(linkStyle)
          .offset(y: -side * 0.015)
      }
      .frame(width: side, height: side)
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private var ringStyle: AnyShapeStyle {
    switch appearance {
    case .template:
      AnyShapeStyle(Color.primary)
    case .brand:
      AnyShapeStyle(
        LinearGradient(
          colors: [Color(red: 0, green: 0.76, blue: 0.66), .primary],
          startPoint: .leading,
          endPoint: .trailing))
    }
  }

  private var linkStyle: AnyShapeStyle {
    AnyShapeStyle(Color.primary)
  }
}
