import Foundation

// MARK: - One link object for every open (SDK-86…91, IOS-32…34, IOS-36…38)

extension DeepLinkNow {

    /// State of the link handler, isolated behind its own lock (IOS-10).
    struct LinkState {
        var handler: (@MainActor (DLNLink) -> Void)?
        var options = DLNLinkOptions()
        /// SDK-89: while `true`, links go to `pending` instead of the handler.
        var holding = false
        var pending = HeldLinks()
        /// SDK-86 / SDK-89: links that arrived before any handler was registered.
        var undelivered = HeldLinks()
        /// Links waiting to be handed to the handler on the main actor, in arrival order.
        var queue: [DLNLink] = []
        /// SDK-88: deferred links already delivered in this process.
        var deliveredDeferredKeys: Set<String> = []
        /// SDK-88: the last direct open, to drop an identical one handed in again right away.
        var lastDirectKey: String?
        var lastDirectAt: Date?
        /// IOS-34: `onLink` was registered before a successful init; run the deferred check after it.
        var waitingForInit = false
    }

    /// SDK-89: the latest link of each kind (one deferred, one direct), handed over deferred first.
    struct HeldLinks {
        var deferred: DLNLink?
        var direct: DLNLink?

        mutating func put(_ link: DLNLink) {
            if link.type == .deferred { deferred = link } else { direct = link }
        }

        var all: [DLNLink] { [deferred, direct].compactMap { $0 } }

        mutating func takeAll() -> [DLNLink] {
            defer { self = HeldLinks() }
            return all
        }
    }

    static let links = Locked(LinkState())

    /// SDK-88 / IOS-33: the same URL handed to `handle(_:)` again within this many seconds is
    /// the OS (or the app's several entry points) replaying one open.
    static let directDedupeWindow: TimeInterval = 3

    // MARK: Public API

    /// Registers the one link handler (SDK-86). It receives a `DLNLink` for the deferred link
    /// (`type == .deferred`, from the first-launch chain this call starts) and for every direct
    /// open the app passes to `handle(_:)` (`type == .direct`). Always called on the main actor.
    ///
    /// - Links that arrived before the handler was registered are replayed to it once (the
    ///   latest of each kind, deferred first; SDK-89).
    /// - The deferred check uses `options.minConfidence` / `useClipboard` / `force` and shares
    ///   its work with `checkDeferredDeepLink` (SDK-27): it still runs once per install. If the
    ///   SDK is not initialized yet, the check runs right after the next successful `initialize`.
    /// - `options.hold` keeps links in `pendingLink` until `releasePendingLink()` (SDK-89).
    /// - `options.resolve` looks each direct open up on the server first (SDK-90).
    ///
    /// Calling it again replaces the handler and options. Never throws (SDK-85).
    public static func onLink(options: DLNLinkOptions = DLNLinkOptions(), _ handler: @escaping @MainActor (DLNLink) -> Void) {
        let waiting: [DLNLink] = links.withLock { s in
            s.handler = handler
            s.options = options
            s.holding = options.hold
            var combined = HeldLinks()
            // Held links first (re-registering without `hold` ends an earlier hold, SDK-89),
            // then newer undelivered ones replace them per kind.
            if !options.hold { combined = s.pending; s.pending = HeldLinks() }
            for link in s.undelivered.takeAll() { combined.put(link) }
            return combined.all
        }
        for link in waiting { route(link) }
        startLinkDeferredCheck()
    }

