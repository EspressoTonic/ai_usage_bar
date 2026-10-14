import Foundation
import Darwin

public enum BridgePaths {
    public static var directory: URL { URL(fileURLWithPath: "/private/tmp/ai-usage-bar-\(getuid())", isDirectory: true) }
    public static var socket: String { directory.appendingPathComponent("bridge.sock").path }
}

public struct BridgeError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

private func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeError("Socket path is too long.") }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return address
}
private func connectedSocket(_ path: String) throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw BridgeError("Cannot create a local connection.") }
    var address = try socketAddress(path)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0 else { close(fd); throw BridgeError("Open AI Usage Bar first.") }
    var uid: uid_t = 0; var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); throw BridgeError("Local bridge owner mismatch.") }
    return fd
}
private func timeouts(_ fd: Int32) {
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
}
private func readLine(_ fd: Int32, maximum: Int) throws -> Data {
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < maximum {
        let count = Darwin.read(fd, &buffer, min(buffer.count, maximum - data.count))
        guard count > 0 else { throw BridgeError("Local bridge timed out or closed.") }
        data.append(contentsOf: buffer.prefix(count))
        if let end = data.firstIndex(of: 10) { return data.prefix(upTo: end) }
    }
    throw BridgeError("Local message exceeds its size limit.")
}
private func writeLine(_ fd: Int32, data: Data) throws {
    let message = data + Data([10])
    try message.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            guard n > 0 else { throw BridgeError("Local bridge write failed.") }
            offset += n
        }
    }
}

public enum UnixBridgeClient {
    public static func request(_ request: BridgeRequest, path: String = BridgePaths.socket) throws -> BridgeResponse {
        let fd = try connectedSocket(path); defer { close(fd) }; timeouts(fd)
        try writeLine(fd, data: JSONEncoder().encode(request))
        return try JSONDecoder().decode(BridgeResponse.self, from: readLine(fd, maximum: 262_144))
    }
}

public final class UnixBridgeServer: @unchecked Sendable {
    private var listener: Int32 = -1
    private let lock = NSLock()
    private let pending = DispatchSemaphore(value: 4)
    private let queue = DispatchQueue(label: "aiusagebar.bridge", qos: .utility)
    private let path: String
    private let handler: @Sendable (BridgeRequest) async -> BridgeResponse
    public init(path: String = BridgePaths.socket, handler: @escaping @Sendable (BridgeRequest) async -> BridgeResponse) {
        self.path = path; self.handler = handler
    }
    public func start() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        var statInfo = stat()
        if lstat(directory.path, &statInfo) == 0 {
            guard (statInfo.st_mode & S_IFMT) == S_IFDIR, statInfo.st_uid == getuid(),
                  statInfo.st_mode & 0o077 == 0 else { throw BridgeError("Bridge directory must be private and owned by this user.") }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }
        if lstat(path, &statInfo) == 0 {
            guard (statInfo.st_mode & S_IFMT) == S_IFSOCK, statInfo.st_uid == getuid() else { throw BridgeError("Bridge path is not this user's socket.") }
            if let fd = try? connectedSocket(path) { close(fd); throw BridgeError("AI Usage Bar is already running.") }
            unlink(path)
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError("Could not create bridge.") }
        var address = try socketAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw BridgeError("Could not bind the local bridge.") }
        guard chmod(path, 0o600) == 0 else { close(fd); unlink(path); throw BridgeError("Could not protect the local socket.") }
        guard listen(fd, 4) == 0 else { close(fd); unlink(path); throw BridgeError("Could not listen on bridge.") }
        lock.lock(); listener = fd; lock.unlock()
        queue.async { [weak self] in
            while let self, self.isCurrent(fd) {
                let peer = accept(fd, nil, nil)
                if peer < 0 { if !self.isCurrent(fd) { break }; continue }
                // Bound asynchronous handlers too; serial accept alone does not bound in-flight Tasks.
                guard self.pending.wait(timeout: .now()) == .success else { close(peer); continue }
                timeouts(peer)
                var uid: uid_t = 0; var gid: gid_t = 0
                guard getpeereid(peer, &uid, &gid) == 0, uid == getuid() else { close(peer); self.pending.signal(); continue }
                do {
                    let request = try JSONDecoder().decode(BridgeRequest.self, from: readLine(peer, maximum: 8192))
                    let handler = self.handler; let pending = self.pending
                    Task {
                        defer { pending.signal() }
                        let response = await handler(request)
                        try? writeLine(peer, data: JSONEncoder().encode(response))
                        close(peer)
                    }
                } catch { close(peer); self.pending.signal() }
            }
        }
    }
    private func isCurrent(_ fd: Int32) -> Bool { lock.lock(); defer { lock.unlock() }; return listener == fd }
    public func stop() {
        lock.lock(); let fd = listener; listener = -1; lock.unlock()
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); unlink(path) }
    }
    deinit { stop() }
}
