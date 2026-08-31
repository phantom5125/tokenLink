import Darwin
import Foundation

public enum JSONLStreamingReaderError: Error, Equatable, Sendable {
  case notRegularFile
  case openFailed(Int32)
  case inspectFailed(Int32)
}

public struct JSONLReadReport: Equatable, Sendable {
  public let bytesRead: Int
  public let deliveredRecordCount: Int
  public let oversizedRecordCount: Int
  public let byteLimitExceeded: Bool

  public init(
    bytesRead: Int,
    deliveredRecordCount: Int,
    oversizedRecordCount: Int,
    byteLimitExceeded: Bool = false
  ) {
    self.bytesRead = bytesRead
    self.deliveredRecordCount = deliveredRecordCount
    self.oversizedRecordCount = oversizedRecordCount
    self.byteLimitExceeded = byteLimitExceeded
  }
}

public struct JSONLStreamingReader: Sendable {
  public static let chunkBytes = 65_536
  public static let maximumRecordBytes = 1_048_576

  public init() {}

  public func read(
    url: URL,
    maximumBytes: Int? = nil,
    onRecord: (Data) -> Void
  ) throws -> JSONLReadReport {
    try Task.checkCancellation()
    let handle = try openRegularFile(at: url)
    defer { try? handle.close() }

    var currentRecord = Data()
    var discardingOversizedRecord = false
    var bytesRead = 0
    var deliveredRecordCount = 0
    var oversizedRecordCount = 0
    var byteLimitExceeded = false
    let byteLimit = maximumBytes.map { max(0, $0) }

    while true {
      try Task.checkCancellation()
      let readCount: Int
      if let byteLimit {
        let remaining = byteLimit - bytesRead
        readCount = remaining >= Self.chunkBytes ? Self.chunkBytes : max(1, remaining + 1)
      } else {
        readCount = Self.chunkBytes
      }
      guard var chunk = try handle.read(upToCount: readCount), !chunk.isEmpty else {
        break
      }
      var stopAfterChunk = false
      if let byteLimit {
        let remaining = max(0, byteLimit - bytesRead)
        if chunk.count > remaining {
          chunk = Data(chunk.prefix(remaining))
          byteLimitExceeded = true
          stopAfterChunk = true
        }
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

      if segmentStart < chunk.endIndex, !discardingOversizedRecord {
        let tail = chunk[segmentStart..<chunk.endIndex]
        if currentRecord.count + tail.count > Self.maximumRecordBytes {
          oversizedRecordCount += 1
          currentRecord.removeAll(keepingCapacity: false)
          discardingOversizedRecord = true
        } else {
          currentRecord.append(contentsOf: tail)
        }
      }
      if stopAfterChunk { break }
    }

    if !byteLimitExceeded, !discardingOversizedRecord, !currentRecord.isEmpty {
      try Task.checkCancellation()
      onRecord(currentRecord)
      deliveredRecordCount += 1
    }
    return JSONLReadReport(
      bytesRead: bytesRead,
      deliveredRecordCount: deliveredRecordCount,
      oversizedRecordCount: oversizedRecordCount,
      byteLimitExceeded: byteLimitExceeded)
  }

  private func openRegularFile(at url: URL) throws -> FileHandle {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    }
    guard descriptor >= 0 else {
      let code = errno
      if code == ELOOP { throw JSONLStreamingReaderError.notRegularFile }
      throw JSONLStreamingReaderError.openFailed(code)
    }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      throw JSONLStreamingReaderError.inspectFailed(code)
    }
    guard metadata.st_mode & S_IFMT == S_IFREG else {
      Darwin.close(descriptor)
      throw JSONLStreamingReaderError.notRegularFile
    }
    return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }
}
