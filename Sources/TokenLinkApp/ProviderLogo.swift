import AppKit
import SwiftUI
import TokenLinkCore

enum ProviderLogo {
  private static let resources: Bundle = {
    let packagedBundle = Bundle.main.resourceURL?
      .appendingPathComponent("TokenLink_TokenLinkApp.bundle")
    if let packagedBundle, let bundle = Bundle(url: packagedBundle) {
      return bundle
    }
    return Bundle.module
  }()

  static func image(for provider: ProviderID) -> Image? {
    guard
      let url = resources.url(
        forResource: provider.rawValue,
        withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    return Image(nsImage: image)
  }
}
