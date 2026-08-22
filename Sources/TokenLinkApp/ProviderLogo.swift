import AppKit
import SwiftUI
import TokenLinkCore

enum ProviderLogo {
  static func image(for provider: ProviderID) -> Image? {
    guard
      let url = Bundle.module.url(
        forResource: provider.rawValue,
        withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    return Image(nsImage: image)
  }
}
