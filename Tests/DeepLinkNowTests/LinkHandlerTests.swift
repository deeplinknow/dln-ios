import XCTest
@testable import DeepLinkNow

/// One link object for every open: `onLink`, `handle`, dedupe, hold and resolve
/// (SDK-86…91, IOS-32…34, IOS-36). Uses the in-memory FakePasteboard.
final class LinkHandlerTests: DLNTestCase {

    private let recorder = LinkRecorder()
    private let clock = TestClock()

    override func setUp() async throws {
        try await super.setUp()
        let clock = self.clock
        DeepLinkNow.environment.withLock { $0.now = { clock.now } }
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        clearCapturedRequests()
    }

    private func register(_ options: DLNLinkOptions = DLNLinkOptions(useClipboard: false)) {
        let recorder = self.recorder
        DeepLinkNow.onLink(options: options) { link in recorder.append(link) }
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: SDK-86 deferred delivery

    func test_SDK_86_deferredLinkIsDeliveredToTheHandler() async throws {
        // SDK-86: registering starts the first-launch check and delivers its link as `.deferred`.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        let links = await recorder.wait(for: 1)
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.type, .deferred)
        XCTAssertEqual(link.source, .fingerprint)
        XCTAssertEqual(link.path, "/promo")
        XCTAssertEqual(link.queryParams["code"], .string("SAVE20"))
        XCTAssertEqual(link.confidenceScore, 87)
        XCTAssertEqual(link.deeplinkId, "3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f")
        XCTAssertNotNil(link.matchDetails)
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey), "SDK-23 still applies")
    }

    func test_SDK_86_clipboardDeferredLinkKeepsItsSource() async throws {
        // SDK-86: deferred sources keep their names in `DLNLink.source`.
        fakePasteboard.content = "https://myapp.deeplinknow.com/products/1?ref=nl"
        register(DLNLinkOptions())
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.type, .deferred)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(link.matchQuality, .high)
    }

    func test_SDK_86_noDeferredLinkDeliversNothing() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 1)
    }

    func test_SDK_86_linkThatArrivedBeforeTheHandlerIsReplayedOnce() async throws {
        // SDK-86: a late handler still gets the latest undelivered link, once.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/early?x=1")))
        register()
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.map { $0.fullPath }, ["/early?x=1"])
        XCTAssertEqual(links.first?.type, .direct)

        // Registering again does not replay it a second time.
        register()
        await recorder.settle()
        XCTAssertEqual(recorder.links.count, 1)
    }

    func test_IOS_34_onLinkBeforeInitializeRunsTheCheckAfterInit() async throws {
        // IOS-34: onLink registered before initialize() runs its deferred check once init succeeds.
        DeepLinkNow.resetForTesting()
        register()
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 0)

        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .deferred)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 1)
    }

    // MARK: SDK-87 direct opens

    func test_SDK_87_directOpenOnAnAppDomainIsDelivered() async throws {
        // SDK-87 / IOS-32: handle() parses with parseLink's rules and delivers `.direct`.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        XCTAssertTrue(DeepLinkNow.handle(url("https://links.myapp.com/products/123?ref=news+letter&tag=a&tag=b")))
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.type, .direct)
        XCTAssertEqual(link.source, .universalLink)
        XCTAssertEqual(link.path, "/products/123")
        XCTAssertEqual(link.fullPath, "/products/123?ref=news+letter&tag=a&tag=b")
        XCTAssertEqual(link.queryParams, ["ref": .string("news letter"), "tag": .list(["a", "b"])])
        XCTAssertEqual(link.url, "https://links.myapp.com/products/123?ref=news+letter&tag=a&tag=b")
        XCTAssertEqual(link.confidenceScore, 100)
        XCTAssertEqual(link.matchQuality, .high)
        XCTAssertNil(link.deeplinkId)
        XCTAssertNil(link.targetUrl)
        XCTAssertNil(link.matchDetails)
    }

    func test_IOS_32_otherHostsAndUndeclaredSchemesReturnFalse() async throws {
        // IOS-32 / SDK-87: anything that is not a link on the app's domains or schemes is the app's to route.
        DeepLinkNow.environment.withLock { $0.declaredURLSchemes = { [] } }
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        XCTAssertFalse(DeepLinkNow.handle(url("https://example.com/products/1")))
        XCTAssertFalse(DeepLinkNow.handle(url("https://otherapp.deeplinknow.com/products/1")))
        XCTAssertFalse(DeepLinkNow.handle(url("myapp://products/1")))
        XCTAssertFalse(DeepLinkNow.handle(url("https://links.myapp.com.evil.com/x")))
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
    }

    func test_IOS_32_beforeInitTheCachedDomainsAreUsed() async throws {
        // IOS-32: a cold start from a custom-domain Universal Link is recognized before
        // initialize() finishes, using the domains saved by the last /init (SDK-83).
        DeepLinkNow.resetForTesting()   // memory only; the init cache in UserDefaults stays
        XCTAssertTrue(DeepLinkNow.handle(url("https://links.myapp.com/cold")))

        // Without a cache, only the provisional SDK-37 rule applies.
        DeepLinkNow.resetForTesting()
        InitCache.clear(in: defaults)
        XCTAssertFalse(DeepLinkNow.handle(url("https://links.myapp.com/cold2")))
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/cold3")))
    }

    func test_SDK_87_handleNeverThrowsOrCrashesOnOddInput() {
        // SDK-85 / SDK-50
        XCTAssertFalse(DeepLinkNow.handle(url("mailto:a@b.com")))
        XCTAssertFalse(DeepLinkNow.handle(url("file:///tmp/x")))
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com")))
    }

    // MARK: SDK-88 dedupe

    func test_SDK_88_aReplayedDirectOpenIsDeliveredOnce() async throws {
        // SDK-88 / IOS-33: the same URL handed in twice right away (e.g. scene(_:willConnectTo:)
        // plus scene(_:continue:)) is one open.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        let link = url("https://myapp.deeplinknow.com/p/1")
        XCTAssertTrue(DeepLinkNow.handle(link))
        XCTAssertTrue(DeepLinkNow.handle(link), "a duplicate is still a DLN link")
        await recorder.settle()
        XCTAssertEqual(recorder.links.count, 1)

        // Still inside the 3-second window (SDK-88): one open.
        clock.advance(by: 2.5)
        XCTAssertTrue(DeepLinkNow.handle(link))
        await recorder.settle()
        XCTAssertEqual(recorder.links.count, 1)

        // Tapping the same link again later is a new open.
        clock.advance(by: 1)
        XCTAssertTrue(DeepLinkNow.handle(link))
        _ = await recorder.wait(for: 2)
        XCTAssertEqual(recorder.links.count, 2)

        // A different URL is never a duplicate.
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/p/2")))
        _ = await recorder.wait(for: 3)
        XCTAssertEqual(recorder.links.map { $0.path }, ["/p/1", "/p/1", "/p/2"])
    }

    func test_SDK_88_deferredLinkIsDeliveredOnceAcrossRegistrations() async throws {
        // SDK-88 / SDK-27: two registrations share one chain and deliver the deferred link once.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        register()
        _ = await recorder.wait(for: 1)
        await recorder.settle()
        XCTAssertEqual(recorder.links.filter { $0.type == .deferred }.count, 1)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 1)
    }

    func test_SDK_88_deferredAndDirectOnTheSameLaunchAreBothDelivered() async throws {
        // SDK-88
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/direct")))
        let links = await recorder.wait(for: 2)
        XCTAssertEqual(Set(links.map { $0.type }), [.deferred, .direct])
    }

    // MARK: SDK-89 hold

    func test_SDK_89_holdKeepsTheLinkUntilReleased() async throws {
        // SDK-89 / IOS-36
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register(DLNLinkOptions(useClipboard: false, hold: true))
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/invite/42")))
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty, "a held link does not reach the handler")
        XCTAssertEqual(DeepLinkNow.pendingLink?.path, "/invite/42")

        DeepLinkNow.releasePendingLink()
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.path, "/invite/42")
        XCTAssertNil(DeepLinkNow.pendingLink)

        // IOS-36: release ends the hold, so the next link goes straight to the handler.
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/next")))
        _ = await recorder.wait(for: 2)
        XCTAssertEqual(recorder.links.map { $0.path }, ["/invite/42", "/next"])
    }

    func test_SDK_89_holdAppliesToTheDeferredLinkToo() async throws {
        // SDK-89: the sign-in gate for a deferred link.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register(DLNLinkOptions(useClipboard: false, hold: true))
        let deadline = Date().addingTimeInterval(3)
        while DeepLinkNow.pendingLink == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(DeepLinkNow.pendingLink?.type, .deferred)
        XCTAssertTrue(recorder.links.isEmpty)
        DeepLinkNow.releasePendingLink()
        let awaited = await recorder.wait(for: 1).first?.type
        XCTAssertEqual(awaited, .deferred)
    }

    func test_SDK_89_onlyTheLatestLinkIsHeld() async throws {
        // SDK-89
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register(DLNLinkOptions(useClipboard: false, hold: true))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/b"))
        XCTAssertEqual(DeepLinkNow.pendingLink?.path, "/b")
        DeepLinkNow.releasePendingLink()
        await recorder.settle()
        XCTAssertEqual(recorder.links.map { $0.path }, ["/b"])
    }

    func test_SDK_89_clearDropsTheHeldLink() async throws {
        // SDK-89 / IOS-36: clear drops it; the hold stays on.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register(DLNLinkOptions(useClipboard: false, hold: true))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        DeepLinkNow.clearPendingLink()
        XCTAssertNil(DeepLinkNow.pendingLink)
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/b"))
        XCTAssertEqual(DeepLinkNow.pendingLink?.path, "/b", "the hold is still on after clear")
        DeepLinkNow.clearPendingLink()
        DeepLinkNow.releasePendingLink()
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
    }

    func test_IOS_36_reRegisteringWithoutHoldDeliversTheHeldLink() async throws {
        // IOS-36: onLink again with hold: false ends the hold, like releasePendingLink().
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register(DLNLinkOptions(useClipboard: false, hold: true))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        register(DLNLinkOptions(useClipboard: false))
        let awaited = await recorder.wait(for: 1).map { $0.path }
        XCTAssertEqual(awaited, ["/a"])
        XCTAssertNil(DeepLinkNow.pendingLink)
    }

    // MARK: SDK-89 one link of each kind

    func test_SDK_89_holdKeepsOneLinkOfEachKindAndReleasesDeferredFirst() async throws {
        // SDK-89 / IOS-36: the latest deferred and the latest direct are both held, deferred first.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register(DLNLinkOptions(useClipboard: false, hold: true))
        let deadline = Date().addingTimeInterval(3)
        while DeepLinkNow.pendingLinks.first(where: { $0.type == .deferred }) == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/b"))
        XCTAssertEqual(DeepLinkNow.pendingLinks.map { $0.type }, [.deferred, .direct])
        XCTAssertEqual(DeepLinkNow.pendingLinks.last?.path, "/b", "only the latest direct link is kept")
        XCTAssertEqual(DeepLinkNow.pendingLink?.type, .deferred, "pendingLink is the one delivered first")
        XCTAssertTrue(recorder.links.isEmpty)

        DeepLinkNow.releasePendingLink()
        let links = await recorder.wait(for: 2)
        XCTAssertEqual(links.map { $0.type }, [.deferred, .direct])
        XCTAssertEqual(links.last?.path, "/b")
        XCTAssertTrue(DeepLinkNow.pendingLinks.isEmpty)
    }

    func test_SDK_89_clearDropsBothHeldLinks() async throws {
        // SDK-89: clear drops the held deferred and direct links.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register(DLNLinkOptions(useClipboard: false, hold: true))
        let deadline = Date().addingTimeInterval(3)
        while DeepLinkNow.pendingLink == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        XCTAssertEqual(DeepLinkNow.pendingLinks.count, 2)
        DeepLinkNow.clearPendingLink()
        XCTAssertTrue(DeepLinkNow.pendingLinks.isEmpty)
        DeepLinkNow.releasePendingLink()
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
    }

    func test_SDK_89_withoutAHandlerOneOfEachKindIsReplayedDeferredFirst() async throws {
        // SDK-89 / SDK-86: before a handler exists the latest of each kind is kept; a late
        // handler gets them deferred first, even though the direct one arrived first.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let deferredResult = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        let deferred = try XCTUnwrap(deferredResult)
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/a"))
        clock.advance(by: 1)
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/b"))
        DeepLinkNow.deliverDeferred(deferred)
        register()
        let links = await recorder.wait(for: 2)
        await recorder.settle()
        XCTAssertEqual(recorder.links.map { $0.type }, [.deferred, .direct])
        XCTAssertEqual(links.last?.path, "/b")
    }

    // MARK: SDK-87 / IOS-38 custom schemes

    private func declare(_ schemes: [String]) {
        DeepLinkNow.environment.withLock { $0.declaredURLSchemes = { schemes } }
    }

    func test_IOS_38_infoPlistSchemeOpenIsDelivered() async throws {
        // SDK-87 / IOS-38: with no options.schemes, Info.plist's CFBundleURLSchemes count.
        declare(["myapp"])
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        XCTAssertTrue(DeepLinkNow.handle(url("myapp://products/123?x=1&x=2&f")))
        let first = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(first)
        XCTAssertEqual(link.type, .direct)
        XCTAssertEqual(link.source, .scheme)
        XCTAssertEqual(link.path, "/products/123")
        XCTAssertEqual(link.fullPath, "/products/123?x=1&x=2&f")
        XCTAssertEqual(link.queryParams, ["x": .list(["1", "2"]), "f": .flag])
        XCTAssertEqual(link.url, "myapp://products/123?x=1&x=2&f")
        XCTAssertEqual(link.confidenceScore, 100)
        XCTAssertNil(link.deeplinkId)
    }

    func test_IOS_38_schemePathShapes() {
        // IOS-38: the host is the first path segment; the scheme is case-insensitive.
        let schemes: Set<String> = ["myapp"]
        XCTAssertEqual(DeepLinkNow.schemeLink(url("myapp://products"), schemes: schemes)?.path, "/products")
        XCTAssertEqual(DeepLinkNow.schemeLink(url("myapp:///products/1"), schemes: schemes)?.path, "/products/1")
        XCTAssertEqual(DeepLinkNow.schemeLink(url("myapp://"), schemes: schemes)?.path, "/")
        XCTAssertEqual(DeepLinkNow.schemeLink(url("MyApp://Products/1"), schemes: schemes)?.path, "/Products/1")
        XCTAssertEqual(DeepLinkNow.schemeLink(url("myapp://p?q=a+b"), schemes: schemes)?.queryParams, ["q": .string("a b")])
        XCTAssertEqual(DeepLinkNow.schemeLink(url("myapp://p#dln=abc"), schemes: schemes)?.url, "myapp://p", "SDK-92")
        XCTAssertNil(DeepLinkNow.schemeLink(url("other://p"), schemes: schemes))
    }

    func test_IOS_38_optionsSchemesReplaceInfoPlist() async throws {
        // SDK-87 / IOS-38: options.schemes, when set, is the list (case-insensitive).
        declare(["myapp"])
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register(DLNLinkOptions(useClipboard: false, schemes: ["Other"]))
        XCTAssertFalse(DeepLinkNow.handle(url("myapp://products/1")))
        XCTAssertTrue(DeepLinkNow.handle(url("other://products/1")))
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.map { $0.source }, [.scheme])
    }

    func test_IOS_38_systemSchemesNeverCount() async throws {
        // SDK-87: system schemes are never the app's, even when listed.
        declare(["mailto", "tel", "sms", "http", "file", "itms-apps"])
        register(DLNLinkOptions(useClipboard: false))
        XCTAssertFalse(DeepLinkNow.handle(url("mailto:a@b.com")))
        XCTAssertFalse(DeepLinkNow.handle(url("tel:+61400000000")))
        XCTAssertFalse(DeepLinkNow.handle(url("sms:+61400000000")))
        XCTAssertFalse(DeepLinkNow.handle(url("http://example.com/x")))
        XCTAssertFalse(DeepLinkNow.handle(url("file:///tmp/x")))
        XCTAssertFalse(DeepLinkNow.handle(url("itms-apps://apps.apple.com/app/id1")))
        register(DLNLinkOptions(useClipboard: false, schemes: ["https", "mailto"]))
        XCTAssertFalse(DeepLinkNow.handle(url("mailto:a@b.com")))
        XCTAssertFalse(DeepLinkNow.handle(url("https://example.com/x")))
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
    }

    func test_IOS_38_schemeOpensAreNeverResolved() async throws {
        // SDK-87 / SDK-90: resolve does not apply to scheme opens.
        declare(["myapp"])
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        StubURLProtocol.stub("resolve", json: Fixtures.resolveOK)
        register(DLNLinkOptions(useClipboard: false, resolve: true))
        XCTAssertTrue(DeepLinkNow.handle(url("myapp://abc123")))
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.source, .scheme)
        XCTAssertNil(links.first?.deeplinkId)
        let viaResolveLink = await DeepLinkNow.resolveLink(url("myapp://abc123"))
        XCTAssertEqual(viaResolveLink?.path, "/abc123")
        XCTAssertNil(viaResolveLink?.deeplinkId)
        XCTAssertTrue(StubURLProtocol.requests(to: "resolve").isEmpty)
    }

    func test_IOS_38_schemeOpensAreDeduped() async throws {
        // SDK-88 applies to scheme opens too.
        declare(["myapp"])
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        XCTAssertTrue(DeepLinkNow.handle(url("myapp://p/1")))
        XCTAssertTrue(DeepLinkNow.handle(url("myapp://p/1")))
        await recorder.settle()
        XCTAssertEqual(recorder.links.count, 1)
    }

    func test_IOS_38_infoPlistLookupReadsCFBundleURLTypes() {
        // IOS-38: the default lookup reads the main bundle and never crashes (xctest has none).
        XCTAssertNotNil(DeepLinkNow.infoPlistURLSchemes())
        XCTAssertFalse(DeepLinkNow.infoPlistURLSchemes().contains("https"))
    }

    // MARK: SDK-90 resolve

    private func resolveRequests() -> [StubURLProtocol.Captured] { StubURLProtocol.requests(to: "resolve") }

    func test_SDK_90_resolveFillsTheStoredLinkFields() async throws {
        // SDK-90 / IOS-37 / API-SDK-74
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        StubURLProtocol.stub("resolve", json: Fixtures.resolveOK)
        register(DLNLinkOptions(useClipboard: false, resolve: true))
        XCTAssertTrue(DeepLinkNow.handle(url("https://links.myapp.com/abc123?utm_source=x&a=b+c")))
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.type, .direct)
        XCTAssertEqual(link.source, .universalLink)
        XCTAssertEqual(link.deeplinkId, "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00")
        XCTAssertEqual(link.targetUrl, "https://yourapp.com/invite/8Fk2")
        XCTAssertEqual(link.campaignId, "3e0b8a51-1c7d-4a2e-b6f9-0d5c4e3b2a19")
        XCTAssertNotNil(link.metadata?["fdl"])
        // Routing fields stay what the user opened.
        XCTAssertEqual(link.fullPath, "/abc123?utm_source=x&a=b+c")

        let request = try XCTUnwrap(resolveRequests().first?.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Self.apiKey)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "path" })?.value, "/abc123?utm_source=x&a=b+c")
        XCTAssertEqual(request.url?.path, "/api/v1/sdk/resolve")
    }

    func test_SDK_90_resolve404DeliversTheLinkUnresolved() async throws {
        // SDK-90
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        StubURLProtocol.stub("resolve", status: 404, json: #"{"error":"Deeplink not found"}"#)
        register(DLNLinkOptions(useClipboard: false, resolve: true))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/nope"))
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.path, "/nope")
        XCTAssertNil(link.deeplinkId)
        XCTAssertEqual(resolveRequests().count, 1)
    }

    func test_SDK_90_resolveTimeoutDeliversTheLinkUnresolvedWithoutRetrying() async throws {
        // SDK-90 / IOS-37: one attempt, bounded by the timeout; a failure never drops the link.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        StubURLProtocol.stub("resolve", error: URLError(.timedOut))
        register(DLNLinkOptions(useClipboard: false, resolve: true))
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/slow"))
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.path, "/slow")
        XCTAssertNil(link.deeplinkId)
        XCTAssertEqual(resolveRequests().count, 1, "resolve is not retried")
    }

    func test_SDK_90_resolveIsBoundedByTheConfiguredTimeoutAsAWhole() async throws {
        // SDK-90 / IOS-37: never delay a link beyond the timeout, whatever the request does.
        let start = Date()
        let result = await DeepLinkNow.withDeadline(seconds: 0.2, fallback: "fallback") {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return "late"
        }
        XCTAssertEqual(result, "fallback")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let fast = await DeepLinkNow.withDeadline(seconds: 5, fallback: "fallback") { "fast" }
        XCTAssertEqual(fast, "fast")
    }

    func test_SDK_90_resolveIsOffByDefault() async throws {
        // SDK-90
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        DeepLinkNow.handle(url("https://myapp.deeplinknow.com/abc123"))
        _ = await recorder.wait(for: 1)
        XCTAssertTrue(resolveRequests().isEmpty)
    }

    func test_SDK_90_resolveLinkReturnsTheResolvedOrUnresolvedLink() async throws {
        // SDK-90: resolveLink(url) async.
        StubURLProtocol.stub("resolve", json: Fixtures.resolveOK)
        let resolved = await DeepLinkNow.resolveLink(url("https://myapp.deeplinknow.com/abc123"))
        XCTAssertEqual(resolved?.deeplinkId, "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00")
        XCTAssertEqual(resolved?.type, .direct)

        StubURLProtocol.reset()
        StubURLProtocol.stub("resolve", status: 404, json: #"{"error":"Deeplink not found"}"#)
        let unresolved = await DeepLinkNow.resolveLink(url("https://myapp.deeplinknow.com/abc123"))
        XCTAssertEqual(unresolved?.path, "/abc123")
        XCTAssertNil(unresolved?.deeplinkId)

        let foreign = await DeepLinkNow.resolveLink(url("https://example.com/abc123"))
        XCTAssertNil(foreign)
    }

    func test_SDK_90_resolveLinkBeforeInitReturnsTheLinkUnresolved() async throws {
        // SDK-90 / IOS-37 / SDK-85: no client → no request, the unresolved link.
        DeepLinkNow.resetForTesting()
        let link = await DeepLinkNow.resolveLink(url("https://myapp.deeplinknow.com/abc123"))
        XCTAssertEqual(link?.path, "/abc123")
        XCTAssertNil(link?.deeplinkId)
        XCTAssertTrue(resolveRequests().isEmpty)
    }

    // MARK: SDK-91 existing calls unchanged

    func test_SDK_91_checkDeferredDeepLinkAndOnLinkRunTheChainOnce() async throws {
        // SDK-91 / SDK-27: an app using both still runs the chain once.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let direct = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(direct?.source, .fingerprint)
        register()
        await recorder.settle()
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 1)
        XCTAssertTrue(recorder.links.isEmpty, "the deferred link was already returned to checkDeferredDeepLink")
    }

    func test_SDK_91_existingCallsStillBehave() async throws {
        // SDK-91: parseLink and the tuple parseDeepLink are unchanged (handleUniversalLink: IOS-31 in LinkRulesTests).
        let link = url("https://myapp.deeplinknow.com/products/1?x=1&x=2")
        let parsed = try XCTUnwrap(DeepLinkNow.parseLink(link))
        XCTAssertEqual(parsed.path, "/products/1")
        XCTAssertEqual(parsed.queryParams["x"], .list(["1", "2"]))
        XCTAssertEqual(parsed.url, "https://myapp.deeplinknow.com/products/1?x=1&x=2")
        XCTAssertEqual(DeepLinkNow.parseDeepLink(link)?.path, "/products/1")
        XCTAssertNil(DeepLinkNow.parseLink(url("myapp://products/1")))

        // DLNLink(deferred) carries every DeferredDeepLink field.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let deferredResult = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        let deferred = try XCTUnwrap(deferredResult)
        let wrapped = DLNLink(deferred)
        XCTAssertEqual(wrapped.type, .deferred)
        XCTAssertEqual(wrapped.source, .fingerprint)
        XCTAssertEqual(wrapped.path, deferred.path)
        XCTAssertEqual(wrapped.fullPath, deferred.fullPath)
        XCTAssertEqual(wrapped.url, deferred.url)
        XCTAssertEqual(wrapped.confidenceScore, deferred.confidenceScore)
        XCTAssertEqual(wrapped.matchQuality, deferred.matchQuality)
        XCTAssertEqual(wrapped.deeplinkId, deferred.deeplinkId)
        XCTAssertEqual(wrapped.targetUrl, deferred.targetUrl)
        XCTAssertEqual(wrapped.campaignId, deferred.campaignId)
        XCTAssertEqual(wrapped.matchedAt, deferred.matchedAt)
        XCTAssertEqual(wrapped.expiresAt, deferred.expiresAt)
        XCTAssertEqual(wrapped.parameters.count, deferred.parameters.count)
    }

    func test_SDK_56_handlerRunsOnTheMainThread() async throws {
        // SDK-56: callback-style APIs call back on the main thread.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let onMain = Locked<Bool?>(nil)
        DeepLinkNow.onLink(options: DLNLinkOptions(useClipboard: false)) { _ in
            onMain.withLock { $0 = Thread.isMainThread }
        }
        await Task.detached { _ = DeepLinkNow.handle(URL(string: "https://myapp.deeplinknow.com/bg")!) }.value
        let deadline = Date().addingTimeInterval(3)
        while onMain.current == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(onMain.current, true)
    }
}

// MARK: - Helpers

final class LinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DLNLink] = []

    func append(_ link: DLNLink) {
        lock.lock(); storage.append(link); lock.unlock()
    }

    var links: [DLNLink] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    /// Waits up to 3 s for at least `count` links.
    func wait(for count: Int) async -> [DLNLink] {
        let deadline = Date().addingTimeInterval(3)
        while links.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return links
    }

    /// Gives in-flight checks and main-actor deliveries time to land.
    func settle() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {}
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date()

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock()
    }
}
