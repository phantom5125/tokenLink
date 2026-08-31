import AppKit
import SwiftUI
import TokenLinkCore

enum ProviderLogo {
  private static let resources: Bundle = {
    let bundleName = "TokenLink_TokenLinkApp.bundle"
    let candidates = [
      Bundle.main.resourceURL?.appendingPathComponent(bundleName),
      Bundle.main.bundleURL.appendingPathComponent(bundleName),
    ]
    for case let url? in candidates {
      if let bundle = Bundle(url: url) { return bundle }
    }
    #if TOKENLINK_PACKAGED_APP
      return Bundle.main
    #else
      return Bundle.module
    #endif
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
