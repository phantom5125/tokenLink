import Foundation

public protocol AppServerTransport: Sendable {
    func start(executable: URL) async throws
    func send(_ message: AppServerMessage) async throws
    func response(id: Int, timeout: Duration) async throws -> Data
    func stop() async
}

public enum AppServerMessage: Equatable, Sendable {
    case initialize
    case initialized
    case rateLimits(id: Int)

    func jsonLine() throws -> Data {
        let object: [String: Any]
        switch self {
        case .initialize:
            object = [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "tokenlink",
                        "title": "TokenLink",
                        "version": "0.1.0",
                    ],
                ],
            ]
        case .initialized:
            object = [
                "method": "initialized",
                "params": [:] as [String: String],
            ]
        case .rateLimits(let id):
            object = [
                "method": "account/rateLimits/read",
                "id": id,
                "params": [:] as [String: String],
            ]
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }
}

public enum AppServerTransportError: Error, Equatable, Sendable {
    case timeout
    case notRunning
    case malformedResponse
    case launch(String)
    case terminated(String)
}

public actor ProcessAppServerTransport: AppServerTransport {
    private var process: Process?
    private var input: FileHandle?
    private var readerTasks: [Task<Void, Never>] = []
    private let responses = JSONLResponseBuffer()
    private let stderrTail = BoundedTextBuffer(limit: 2_000)

    public init() {}

    public func start(executable: URL) async throws {
        if process != nil { await stop() }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppServerTransportError.launch(error.localizedDescription)
        }

        self.process = process
        self.input = stdin.fileHandleForWriting
        let responseBuffer = responses
        let errorBuffer = stderrTail
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        readerTasks = [
            Task.detached {
                while !Task.isCancelled {
                    let data = stdoutHandle.availableData
                    if data.isEmpty { break }
                    await responseBuffer.append(data)
                }
            },
            Task.detached {
                while !Task.isCancelled {
                    let data = stderrHandle.availableData
                    if data.isEmpty { break }
                    await errorBuffer.append(data)
                }
            },
        ]
    }

    public func send(_ message: AppServerMessage) async throws {
        guard let process, process.isRunning, let input else {
            throw AppServerTransportError.notRunning
        }
        do {
            try input.write(contentsOf: message.jsonLine())
        } catch {
            throw AppServerTransportError.terminated(error.localizedDescription)
        }
    }

    public func response(id: Int, timeout: Duration) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if let line = await responses.takeResponse(id: id) {
                return line
            }
            if let process, !process.isRunning {
                let tail = await stderrTail.text()
                throw AppServerTransportError.terminated(tail)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw AppServerTransportError.timeout
    }

    public func stop() async {
        try? input?.close()
        if let process, process.isRunning {
            process.terminate()
        }
        for task in readerTasks { task.cancel() }
        readerTasks.removeAll()
        input = nil
        process = nil
        await responses.reset()
    }
}

public struct CodexAppServerClient: Sendable {
    private let executable: URL
    private let transport: any AppServerTransport

    public init(executable: URL, transport: any AppServerTransport) {
        self.executable = executable
        self.transport = transport
    }

    public func readRateLimits(timeout: Duration = .seconds(5)) async throws -> Data {
        do {
            try await transport.start(executable: executable)
            try await transport.send(.initialize)
            try await transport.send(.initialized)
            try await transport.send(.rateLimits(id: 1))
            let response = try await transport.response(id: 1, timeout: timeout)
            await transport.stop()
            return response
        } catch {
            await transport.stop()
            throw error
        }
    }
}

private actor JSONLResponseBuffer {
    private var partial = Data()
    private var lines: [Data] = []

    func append(_ data: Data) {
        partial.append(data)
        while let newline = partial.firstIndex(of: 0x0A) {
            let line = Data(partial[..<newline])
            partial.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
    }

    func takeResponse(id: Int) -> Data? {
        guard let index = lines.firstIndex(where: { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let number = object["id"] as? NSNumber
            else { return false }
            return number.intValue == id
        }) else { return nil }
        return lines.remove(at: index)
    }

    func reset() {
        partial.removeAll(keepingCapacity: false)
        lines.removeAll(keepingCapacity: false)
    }
}

private actor BoundedTextBuffer {
    private let limit: Int
    private var data = Data()

    init(limit: Int) { self.limit = limit }

    func append(_ newData: Data) {
        data.append(newData)
        if data.count > limit {
            data.removeFirst(data.count - limit)
        }
    }

    func text() -> String {
        String(decoding: data, as: UTF8.self)
    }
}
