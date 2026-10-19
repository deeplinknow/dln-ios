import Foundation
import UIKit

/// Indirection over `UIPasteboard` so the deferred chain can be tested without the
/// iOS 16+ paste prompt. Every UIKit access happens on the main thread (IOS-11).
protocol PasteboardSource: AnyObject {
    /// Cheap check that never reads the content (no paste prompt).
    func hasContentWithoutReading() -> Bool
    /// iOS 14+: `detectPatterns(for: [.probableWebURL])`. `nil` = unknown (API unavailable or failed).
    func probablyContainsWebURL() async -> Bool?
    /// Reads the plain-text content. May show the system paste prompt.
    func readString() async -> String?
    /// Synchronous read for the legacy `checkClipboard()` API.
    func readStringSync() -> String?
}

final class SystemPasteboard: PasteboardSource {

    private func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }

    func hasContentWithoutReading() -> Bool {
        onMain {
            let board = UIPasteboard.general
            return board.hasURLs || board.hasStrings
        }
    }

    func probablyContainsWebURL() async -> Bool? {
        guard #available(iOS 14.0, macCatalyst 14.0, *) else {
            return await MainActor.run { UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings }
        }
        let hasAny = await MainActor.run { UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings }
        if !hasAny { return false }
        // detectPatterns may never call back (seen on Mac Catalyst), so race it against a
        // 1 s timeout; "unknown" (nil) means the caller falls back to reading.
        let resumed = Locked(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let finish: (Bool?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if first { continuation.resume(returning: value) }
            }
            DispatchQueue.main.async {
                UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                    switch result {
                    case .success(let patterns): finish(patterns.contains(.probableWebURL))
                    case .failure: finish(nil)
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { finish(nil) }
        }
    }

    func readString() async -> String? {
        await MainActor.run { UIPasteboard.general.string }
    }

    func readStringSync() -> String? {
        onMain { UIPasteboard.general.string }
    }
}
