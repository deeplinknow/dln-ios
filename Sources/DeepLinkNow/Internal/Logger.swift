import Foundation

/// `[DeepLinkNow]`-prefixed logging (SDK-70/71). Debug lines only with `enableLogs`;
/// warnings always. Never pass the API key or non-DLN clipboard content here.
struct Logger: Sendable {
    let enabled: Bool
    let sink: @Sendable (String) -> Void

    func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        sink("[DeepLinkNow] " + message())
    }

    func warn(_ message: String) {
        sink("[DeepLinkNow] Warning: " + message)
    }

    /// `dln_pub_test_0123456789abcdef` → `dln_…cdef` (SDK-63).
    static func mask(_ apiKey: String) -> String {
        guard apiKey.count > 8 else { return "…" }
        let prefix = apiKey.prefix(4)
        let suffix = apiKey.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
