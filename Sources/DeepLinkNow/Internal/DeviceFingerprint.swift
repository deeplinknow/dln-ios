import Foundation
import UIKit

/// Builds the `/sdk/match` request body (SDK-21/22/60, IOS-20/21/22).
/// UIKit values are read on the main actor (IOS-11); the rest is plain data.
struct DeviceSnapshot {
    let systemVersion: String
    let hardwareModel: String       // UIDevice.model, e.g. "iPhone" (used in the UA only)
    let deviceClass: String         // web device class: iPhone / iPad
    let isTablet: Bool
    let screenWidth: Int            // logical points
    let screenHeight: Int
    let pixelRatio: Double
    let vendorId: String?

    @MainActor static func current() -> DeviceSnapshot {
        let device = UIDevice.current
        let screen = UIScreen.main
        let isPad = device.userInterfaceIdiom == .pad
        return DeviceSnapshot(
            systemVersion: device.systemVersion,
            hardwareModel: device.model,
            deviceClass: isPad ? "iPad" : "iPhone",
            isTablet: isPad,
            screenWidth: Int(screen.bounds.width),
            screenHeight: Int(screen.bounds.height),
            pixelRatio: (Double(screen.scale) * 100).rounded() / 100,
            vendorId: device.identifierForVendor?.uuidString
        )
    }
}

enum DeviceFingerprint {
    /// Process start, used as `installed_at` (the SDK instance creation time).
    static let processStart = Date()

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func simpleHash(_ str: String) -> String {
        // Same algorithm as SDK <= 1.0.4, so the value is stable across versions.
        var hash: Int = 0
        for char in str.unicodeScalars {
            hash = ((hash << 5) &- hash) &+ Int(char.value)
        }
        return String(hash, radix: 16)
    }

    /// SDK-22: the user's preferred language as a BCP-47 tag (`fr-FR`), comparable with the
    /// browser's `navigator.language` on the link page. `Locale.current` follows the app's
    /// bundled localizations (an English-only app on a French device reports `en-FR`), so it
    /// is only the fallback, then `en-US`.
    static func language(preferred: [String] = Locale.preferredLanguages,
                         current: Locale = .current) -> String {
        bcp47(preferred.first) ?? bcp47(current.identifier) ?? "en-US"
    }

    /// `fr_FR@calendar=gregorian` → `fr-FR`. Empty input yields nil.
    static func bcp47(_ identifier: String?) -> String? {
        guard let identifier = identifier else { return nil }
        let tag = (identifier.split(separator: "@").first.map(String.init) ?? "")
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    static func body(snapshot s: DeviceSnapshot, now: Date = Date()) -> [String: Any] {
        let language = language()
        let timezone = TimeZone.current.identifier
        let userAgent = "Mozilla/5.0 (\(s.hardwareModel); CPU iOS \(s.systemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(s.systemVersion) Mobile/15E148 Safari/604.1"
        let hardwareFingerprint = simpleHash([
            "ios", s.systemVersion, String(s.screenWidth), String(s.screenHeight),
            String(s.pixelRatio), language, timezone,
        ].joined(separator: "|"))

        let metadata: [String: Any] = [
            "screen_width": s.screenWidth,
            "screen_height": s.screenHeight,
            "pixel_ratio": s.pixelRatio,
            "color_depth": 32,
            "is_tablet": s.isTablet,
            "cpu_cores": ProcessInfo.processInfo.processorCount,
            "source": "mobile",
        ]

        let fingerprint: [String: Any] = [
            "user_agent": userAgent,
            "platform": "ios",
            "os_version": s.systemVersion,
            "device_model": s.deviceClass,
            "language": language,
            "timezone": timezone,
            "installed_at": iso8601(processStart),
            "last_opened_at": iso8601(now),
            "device_id": s.vendorId ?? NSNull(),
            "advertising_id": NSNull(),          // IOS-20: never read the IDFA
            "vendor_id": s.vendorId ?? NSNull(),
            "hardware_fingerprint": hardwareFingerprint,
            "screen_width": s.screenWidth,
            "screen_height": s.screenHeight,
            "pixel_ratio": s.pixelRatio,
            "metadata": metadata,
        ]
        return ["fingerprint": fingerprint]
    }
}
