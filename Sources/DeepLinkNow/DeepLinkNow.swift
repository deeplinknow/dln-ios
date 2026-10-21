import Foundation
import UIKit

/// DeepLinkNow iOS SDK. All members are static; internal state is lock-isolated (IOS-10).
///
/// Typical use:
/// ```swift
/// try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: "…"))
/// if let link = try await DeepLinkNow.checkDeferredDeepLink() { route(link.path, link.queryParams) }
/// ```
public final class DeepLinkNow {

    /// SDK version. Kept in sync with `DeepLinkNow.podspec` (IOS-01).
    public static let sdkVersion = "1.3.0"

    static let deferredCompletedKey = "com.deeplinknow.deferredCheckCompleted"
    static let clipboardCheckedKey = "com.deeplinknow.clipboardChecked"

    private init() {}

    // MARK: - Internal state

    /// A successfully initialized configuration. Immutable once built.
    final class Client {
        let api: APIClient
        let appInfo: DLNAppInfo
        let domains: Set<String>
        let logger: Logger

        init(api: APIClient, appInfo: DLNAppInfo, logger: Logger) {
            self.api = api
            self.appInfo = appInfo
            self.domains = Set(appInfo.linkDomains)
            self.logger = logger
        }
    }

    struct InFlightInit {
        let id: UUID
        let apiKey: String
        let baseUrl: String
        let task: Task<Client, Error>
    }

    struct State {
        var client: Client?
        var initError: DeepLinkNowError?
        var inFlight: InFlightInit?
        var deferred: (id: UUID, task: Task<DLNDeferredDeepLink?, Error>)?
        var enableLogs = false
        /// SDK-83: only the first initialize of a process may use the device cache;
        /// calling initialize again always asks the server (SDK-07).
        var initCacheConsulted = false
        /// SDK-85: the last failure of an everyday call, and which kind of call it came from.
        var lastError: DeepLinkNowError?
        var lastErrorKind: CallKind?
    }

    /// SDK-85: the kinds of call that set and clear `lastError`.
    enum CallKind {
        case initialize, deferredDeepLink, findDeferredUser
    }

    /// SDK-85: records a failure in `lastError` and returns it as a `DeepLinkNowError`.
    @discardableResult
    static func recordFailure(_ error: Error, kind: CallKind) -> DeepLinkNowError {
        let dlnError = (error as? DeepLinkNowError) ?? DeepLinkNowError(.network, underlying: error)
        state.withLock { s in
            s.lastError = dlnError
            s.lastErrorKind = kind
        }
        return dlnError
    }

    /// SDK-85: a success clears `lastError` when it came from the same kind of call.
    static func recordSuccess(kind: CallKind) {
        state.withLock { s in
            if s.lastErrorKind == kind {
                s.lastError = nil
                s.lastErrorKind = nil
            }
        }
    }

    /// Test seams. Production values are UIKit / `UserDefaults.standard` / `print`.
    struct Environment {
        var defaults: UserDefaults = .standard
        var pasteboard: PasteboardSource = SystemPasteboard()
        var logSink: (String) -> Void = { print($0) }
        var retryDelayScale: Double = 1
        var now: () -> Date = Date.init
    }

    static let state = Locked(State())
    static let environment = Locked(Environment())

    static var logger: Logger {
        let enabled = state.withLock { $0.enableLogs }
        let sink = environment.withLock { $0.logSink }
        return Logger(enabled: enabled, sink: sink)
    }

    /// Clears all in-memory state (tests only).
    static func resetForTesting() {
        state.withLock { state in
            state.inFlight?.task.cancel()
            state.deferred?.task.cancel()
            state = State()
        }
    }

    // MARK: - Initialization (SDK-01…09, IOS-05…08)

    /// Validates the API key and loads the app's link domains.
    /// Failures are logged, not thrown (SDK-85); check `isInitialized` / `initializationError` /
    /// `lastError`, or use `initializeThrowing(config:urlSession:)`.
    public static func initialize(config: DLNConfig, urlSession: URLSessionProtocol = URLSession.shared) async {
        do {
            _ = try await initializeThrowing(config: config, urlSession: urlSession)
        } catch {
            logger.warn("Initialization failed: \(error)")
        }
    }

