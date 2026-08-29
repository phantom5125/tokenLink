import Foundation

public struct JSONLReadReport: Equatable, Sendable {
  public let bytesRead: Int
  public let deliveredRecordCount: Int
  public let oversizedRecordCount: Int

  public init(
    bytesRead: Int,
    deliveredRecordCount: Int,
    oversizedRecordCount: Int
  ) {
    self.bytesRead = bytesRead
    self.deliveredRecordCount = deliveredRecordCount
    self.oversizedRecordCount = oversizedRecordCount
  }
}

public struct JSONLStreamingReader: Sendable {
  public static let chunkBytes = 65_536
  public static let maximumRecordBytes = 1_048_576

  public init() {}

  public func read(
    url: URL,
    onRecord: (Data) -> Void
  ) throws -> JSONLReadReport {
    try Task.checkCancellation()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var currentRecord = Data()
    var discardingOversizedRecord = false
    var bytesRead = 0
    var deliveredRecordCount = 0
    var oversizedRecordCount = 0

    while true {
      try Task.checkCancellation()
      guard let chunk = try handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty else {
        break
      }
      bytesRead += chunk.count
      var segmentStart = chunk.startIndex

      for index in chunk.indices where chunk[index] == 0x0A {
        try Task.checkCancellation()
        if discardingOversizedRecord {
          discardingOversizedRecord = false
        } else {
          let segment = chunk[segmentStart..<index]
          if currentRecord.count + segment.count > Self.maximumRecordBytes {
            oversizedRecordCount += 1
            currentRecord.removeAll(keepingCapacity: false)
          } else {
            currentRecord.append(contentsOf: segment)
            if !currentRecord.isEmpty {
              onRecord(currentRecord)
              deliveredRecordCount += 1
              currentRecord.removeAll(keepingCapacity: false)
            }
          }
        }
        segmentStart = chunk.index(after: index)
      }

      guard segmentStart < chunk.endIndex else { continue }
      if discardingOversizedRecord { continue }
      let tail = chunk[segmentStart..<chunk.endIndex]
      if currentRecord.count + tail.count > Self.maximumRecordBytes {
        oversizedRecordCount += 1
        currentRecord.removeAll(keepingCapacity: false)
        discardingOversizedRecord = true
      } else {
        currentRecord.append(contentsOf: tail)
      }
    }

    if !discardingOversizedRecord, !currentRecord.isEmpty {
      try Task.checkCancellation()
      onRecord(currentRecord)
      deliveredRecordCount += 1
    }
    return JSONLReadReport(
      bytesRead: bytesRead,
      deliveredRecordCount: deliveredRecordCount,
      oversizedRecordCount: oversizedRecordCount)
  }
}
