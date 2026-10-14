import Foundation
import Darwin

/// Owner-only files, relative to an opened directory. Never follows a file/directory symlink.
public enum PrivateFiles {
    private static func directoryFD(_ directory: URL, create: Bool) throws -> Int32 {
        if create, mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw BridgeError("Cannot create private storage.") }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BridgeError("Private storage directory is unavailable.") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            close(fd); throw BridgeError("Storage must be an owner-only directory belonging to this user.")
        }
        return fd
    }
    private static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw BridgeError("Invalid private file name.")
        }
    }
    public static func read(directory: URL, name: String, maximum: Int = 1_048_576) throws -> Data? {
        try validate(name)
        guard maximum >= 0, maximum <= 1_048_576 else { throw BridgeError("Invalid private file size limit.") }
        let parent = try directoryFD(directory, create: true); defer { close(parent) }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw BridgeError("Private file is unavailable or is a symbolic link.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_size <= maximum else { throw BridgeError("Private file ownership, permissions or size is invalid.") }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maximum {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximum + 1 - data.count))
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw BridgeError("Private file could not be read.") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw BridgeError("Private file exceeds its size limit.")
    }
    public static func write(_ data: Data, directory: URL, name: String) throws {
        try validate(name)
        guard data.count <= 1_048_576 else { throw BridgeError("Private file exceeds its size limit.") }
        let parent = try directoryFD(directory, create: true); defer { close(parent) }
        // Atomic rename replaces a destination symlink itself; it never writes through one.
        let temporary = ".write-" + UUID().uuidString
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BridgeError("Cannot create a private temporary file.") }
        defer { close(fd); unlinkat(parent, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw BridgeError("Private file could not be saved.") }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(parent, temporary, parent, name) == 0 else { throw BridgeError("Private file could not be committed.") }
    }
    public static func remove(directory: URL, name: String) throws {
        try validate(name)
        let parent = try directoryFD(directory, create: true); defer { close(parent) }
        guard unlinkat(parent, name, 0) == 0 || errno == ENOENT else { throw BridgeError("Private file could not be removed.") }
    }
}