    /// Validates the API key and loads the app's link domains, throwing a `DeepLinkNowError`
    /// (`invalidApiKey`, `accountInactive`, `noCredits`, `rateLimited`, `network`, `server`,
    /// `invalidResponse`, `invalidConfiguration`) on failure. A failure leaves `isInitialized == false`.
    /// The error is also recorded in `lastError` (SDK-85).
    @discardableResult
    public static func initializeThrowing(config: DLNConfig, urlSession: URLSessionProtocol = URLSession.shared) async throws -> DLNAppInfo {
        do {
            let info = try await performInitialize(config: config, urlSession: urlSession)
            recordSuccess(kind: .initialize)
            return info
        } catch {
            throw recordFailure(error, kind: .initialize)
        }
    }

    private static func performInitialize(config: DLNConfig, urlSession: URLSessionProtocol) async throws -> DLNAppInfo {
        let env = environment.current
        let configLogger = Logger(enabled: config.enableLogs, sink: env.logSink)

        let api: APIClient
        do {
            api = try APIClient(config: config, session: urlSession, logger: configLogger, delayScale: env.retryDelayScale)
        } catch {
            let dlnError = (error as? DeepLinkNowError) ?? DeepLinkNowError(.invalidConfiguration, underlying: error)
            state.withLock { s in
                s.inFlight?.task.cancel()
                s.inFlight = nil
                s.client = nil
                s.initError = dlnError
                s.enableLogs = config.enableLogs
            }
            throw dlnError
        }

        // Share an identical in-flight request (SDK-07), otherwise start a new one that supersedes it.
        let (id, task): (UUID, Task<Client, Error>) = state.withLock { s in
            s.enableLogs = config.enableLogs
            if let current = s.inFlight, current.apiKey == api.apiKey, current.baseUrl == api.baseUrl {
                return (current.id, current.task)
            }
            let id = UUID()
            let task = Task<Client, Error> { try await performInit(api: api, logger: configLogger) }
            s.inFlight = InFlightInit(id: id, apiKey: api.apiKey, baseUrl: api.baseUrl, task: task)
            return (id, task)
        }

        do {
            let client = try await task.value
            state.withLock { s in
                if s.inFlight?.id == id {
                    s.inFlight = nil
                    s.client = client
                    s.initError = nil
                }
            }
            return client.appInfo
        } catch {
            let dlnError = (error as? DeepLinkNowError) ?? DeepLinkNowError(.network, underlying: error)
            state.withLock { s in
                if s.inFlight?.id == id {
                    s.inFlight = nil
                    s.client = nil
                    s.initError = dlnError
                }
            }
            throw dlnError
        }
    }

    private static func performInit(api: APIClient, logger: Logger) async throws -> Client {
        let env = environment.current
        // SDK-83: a cold start within 24 hours of the last /init (same UTC month) reuses it.
        let firstInProcess = state.withLock { s -> Bool in
            defer { s.initCacheConsulted = true }
            return !s.initCacheConsulted
        }
        if firstInProcess,
           let cached = InitCache.load(from: env.defaults),
           cached.isUsable(apiKey: api.apiKey, baseUrl: api.baseUrl, now: env.now()) {
            logger.debug("Initialized app \(cached.alias) from the device cache (no /init request)")
            return Client(api: api, appInfo: cached.appInfo, logger: logger)
        }

        logger.debug("Initializing (key \(Logger.mask(api.apiKey)), baseUrl \(api.baseUrl))")
        // BILL-20: send the IDFV (same value as /match device_id) so MAU is counted per device.
        // FP-21: say which SDK is counting.
        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        let data = try await post(api, "init", body: [
            "device_id": deviceId ?? NSNull(),
            "sdk": "ios/\(sdkVersion)",
        ])
        let response: InitResponse
        do {
            response = try JSONDecoder().decode(InitResponse.self, from: data)
        } catch {
            throw DeepLinkNowError(.invalidResponse, statusCode: 200, message: "Unexpected /init response", underlying: error)
        }
        let alias = response.app.alias.lowercased()
        guard !alias.isEmpty else {
            throw DeepLinkNowError(.invalidResponse, statusCode: 200, message: "Missing app alias")
        }
        var domains = ["\(alias).deeplinknow.com"]
        let custom = (response.app.customDomains ?? [])
            .filter { $0.verified == true }
            .compactMap { $0.domain.map(LinkParsing.normalizeHost) }
            .filter { !$0.isEmpty }
        for domain in custom where !domains.contains(domain) { domains.append(domain) }

        let info = DLNAppInfo(
            appId: response.app.id,
            alias: alias,
            name: response.app.name,
            linkDomains: domains,
            primaryDomain: custom.first ?? domains[0],
            accountStatus: response.account.status.rawValue,
            creditsRemaining: response.account.creditsRemaining
        )
        logger.debug("Initialized app \(alias); link domains: \(domains.joined(separator: ", "))")
        InitCache(apiKey: api.apiKey, baseUrl: api.baseUrl, savedAt: env.now(), appInfo: info).save(to: env.defaults)
        return Client(api: api, appInfo: info, logger: logger)
    }

