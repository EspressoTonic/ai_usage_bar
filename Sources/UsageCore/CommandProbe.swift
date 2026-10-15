import Foundation
import Darwin

struct CommandOutput { let status: Int32; let stdout: Data; let stderr: Data }

/// One owned process group, bounded pipes and a monotonic deadline. Blocking
/// POSIX operations run on GCD, never Swift's cooperative executor.
struct ProbeDialogue {
    var initialInput: Data
    var receive: (Data) throws -> (input: Data, finished: Bool)
}

enum CommandProbe {
    private final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        private var cancelled = false
        func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true; if let pid { kill(-pid, SIGKILL) } }
        func register(_ value: pid_t) { lock.lock(); defer { lock.unlock() }; pid = value; if cancelled { kill(-value, SIGKILL) } }
        func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
        func wait(_ value: pid_t, status: inout Int32) -> pid_t {
            lock.lock(); defer { lock.unlock() }
            var info = siginfo_t()
            let observed = waitid(P_PID, id_t(value), &info, WEXITED | WNOHANG | WNOWAIT)
            if observed < 0 { return -1 }
            guard info.si_pid == value else { return 0 }
            // Keep the exited parent unreaped until its group is stopped, so
            // its PID/group identity cannot be recycled before the signal.
            kill(-value, SIGKILL)
            let reaped = waitpid(value, &status, WNOHANG)
            if reaped == value { pid = nil }
            return reaped
        }
        func finish(_ value: pid_t) {
            lock.lock(); defer { lock.unlock() }
            guard pid == value else { return }
            kill(-value, SIGKILL)
            var status: Int32 = 0
            while waitpid(value, &status, 0) < 0 && errno == EINTR {}
            pid = nil
        }
    }
    static func run(executable: URL, arguments: [String], environment: [String: String], directory: URL,
                    timeout: TimeInterval, maximum: Int = 1_048_576, dialogue: ProbeDialogue? = nil) async throws -> CommandOutput {
        guard timeout.isFinite, timeout > 0, timeout <= 90, maximum > 0, maximum <= 1_048_576 else {
            throw ProviderFailure(.configuration, "Invalid CLI probe limits.")
        }
        let control = Control()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try execute(executable: executable, arguments: arguments,
                        environment: environment, directory: directory, timeout: timeout, maximum: maximum, control: control, dialogue: dialogue)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { control.cancel() })
    }
    private static func execute(executable: URL, arguments: [String], environment: [String: String], directory: URL,
                                timeout: TimeInterval, maximum: Int, control: Control, dialogue: ProbeDialogue?) throws -> CommandOutput {
        try control.check()
        var descriptors: [Int32] = []
        func pipePair() throws -> [Int32] {
            var pair: [Int32] = [0, 0]
            guard pipe(&pair) == 0 else { throw ProviderFailure(.transport, "Could not prepare the CLI probe.") }
            descriptors += pair
            for fd in pair { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
            return pair
        }
        defer { for fd in descriptors where fd >= 0 { close(fd) } }
        let output = try pipePair(), errorOutput = try pipePair()
        let input = dialogue == nil ? nil : try pipePair()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw ProviderFailure(.transport, "Could not prepare the CLI probe.") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw ProviderFailure(.transport, "Could not prepare the CLI probe.") }
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        let setup = [posix_spawnattr_setflags(&attributes, flags), posix_spawnattr_setpgroup(&attributes, 0),
                     posix_spawn_file_actions_addchdir_np(&actions, directory.path),
                     input.map { posix_spawn_file_actions_adddup2(&actions, $0[0], STDIN_FILENO) } ?? posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
                     posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO),
                     posix_spawn_file_actions_adddup2(&actions, errorOutput[1], STDERR_FILENO)]
        guard setup.allSatisfy({ $0 == 0 }) else { throw ProviderFailure(.transport, "Could not prepare the CLI probe.") }
        for fd in descriptors { guard posix_spawn_file_actions_addclose(&actions, fd) == 0 else { throw ProviderFailure(.transport, "Could not prepare the CLI probe.") } }
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let env = environment.keys.sorted().map { strdup("\($0)=\(environment[$0]!)") } + [nil]
        defer { for value in argv + env { free(value) } }
        var pid: pid_t = 0
        let launched = argv.withUnsafeBufferPointer { av in env.withUnsafeBufferPointer { ev in
            posix_spawn(&pid, executable.path, &actions, &attributes,
                        UnsafeMutablePointer(mutating: av.baseAddress!), UnsafeMutablePointer(mutating: ev.baseAddress!))
        } }
        guard launched == 0 else { throw ProviderFailure(.configuration, "CLI could not be launched. Check the selected executable.") }
        control.register(pid); defer { control.finish(pid) }
        for fd in [output[1], errorOutput[1]] + (input.map { [$0[0]] } ?? []) {
            close(fd); if let index = descriptors.firstIndex(of: fd) { descriptors[index] = -1 }
        }
        var streams = [pollfd(fd: output[0], events: Int16(POLLIN), revents: 0),
                       pollfd(fd: errorOutput[0], events: Int16(POLLIN), revents: 0)]
        for item in streams { _ = fcntl(item.fd, F_SETFL, O_NONBLOCK) }
        if let input { _ = fcntl(input[1], F_SETFL, O_NONBLOCK); _ = fcntl(input[1], F_SETNOSIGPIPE, 1) }
        var pending = dialogue?.initialInput ?? Data(), lines = Data(), finished = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffers = [Data(), Data()], status: Int32 = 0, exited = false
        while true {
            try control.check()
            if ProcessInfo.processInfo.systemUptime >= deadline {
                throw ProviderFailure(.transport, "CLI quota read timed out. Verify sign-in and connectivity in its terminal.")
            }
            if let input, !pending.isEmpty {
                let sent = pending.withUnsafeBytes { Darwin.write(input[1], $0.baseAddress, $0.count) }
                if sent > 0 { pending.removeFirst(sent) }
                else if sent < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
                    throw ProviderFailure(.transport, "CLI input connection closed.")
                }
            }
            let polled = poll(&streams, nfds_t(streams.count), 40)
            if polled < 0 && errno != EINTR { throw ProviderFailure(.transport, "CLI output could not be read.") }
            for index in streams.indices where streams[index].fd >= 0 && streams[index].revents != 0 {
                var bytes = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = Darwin.read(streams[index].fd, &bytes, bytes.count)
                    if count > 0 {
                        guard buffers[0].count + buffers[1].count + count <= maximum else {
                            throw ProviderFailure(.malformed, "CLI output exceeded its size limit.")
                        }
                        buffers[index].append(contentsOf: bytes.prefix(count))
                        if index == 0, let dialogue {
                            lines.append(contentsOf: bytes.prefix(count))
                            while let end = lines.firstIndex(of: 10) {
                                let line = Data(lines[..<end]); lines.removeSubrange(...end)
                                let next = try dialogue.receive(line)
                                guard pending.count + next.input.count <= 16_384 else {
                                    throw ProviderFailure(.malformed, "CLI request exceeded its size limit.")
                                }
                                pending.append(next.input); finished = next.finished
                                if finished { break }
                            }
                            if finished { break }
                        }
                    } else if count == 0 { streams[index].fd = -1; break }
                    else if errno == EINTR { continue }
                    else if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    else { throw ProviderFailure(.transport, "CLI output could not be read.") }
                    try control.check()
                    if ProcessInfo.processInfo.systemUptime >= deadline { break }
                }
            }
            if finished {
                try control.check()
                return CommandOutput(status: 0, stdout: Data(), stderr: Data())
            }
            if !exited {
                let result = control.wait(pid, status: &status)
                if result == pid { exited = true }
                else if result < 0 && errno != EINTR { throw ProviderFailure(.transport, "CLI completion could not be verified.") }
            }
            if exited && streams.allSatisfy({ $0.fd < 0 }) { break }
        }
        try control.check()
        let signal = status & 0x7f
        return CommandOutput(status: signal == 0 ? (status >> 8) & 0xff : 128 + signal,
                             stdout: buffers[0], stderr: buffers[1])
    }
}
