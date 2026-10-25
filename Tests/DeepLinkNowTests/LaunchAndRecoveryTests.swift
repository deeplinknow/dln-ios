import XCTest
import UIKit
@testable import DeepLinkNow

/// 1.4.1: cold-start launch options (IOS-39), the resolve deadline while init hangs (IOS-37),
/// a held deferred link that survives a relaunch (IOS-40) and the retry of a failed
/// handler check (IOS-41).
final class LaunchAndRecoveryTests: DLNTestCase {

    private let recorder = LinkRecorder()
    private let clock = TestClock()

    override func setUp() async throws {
        try await super.setUp()
        let clock = self.clock
        DeepLinkNow.environment.withLock { $0.now = { clock.now } }
    }

    private func register(_ options: DLNLinkOptions = DLNLinkOptions(useClipboard: false)) {
        let recorder = self.recorder
        DeepLinkNow.onLink(options: options) { link in recorder.append(link) }
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    private var savedLink: SavedDeferredLink? { SavedDeferredLink.load(from: defaults) }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: IOS-39 launch options and user activities

    func test_IOS_39_browsingActivityIsHandedOverAsAUniversalLink() async throws {
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url("https://links.myapp.com/products/7?x=1")
        XCTAssertTrue(DeepLinkNow.handle(activity))
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .direct)
        XCTAssertEqual(links.first?.source, .universalLink)
        XCTAssertEqual(links.first?.fullPath, "/products/7?x=1")

        let other = NSUserActivity(activityType: "com.myapp.handoff")
        other.webpageURL = url("https://links.myapp.com/products/8")
        XCTAssertFalse(DeepLinkNow.handle(other), "only NSUserActivityTypeBrowsingWeb carries a link")
        XCTAssertFalse(DeepLinkNow.handle(NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)))
    }

    func test_IOS_39_launchOptionsHandOverActivitiesAndURLs() async throws {
        // IOS-39: what `handle(_ connectionOptions:)` does with `userActivities` and `urlContexts`
        // (UIScene.ConnectionOptions has no public initializer, so the shared helper is tested).
        DeepLinkNow.environment.withLock { $0.declaredURLSchemes = { ["myapp"] } }
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        register()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url("https://myapp.deeplinknow.com/cold")
        XCTAssertTrue(DeepLinkNow.handleLaunch(activities: [activity], urls: [url("myapp://scheme/open")]))
        let links = await recorder.wait(for: 2)
        XCTAssertEqual(links.map { $0.source }, [.universalLink, .scheme])
        XCTAssertEqual(links.map { $0.path }, ["/cold", "/scheme/open"])

        XCTAssertFalse(DeepLinkNow.handleLaunch(activities: [], urls: [url("https://example.com/x")]))
        XCTAssertFalse(DeepLinkNow.handleLaunch(activities: [], urls: []))
    }

    // MARK: IOS-37 resolve deadline

    func test_IOS_37_deadlineDoesNotWaitForAnOperationThatIgnoresCancellation() async {
        // IOS-37 / SDK-90: the old task-group deadline waited for every child, so an operation
        // that ignores cancellation held the caller past the timeout.
        let start = Date()
        let result = await DeepLinkNow.withDeadline(seconds: 0.2, fallback: "fallback") {
            await NonCancellableWait.seconds(2)
            return "late"
        }
        XCTAssertEqual(result, "fallback")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func test_IOS_37_resolveIsBoundedWhileInitIsStillInFlight() async throws {
        // IOS-37: the whole lookup, including waiting for an init that hangs (and ignores
        // cancellation), takes at most DLNConfig.timeout; the link arrives unresolved.
        let session = HangingInitSession(hang: 2)
        let config = DLNConfig(apiKey: Self.apiKey, timeout: 0.3, retryAttempts: 0)
        let initTask = Task { await DeepLinkNow.initialize(config: config, urlSession: session) }
        await waitUntil { DeepLinkNow.state.withLock { $0.inFlight != nil } }

        var start = Date()
        let resolved = await DeepLinkNow.resolveLink(url("https://myapp.deeplinknow.com/abc123"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.2)
        XCTAssertEqual(resolved?.path, "/abc123")
        XCTAssertNil(resolved?.deeplinkId)

        register(DLNLinkOptions(useClipboard: false, resolve: true))
        start = Date()
        XCTAssertTrue(DeepLinkNow.handle(url("https://myapp.deeplinknow.com/slow")))
        let links = await recorder.wait(for: 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.2)
        XCTAssertEqual(links.first?.path, "/slow")
        XCTAssertNil(links.first?.deeplinkId)

        // Let the hung init and the deferred check behind it finish before tearDown.
        await initTask.value
        await recorder.settle()
    }

    // MARK: IOS-40 a held deferred link survives a relaunch

    /// Holds the deferred fingerprint link, as a sign-in gate would.
    private func holdDeferredLink() async throws {
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register(DLNLinkOptions(useClipboard: false, hold: true))
        await waitUntil { DeepLinkNow.pendingLink != nil }
        XCTAssertEqual(DeepLinkNow.pendingLink?.type, .deferred)
    }

    /// What a new process sees: memory gone, `UserDefaults` kept.
    private func relaunch() async {
        DeepLinkNow.resetForTesting()
        await initializeSDK()
        clearCapturedRequests()
    }

    func test_IOS_40_heldDeferredLinkSurvivesTheAppBeingKilled() async throws {
        try await holdDeferredLink()
        XCTAssertNotNil(savedLink, "a held deferred link is saved")
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))

        await relaunch()
        clock.advance(by: 10 * 60)   // the user went to fetch the sign-in code
        register(DLNLinkOptions(useClipboard: false, hold: true))
        let held = try XCTUnwrap(DeepLinkNow.pendingLink)
        XCTAssertEqual(held.type, .deferred)
        XCTAssertEqual(held.source, .fingerprint)
        XCTAssertEqual(held.fullPath, "/promo?code=SAVE20&debug")
        XCTAssertEqual(held.queryParams["code"], .string("SAVE20"))
        XCTAssertEqual(held.deeplinkId, "3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f")
        XCTAssertEqual(held.confidenceScore, 87)
        XCTAssertNotNil(held.matchDetails)
        XCTAssertEqual(held.metadata?["source"]?.value as? String, "newsletter")
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 0, "the chain is not run again")

        DeepLinkNow.releasePendingLink()
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.map { $0.type }, [.deferred])
        await waitUntil { self.savedLink == nil }
        XCTAssertNil(savedLink, "delivered, so it is gone")

        await relaunch()
        register()
        await recorder.settle()
        XCTAssertEqual(recorder.links.count, 1, "never delivered twice")
    }

    func test_IOS_40_savedLinkWithoutHoldIsDeliveredOnTheNextLaunch() async throws {
        try await holdDeferredLink()
        await relaunch()
        register()
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .deferred)
        XCTAssertEqual(links.first?.path, "/promo")
    }

    func test_IOS_40_savedLinkExpiresAfter24Hours() async throws {
        try await holdDeferredLink()
        await relaunch()
        clock.advance(by: 24 * 60 * 60 + 1)
        register(DLNLinkOptions(useClipboard: false, hold: true))
        XCTAssertNil(DeepLinkNow.pendingLink)
        XCTAssertNil(savedLink, "an expired link is deleted")
    }

    func test_IOS_40_clearPendingLinkAndResetDeleteTheSavedLink() async throws {
        try await holdDeferredLink()
        DeepLinkNow.clearPendingLink()
        XCTAssertNil(savedLink)

        DeepLinkNow.resetDeferredDeepLink()   // so the chain runs again and finds the link
        DeepLinkNow.resetForTesting()
        try await holdDeferredLink()
        XCTAssertNotNil(savedLink)
        DeepLinkNow.resetDeferredDeepLink()
        XCTAssertNil(savedLink)
    }

    func test_IOS_40_aDeliveredDeferredLinkIsNotKept() async throws {
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        _ = await recorder.wait(for: 1)
        await recorder.settle()
        XCTAssertNil(savedLink)
    }

    // MARK: IOS-41 a failed handler check runs again

    private func failFirstMatch() async {
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0))
        StubURLProtocol.stub("match", error: URLError(.notConnectedToInternet))
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        await waitUntil { StubURLProtocol.requests(to: "match").count == 1 && DeepLinkNow.lastError != nil }
        await recorder.settle()
        XCTAssertTrue(recorder.links.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey), "SDK-24")
    }

    func test_IOS_41_offlineCheckRunsAgainWhenTheAppBecomesActive() async throws {
        await failFirstMatch()
        await MainActor.run {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .deferred)
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 2)

        // Once it has succeeded, becoming active again does nothing.
        await MainActor.run {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        await recorder.settle()
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 2)
    }

    func test_IOS_41_failedCheckRunsAgainOnTheNextInitialize() async throws {
        await failFirstMatch()
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0))
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .deferred)
    }

    func test_IOS_41_failedCheckRunsAgainOnTheNextOnLink() async throws {
        await failFirstMatch()
        register()
        let links = await recorder.wait(for: 1)
        XCTAssertEqual(links.first?.type, .deferred)
    }

    func test_IOS_41_aRejectedKeyIsNotRetriedWhenTheAppBecomesActive() async throws {
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0))
        StubURLProtocol.stub("match", status: 401, json: Fixtures.errorInvalidKey)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        register()
        await waitUntil { StubURLProtocol.requests(to: "match").count == 1 && DeepLinkNow.lastError != nil }
        await MainActor.run {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        await recorder.settle()
        XCTAssertEqual(StubURLProtocol.requests(to: "match").count, 1)
        XCTAssertTrue(recorder.links.isEmpty)
    }
}

// MARK: - Helpers

/// Waits on a dispatch timer, not `Task.sleep`, so cancelling the task has no effect.
enum NonCancellableWait {
    static func seconds(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }
}

/// `/init` hangs for `hang` seconds whatever happens to the task; everything else answers at once.
final class HangingInitSession: URLSessionProtocol, @unchecked Sendable {
    let hang: TimeInterval

    init(hang: TimeInterval) { self.hang = hang }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let endpoint = request.url?.lastPathComponent ?? ""
        if endpoint == "init" { await NonCancellableWait.seconds(hang) }
        let body: String
        switch endpoint {
        case "init": body = Fixtures.initWithVerifiedCustomDomain
        case "match": body = Fixtures.matchEmpty
        default: body = #"{"error":"Deeplink not found"}"#
        }
        let status = endpoint == "init" || endpoint == "match" ? 200 : 404
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }
}
