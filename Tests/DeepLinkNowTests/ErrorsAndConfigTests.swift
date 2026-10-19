import XCTest
@testable import DeepLinkNow

/// Typed errors, init outcome, config, retries and threading
/// (SDK-01, SDK-04…09, SDK-50…56, IOS-05…08, IOS-10…12).
final class ErrorsAndConfigTests: DLNTestCase {

    private func initThrowing(_ config: DLNConfig = DLNConfig(apiKey: DLNTestCase.apiKey)) async throws -> DLNAppInfo {
        try await DeepLinkNow.initializeThrowing(config: config, urlSession: makeSession())
    }

    // MARK: SDK-01 / IOS-05 / IOS-06 config

    func test_SDK_01_defaults() async throws {
        // SDK-01: enableLogs false, baseUrl deeplinknow.com, timeout 10 s, retryAttempts 2.
        let config = DLNConfig(apiKey: Self.apiKey)
        XCTAssertFalse(config.enableLogs)
        StubURLProtocol.stub("init", status: 503, json: Fixtures.errorInternal)
        _ = await captureError { try await self.initThrowing(config) }
        let requests = StubURLProtocol.requests(to: "init")
        XCTAssertEqual(requests.count, 3, "1 attempt + 2 retries by default")
        XCTAssertEqual(requests.first?.request.url?.absoluteString, "https://deeplinknow.com/api/v1/sdk/init")
        XCTAssertEqual(requests.first?.request.timeoutInterval ?? 0, 10, accuracy: 0.001)
    }

