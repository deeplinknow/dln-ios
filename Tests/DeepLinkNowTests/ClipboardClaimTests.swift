import XCTest
import UIKit
@testable import DeepLinkNow

/// Claiming a clipboard hit (SDK-92, SDK-93, IOS-35) and stripping the `dln` fragment.
/// Uses the in-memory FakePasteboard, so it runs on the Simulator as well as Catalyst.
final class ClipboardClaimTests: DLNTestCase {

    private let clickId = "0d7e2c9a-5b1f-4e8c-9a3d-7f6b2e1c4d55"
    private var copied: String { "https://myapp.deeplinknow.com/products/9?ref=nl#dln=\(clickId)" }

    override func setUp() async throws {
        try await super.setUp()
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        clearCapturedRequests()
    }

    private var lookups: [StubURLProtocol.Captured] { StubURLProtocol.requests(to: "referrer-lookup") }
    private var matchRequests: Int { StubURLProtocol.requests(to: "match").count }

    // MARK: SDK-93

    func test_SDK_93_claim200DeliversTheClipboardLinkWithServerFields() async throws {
        // SDK-93 / IOS-35
        fakePasteboard.content = copied
        StubURLProtocol.stub("referrer-lookup", json: Fixtures.referrerLookupOK)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let linkResult = await DeepLinkNow.checkDeferredDeepLink()
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(link.confidenceScore, 100)
        XCTAssertEqual(link.matchQuality, .high)
        XCTAssertEqual(link.deeplinkId, "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00")
        XCTAssertEqual(link.targetUrl, "products/9?ref=nl")
        XCTAssertEqual(link.campaignId, "3e0b8a51-1c7d-4a2e-b6f9-0d5c4e3b2a19")
        XCTAssertEqual(link.metadata?["source"]?.value as? String, "newsletter")
        XCTAssertEqual(link.matchedAt, "2026-10-18T09:20:00.000Z")
        XCTAssertEqual(link.expiresAt, "2026-10-18T10:20:00.000Z")
        // Routing fields come from the copied URL; the fragment is gone (SDK-92).
        XCTAssertEqual(link.path, "/products/9")
        XCTAssertEqual(link.fullPath, "/products/9?ref=nl")
        XCTAssertEqual(link.url, "https://myapp.deeplinknow.com/products/9?ref=nl")
        XCTAssertNil(link.matchDetails)
        XCTAssertEqual(matchRequests, 0, "a claimed clipboard hit does not call /match")
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))

        let request = try XCTUnwrap(lookups.first?.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Self.apiKey)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "fp_id" })?.value, clickId)
        XCTAssertEqual(items.first(where: { $0.name == "source" })?.value, "clipboard")
        // SDK-93 / IOS-35: the same device id as /init and /match.
        let idfv = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        XCTAssertEqual(items.first(where: { $0.name == "device_id" })?.value, idfv)
        XCTAssertFalse(request.url!.absoluteString.contains(Self.apiKey), "SDK-63: the key is never in the URL")
    }

    func test_SDK_93_claim404SkipsTheStaleLinkAndContinuesToMatch() async throws {
        // SDK-93 / IOS-35: unknown or already claimed → stale → /match.
        fakePasteboard.content = copied
        StubURLProtocol.stub("referrer-lookup", status: 404, json: #"{"success":false,"message":"Fingerprint not found"}"#)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let linkResult = await DeepLinkNow.checkDeferredDeepLink()
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.source, .fingerprint)
        XCTAssertEqual(matchRequests, 1)
        XCTAssertEqual(lookups.count, 1, "404 is not retried (SDK-53)")
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.clipboardCheckedKey), "the pasteboard is not read again (IOS-27)")
    }

    func test_SDK_93_claim410SkipsTheStaleLinkAndContinuesToMatch() async throws {
        // SDK-93: expired past the claim window → stale → /match; an empty /match is definitive.
        fakePasteboard.content = copied
        StubURLProtocol.stub("referrer-lookup", status: 410, json: #"{"success":false,"message":"Fingerprint has expired"}"#)
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let link = await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertNil(link)
        XCTAssertEqual(matchRequests, 1)
        XCTAssertEqual(lookups.count, 1)
        XCTAssertTrue(defaults.bool(forKey: DeepLinkNow.deferredCompletedKey))
    }

    func test_IOS_35_aClaimedClipboardLinkIsDeliveredWhateverItsAge() async throws {
        // IOS-35 ("trust the clipboard", owner 2026-10-25): the SDK has no age check of its own.
        // A 200 for a click days old, whose 1-hour fingerprint window ended long ago, is delivered.
        fakePasteboard.content = copied
        let old = Fixtures.referrerLookupOK
            .replacingOccurrences(of: "2026-10-18T09:20:00.000Z", with: "2026-09-28T09:20:00.000Z")
            .replacingOccurrences(of: "2026-10-18T10:20:00.000Z", with: "2026-09-28T10:20:00.000Z")
        StubURLProtocol.stub("referrer-lookup", json: old)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let linkResult = await DeepLinkNow.checkDeferredDeepLink()
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(link.deeplinkId, "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00")
        XCTAssertEqual(link.expiresAt, "2026-09-28T10:20:00.000Z")
        XCTAssertEqual(matchRequests, 0, "the clipboard link beats any fingerprint candidate")
    }

    func test_SDK_93_networkErrorDeliversTheLocallyParsedLink() async throws {
        // SDK-93 / IOS-35: fail open.
        fakePasteboard.content = copied
        StubURLProtocol.stub("referrer-lookup", error: URLError(.notConnectedToInternet))
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let linkResult = await DeepLinkNow.checkDeferredDeepLink()
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(link.path, "/products/9")
        XCTAssertEqual(link.url, "https://myapp.deeplinknow.com/products/9?ref=nl")
        XCTAssertNil(link.deeplinkId)
        XCTAssertEqual(matchRequests, 0)
        XCTAssertNil(DeepLinkNow.lastError, "a failed claim is not a failed check")
    }

    func test_SDK_93_timeoutAndServerErrorsAlsoFailOpen() async throws {
        // SDK-93: timeout, 5xx and an unexpected body all deliver the copied link.
        let failures: [(String, () -> Void)] = [
            ("timeout", { StubURLProtocol.stub("referrer-lookup", error: URLError(.timedOut)) }),
            ("500", { StubURLProtocol.stub("referrer-lookup", status: 500, json: Fixtures.errorInternal) }),
            ("test key body", { StubURLProtocol.stub("referrer-lookup", json: Fixtures.testKeyDefault) }),
        ]
        for (name, stub) in failures {
            StubURLProtocol.reset()
            stub()
            fakePasteboard.content = copied
            let link = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(force: true))
            XCTAssertEqual(link?.source, .clipboard, name)
            XCTAssertNil(link?.deeplinkId, name)
            XCTAssertEqual(matchRequests, 0, name)
        }
    }

    func test_SDK_93_withoutTheFragmentNothingChanges() async throws {
        // SDK-93: no `#dln=` → no claim request, today's behaviour.
        fakePasteboard.content = "https://myapp.deeplinknow.com/products/9?ref=nl"
        let linkResult = await DeepLinkNow.checkDeferredDeepLink()
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertNil(link.deeplinkId)
        XCTAssertTrue(lookups.isEmpty)
        XCTAssertEqual(matchRequests, 0)
    }

    func test_SDK_93_claimedLinkReachesTheHandler() async throws {
        // SDK-93 + SDK-86: onLink gets the claimed clipboard link as `.deferred`.
        fakePasteboard.content = copied
        StubURLProtocol.stub("referrer-lookup", json: Fixtures.referrerLookupOK)
        let recorder = LinkRecorder()
        DeepLinkNow.onLink { recorder.append($0) }
        let linkResult = await recorder.wait(for: 1).first
        let link = try XCTUnwrap(linkResult)
        XCTAssertEqual(link.type, .deferred)
        XCTAssertEqual(link.source, .clipboard)
        XCTAssertEqual(link.deeplinkId, "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00")
    }

    // MARK: SDK-92 fragment stripping

    func test_SDK_92_parsingStripsTheDlnFragmentParameter() throws {
        // SDK-92: the fragment never changes path or query; `url` loses the `dln` parameter.
        let parsed = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: copied)!))
        XCTAssertEqual(parsed.url, "https://myapp.deeplinknow.com/products/9?ref=nl")
        XCTAssertEqual(parsed.fullPath, "/products/9?ref=nl")
        XCTAssertEqual(parsed.path, "/products/9")
        XCTAssertEqual(parsed.queryParams, ["ref": .string("nl")])

        let other = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/p#tab=2&dln=\(clickId)")!))
        XCTAssertEqual(other.url, "https://myapp.deeplinknow.com/p#tab=2", "other fragment content is kept")

        let first = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/p#dln=\(clickId)&tab=2")!))
        XCTAssertEqual(first.url, "https://myapp.deeplinknow.com/p#tab=2")

        let plain = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/p#section")!))
        XCTAssertEqual(plain.url, "https://myapp.deeplinknow.com/p#section", "a fragment without `dln` is untouched")

        let empty = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/p?q=1#dln=")!))
        XCTAssertEqual(empty.url, "https://myapp.deeplinknow.com/p?q=1")
        XCTAssertEqual(empty.fullPath, "/p?q=1")

        // A `dln` query parameter is part of the link, not the handoff.
        let query = try XCTUnwrap(DeepLinkNow.parseLink(URL(string: "https://myapp.deeplinknow.com/p?dln=1")!))
        XCTAssertEqual(query.queryParams, ["dln": .string("1")])
        XCTAssertEqual(query.url, "https://myapp.deeplinknow.com/p?dln=1")
    }

    func test_SDK_92_clickIdIsReadFromTheFragment() {
        // SDK-92 (internal): the id the claim uses.
        XCTAssertEqual(LinkParsing.stripClickIdFragment("https://a.deeplinknow.com/p#dln=abc").clickId, "abc")
        XCTAssertEqual(LinkParsing.stripClickIdFragment("https://a.deeplinknow.com/p#x=1&dln=abc").clickId, "abc")
        XCTAssertNil(LinkParsing.stripClickIdFragment("https://a.deeplinknow.com/p#dln=").clickId)
        XCTAssertNil(LinkParsing.stripClickIdFragment("https://a.deeplinknow.com/p#dlnx=abc").clickId)
        XCTAssertNil(LinkParsing.stripClickIdFragment("https://a.deeplinknow.com/p?dln=abc").clickId)
    }

    func test_SDK_92_checkClipboardAndHandleReturnTheStrippedURL() async throws {
        // SDK-92: every parse path strips it.
        fakePasteboard.content = copied
        XCTAssertEqual(DeepLinkNow.checkClipboard(), "https://myapp.deeplinknow.com/products/9?ref=nl")

        let recorder = LinkRecorder()
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        DeepLinkNow.onLink(options: DLNLinkOptions(useClipboard: false)) { recorder.append($0) }
        XCTAssertTrue(DeepLinkNow.handle(URL(string: copied)!))
        let awaited = await recorder.wait(for: 1).first?.url
        XCTAssertEqual(awaited, "https://myapp.deeplinknow.com/products/9?ref=nl")
        XCTAssertTrue(lookups.isEmpty, "a direct open never claims")
    }
}