    /// Hands a URL that opened the app to the SDK (SDK-87): call it from `.onOpenURL`,
    /// `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`, `scene(_:continue:)`,
    /// `scene(_:openURLContexts:)` or `application(_:continue:restorationHandler:)`.
    ///
    /// Returns `true` and delivers a `DLNLink` (`type == .direct`) when the URL is a link on the
    /// app's domains (the `parseLink(_:)` rules, `source == .universalLink`) or uses one of the
    /// app's custom URL schemes (`source == .scheme`, IOS-38). Returns `false` and delivers
    /// nothing for any other URL. The same URL handed in again within 3 seconds is delivered
    /// once (SDK-88) but still returns `true`.
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        let schemes = links.withLock { $0.options.schemes }
        guard let link = directLink(url, domains: handleDomains) ?? schemeLink(url, schemes: schemes) else { return false }
        let now = environment.withLock { $0.now }()
        let (duplicate, resolve): (Bool, Bool) = links.withLock { s in
            if s.lastDirectKey == link.url, let last = s.lastDirectAt {
                let age = now.timeIntervalSince(last)
                if age >= 0 && age < directDedupeWindow { return (true, s.options.resolve) }
            }
            s.lastDirectKey = link.url
            s.lastDirectAt = now
            return (false, s.options.resolve)
        }
        if duplicate {
            logger.debug("handle: \(link.url) was just delivered; ignoring the repeat")
            return true
        }
        logger.debug("handle: direct open \(link.url)")
        if resolve && link.source != .scheme {   // scheme opens are never resolved (SDK-87, SDK-90)
            Task { route(await resolveOrKeep(link)) }
        } else {
            route(link)
        }
        return true
    }

    /// The held link that `releasePendingLink()` would deliver first (SDK-89): the held
    /// deferred link, else the held direct one. See `pendingLinks` for both.
    public static var pendingLink: DLNLink? {
        links.withLock { $0.pending.all.first }
    }

    /// Every held link, deferred first: the latest of each kind (SDK-89).
    public static var pendingLinks: [DLNLink] {
        links.withLock { $0.pending.all }
    }

    /// Ends the hold (the app is ready, e.g. the user signed in) and delivers the held links,
    /// if any, deferred first (SDK-89). Later links go straight to the handler until `onLink`
    /// is registered again with `hold: true`.
    public static func releasePendingLink() {
        let held: [DLNLink] = links.withLock { s in
            s.holding = false
            return s.pending.takeAll()
        }
        for link in held { route(link) }
    }

    /// Drops the held links without delivering them (SDK-89). The hold stays on.
    public static func clearPendingLink() {
        links.withLock { $0.pending = HeldLinks() }
    }

    /// Looks a link on the app's domains up with `GET /api/v1/sdk/resolve` (SDK-90) and
    /// returns it with `deeplinkId`, `targetUrl`, `campaignId` and `metadata` filled from the
    /// stored link. A 404, a timeout or any error returns the link unresolved. Returns `nil`
    /// only when the URL is not a link on the app's domains. Never throws (SDK-85).
    public static func resolveLink(_ url: URL) async -> DLNLink? {
        let domains = (try? await requireClient())?.domains ?? handleDomains
        if let link = directLink(url, domains: domains) { return await resolveOrKeep(link) }
        // A scheme open is the app's link but is never resolved (SDK-87).
        return schemeLink(url, schemes: links.withLock { $0.options.schemes })
    }

    // MARK: Delivery

    /// Hands a link to the handler, or holds it, or keeps it for a late handler.
    static func route(_ link: DLNLink) {
        let drain: Bool = links.withLock { s in
            if s.holding {
                s.pending.put(link)
                return false
            }
            if s.handler == nil {
                s.undelivered.put(link)
                return false
            }
            s.queue.append(link)
            return true
        }
        if drain {
            Task { @MainActor in drainLinkQueue() }
        }
    }

    /// Calls the handler for every queued link, in order, on the main actor.
    @MainActor static func drainLinkQueue() {
        while true {
            let next: (DLNLink, @MainActor (DLNLink) -> Void)? = links.withLock { s in
                guard let handler = s.handler, !s.queue.isEmpty else { return nil }
                return (s.queue.removeFirst(), handler)
            }
            guard let item = next else { return }
            item.1(item.0)
        }
    }

    /// SDK-88: a deferred link is delivered at most once per process.
    static func deliverDeferred(_ deferred: DLNDeferredDeepLink) {
        let link = DLNLink(deferred)
        let key = "\(link.source.rawValue)|\(link.deeplinkId ?? "")|\(link.url)"
        let fresh: Bool = links.withLock { s in
            s.deliveredDeferredKeys.insert(key).inserted
        }
        if fresh { route(link) }
    }

    // MARK: Deferred check for the handler (SDK-86, IOS-34)

    static func startLinkDeferredCheck() {
        let ready = state.withLock { $0.client != nil || $0.inFlight != nil }
        if ready {
            Task { await runLinkDeferredCheck() }
        } else {
            waitForInitThenCheck()
        }
    }

    /// Marks the check as waiting for `initialize`, then re-checks so an init that finished in
    /// between still starts it (exactly once: whoever clears the flag runs the check).
    static func waitForInitThenCheck() {
        links.withLock { $0.waitingForInit = true }
        logger.debug("onLink: the deferred check will run after initialize()")
        if isInitialized { startLinkDeferredCheckAfterInit() }
    }

    /// Called after every successful initialize.
    static func startLinkDeferredCheckAfterInit() {
        let run: Bool = links.withLock { s in
            let waiting = s.waitingForInit
            s.waitingForInit = false
            return waiting
        }
        if run {
            Task { await runLinkDeferredCheck() }
        }
    }

    static func runLinkDeferredCheck() async {
        let options = links.withLock { $0.options }
        do {
            if let deferred = try await checkDeferredDeepLinkThrowing(options.deferredOptions) {
                deliverDeferred(deferred)
            }
        } catch let error as DeepLinkNowError where error.code == .notInitialized {
            // The init this check waited for failed; try again after the next successful one.
            waitForInitThenCheck()
        } catch {
            logger.warn("onLink: deferred check failed: \(error)")
        }
    }

    // MARK: Direct opens

    /// IOS-32: the app's link domains after init; before it, the domains from the last
    /// successful `/init` saved on this device (SDK-83), so a cold start from a Universal Link
    /// on a custom domain is recognized before `initialize` finishes; else the provisional
    /// SDK-37 rule.
    static var handleDomains: Set<String>? {
        if let domains = currentDomains { return domains }
        let defaults = environment.withLock { $0.defaults }
        if let cached = InitCache.load(from: defaults), !cached.linkDomains.isEmpty {
            return Set(cached.linkDomains)
        }
        return nil
    }

    /// IOS-38 / SDK-87: a URL in one of the app's custom schemes: `options.schemes` when set,
    /// else the `CFBundleURLSchemes` the app declares in Info.plist. System schemes never count.
    static func schemeLink(_ url: URL, schemes optionSchemes: Set<String>) -> DLNLink? {
        let declared: [String] = optionSchemes.isEmpty
            ? environment.withLock { $0.declaredURLSchemes }()
            : Array(optionSchemes)
        let appSchemes = Set(declared.map { $0.lowercased() }).subtracting(LinkParsing.systemSchemes)
        guard let parsed = LinkParsing.parseScheme(url: url, schemes: appSchemes) else { return nil }
        return DLNLink(type: .direct, path: parsed.path, queryParams: parsed.queryParams,
                       fullPath: parsed.fullPath, url: parsed.url, source: .scheme,
                       confidenceScore: 100, matchQuality: .high, deeplinkId: nil, targetUrl: nil,
                       campaignId: nil, metadata: nil, matchedAt: nil, expiresAt: nil, matchDetails: nil)
    }

    /// The schemes in the main bundle's Info.plist (`CFBundleURLTypes` → `CFBundleURLSchemes`).
    static func infoPlistURLSchemes() -> [String] {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else { return [] }
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    static func directLink(_ url: URL, domains: Set<String>?) -> DLNLink? {
        guard let parsed = LinkParsing.parse(url: url, domains: domains) else { return nil }
        return DLNLink(type: .direct, path: parsed.path, queryParams: parsed.queryParams,
                       fullPath: parsed.fullPath, url: parsed.url, source: .universalLink,
                       confidenceScore: 100, matchQuality: .high, deeplinkId: nil, targetUrl: nil,
                       campaignId: nil, metadata: nil, matchedAt: nil, expiresAt: nil, matchDetails: nil)
    }

    /// SDK-90: one `/sdk/resolve` attempt, bounded by the configured timeout as a whole.
    /// Any failure keeps the link unresolved.
    static func resolveOrKeep(_ link: DLNLink) async -> DLNLink {
        let timeout = state.withLock { $0.client?.api.timeout } ?? APIClient.defaultTimeout
        let log = logger
        return await withDeadline(seconds: timeout, fallback: link) {
            do {
                let client = try await requireClient()
                let data = try await get(client.api, "resolve", query: [("path", link.fullPath)], retryAttempts: 0)
                guard let envelope = try? JSONDecoder().decode(DeeplinkEnvelope.self, from: data) else {
                    log.debug("resolve: unexpected response; delivering \(link.fullPath) unresolved")
                    return link
                }
                return link.resolved(with: envelope.deeplink)
            } catch {
                let code = (error as? DeepLinkNowError).map { e in e.statusCode.map(String.init) ?? e.code.rawValue } ?? "error"
                log.debug("resolve: \(link.fullPath) not resolved (\(code)); delivering it unresolved")
                return link
            }
        }
    }

    /// Runs `operation`, returning `fallback` if it has not finished after `seconds`.
    static func withDeadline<T>(seconds: TimeInterval, fallback: T, _ operation: @escaping () async -> T) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                // Bounded and finite, so the conversion cannot trap (SDK-50).
                let bounded = seconds.isFinite ? min(max(seconds, 0), 600) : APIClient.defaultTimeout
                if bounded > 0 { try? await Task.sleep(nanoseconds: UInt64(bounded * 1_000_000_000)) }
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? fallback
        }
    }
}

/// `{"deeplink": Deeplink}` from `/sdk/resolve` and `{"success": true, "deeplink": Deeplink}`
/// from `/sdk/referrer-lookup` (API-SDK-45, API-SDK-74).
struct DeeplinkEnvelope: Decodable {
    let deeplink: DeeplinkMatch
}