    /// `true` once an initialization has succeeded (and no later one has failed).
    public static var isInitialized: Bool {
        state.withLock { $0.client != nil }
    }

    /// The error the most recent initialization failed with, or `nil`.
    public static var initializationError: DeepLinkNowError? {
        state.withLock { $0.initError }
    }

    /// SDK-85: the typed error (SDK-55) from the most recent failed `initialize` /
    /// `initializeThrowing`, `checkDeferredDeepLink` / `checkDeferredDeepLinkThrowing` or
    /// `findDeferredUser` / `findDeferredUserThrowing`, or `nil`. The next successful call of
    /// the same kind clears it.
    public static var lastError: DeepLinkNowError? {
        state.withLock { $0.lastError }
    }

    /// App info from the last successful initialization.
    public static var appInfo: DLNAppInfo? {
        state.withLock { $0.client?.appInfo }
    }

    /// Waits for an in-flight init (SDK-06), else returns the current client or throws `.notInitialized`.
    static func requireClient() async throws -> Client {
        let snapshot = state.withLock { s in (s.inFlight?.task, s.client, s.initError) }
        if let task = snapshot.0 {
            do {
                return try await task.value
            } catch {
                let cause = (error as? DeepLinkNowError) ?? DeepLinkNowError(.network, underlying: error)
                throw DeepLinkNowError(.notInitialized, message: "Initialization failed", underlying: cause)
            }
        }
        if let client = snapshot.1 { return client }
        throw DeepLinkNowError(.notInitialized, message: "Call initialize() first", underlying: snapshot.2)
    }

    /// The trusted domains: the app's link domains after a successful init, `nil` before (provisional rule).
    static var currentDomains: Set<String>? {
        state.withLock { $0.client?.domains }
    }

    // MARK: - Deferred deep link (SDK-10…27, IOS-15/18)

    /// The one call: returns the deferred deep link on the first launch after install.
    ///
    /// Chain: pasteboard (when `useClipboard`) → fingerprint `/match`. Returns `nil` when nothing
    /// was found, or on any launch after a definitive outcome (unless `force`).
    ///
    /// Never throws (SDK-85): a failure (`.notInitialized`, `.network`, `.invalidApiKey`, …) also
    /// returns `nil`, is logged as a warning and is kept in `lastError`. Errors do not consume the
    /// first launch, so a later call retries. Use `checkDeferredDeepLinkThrowing` to get the error.
    public static func checkDeferredDeepLink(_ options: DLNDeferredOptions = DLNDeferredOptions()) async -> DLNDeferredDeepLink? {
        do {
            return try await checkDeferredDeepLinkThrowing(options)
        } catch let error as DeepLinkNowError where error.code == .notInitialized {
            logger.warn("checkDeferredDeepLink: SDK not initialized. Call initialize() first")
            return nil
        } catch {
            logger.warn("checkDeferredDeepLink failed: \(error)")
            return nil
        }
    }

    /// `checkDeferredDeepLink`, but throws `DeepLinkNowError` on failure (`.notInitialized`,
    /// `.network`, …). The error is also recorded in `lastError` (SDK-85).
    public static func checkDeferredDeepLinkThrowing(_ options: DLNDeferredOptions = DLNDeferredOptions()) async throws -> DLNDeferredDeepLink? {
        do {
            let link = try await runSharedDeferredCheck(options)
            recordSuccess(kind: .deferredDeepLink)
            return link
        } catch {
            throw recordFailure(error, kind: .deferredDeepLink)
        }
    }

