import Foundation
import Testing
import TokenLinkDevice

@Test func watchFaceIDUsesStableStringEncoding() throws {
  let faceID = try #require(WatchFaceID(rawValue: "community.pixel-pet"))

  let data = try JSONEncoder().encode(faceID)

  #expect(String(decoding: data, as: UTF8.self) == #""community.pixel-pet""#)
  #expect(try JSONDecoder().decode(WatchFaceID.self, from: data) == faceID)
}

@Test func watchFaceIDRejectsUnsafeOrUnboundedValues() {
  #expect(WatchFaceID(rawValue: "") == nil)
  #expect(WatchFaceID(rawValue: "Community/Pet") == nil)
  #expect(WatchFaceID(rawValue: String(repeating: "a", count: 65)) == nil)
  #expect(WatchFaceID(rawValue: "author.pet_2") != nil)
}
