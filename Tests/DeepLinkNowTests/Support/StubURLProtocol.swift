import Foundation
import UIKit
import XCTest
@testable import DeepLinkNow

/// URLProtocol stub registered on an ephemeral URLSession that is injected via
/// `DeepLinkNow.initialize(config:urlSession:)` (the SDK's existing public seam).
/// Stubs are keyed by endpoint (last path component: "init", "match", ...).
/// Each endpoint holds a queue; the last stub in a queue is sticky.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = ["Content-Type": "application/json"]
        var error: Error?
    }

    struct Captured {
        let request: URLRequest
        let body: Data?

        var json: [String: Any]? {
            guard let body = body else { return nil }
            return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    private static let lock = NSLock()
    private static var stubs: [String: [Stub]] = [:]
    private static var captured: [Captured] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        stubs = [:]
        captured = []
    }

    static func stub(_ endpoint: String, status: Int = 200, json: String) {
        enqueue(endpoint, Stub(status: status, body: Data(json.utf8)))
    }

    static func stub(_ endpoint: String, status: Int, raw: String, contentType: String) {
        enqueue(endpoint, Stub(status: status, body: Data(raw.utf8), headers: ["Content-Type": contentType]))
    }

    static func stub(_ endpoint: String, status: Int, json: String, headers: [String: String]) {
        var all = ["Content-Type": "application/json"]
        headers.forEach { all[$0.key] = $0.value }
        enqueue(endpoint, Stub(status: status, body: Data(json.utf8), headers: all))
    }

    static func stub(_ endpoint: String, error: Error) {
        enqueue(endpoint, Stub(error: error))
    }

    static func enqueue(_ endpoint: String, _ stub: Stub) {
        lock.lock(); defer { lock.unlock() }
        stubs[endpoint, default: []].append(stub)
    }

    static var requests: [Captured] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    static func requests(to endpoint: String) -> [Captured] {
        requests.filter { $0.request.url?.lastPathComponent == endpoint }
    }

    private static func nextStub(for endpoint: String) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        guard var queue = stubs[endpoint], !queue.isEmpty else { return nil }
        let stub = queue.count > 1 ? queue.removeFirst() : queue[0]
        stubs[endpoint] = queue
        return stub
    }

    private static func record(_ c: Captured) {
        lock.lock(); defer { lock.unlock() }
        captured.append(c)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.record(Captured(request: request, body: Self.readBody(of: request)))

        let endpoint = request.url?.lastPathComponent ?? ""
        let stub = StubURLProtocol.nextStub(for: endpoint)
            ?? Stub(status: 404, body: Data(#"{"error":"No stub for \#(endpoint)"}"#.utf8))

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves `httpBody` into `httpBodyStream` before it reaches a URLProtocol.
    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Shared test harness

class DLNTestCase: XCTestCase {
    static let apiKey = "dln_pub_test_0123456789abcdef"
    static let alias = "myapp"
    static let defaultsSuite = "com.deeplinknow.tests"

    /// Captured SDK log lines (the SDK's log sink is redirected here).
    let logs = LogCapture()
    /// Fake pasteboard used by the deferred chain unless a test opts into the real one.
    let fakePasteboard = FakePasteboard()
    var defaults: UserDefaults { UserDefaults(suiteName: Self.defaultsSuite)! }

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        DeepLinkNow.resetForTesting()
        UserDefaults().removePersistentDomain(forName: Self.defaultsSuite)
        let logs = self.logs
        let board = fakePasteboard
        let suite = Self.defaultsSuite
        DeepLinkNow.environment.withLock { env in
            env.defaults = UserDefaults(suiteName: suite)!
            env.pasteboard = board
            env.logSink = { logs.append($0) }
            env.retryDelayScale = 0
        }
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        DeepLinkNow.resetForTesting()
        UserDefaults().removePersistentDomain(forName: Self.defaultsSuite)
        DeepLinkNow.environment.withLock { env in
            env = DeepLinkNow.Environment()
            env.retryDelayScale = 0
        }
        try await super.tearDown()
    }

    /// Switch the SDK to the real UIPasteboard (Catalyst-only clipboard tests).
    func useSystemPasteboard() {
        DeepLinkNow.environment.withLock { $0.pasteboard = SystemPasteboard() }
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Initializes the SDK against a stubbed /init response (legacy non-throwing API).
    func initializeSDK(
        initJSON: String = Fixtures.initWithVerifiedCustomDomain,
        status: Int = 200,
        config: DLNConfig = DLNConfig(apiKey: DLNTestCase.apiKey)
    ) async {
        StubURLProtocol.stub("init", status: status, json: initJSON)
        await DeepLinkNow.initialize(config: config, urlSession: makeSession())
    }

    /// Clears request history so assertions only see requests made after this call.
    func clearCapturedRequests() {
        StubURLProtocol.resetCapturedOnly()
    }

    /// Runs `body` and returns the DeepLinkNowError it threw (fails the test if it did not throw one).
    func captureError<T>(_ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async -> DeepLinkNowError? {
        do {
            _ = try await body()
            XCTFail("expected a DeepLinkNowError", file: file, line: line)
            return nil
        } catch let error as DeepLinkNowError {
            return error
        } catch {
            XCTFail("unexpected error type \(error)", file: file, line: line)
            return nil
        }
    }
}

final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    var joined: String { lines.joined(separator: "\n") }
}

/// In-memory pasteboard. Counts reads so tests can assert "no read / no prompt".
final class FakePasteboard: PasteboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _content: String?
    private var _reads = 0
    private var _detectCalls = 0
    /// Simulates `detectPatterns` (nil = API unavailable).
    var detectResultOverride: Bool??

    var content: String? {
        get { lock.lock(); defer { lock.unlock() }; return _content }
        set { lock.lock(); _content = newValue; lock.unlock() }
    }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return _reads }
    var detectCalls: Int { lock.lock(); defer { lock.unlock() }; return _detectCalls }

    func hasContentWithoutReading() -> Bool { content != nil }

    func probablyContainsWebURL() async -> Bool? {
        lock.lock(); _detectCalls += 1; lock.unlock()
        if let override = detectResultOverride { return override }
        guard let text = content else { return false }
        return text.contains("://")
    }

    func readString() async -> String? { readStringSync() }

    func readStringSync() -> String? {
        lock.lock(); defer { lock.unlock() }
        _reads += 1
        return _content
    }
}

extension StubURLProtocol {
    static func resetCapturedOnly() {
        lock.lock(); defer { lock.unlock() }
        captured = []
    }
}

// MARK: - Pasteboard

/// On iOS 16+ a programmatic read of UIPasteboard.general from a process that did not
/// write the content shows the "Allow Paste" prompt and blocks the calling thread. The
/// SPM xctest runner on the iOS Simulator has no UI to answer it, so every read hangs.
/// Clipboard tests therefore run on Mac Catalyst (no prompt) and skip on the Simulator
/// unless DLN_RUN_PASTEBOARD_TESTS=1 is set (e.g. when paste is pre-allowed manually).
enum PasteboardSupport {
    static func requireReadablePasteboard() throws {
        #if targetEnvironment(macCatalyst)
        return
        #else
        if ProcessInfo.processInfo.environment["DLN_RUN_PASTEBOARD_TESTS"] == "1" { return }
        throw XCTSkip("UIPasteboard reads block on the iOS 16+ paste prompt under xctest; run on Mac Catalyst")
        #endif
    }

    /// Saves and restores the real pasteboard (on Catalyst this is the user's Mac clipboard).
    @MainActor static func snapshot() -> [[String: Any]] { UIPasteboard.general.items }
    @MainActor static func restore(_ items: [[String: Any]]) { UIPasteboard.general.items = items }
}
