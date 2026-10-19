import XCTest
@testable import DeepLinkNow

/// SDK-85 / SDK-10: the everyday calls never throw; failures come back as `nil`, are logged
/// and are kept in `DeepLinkNow.lastError` until the next success of the same kind.
final class NonBlockingTests: DLNTestCase {

    private func initialize() async throws {
        StubURLProtocol.stub("init", json: Fixtures.initWithVerifiedCustomDomain)
        _ = try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0), urlSession: makeSession())
    }

    func test_SDK_85_checkDeferredDeepLinkReturnsNilWhenNotInitialized() async {
        // SDK-85 / SDK-10 / SDK-04
        let link = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertNil(link)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .notInitialized)
        XCTAssertTrue(logs.joined.contains("Warning"), "the failure is logged as a warning")
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
    }

    func test_SDK_85_checkDeferredDeepLinkReturnsNilOn401() async throws {
        // SDK-85 / SDK-10 / SDK-55
        try await initialize()
        StubURLProtocol.stub("match", status: 401, json: Fixtures.errorInvalidKey)
        let link = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertNil(link)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .invalidApiKey)
        XCTAssertEqual(DeepLinkNow.lastError?.statusCode, 401)
        XCTAssertTrue(logs.joined.contains("Warning: checkDeferredDeepLink failed"))
    }

    func test_SDK_85_checkDeferredDeepLinkReturnsNilWhenOffline() async throws {
        // SDK-85 / SDK-10
        try await initialize()
        StubURLProtocol.stub("match", error: URLError(.notConnectedToInternet))
        let link = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertNil(link)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .network)
        XCTAssertFalse(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey), "an error does not consume the first launch")
    }

    func test_SDK_85_laterSuccessClearsLastError() async throws {
        // SDK-85
        try await initialize()
        StubURLProtocol.stub("match", error: URLError(.notConnectedToInternet))
        _ = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertNotNil(DeepLinkNow.lastError)

        StubURLProtocol.reset()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let link = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertNotNil(link)
        XCTAssertNil(DeepLinkNow.lastError)
    }

    func test_SDK_85_successOfAnotherKindKeepsLastError() async throws {
        // SDK-85: only a success of the same kind clears lastError.
        StubURLProtocol.stub("init", status: 401, json: Fixtures.errorInvalidKey)
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey, retryAttempts: 0), urlSession: makeSession())
        XCTAssertEqual(DeepLinkNow.lastError?.code, .invalidApiKey)
        XCTAssertEqual(DeepLinkNow.initializationError?.code, .invalidApiKey)

        StubURLProtocol.reset()
        try await initialize()
        XCTAssertNil(DeepLinkNow.lastError, "a successful init clears the init failure")
    }

    func test_SDK_85_findDeferredUserRecordsAndClearsLastError() async throws {
        // SDK-85
        let none = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(none)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .notInitialized)

        try await initialize()
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertNotNil(response)
        XCTAssertNil(DeepLinkNow.lastError)
    }

    func test_SDK_85_throwingVariantStillThrows() async throws {
        // SDK-85 / SDK-55: the opt-in variant keeps the typed errors.
        let notInit = await captureError { try await DeepLinkNow.checkDeferredDeepLinkThrowing(DLNDeferredOptions(useClipboard: false)) }
        XCTAssertEqual(notInit?.code, .notInitialized)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .notInitialized)

        try await initialize()
        StubURLProtocol.stub("match", status: 401, json: Fixtures.errorInvalidKey)
        let unauthorized = await captureError { try await DeepLinkNow.checkDeferredDeepLinkThrowing(DLNDeferredOptions(useClipboard: false)) }
        XCTAssertEqual(unauthorized?.code, .invalidApiKey)
        XCTAssertEqual(DeepLinkNow.lastError?.code, .invalidApiKey)
    }
}
