import XCTest
@testable import DeepLinkNow

/// `checkDeferredDeepLink(_:)`: the iOS chain, result shape, minConfidence and first-launch
/// semantics (SDK-10, SDK-12…19, SDK-23…27, SDK-42…45, IOS-15, IOS-16, IOS-18, IOS-27).
/// Uses the in-memory FakePasteboard, so it runs on the Simulator as well as Catalyst.
final class DeferredDeepLinkTests: DLNTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        clearCapturedRequests()
    }

    private var matchRequests: Int { StubURLProtocol.requests(to: "match").count }

    private func requireLink(_ options: DLNDeferredOptions = DLNDeferredOptions(), file: StaticString = #filePath, line: UInt = #line) async throws -> DLNDeferredDeepLink {
        let result = try await DeepLinkNow.checkDeferredDeepLink(options)
        return try XCTUnwrap(result, "expected a deferred deep link", file: file, line: line)
    }

    private func assertNoLink(_ options: DLNDeferredOptions = DLNDeferredOptions(), file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await DeepLinkNow.checkDeferredDeepLink(options)
        XCTAssertNil(result, file: file, line: line)
    }

    // MARK: SDK-10 / SDK-12 / IOS-15 chain

    func test_SDK_10_resolvesToNilWhenNothingFound() async throws {
        // SDK-10: exactly one of link / nil / error.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let result = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertNil(result)
    }

    func test_SDK_12_clipboardHitStopsTheChainWithoutMatch() async throws {
        // SDK-12 / IOS-15
        fakePasteboard.content = "https://myapp.deeplinknow.com/products/123?ref=newsletter"
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let link = try await requireLink()
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(matchRequests, 0, "a clipboard hit must not call /match")
    }

    func test_IOS_15_nonDLNClipboardFallsBackToFingerprint() async throws {
        // IOS-15 / SDK-12 / FLOW-14: a non-DLN host on the clipboard is ignored.
        fakePasteboard.content = "https://example.com/products/123"
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let link = try await requireLink()
        XCTAssertEqual(link.source, .fingerprint)
        XCTAssertEqual(matchRequests, 1)
    }

    func test_SDK_12_useClipboardFalseNeverTouchesThePasteboard() async throws {
        // SDK-12 / SDK-42
        fakePasteboard.content = "https://myapp.deeplinknow.com/products/123"
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let link = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link?.source, .fingerprint)
        XCTAssertEqual(fakePasteboard.reads, 0)
        XCTAssertEqual(fakePasteboard.detectCalls, 0)
    }

    func test_SDK_41_patternPrecheckSkipsTheReadWhenNoWebURL() async throws {
        // SDK-41 / IOS-25: detectPatterns says "no web URL" → no read, no prompt.
        fakePasteboard.content = "just some text"
        fakePasteboard.detectResultOverride = .some(false)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertEqual(fakePasteboard.reads, 0)
        XCTAssertEqual(matchRequests, 1)
    }

    func test_SDK_45_deniedPasteCountsAsNothingFound() async throws {
        // SDK-45: Don't Allow → string is nil → continue to fingerprint, no error.
        fakePasteboard.content = nil
        fakePasteboard.detectResultOverride = .some(true)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let link = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertEqual(link?.source, .fingerprint)
        XCTAssertEqual(fakePasteboard.reads, 1)
    }

    // MARK: SDK-15 / SDK-16 / SDK-17 / SDK-18 / SDK-19 result shape

    func test_SDK_16_clipboardResultIs100High() async throws {
        // SDK-16 / SDK-15 / SDK-18 (url = copied URL) / SDK-17 (fields from parseDeepLink)
        let copied = "https://links.myapp.com/products/123?ref=news+letter&tag=a&tag=b"
        fakePasteboard.content = copied
        let link = try await requireLink()
        XCTAssertEqual(link.confidenceScore, 100)
        XCTAssertEqual(link.matchQuality, .high)
        XCTAssertEqual(link.url, copied)
        XCTAssertEqual(link.path, "/products/123")
        XCTAssertEqual(link.fullPath, "/products/123?ref=news+letter&tag=a&tag=b")
        XCTAssertEqual(link.queryParams, ["ref": .string("news letter"), "tag": .list(["a", "b"])])
        XCTAssertNil(link.deeplinkId)
        XCTAssertNil(link.matchDetails)
    }

    func test_SDK_16_fingerprintResultCarriesServerScoreAndQuality() async throws {
        // SDK-16
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(confidence: 61, quality: "MEDIUM")]))
        let link = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link.confidenceScore, 61)
        XCTAssertEqual(link.matchQuality, .medium)
    }

    func test_SDK_16_matchQualityDerivedWhenServerOmitsIt() async throws {
        // SDK-16: ≥75 HIGH, 50–74 MEDIUM, else LOW.
        let noQuality = { (score: Int) in
            Fixtures.match(confidence: score).replacingOccurrences(of: #""match_quality": "HIGH","#, with: "")
        }
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([noQuality(80), noQuality(74), noQuality(30)]))
        let response = try await DeepLinkNow.findDeferredUserThrowing()
        XCTAssertEqual(response.matches.map { $0.matchQuality }, [.high, .medium, .low])
        XCTAssertEqual(ConfidenceLevel.forScore(75), .high)
        XCTAssertEqual(ConfidenceLevel.forScore(50), .medium)
        XCTAssertEqual(ConfidenceLevel.forScore(49.9), .low)
    }

    func test_SDK_17_fingerprintFieldsComeFromFullPathAndQueryParams() async throws {
        // SDK-17: fullPath = full_path, queryParams = query_params (unchanged), path derived.
        let extra = #""query_params": { "code": "SAVE20", "debug": true, "t": ["a", "b"] }, "full_path": "/promo/x?code=SAVE20&debug&t=a&t=b","#
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(targetURL: "/promo", extraDeeplinkFields: extra)]))
        let link = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link.fullPath, "/promo/x?code=SAVE20&debug&t=a&t=b", "canonical target_url must not replace full_path")
        XCTAssertEqual(link.path, "/promo/x")
        XCTAssertEqual(link.queryParams, ["code": .string("SAVE20"), "debug": .flag, "t": .list(["a", "b"])])
    }

    func test_SDK_17_fallbacksForOlderServers() async throws {
        // SDK-17: no full_path → target_url when it is a path; no query_params → parse fullPath.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(targetURL: "/promo?code=SAVE+20&f", extraDeeplinkFields: ""),
        ]))
        let link = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link.fullPath, "/promo?code=SAVE+20&f")
        XCTAssertEqual(link.path, "/promo")
        XCTAssertEqual(link.queryParams, ["code": .string("SAVE 20"), "f": .flag])

        // SDK-17 (updated): on-demand links store target_url without the leading slash.
        DeepLinkNow.resetDeferredDeepLink()
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(targetURL: "promo?code=X", extraDeeplinkFields: ""),
        ]))
        let noSlash = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(noSlash.fullPath, "/promo?code=X")
        XCTAssertEqual(noSlash.path, "/promo")
        XCTAssertEqual(noSlash.queryParams, ["code": .string("X")])
        XCTAssertEqual(noSlash.url, "https://links.myapp.com/promo?code=X")

        // Absolute target on another host: its path + query.
        DeepLinkNow.resetDeferredDeepLink()
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(targetURL: "https://example.com/page?a=1", extraDeeplinkFields: ""),
        ]))
        let absolute = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(absolute.fullPath, "/page?a=1")

        // No target_url at all: "/".
        DeepLinkNow.resetDeferredDeepLink()
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(targetURL: "", extraDeeplinkFields: ""),
        ]))
        let empty = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(empty.fullPath, "/")
        XCTAssertEqual(empty.path, "/")
    }

    func test_SDK_18_urlForServerSources() async throws {
        // SDK-18: absolute target_url on a link domain is used; otherwise https://{primary}{fullPath}.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(targetURL: "https://myapp.deeplinknow.com/promo?code=SAVE20"),
        ]))
        let onDomain = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(onDomain.url, "https://myapp.deeplinknow.com/promo?code=SAVE20")

        DeepLinkNow.resetDeferredDeepLink()
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(targetURL: "https://example.com/web")]))
        let offDomain = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(offDomain.url, "https://links.myapp.com/promo?code=SAVE20&debug")
        XCTAssertEqual(offDomain.targetUrl, "https://example.com/web", "targetUrl is returned unchanged")
    }

    func test_SDK_19_serverFieldsExposed() async throws {
        // SDK-19 / SDK-15
        let extra = #""campaign_id": "camp-1", "query_params": {}, "full_path": "/promo","#
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(id: "dl-1", extraDeeplinkFields: extra)]))
        let link = try await requireLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link.source, .fingerprint)
        XCTAssertEqual(link.deeplinkId, "dl-1")
        XCTAssertEqual(link.campaignId, "camp-1")
        XCTAssertEqual(link.targetUrl, "/promo?code=SAVE20&debug")
        XCTAssertEqual(link.metadata?["source"]?.value as? String, "newsletter")
        XCTAssertNotNil(link.matchedAt)
        XCTAssertNotNil(link.expiresAt)
        XCTAssertEqual(link.matchDetails?.ipMatch.score, 40)
    }

    // MARK: SDK-13 / SDK-14 candidate selection

    func test_SDK_13_firstCandidateWithDeeplinkInServerOrder() async throws {
        // SDK-13: no re-scoring or reordering; matches without deeplink are skipped.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(id: "no-link", confidence: 95, includeDeeplink: false),
            Fixtures.match(id: "second", confidence: 40, quality: "LOW"),
            Fixtures.match(id: "third", confidence: 90),
        ]))
        let link = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(link?.deeplinkId, "second")
        XCTAssertEqual(link?.matchQuality, .low)
    }

    func test_SDK_14_minConfidenceOffByDefaultAndFiltersWhenSet() async throws {
        // SDK-14
        XCTAssertNil(DLNDeferredOptions().minConfidence)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(id: "low", confidence: 31, quality: "LOW"),
            Fixtures.match(id: "mid", confidence: 60, quality: "MEDIUM"),
        ]))
        let unfiltered = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(unfiltered?.deeplinkId, "low")

        let filtered = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(minConfidence: 50, useClipboard: false, force: true))
        XCTAssertEqual(filtered?.deeplinkId, "mid")

        let none = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(minConfidence: 99, useClipboard: false, force: true))
        XCTAssertNil(none)
    }

    func test_SDK_14_minConfidenceDoesNotApplyToClipboard() async throws {
        // SDK-14
        fakePasteboard.content = "https://myapp.deeplinknow.com/x"
        let link = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(minConfidence: 101))
        XCTAssertEqual(link?.source, .clipboard)
    }

    // MARK: SDK-23…27 / IOS-18 first-launch semantics

    func test_SDK_23_definitiveOutcomeSetsFlagAndLaterCallsAreSilent() async throws {
        // SDK-23 / IOS-18
        fakePasteboard.content = "https://example.com/nope"
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        _ = try await requireLink()
        XCTAssertTrue(defaults.bool(forKey: "com.deeplinknow.deferredCheckCompleted"))

        clearCapturedRequests()
        let readsBefore = fakePasteboard.reads
        let again = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertNil(again)
        XCTAssertEqual(matchRequests, 0, "no network after completion")
        XCTAssertEqual(fakePasteboard.reads, readsBefore, "no clipboard access after completion")
    }

    func test_SDK_23_emptyMatchIsDefinitive() async throws {
        // SDK-23
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        try await assertNoLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
    }

    func test_SDK_23_forceIgnoresTheFlag() async throws {
        // SDK-23: force
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        _ = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        let forced = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false, force: true))
        XCTAssertNotNil(forced)
        XCTAssertEqual(matchRequests, 2)
    }

    func test_SDK_24_errorsDoNotSetTheFlag() async throws {
        // SDK-24 / SDK-54
        for (status, body) in [(500, Fixtures.errorInternal), (429, Fixtures.errorRateLimited), (200, "<html>portal</html>")] {
            StubURLProtocol.reset()
            StubURLProtocol.stub("match", status: status, json: body)
            let error = await captureError { try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false)) }
            XCTAssertNotNil(error)
            XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey), "HTTP \(status) must not set the flag")
        }
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", error: URLError(.notConnectedToInternet))
        let offline = await captureError { try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false)) }
        XCTAssertEqual(offline?.code, .network)
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))

        // The next call tries again and can succeed.
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        _ = try await requireLink(DLNDeferredOptions(useClipboard: false))
    }

    func test_SDK_24_notInitializedDoesNotSetTheFlag() async throws {
        // SDK-24
        DeepLinkNow.resetForTesting()
        let error = await captureError { try await DeepLinkNow.checkDeferredDeepLink() }
        XCTAssertEqual(error?.code, .notInitialized)
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
    }

    func test_SDK_25_flagLivesInLocalUserDefaultsOnly() async throws {
        // SDK-25 / IOS-18: an SDK-namespaced UserDefaults key (deleted on uninstall, not in iCloud KVS).
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertEqual(DeepLinkNow.deferredCompletedKey, "com.deeplinknow.deferredCheckCompleted")
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
    }

    func test_SDK_26_resetClearsTheFlag() async throws {
        // SDK-26
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        fakePasteboard.content = "https://example.com"
        _ = try await DeepLinkNow.checkDeferredDeepLink()
        DeepLinkNow.resetDeferredDeepLink()
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.clipboardCheckedKey))
        _ = try await requireLink()
        XCTAssertEqual(fakePasteboard.reads, 2, "the clipboard is checked again after a reset")
    }

    func test_SDK_27_concurrentCallsShareOneRun() async throws {
        // SDK-27
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(id: "shared")]))
        let options = DLNDeferredOptions(useClipboard: false)
        async let a = DeepLinkNow.checkDeferredDeepLink(options)
        async let b = DeepLinkNow.checkDeferredDeepLink(options)
        async let c = DeepLinkNow.checkDeferredDeepLink(options)
        let results = try await [a, b, c]
        XCTAssertEqual(matchRequests, 1)
        XCTAssertEqual(results.map { $0?.deeplinkId }, ["shared", "shared", "shared"])
    }

    // MARK: IOS-27 / SDK-42 / SDK-43 / SDK-44 pasteboard discipline

    func test_IOS_27_pasteboardReadAtMostOncePerInstall() async throws {
        // IOS-27 / SDK-42: even if /match fails after the read, the next run does not read again.
        fakePasteboard.content = "https://example.com/unrelated"
        StubURLProtocol.stub("match", status: 500, json: Fixtures.errorInternal)
        _ = await captureError { try await DeepLinkNow.checkDeferredDeepLink() }
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertEqual(fakePasteboard.reads, 1)
    }

    func test_SDK_42_initNeverReadsTheClipboard() async {
        // SDK-42 / SDK-09
        fakePasteboard.content = "https://myapp.deeplinknow.com/x"
        await initializeSDK()
        XCTAssertEqual(fakePasteboard.reads, 0)
        XCTAssertEqual(fakePasteboard.detectCalls, 0)
    }

    func test_SDK_43_neverWritesOrClearsTheClipboard() async throws {
        // SDK-43
        let copied = "https://myapp.deeplinknow.com/x"
        fakePasteboard.content = copied
        _ = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertEqual(fakePasteboard.content, copied)
    }

    func test_SDK_44_nonDLNClipboardContentIsNeverLogged() async throws {
        // SDK-44 / SDK-71 / IOS-27
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
        fakePasteboard.content = "https://secret.example.com/private-token-123"
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertFalse(logs.joined.contains("private-token-123"))
    }

    // MARK: IOS-16 decoding

    func test_IOS_16_matchQualityQueryParamsAndFullPathDecoded() async throws {
        // IOS-16 / SDK-20
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(quality: "MEDIUM")]))
        let response = try await DeepLinkNow.findDeferredUserThrowing()
        let match = try XCTUnwrap(response.matches.first)
        XCTAssertEqual(match.matchQuality, .medium)
        XCTAssertEqual(match.deeplink?.queryParams, ["code": .string("SAVE20"), "debug": .flag])
        XCTAssertEqual(match.deeplink?.fullPath, "/promo?code=SAVE20&debug")
    }

    // MARK: SDK-06 waits for init

    func test_SDK_06_waitsForInFlightInitialization() async throws {
        // SDK-06: a call made while init is in flight waits for it instead of failing.
        DeepLinkNow.resetForTesting()
        StubURLProtocol.reset()
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(id: "after-init")]))
        let session = makeSession()
        let initTask = Task { try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey), urlSession: session) }
        // Give the init task a chance to register itself, then ask for the link.
        while !DeepLinkNow.state.withLock({ $0.inFlight != nil || $0.client != nil }) { await Task.yield() }
        let link = try await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        _ = try await initTask.value
        XCTAssertEqual(link?.deeplinkId, "after-init")
    }
}
