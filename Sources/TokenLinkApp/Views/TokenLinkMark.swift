import AppKit
import SwiftUI

/// The in-app and menu-bar mark comes from the installed application icon. The
/// ICNS is generated from assets/branding/logo-mark-light.png, so these surfaces
/// cannot drift into a separately drawn or differently weighted logo.
struct TokenLinkMark: View {
  var body: some View {
    Image(nsImage: NSApplication.shared.applicationIconImage)
      .resizable()
      .interpolation(.high)
      .aspectRatio(1, contentMode: .fit)
      .accessibilityHidden(true)
  }
}
