import AppKit
import SwiftUI

/// The in-app and menu-bar mark comes from the installed application icon. The
/// ICNS is generated from assets/branding/logo-mark-light.png, so these surfaces
/// cannot drift into a separately drawn or differently weighted logo.
@MainActor
struct TokenLinkMark: View {
  let pointSize: CGFloat

  init(pointSize: CGFloat = 18) {
    self.pointSize = pointSize
  }

  var body: some View {
    Image(nsImage: Self.image(pointSize: pointSize))
      .frame(width: pointSize, height: pointSize)
      .fixedSize()
      .accessibilityHidden(true)
  }

  /// `MenuBarExtra` may size a large source `NSImage` before SwiftUI applies a
  /// frame, which makes a 1024 px application icon reserve a huge status-item
  /// slot. Give AppKit a native point-sized image instead. The pixels still
  /// come exclusively from the packaged branding-derived application icon.
  static func image(pointSize: CGFloat) -> NSImage {
    let side = max(1, pointSize)
    let size = NSSize(width: side, height: side)
    let source = NSApplication.shared.applicationIconImage ?? NSImage(size: size)
    let image = NSImage(size: size, flipped: false) { destination in
      source.draw(
        in: destination,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high])
      return true
    }
    image.size = size
    return image
  }
}
