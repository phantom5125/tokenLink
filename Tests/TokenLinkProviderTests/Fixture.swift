import Foundation

enum Fixture {
  static func load(_ name: String) throws -> Data {
    // The manual test runner used in this repo has no resource bundle, so
    // resolve fixtures relative to this file instead of `Bundle.module`.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appending(path: "Fixtures")
      .appending(path: name)
    return try Data(contentsOf: url)
  }
}
