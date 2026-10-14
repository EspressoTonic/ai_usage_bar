import Foundation

/// Streams provider JSON rather than buffering an unbounded body before validating its size.
enum BoundedHTTP {
    static func data(for request: URLRequest, maximum: Int = 1_048_576,
                     configuration: URLSessionConfiguration = .ephemeral) async throws -> (Data, HTTPURLResponse) {
        guard maximum > 0, maximum <= 1_048_576 else {
            throw ProviderFailure(.configuration, "Invalid provider response size limit.")
        }
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        // Cancels the unread body on status rejection, overflow, cancellation or any other exit.
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let (bytes, response) = try await session.bytes(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else {
                    throw ProviderFailure(.malformed, "Invalid provider response.")
                }
                // Caller classifies HTTP errors using headers. Never retain their arbitrary response bodies.
                guard (200..<300).contains(http.statusCode) else { return (Data(), http) }
                guard http.expectedContentLength <= Int64(maximum) else {
                    throw ProviderFailure(.malformed, "Provider response exceeded its size limit.")
                }
                var data = Data()
                if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < maximum else {
                        throw ProviderFailure(.malformed, "Provider response exceeded its size limit.")
                    }
                    data.append(byte)
                }
                return (data, http)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let failure = error as? ProviderFailure { throw failure }
                // Raw transport errors can include URLs or private server details.
                throw ProviderFailure(.transport, "Network request failed or timed out.")
            }
        } onCancel: { session.invalidateAndCancel() }
    }
}

enum RateLimitBackoff {
    static func delay(_ header: String?) -> TimeInterval {
        let parsed = header.flatMap(Double.init)
        return parsed.flatMap { $0.isFinite ? min(86_400, max(30, $0)) : nil } ?? 120
    }
}
