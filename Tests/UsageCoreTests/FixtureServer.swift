import Foundation

/// Process/pipe APIs are blocking. Dispatch them outside Swift's cooperative executor,
/// including cleanup, so parallel native tests leave workers available for networking.
final class FixtureServer: @unchecked Sendable {
    let port: Int
    private let process: Process
    private let output: Pipe
    private init(port: Int, process: Process, output: Pipe) {
        self.port = port; self.process = process; self.output = output
    }
    private static func blocking<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result(catching: work))
            }
        }
    }
    static func withServer<T>(script: URL, mode: String,
                              body: (FixtureServer) async throws -> T) async throws -> T {
        let server: FixtureServer = try await blocking {
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script.path, mode]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let line = output.fileHandleForReading.availableData
            guard let port = Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(port) else {
                if process.isRunning { process.terminate() }; process.waitUntilExit()
                throw NSError(domain: "LoopbackFixture", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Fixture did not report a valid port."])
            }
            return FixtureServer(port: port, process: process, output: output)
        }
        do {
            let result = try await body(server)
            await server.stop()
            return result
        } catch {
            await server.stop()
            throw error
        }
    }
    func waitForBody() async throws -> Bool {
        try await Self.blocking {
            let marker = self.output.fileHandleForReading.availableData
            return String(decoding: marker, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "body-started"
        }
    }
    private func stop() async {
        _ = try? await Self.blocking {
            if self.process.isRunning { self.process.terminate() }
            self.process.waitUntilExit()
        }
    }
}


/// The app can run one named Codex probe plus one Antigravity probe. Bound
/// synthetic native processes the same way while HTTP/RPC tests remain parallel.
actor FixtureProcessBudget {
    static let shared = FixtureProcessBudget()
    private var available = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if available > 0 { available -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if !waiters.isEmpty { waiters.removeFirst().resume() }
        else { available += 1 }
    }
    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do { let value = try await body(); release(); return value }
        catch { release(); throw error }
    }
}