    private static func runSharedDeferredCheck(_ options: DLNDeferredOptions) async throws -> DLNDeferredDeepLink? {
        let (id, task): (UUID, Task<DLNDeferredDeepLink?, Error>) = state.withLock { s in
            if let current = s.deferred { return (current.id, current.task) }
            let id = UUID()
            let task = Task<DLNDeferredDeepLink?, Error> { try await runDeferredChain(options) }
            s.deferred = (id, task)
            return (id, task)
        }
        defer {
            state.withLock { s in
                if s.deferred?.id == id { s.deferred = nil }
            }
        }
        return try await task.value
    }

    /// Clears the first-launch flag so the next `checkDeferredDeepLink` runs the chain again (SDK-26).
    public static func resetDeferredDeepLink() {
        let defaults = environment.withLock { $0.defaults }
        defaults.removeObject(forKey: deferredCompletedKey)
        defaults.removeObject(forKey: clipboardCheckedKey)
        InitCache.clear(in: defaults)
        state.withLock { s in
            s.deferred = nil
        }
        logger.debug("Deferred deep link state reset")
    }

    private static func runDeferredChain(_ options: DLNDeferredOptions) async throws -> DLNDeferredDeepLink? {
        let client = try await requireClient()
        let log = client.logger
        let env = environment.current
        let defaults = env.defaults

        if !options.force && defaults.bool(forKey: deferredCompletedKey) {
            log.debug("checkDeferredDeepLink: already completed on an earlier launch; returning nil")
            return nil
        }

        // 1. Pasteboard (SDK-12, IOS-27): at most one read per install unless forced.
        if options.useClipboard && (options.force || !defaults.bool(forKey: clipboardCheckedKey)) {
            let likely = await env.pasteboard.probablyContainsWebURL()
            if likely == false {
                log.debug("checkDeferredDeepLink: clipboard has no web URL (not read)")
            } else {
                let text = await env.pasteboard.readString()
                defaults.set(true, forKey: clipboardCheckedKey)
                if let text = text, let parsed = validatedClipboardLink(text, domains: client.domains) {
                    log.debug("checkDeferredDeepLink: clipboard hit \(parsed.url)")
                    defaults.set(true, forKey: deferredCompletedKey)
                    return DLNDeferredDeepLink(
                        path: parsed.path, queryParams: parsed.queryParams, fullPath: parsed.fullPath,
                        url: parsed.url, source: .clipboard, confidenceScore: 100, matchQuality: .high,
                        deeplinkId: nil, targetUrl: nil, campaignId: nil, metadata: nil,
                        matchedAt: nil, expiresAt: nil, matchDetails: nil)
                }
                log.debug("checkDeferredDeepLink: clipboard has no DLN link")
            }
        }

        // 2. Fingerprint (SDK-13/14). Errors propagate and leave the flag unset (SDK-24).
        let response: MatchResponse
        do {
            response = try await fetchMatches(client)
        } catch {
            log.debug("checkDeferredDeepLink: /match failed (\((error as? DeepLinkNowError)?.code.rawValue ?? "error"))")
            throw error
        }
        defaults.set(true, forKey: deferredCompletedKey)
        for match in response.matches {
            guard let deeplink = match.deeplink else { continue }
            if let min = options.minConfidence, match.confidenceScore < min { continue }
            log.debug("checkDeferredDeepLink: fingerprint match \(match.confidenceScore) \(match.matchQuality.rawValue)")
            return makeDeferred(from: match, deeplink: deeplink, client: client)
        }
        log.debug("checkDeferredDeepLink: no eligible fingerprint candidate (\(response.matches.count) returned)")
        return nil
    }

