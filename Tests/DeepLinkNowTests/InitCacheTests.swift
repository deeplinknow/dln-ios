import XCTest
@testable import DeepLinkNow

/// SDK-83: a cold start within 24 hours of the last /init, in the same UTC month,
/// initializes from the device cache with no network request.
final class InitCacheTests: DLNTestCase {

    private var clock = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-15 (UTC)

    override func setUp() async throws {
        try await super.setUp()
        setClock(clock)
    }

    private func setClock(_ date: Date) {
        clock = date
        DeepLinkNow.environment.withLock { $0.now = { date } }
    }

    /// A new process: in-memory state gone, UserDefaults kept.
    private func relaunch() {
        DeepLinkNow.resetForTesting()
        StubURLProtocol.reset()
    }

    /// Initialize without stubbing /init, for cold starts the cache should serve.
    private func initializeWithoutStub() async {
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey), urlSession: makeSession())
    }

    private func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    func test_SDK_83_coldStartWithin24HoursUsesTheCache() async throws {
        await initializeSDK()
        let first = try XCTUnwrap(DeepLinkNow.appInfo)
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)

        relaunch()
        setClock(clock.addingTimeInterval(23 * 3600))
        await initializeWithoutStub()

        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 0, "served from the cache")
        XCTAssertTrue(DeepLinkNow.isInitialized)
        XCTAssertEqual(DeepLinkNow.appInfo, first)
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com"))
    }

    func test_SDK_83_after24HoursItAsksTheServerAgain() async throws {
        await initializeSDK()
        relaunch()
        setClock(clock.addingTimeInterval(24 * 3600 + 1))
        await initializeSDK()
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
    }

    func test_SDK_83_BILL_19_aNewUtcMonthAlwaysAsksTheServer() async throws {
        // Every device must reach /init at least once a month, or MAU undercounts.
        setClock(utc("2026-10-31T23:00:00Z"))
        await initializeSDK()
        relaunch()
        setClock(utc("2026-11-01T01:00:00Z"))
        await initializeSDK()
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
    }

    func test_SDK_83_aDifferentKeyOrBaseUrlIgnoresTheCache() async throws {
        await initializeSDK()
        relaunch()
        await initializeSDK(config: DLNConfig(apiKey: "dln_pub_other_0123456789abcdef"))
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
        relaunch()
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, baseUrl: "http://localhost:3000"))
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
    }

    func test_SDK_83_SDK_07_initializingAgainInTheSameProcessAlwaysAsksTheServer() async throws {
        await initializeSDK()
        relaunch()
        await initializeWithoutStub() // cold start: cache
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 0)
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com"))
        await initializeSDK(initJSON: Fixtures.initNoCustomDomain) // explicit re-init: network
        XCTAssertEqual(StubURLProtocol.requests(to: "init").count, 1)
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"))
    }

    func test_SDK_83_aRejectedKeyClearsTheCache() async throws {
        await initializeSDK()
        XCTAssertNotNil(InitCache.load(from: defaults))
        setClock(clock.addingTimeInterval(25 * 3600))
        relaunch()
        await initializeSDK(initJSON: #"{"error":"Invalid API key"}"#, status: 401)
        XCTAssertFalse(DeepLinkNow.isInitialized)
        XCTAssertNil(InitCache.load(from: defaults))
    }

    func test_SDK_83_SDK_26_resetDeferredDeepLinkClearsTheCache() async throws {
        await initializeSDK()
        DeepLinkNow.resetDeferredDeepLink()
        XCTAssertNil(InitCache.load(from: defaults))
    }

    func test_SDK_83_aFailedInitLeavesNoCache() async throws {
        await initializeSDK(initJSON: #"{"error":"boom"}"#, status: 500)
        XCTAssertNil(InitCache.load(from: defaults))
    }
}
