import DeepLinkNow
import Foundation

/// All DeepLinkNow calls in this example live here.
///
/// The whole integration is three calls:
///   1. `DeepLinkNow.initializeThrowing(config:)`   once, at startup (throws `DeepLinkNowError`)
///   2. `DeepLinkNow.checkDeferredDeepLink()`        once, on first launch after install (never throws)
///   3. `DeepLinkNow.parseLink(_:)`                  for Universal Links that open the app
@MainActor
final class DeepLinkModel: ObservableObject {
    /// "test_api_key" is DeepLinkNow's demo key (returns sample data). Use your app's key from
    /// the dashboard (Dashboard → your app → API keys) to test real links.
    static let apiKey = "test_api_key"

    @Published var isInitialized = false
    @Published var initError: String?

    /// `nil` = not checked yet. `.some(nil)` = checked, no deferred link.
    @Published var deferredLink: DLNDeferredDeepLink??
    @Published var deferredError: String?

    /// Fingerprint matches below this score are ignored. `nil` (off) by default: the SDK
    /// returns the best candidate and you decide using confidenceScore / matchQuality.
    @Published var minConfidence: Double?

    @Published var openedLink: DLNParsedLink?
    @Published var openedLinkError: String?

    func start() async {
        guard !isInitialized else { return }
        do {
            try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
            isInitialized = true
        } catch {
            initError = String(describing: error)
            return
        }
        await checkDeferredDeepLink(force: false)
    }

    /// Returns nil when there is no link, or when this install has already been checked
    /// (unless `force`). On iOS it reads the pasteboard first (the landing page copied the
    /// link there; iOS 16+ may ask the user to allow pasting), then falls back to fingerprinting.
    func checkDeferredDeepLink(force: Bool) async {
        // Never throws (SDK-85): nil means "no link" or "the check failed". Your app just carries
        // on to its normal start screen; DeepLinkNow.lastError says why when it failed.
        let link = await DeepLinkNow.checkDeferredDeepLink(
            DLNDeferredOptions(minConfidence: minConfidence, force: force)
        )
        deferredLink = .some(link)
        deferredError = link == nil ? DeepLinkNow.lastError.map { String(describing: $0) } : nil
        // In a real app: if let link { router.open(path: link.path, query: link.queryParams) }
    }

    /// For testing: forget that this install was checked, so the next check runs again.
    func resetDeferredDeepLink() {
        DeepLinkNow.resetDeferredDeepLink()
        deferredLink = nil
    }

    func handleOpenedLink(_ url: URL) {
        // nil when the URL is not on one of your app's DeepLinkNow domains.
        openedLink = DeepLinkNow.parseLink(url)
        openedLinkError = openedLink == nil ? "Not a DeepLinkNow link: \(url.absoluteString)" : nil
    }
}

/// `["ref": .string("nl"), "beta": .flag]` → `beta=true, ref=nl`
func describe(_ query: [String: DLNQueryValue]) -> String {
    if query.isEmpty { return "{}" }
    return query.keys.sorted().map { key -> String in
        switch query[key]! {
        case .string(let value): return "\(key)=\(value)"
        case .flag: return "\(key)=true"
        case .list(let values): return "\(key)=[\(values.joined(separator: ", "))]"
        }
    }.joined(separator: ", ")
}