    /// SDK-17/18/19.
    static func makeDeferred(from match: Match, deeplink: DeeplinkMatch, client: Client) -> DLNDeferredDeepLink {
        let fullPath: String
        if let serverFullPath = deeplink.fullPath, !serverFullPath.isEmpty {
            fullPath = serverFullPath.hasPrefix("/") ? serverFullPath : "/" + serverFullPath
        } else if deeplink.targetUrl.isEmpty {
            fullPath = "/"
        } else if let absolute = URLComponents(string: deeplink.targetUrl),
                  let scheme = absolute.scheme?.lowercased(), scheme == "https" || scheme == "http", absolute.host != nil {
            // Absolute dashboard target: use its path + query.
            let path = absolute.percentEncodedPath.isEmpty ? "/" : absolute.percentEncodedPath
            let query = absolute.percentEncodedQuery ?? ""
            fullPath = query.isEmpty ? path : path + "?" + query
        } else {
            // On-demand links store `promo?code=…` without the leading slash (SDK-17).
            fullPath = deeplink.targetUrl.hasPrefix("/") ? deeplink.targetUrl : "/" + deeplink.targetUrl
        }
        let queryParams = deeplink.queryParams ?? LinkParsing.parseQuery(LinkParsing.query(fromFullPath: fullPath)).0

        let url: String
        if let target = URLComponents(string: deeplink.targetUrl),
           let scheme = target.scheme?.lowercased(), scheme == "https" || scheme == "http",
           let host = target.host, LinkParsing.isAllowedHost(host, domains: client.domains) {
            url = deeplink.targetUrl
        } else {
            url = "https://\(client.appInfo.primaryDomain)\(fullPath)"
        }

        return DLNDeferredDeepLink(
            path: LinkParsing.path(fromFullPath: fullPath),
            queryParams: queryParams,
            fullPath: fullPath,
            url: url,
            source: .fingerprint,
            confidenceScore: match.confidenceScore,
            matchQuality: match.matchQuality,
            deeplinkId: deeplink.id,
            targetUrl: deeplink.targetUrl,
            campaignId: deeplink.campaignId,
            metadata: deeplink.metadata,
            matchedAt: deeplink.matchedAt.isEmpty ? nil : deeplink.matchedAt,
            expiresAt: deeplink.expiresAt.isEmpty ? nil : deeplink.expiresAt,
            matchDetails: match.matchDetails)
    }

    // MARK: - Fingerprint matching (SDK-20/21/22)

    /// All fingerprint candidates from `/api/v1/sdk/match`, unfiltered and in server order.
    /// Returns `nil` when not initialized or on any error (logged, and kept in `lastError`, SDK-85);
    /// use `findDeferredUserThrowing()` for the error, or `checkDeferredDeepLink()`.
    public static func findDeferredUser() async -> MatchResponse? {
        do {
            return try await findDeferredUserThrowing()
        } catch let error as DeepLinkNowError where error.code == .notInitialized {
            logger.warn("SDK not initialized. Call initialize() first")
            return nil
        } catch {
            logger.warn("findDeferredUser failed: \(error)")
            return nil
        }
    }

    /// All fingerprint candidates from `/api/v1/sdk/match`, unfiltered and in server order.
    /// Zero matches is an empty response, not an error. Throws `DeepLinkNowError`, also
    /// recorded in `lastError` (SDK-85).
    public static func findDeferredUserThrowing() async throws -> MatchResponse {
        do {
            let client = try await requireClient()
            let response = try await fetchMatches(client)
            recordSuccess(kind: .findDeferredUser)
            return response
        } catch {
            throw recordFailure(error, kind: .findDeferredUser)
        }
    }

    /// Every SDK request goes through here. SDK-83: a 401 invalid key or 403 inactive account
    /// from any endpoint (`init`, `match`) deletes the init cache, so a revoked key or a closed
    /// account stops initializing from the device cache on the next launch.
    private static func post(_ api: APIClient, _ endpoint: String, body: [String: Any]) async throws -> Data {
        do {
            return try await api.post(endpoint, body: body)
        } catch let error as DeepLinkNowError where error.code == .invalidApiKey || error.code == .accountInactive {
            InitCache.clear(in: environment.current.defaults)
            throw error
        }
    }

    private static func fetchMatches(_ client: Client) async throws -> MatchResponse {
        let snapshot = await MainActor.run { DeviceSnapshot.current() }
        let body = DeviceFingerprint.body(snapshot: snapshot)
        client.logger.debug("Sending match request")
        let data = try await post(client.api, "match", body: body)
        do {
            let response = try JSONDecoder().decode(MatchResponse.self, from: data)
            client.logger.debug("Match response: \(response.matches.count) candidate(s)")
            return response
        } catch {
            throw DeepLinkNowError(.invalidResponse, statusCode: 200, message: "Unexpected /match response", underlying: error)
        }
    }

    // MARK: - Pasteboard (SDK-40…45, IOS-25…27)

    /// Cheap "is there probably a link on the pasteboard" check. Never reads the content, so it
    /// never shows the paste prompt (`hasURLs || hasStrings`). `true` means "worth calling
    /// `checkClipboard()`", not "verified".
    public static func hasDeepLinkToken() -> Bool {
        guard isInitialized else {
            logger.warn("SDK not initialized. Call initialize() first")
            return false
        }
        return environment.withLock { $0.pasteboard }.hasContentWithoutReading()
    }

