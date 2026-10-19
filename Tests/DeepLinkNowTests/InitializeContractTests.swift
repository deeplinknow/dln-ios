import XCTest
@testable import DeepLinkNow

/// `initialize(config:urlSession:)` against the contract of web/app/api/v1/sdk/init/route.ts.
final class InitializeContractTests: DLNTestCase {

    // MARK: Request contract

    // SDK-02
    func testInitSendsPOSTToInitEndpointWithApiKeyHeader() async throws {
        await initializeSDK()

        let requests = StubURLProtocol.requests(to: "init")
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first?.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://deeplinknow.com/api/v1/sdk/init")
        // middleware/utils/auth.ts reads the key from the `x-api-key` header only.
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Self.apiKey)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(request.url!.absoluteString.contains(Self.apiKey), "SDK-02: key never in the URL")
    }

    func test_BILL_20_initBodyCarriesDeviceIdMatchingMatchRequest() async throws {
        // BILL-20: init sends JSON {"device_id": IDFV | null}, the same value as /match device_id.
        await initializeSDK()
        let initRequest = try XCTUnwrap(StubURLProtocol.requests(to: "init").first)
        XCTAssertEqual(initRequest.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(initRequest.json, "init body must be a JSON object")
        XCTAssertEqual(Set(body.keys), ["device_id", "sdk"])
        // FP-21: the SDK names itself so the server can see which versions count MAU.
        XCTAssertEqual(body["sdk"] as? String, "ios/\(DeepLinkNow.sdkVersion)")
        let deviceId = try XCTUnwrap(body["device_id"])
        if let idfv = deviceId as? String {
            XCTAssertNotNil(UUID(uuidString: idfv))
        } else {
            XCTAssertTrue(deviceId is NSNull)
        }
        XCTAssertNil(body["api_key"], "the key travels only in the header")

        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.findDeferredUserThrowing()
        let fingerprint = try XCTUnwrap(StubURLProtocol.requests(to: "match").last?.json?["fingerprint"] as? [String: Any])
        XCTAssertEqual(body["device_id"] as? String, fingerprint["device_id"] as? String)
        XCTAssertEqual(body["device_id"] is NSNull, fingerprint["device_id"] is NSNull)
    }

    func testInitUsesCustomBaseUrl() async throws {
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, baseUrl: "http://localhost:3000"))
        let url = try XCTUnwrap(StubURLProtocol.requests(to: "init").first?.request.url)
        XCTAssertEqual(url.absoluteString, "http://localhost:3000/api/v1/sdk/init")
    }

    func testInitBaseUrlWithTrailingSlashProducesCleanPath() async throws {
        // SDK-01 / IOS-05. Was a BUG: makeAPIRequest builds "\(baseUrl)/api/v1/sdk/\(endpoint)" without normalising,
        // so a baseUrl of "https://deeplinknow.com/" yields "//api/v1/sdk/init", which does not
        // match the Next.js route / middleware API-key path checks.
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, baseUrl: "https://deeplinknow.com/"))
        let url = try XCTUnwrap(StubURLProtocol.requests(to: "init").first?.request.url)
        XCTAssertEqual(url.path, "/api/v1/sdk/init")
    }

    // IOS-06
    func testInitAppliesConfiguredTimeout() async throws {
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, timeout: 7))
        let request = try XCTUnwrap(StubURLProtocol.requests(to: "init").first?.request)
        XCTAssertEqual(request.timeoutInterval, 7, accuracy: 0.001)
    }

    // MARK: Response decoding / stored config

    // SDK-03
    func testVerifiedCustomDomainAndAliasDomainsAreStored() async {
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)

        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("otherapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("evil.com"))
    }

    func testServerShapeWithoutCustomDomainDecodes() async {
        // Server always sends custom_domains: [{domain: null, verified: false}] and null
        // platform fields when the app has none configured. Must not fail decoding.
        await initializeSDK(initJSON: Fixtures.initNoCustomDomain)
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"))
    }

    func testUnverifiedCustomDomainIsNotTrusted() async {
        await initializeSDK(initJSON: Fixtures.initUnverifiedCustomDomain)
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("pending.myapp.com"))
    }

    func testNullVerifiedCustomDomainIsNotTrusted() async {
        await initializeSDK(initJSON: Fixtures.initNullVerified)
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"))
    }

    // SDK-07
    func testReinitializeReplacesPreviousDomains() async {
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com"))

        StubURLProtocol.reset()
        await initializeSDK(initJSON: Fixtures.initNoCustomDomain)
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"))
    }

    // MARK: Errors (IOS-07 / SDK-04: each leaves isInitialized == false, no custom domains
    // trusted, a typed initializationError, and must not crash)

    private func assertInitFails(status: Int, body: String, expected: DeepLinkNowError.Code,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        // Start from a successful init so we can prove the failure does not keep stale domains.
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        XCTAssertTrue(DeepLinkNow.isInitialized, file: file, line: line)
        StubURLProtocol.reset()
        await initializeSDK(initJSON: body, status: status)
        XCTAssertFalse(DeepLinkNow.isInitialized, file: file, line: line)
        XCTAssertEqual(DeepLinkNow.initializationError?.code, expected, file: file, line: line)
        // SDK-37: back to the provisional rule; the verified custom domain is no longer trusted.
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"), file: file, line: line)
        XCTAssertNil(DeepLinkNow.parseDeepLink(URL(string: "https://links.myapp.com/x")!), file: file, line: line)
        XCTAssertNil(DeepLinkNow.createDeepLink(path: "/x"), file: file, line: line)
    }

    func testInvalidApiKey401() async { await assertInitFails(status: 401, body: Fixtures.errorInvalidKey, expected: .invalidApiKey) }
    func testInactiveAccount403() async { await assertInitFails(status: 403, body: Fixtures.errorAccountInactive, expected: .accountInactive) }
    func testNoCredits403() async { await assertInitFails(status: 403, body: Fixtures.errorNoCredits, expected: .noCredits) }
    func testRateLimited429() async { await assertInitFails(status: 429, body: Fixtures.errorRateLimited, expected: .rateLimited) }
    func testZodError400WithArrayDetails() async { await assertInitFails(status: 400, body: Fixtures.errorZod, expected: .badRequest) }
    func testInternalError500() async { await assertInitFails(status: 500, body: Fixtures.errorInternal, expected: .server) }
    func testNonJSONErrorPage502() async { await assertInitFails(status: 502, body: "<html>Bad Gateway</html>", expected: .server) }
    func testMalformedJSON200() async { await assertInitFails(status: 200, body: #"{"app": {"id": "x""#, expected: .invalidResponse) }
    func testTestKeyDefaultBody200() async { await assertInitFails(status: 200, body: Fixtures.testKeyDefault, expected: .invalidResponse) }

    func testTransportErrorDoesNotCrash() async {
        StubURLProtocol.stub("init", error: URLError(.notConnectedToInternet))
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey), urlSession: makeSession())
        XCTAssertFalse(DeepLinkNow.isInitialized)
        XCTAssertEqual(DeepLinkNow.initializationError?.code, .network)
    }

    func testRetryAttemptsConfigIsHonoured() async {
        // SDK-53 / IOS-06. Was a BUG: DLNConfig.retryAttempts is public API but is never read anywhere in the SDK.
        // Intended: a transient 5xx is retried up to `retryAttempts` times. A lost init/match
        // on first launch loses the deferred deep link permanently.
        StubURLProtocol.stub("init", status: 503, json: Fixtures.errorInternal)
        StubURLProtocol.stub("init", status: 200, json: Fixtures.initWithVerifiedCustomDomain)
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 2),
                                     urlSession: makeSession())
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 2, "expected one retry after a 503")
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
    }
}
