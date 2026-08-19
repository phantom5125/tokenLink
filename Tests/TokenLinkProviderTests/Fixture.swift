import Foundation

enum Fixture {
  static func load(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
  }
}