    /// Like `hasDeepLinkToken()`, but uses `detectPatterns(for: [.probableWebURL])` on iOS 14+.
    /// Never reads the content.
    public static func hasDeepLinkTokenAsync() async -> Bool {
        guard isInitialized else { return false }
        let board = environment.withLock { $0.pasteboard }
        if let likely = await board.probablyContainsWebURL() { return likely }
        return board.hasContentWithoutReading()
    }

    /// Returns the pasteboard text when it is exactly one link on the app's domains, else `nil`.
    /// Reads `UIPasteboard.general.string` (may show the iOS 16+ paste prompt).
    public static func checkClipboard() -> String? {
        guard let domains = currentDomains else {
            logger.warn("SDK not initialized. Call initialize() first")
            return nil
        }
        let board = environment.withLock { $0.pasteboard }
        guard let text = board.readStringSync(),
              let parsed = validatedClipboardLink(text, domains: domains) else {
            return nil
        }
        logger.debug("Found DLN link on the pasteboard: \(parsed.url)")
        return parsed.url
    }

    /// SDK-40: trimmed, a single absolute URL, passing the host rule.
    static func validatedClipboardLink(_ text: String, domains: Set<String>?) -> LinkParsing.Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return LinkParsing.parse(trimmed, domains: domains)
    }

    // MARK: - Parsing (SDK-30…38, IOS-28)

    /// `true` when `domain` (a host) is one of the app's link domains (SDK-31). Before a successful
    /// init, any non-reserved `{alias}.deeplinknow.com` host is accepted provisionally (SDK-37).
    public static func isValidDomain(_ domain: String) -> Bool {
        LinkParsing.isAllowedHost(domain, domains: currentDomains)
    }

    /// Parses a Universal Link on the app's domains: undecoded `path`, `queryParams`
    /// (string / flag / list), `fullPath`, `url`. Returns `nil` for any other URL.
    public static func parseLink(_ url: URL) -> DLNParsedLink? {
        guard let parsed = LinkParsing.parse(url: url, domains: currentDomains) else { return nil }
        return DLNParsedLink(path: parsed.path, queryParams: parsed.queryParams, fullPath: parsed.fullPath, url: parsed.url)
    }

    /// Tuple form of `parseLink(_:)`. `path` is not decoded; parameter values are `String`,
    /// `true` (flag, `?k` / `?k=`) or `[String]` (repeated key).
    public static func parseDeepLink(_ url: URL) -> (path: String, parameters: [String: Any])? {
        guard let link = parseLink(url) else { return nil }
        return (link.path, link.parameters)
    }

    /// Builds an https link on the app's primary link domain that `parseLink` round-trips (IOS-29).
    /// Returns `nil` before a successful initialization.
    public static func createDeepLink(
        path: String,
        customParameters: DLNCustomParameters? = nil
    ) -> URL? {
        guard let info = appInfo else { return nil }
        var encodedPath = path.hasPrefix("/") ? path : "/" + path
        encodedPath = encodedPath.addingPercentEncoding(withAllowedCharacters: LinkParsing.pathAllowed) ?? encodedPath
        var string = "https://\(info.primaryDomain)\(encodedPath)"
        if let params = customParameters?.dictionary, !params.isEmpty {
            let query = params.keys.sorted().map { key in
                "\(LinkParsing.encodeQueryComponent(key))=\(LinkParsing.encodeQueryComponent(params[key] ?? ""))"
            }.joined(separator: "&")
            string += "?" + query
        }
        return URL(string: string)
    }

    // MARK: - Deprecated link handlers (IOS-31)

    /// Parses a Universal Link; same as `parseLink(_:)`.
    @available(*, deprecated, renamed: "parseLink(_:)")
    @discardableResult
    public static func handleUniversalLink(_ url: URL) -> DLNParsedLink? {
        parseLink(url)
    }

    /// Not supported: DLN links are https Universal Links. Custom URL schemes belong to the app.
    /// Does nothing; route custom-scheme URLs in your app.
    @available(*, deprecated, message: "Custom URL schemes are not supported by DeepLinkNow. Use Universal Links and parseLink(_:).")
    public static func handleCustomScheme(_ url: URL) {
        logger.debug("handleCustomScheme is not supported; ignoring \(url.scheme ?? "")://")
    }
}