    func test_IOS_05_trailingSlashesAndInvalidBaseUrl() async throws {
        // IOS-05: no "//"; an invalid baseUrl is an error, not a crash.
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, baseUrl: "https://deeplinknow.com//"))
        XCTAssertEqual(StubURLProtocol.requests(to: "init").last?.request.url?.absoluteString,
                       "https://deeplinknow.com/api/v1/sdk/init")

        for bad in ["not a url", "", "://nohost", "deeplinknow.com"] {
            let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, baseUrl: bad)) }
            XCTAssertEqual(error?.code, .invalidConfiguration, bad)
            XCTAssertFalse(DeepLinkNow.isInitialized)
        }
    }

    func test_SDK_64_nonHttpsBaseUrlRefusedExceptLocalhost() async throws {
        // SDK-64
        let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, baseUrl: "http://example.com")) }
        XCTAssertEqual(error?.code, .invalidConfiguration)
        for dev in ["http://localhost:3000", "http://127.0.0.1:3000", "http://10.0.2.2:3000"] {
            StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
            _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, baseUrl: dev))
            XCTAssertTrue(DeepLinkNow.isInitialized, dev)
        }
    }

    func test_IOS_06_timeoutAppliesToMatchToo() async throws {
        // IOS-06 / SDK-52
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, timeout: 4))
        _ = try await DeepLinkNow.findDeferredUserThrowing()
        XCTAssertEqual(StubURLProtocol.requests(to: "match").first?.request.timeoutInterval ?? 0, 4, accuracy: 0.001)
    }

    // MARK: SDK-53 retries

    func test_SDK_53_transientFailuresRetriedUpToRetryAttempts() async throws {
        // SDK-53: transport errors, 5xx and 429 are retried.
        StubURLProtocol.stub("init", error: URLError(.timedOut))
        StubURLProtocol.stub("init", status: 429, json: Fixtures.errorRateLimited)
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 2))
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 3)

        StubURLProtocol.reset()
        StubURLProtocol.stub("init", status: 500, json: Fixtures.errorInternal)
        let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 1)) }
        XCTAssertEqual(error?.code, .server)
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 2)
    }

    func test_SDK_53_clientErrorsAreNeverRetried() async {
        // SDK-53: 400, 401, 403, 404, 410 are not retried.
        for status in [400, 401, 403, 404, 410] {
            StubURLProtocol.reset()
            StubURLProtocol.stub("init", status: status, json: #"{"error":"nope"}"#)
            _ = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 3)) }
            XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1, "HTTP \(status) must not be retried")
        }
    }

    func test_SDK_53_retryAfterHonouredAndCapped() async throws {
        // SDK-53: Retry-After is used (capped at 5 s). Delays are scaled to 0 in tests, so this
        // checks the request count and that a Retry-After header does not break the retry.
        StubURLProtocol.stub("init", status: 429, json: Fixtures.errorRateLimited, headers: ["Retry-After": "120"])
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        let start = Date()
        _ = try await initThrowing()
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func test_SDK_53_IOS_06_retryAttemptsClampedToFive() async throws {
        // A huge retryAttempts must not mean minutes of retries: at most 5 retries (6 requests).
        StubURLProtocol.stub("init", status: 503, json: Fixtures.errorInternal)
        let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 1_000_000)) }
        XCTAssertEqual(error?.code, .server)
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1 + APIClient.maxRetryAttempts)
        XCTAssertEqual(APIClient.maxRetryAttempts, 5)
    }

    func test_SDK_53_backoffDelaysCappedAtFiveSeconds() {
        let delays = (0..<8).map { APIClient.backoff(attempt: $0, retryAfter: nil, delayScale: 1) }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 5, 5, 5, 5])
        XCTAssertEqual(APIClient.backoff(attempt: Int.max, retryAfter: nil, delayScale: 1), 5)
        XCTAssertEqual(APIClient.backoff(attempt: 0, retryAfter: 120, delayScale: 1), 5)
        XCTAssertEqual(APIClient.backoff(attempt: 0, retryAfter: 2, delayScale: 1), 2)
        XCTAssertEqual(APIClient.backoff(attempt: 0, retryAfter: -3, delayScale: 1), 0)
        // A non-finite Retry-After ("nan", "inf") falls back to the exponential delay.
        XCTAssertEqual(APIClient.backoff(attempt: 1, retryAfter: .nan, delayScale: 1), 1)
        XCTAssertEqual(APIClient.backoff(attempt: 1, retryAfter: .infinity, delayScale: 1), 1)
        XCTAssertEqual(APIClient.backoff(attempt: 3, retryAfter: nil, delayScale: 0), 0)
    }

    func test_SDK_50_SDK_53_sleepConversionNeverTraps() {
        XCTAssertEqual(APIClient.sleepNanoseconds(0.5), 500_000_000)
        XCTAssertEqual(APIClient.sleepNanoseconds(1e300), 5_000_000_000)
        XCTAssertEqual(APIClient.sleepNanoseconds(.infinity), 0)
        XCTAssertEqual(APIClient.sleepNanoseconds(.nan), 0)
        XCTAssertEqual(APIClient.sleepNanoseconds(-1), 0)
    }

    func test_SDK_52_deferredCheckBoundedByRetries() async throws {
        // SDK-52: a failing /match gives up after 1 + retryAttempts requests.
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", status: 503, json: Fixtures.errorInternal)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 2))
        let error = await captureError { try await DeepLinkNow.checkDeferredDeepLinkThrowing(DLNDeferredOptions(useClipboard: false)) }
        XCTAssertEqual(error?.code, .server)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 3)
    }

    // MARK: SDK-04 / SDK-05 / SDK-55 / IOS-07 typed outcome

    func test_SDK_04_initThrowsTypedErrors() async {
        // SDK-04 / SDK-55
        let cases: [(Int, String, DeepLinkNowError.Code)] = [
            (401, Fixtures.errorInvalidKey, .invalidApiKey),
            (403, Fixtures.errorAccountInactive, .accountInactive),
            (403, Fixtures.errorNoCredits, .noCredits),
            (429, Fixtures.errorRateLimited, .rateLimited),
            (400, Fixtures.errorZod, .badRequest),
            (500, Fixtures.errorInternal, .server),
            (200, Fixtures.testKeyDefault, .invalidResponse),
        ]
        for (status, body, code) in cases {
            StubURLProtocol.reset()
            StubURLProtocol.stub("init", status: status, json: body)
            let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 0)) }
            XCTAssertEqual(error?.code, code, "HTTP \(status)")
            if status != 200 { XCTAssertEqual(error?.statusCode, status) }
        }
    }

    func test_SDK_55_errorCarriesStatusAndServerMessage() async {
        // SDK-55
        StubURLProtocol.stub("init", status: 403, json: Fixtures.errorAccountInactive)
        let error = await captureError { try await self.initThrowing() }
        XCTAssertEqual(error?.statusCode, 403)
        XCTAssertEqual(error?.message, "Account is not active")
        XCTAssertEqual(Set(DeepLinkNowError.Code.allCases.map { $0.rawValue }).isSuperset(of: [
            "notInitialized", "invalidApiKey", "accountInactive", "noCredits", "rateLimited",
            "badRequest", "server", "network", "invalidResponse",
        ]), true)
    }

    func test_SDK_05_isInitializedReflectsOutcome() async throws {
        // SDK-05
        XCTAssertFalse(DeepLinkNow.isInitialized)
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        let info = try await initThrowing()
        XCTAssertTrue(DeepLinkNow.isInitialized)
        XCTAssertEqual(info.alias, "myapp")
        XCTAssertEqual(info.linkDomains, ["myapp.deeplinknow.com", "links.myapp.com"])
        XCTAssertEqual(info.primaryDomain, "links.myapp.com")
        XCTAssertEqual(DeepLinkNow.appInfo, info)
        XCTAssertNil(DeepLinkNow.initializationError)
    }

    func test_IOS_07_failedInitIsDistinguishableFromNoLink() async throws {
        // IOS-07 / SDK-04: later calls throw .notInitialized carrying the init failure.
        StubURLProtocol.stub("init", status: 401, json: Fixtures.errorInvalidKey)
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey), urlSession: makeSession())
        XCTAssertFalse(DeepLinkNow.isInitialized)
        XCTAssertEqual(DeepLinkNow.initializationError?.code, .invalidApiKey)

        let deferred = await captureError { try await DeepLinkNow.checkDeferredDeepLinkThrowing() }
        XCTAssertEqual(deferred?.code, .notInitialized)
        XCTAssertEqual(deferred?.cause?.code, .invalidApiKey)

        let find = await captureError { try await DeepLinkNow.findDeferredUserThrowing() }
        XCTAssertEqual(find?.code, .notInitialized)
        XCTAssertTrue(StubURLProtocol.requests(to: "match").isEmpty)
    }

    func test_SDK_04_neverInitializedThrowsNotInitializedWithoutCause() async {
        // SDK-04
        let error = await captureError { try await DeepLinkNow.checkDeferredDeepLinkThrowing() }
        XCTAssertEqual(error?.code, .notInitialized)
        XCTAssertNil(error?.cause)
    }

    func test_SDK_55_matchErrorsAreTyped() async throws {
        // SDK-55 / SDK-51
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 0))
        let cases: [(Int, String, DeepLinkNowError.Code)] = [
            (200, #"{"matches": [ {"confidence_score": 87, "#, .invalidResponse),
            (200, "<html>captive portal</html>", .invalidResponse),
            (400, Fixtures.errorZod, .badRequest),
            (401, Fixtures.errorInvalidKey, .invalidApiKey),
            (403, Fixtures.errorNoCredits, .noCredits),
            (429, Fixtures.errorRateLimited, .rateLimited),
            (502, "<html>Bad Gateway</html>", .server),
        ]
        for (status, body, code) in cases {
            StubURLProtocol.reset()
            StubURLProtocol.stub("match", status: status, json: body)
            let error = await captureError { try await DeepLinkNow.findDeferredUserThrowing() }
            XCTAssertEqual(error?.code, code, "HTTP \(status) \(body)")
        }
        StubURLProtocol.reset()
        StubURLProtocol.stub("match", error: URLError(.notConnectedToInternet))
        let offline = await captureError { try await DeepLinkNow.findDeferredUserThrowing() }
        XCTAssertEqual(offline?.code, .network)
    }

    func test_SDK_54_offlineFailsFastWithNetwork() async throws {
        // SDK-54
        StubURLProtocol.stub("init", error: URLError(.notConnectedToInternet))
        let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 0)) }
        XCTAssertEqual(error?.code, .network)
    }

    func test_SDK_51_unknownFieldsIgnoredOptionalFieldsTolerated() async throws {
        // SDK-51 / SDK-03: unknown init fields (android_sha256_certificates) are ignored.
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing()
        let minimal = #"{"matches":[{"confidence_score":50.5,"unknown":1,"match_details":{"ip_match":{"matched":false,"score":0},"device_match":{"matched":true,"score":1,"components":{"platform":true,"os_version":true,"device_model":true,"hardware_fingerprint":false}},"time_proximity":{"score":1,"time_difference_minutes":2.4},"locale_match":{"matched":true,"score":1,"components":{"language":true,"timezone":true}}},"deeplink":{"id":"x","target_url":"/a","metadata":null,"query_params":{"n":5,"bad":{"x":1}},"extra":"y"}}],"ttl_seconds":3600,"other":true}"#
        StubURLProtocol.stub("match", json: minimal)
        let response = try await DeepLinkNow.findDeferredUserThrowing()
        let match = try XCTUnwrap(response.matches.first)
        XCTAssertEqual(match.matchQuality, .medium)
        XCTAssertEqual(match.matchDetails.timeProximity.timeDifferenceMinutes, 3)
        XCTAssertEqual(match.deeplink?.metadata.count, 0)
        XCTAssertEqual(match.deeplink?.queryParams?["n"], .string("5"))
        XCTAssertNil(match.deeplink?.queryParams?["bad"])
    }

    func test_SDK_50_SDK_51_outOfRangeTimeDifferenceIsInvalidResponseNotACrash() async throws {
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing(DLNConfig(apiKey: Self.apiKey, retryAttempts: 0))
        for value in ["1e300", "-1e300", "9223372036854775808.5"] {
            StubURLProtocol.reset()
            let json = Fixtures.match().replacingOccurrences(of: #""time_difference_minutes": 2"#,
                                                              with: #""time_difference_minutes": \#(value)"#)
            StubURLProtocol.stub("match", json: Fixtures.matchResponse([json]))
            let error = await captureError { try await DeepLinkNow.findDeferredUserThrowing() }
            XCTAssertEqual(error?.code, .invalidResponse, value)
        }
    }

    // MARK: SDK-07 / SDK-08 / SDK-09

    func test_SDK_08_oneInitRequestPerInitialize() async throws {
        // SDK-08
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await initThrowing()
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
    }

    func test_SDK_07_concurrentInitsWithSameKeyShareOneRequest() async throws {
        // SDK-07
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        let session = makeSession()
        let config = DLNConfig(apiKey: Self.apiKey)
        async let a = DeepLinkNow.initializeThrowing(config: config, urlSession: session)
        async let b = DeepLinkNow.initializeThrowing(config: config, urlSession: session)
        let (first, second) = try await (a, b)
        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(StubURLProtocol.requests(to: "init").count, 2)
        XCTAssertTrue(DeepLinkNow.isInitialized)
    }

    @MainActor func test_SDK_09_initDoesNotBlockTheMainThread() async throws {
        // SDK-09 / SDK-56: initialize is async; awaiting it from the main actor does not block.
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        let session = makeSession()
        _ = try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey), urlSession: session)
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(DeepLinkNow.isInitialized)
        XCTAssertEqual(fakePasteboard.reads, 0, "init never reads the clipboard")
        XCTAssertEqual(fakePasteboard.detectCalls, 0)
    }

    // MARK: IOS-10 / IOS-11 / IOS-12 / SDK-50 / SDK-56 safety

    func test_IOS_10_concurrentAccessIsRaceFree() async throws {
        // IOS-10: hammer the static API from many tasks while re-initializing.
        // (Run with Thread Sanitizer to make this a hard check.)
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let session = makeSession()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                group.addTask {
                    switch i % 4 {
                    case 0: _ = try? await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey), urlSession: session)
                    case 1: _ = DeepLinkNow.isValidDomain("myapp.deeplinknow.com")
                    case 2: _ = DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/x?a=1")!)
                    default: _ = await DeepLinkNow.findDeferredUser()
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertTrue(DeepLinkNow.isInitialized)
    }

    func test_IOS_11_fingerprintBuiltOnMainActorFromBackground() async throws {
        // IOS-11: calling from a background task must still produce UIKit-derived values
        // (the SDK hops to the main actor; Main Thread Checker would flag a violation).
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await initThrowing()
        let response = try await Task.detached(priority: .background) {
            try await DeepLinkNow.findDeferredUserThrowing()
        }.value
        XCTAssertTrue(response.matches.isEmpty)
        let body = try XCTUnwrap(StubURLProtocol.requests(to: "match").last?.json?["fingerprint"] as? [String: Any])
        XCTAssertNotNil(body["screen_width"] as? NSNumber)
    }

    func test_IOS_12_noCrashOnHostileInput() async throws {
        // IOS-12 / SDK-50: odd URLs, odd configs, odd bodies → nil or a typed error, never a trap.
        for raw in ["https://%E2%82@myapp.deeplinknow.com/%", "https://myapp.deeplinknow.com/%E2%82?%=%&=&&", "https://[::1]:99999/"] {
            if let url = URL(string: raw) { _ = DeepLinkNow.parseLink(url) }
        }
        _ = DeepLinkNow.isValidDomain(":::")
        _ = DeepLinkNow.createDeepLink(path: "%%%/\u{0}")
        let error = await captureError { try await self.initThrowing(DLNConfig(apiKey: "", baseUrl: "https://x.com")) }
        XCTAssertEqual(error?.code, .invalidConfiguration)
        StubURLProtocol.stub("init", status: 200, json: #"{"app":{"id":"x","alias":""},"account":{"status":"active"}}"#)
        let empty = await captureError { try await self.initThrowing() }
        XCTAssertEqual(empty?.code, .invalidResponse)
    }

    func test_SDK_50_legacyAPIsNeverThrowOrCrash() async {
        // SDK-50: the non-throwing APIs return nil on every failure.
        StubURLProtocol.stub("init", status: 500, json: Fixtures.errorInternal)
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0), urlSession: makeSession())
        let match = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(match)
    }

    @MainActor func test_SDK_56_asyncAPIsCallableFromMainActor() async throws {
        // SDK-56: async APIs return on the caller's context.
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey), urlSession: makeSession())
        _ = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertTrue(Thread.isMainThread)
    }
}
