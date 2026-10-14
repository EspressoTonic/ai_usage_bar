import Foundation
import Darwin

/// Validates the opened object, so rotation/path replacement cannot bypass type/size checks.
enum CredentialFile {
    static func read(_ url: URL, maximum: Int = 1_048_576) throws -> Data {
        guard url.isFileURL, !url.path.utf8.contains(0), maximum >= 0, maximum <= 1_048_576 else {
            throw ProviderFailure(.configuration, "Invalid CLI sign-in file location or size limit.")
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw ProviderFailure(.configuration, "CLI sign-in file is unavailable. Choose the actual file, not a symlink, or sign in with the CLI first.")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            throw ProviderFailure(.configuration, "CLI sign-in must be a regular file owned by your user.")
        }
        guard info.st_mode & 0o077 == 0 else {
            throw ProviderFailure(.configuration, "CLI sign-in file permissions are too broad. Restrict the file to your user (0600) before enabling this adapter.")
        }
        guard info.st_size >= 0, info.st_size <= maximum else {
            throw ProviderFailure(.configuration, "CLI sign-in file is unexpectedly large.")
        }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maximum {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximum + 1 - data.count))
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ProviderFailure(.configuration, "CLI sign-in file could not be read.") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        // Also catches a file growing after fstat; allocation never exceeds the limit by more than one byte.
        throw ProviderFailure(.configuration, "CLI sign-in file exceeds its size limit.")
    }
}
