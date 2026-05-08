import Foundation

actor CodexAppServerClient {
    private let slot: Int
    private let codexHome: URL
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var readTask: Task<Void, Never>?

    init(slot: Int) throws {
        self.slot = slot
        guard let home = AccountSlotStore.codexHome(for: slot, create: true) else {
            throw LimitBarError.message("Application Support is unavailable.")
        }
        self.codexHome = home
        try AccountSlotStore.migrateLegacyCodexHomeIfNeeded(for: slot)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    }

    deinit {
        readTask?.cancel()
        if process.isRunning {
            process.terminate()
        }
    }

    func start() async throws {
        let codexPath = try Self.findCodexExecutable()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = [
            "app-server",
            "--listen", "stdio://",
            "-c", "cli_auth_credentials_store=\"file\"",
            "-c", "analytics.enabled=false"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CODEX_HOME": codexHome.path
        ]) { _, new in new }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        readTask = Task.detached { [weak self, output, process] in
            await Self.readLoop(output: output, process: process, owner: self)
        }

        _ = try await requestUntyped(
            "initialize",
            params: [
                "clientInfo": ["name": "LimitBar", "version": Bundle.main.appVersion],
                "protocolVersion": "2"
            ]
        )
        KeychainStore.saveAccountMarker(slot: slot, codexHome: codexHome.path)
    }

    func request<T: Decodable>(_ method: String, params: [String: Any]) async throws -> T {
        let data = try await requestUntyped(method, params: params)
        return try decoder.decode(T.self, from: data)
    }

    func requestUntyped(_ method: String, params: [String: Any]) async throws -> Data {
        guard process.isRunning else { throw LimitBarError.processUnavailable }
        let id = nextID
        nextID += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var line = data
        line.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [id] in
                try? await Task.sleep(nanoseconds: LimitBarConstants.codexRequestTimeoutNanoseconds)
                self.failRequest(
                    id,
                    error: LimitBarError.requestTimedOut(detail: "\(method) timed out waiting for Codex app-server.")
                )
            }
            pending[id] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
            input.fileHandleForWriting.write(line)
        }
    }

    private static func readLoop(output: Pipe, process: Process, owner: CodexAppServerClient?) async {
        let handle = output.fileHandleForReading
        var buffer = Data()

        while process.isRunning {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                await owner?.handleLine(Data(line))
            }
        }

        await owner?.failPendingRequests()
    }

    private func failPendingRequests() {
        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: LimitBarError.processUnavailable)
        }
    }

    private func failRequest(_ id: Int, error: Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(throwing: error)
    }

    private func handleLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? Int
        else {
            return
        }

        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()

        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "Codex request failed."
            request.continuation.resume(throwing: LimitBarError.message(message))
            return
        }

        guard let result = object["result"] else {
            request.continuation.resume(throwing: LimitBarError.invalidResponse)
            return
        }

        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            request.continuation.resume(returning: resultData)
        } catch {
            request.continuation.resume(throwing: error)
        }
    }

    private static func findCodexExecutable() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw LimitBarError.message("Could not find the Codex CLI. Install Codex or add it to /opt/homebrew/bin/codex.")
    }

}

private struct PendingRequest {
    let continuation: CheckedContinuation<Data, Error>
    let timeoutTask: Task<Void, Never>
}
