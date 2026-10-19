import XCTest
import UIKit
@testable import DeepLinkNow

/// `checkClipboard()` / `hasDeepLinkToken()`.
/// The landing page (components/universal-links.tsx) copies `window.location.href`, i.e.
/// `https://<alias>.deeplinknow.com/...` or `https://<custom-domain>/...`.
final class ClipboardTests: DLNTestCase {

    private var savedPasteboard: [[String: Any]] = []

    override func setUp() async throws {
        try await super.setUp()
        try PasteboardSupport.requireReadablePasteboard()
        savedPasteboard = await PasteboardSupport.snapshot()
        useSystemPasteboard()
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
    }

    override func tearDown() async throws {
        let saved = savedPasteboard
        await PasteboardSupport.restore(saved)
        try await super.tearDown()
    }

    @MainActor private func setClipboard(_ value: String?) {
        if let value = value {
            UIPasteboard.general.string = value
        } else {
            UIPasteboard.general.items = []
        }
    }

    @MainActor private func check(_ value: String?) -> String? {
        setClipboard(value)
        return DeepLinkNow.checkClipboard()
    }

    // MARK: Accepted

    @MainActor func testAcceptsOwnAliasLink() {
        let link = "https://myapp.deeplinknow.com/promo?code=SAVE20"
        XCTAssertEqual(check(link), link)
    }

    @MainActor func testAcceptsVerifiedCustomDomainFromInitConfig() {
        let link = "https://links.myapp.com/promo?code=SAVE20"
        XCTAssertEqual(check(link), link)
    }

    @MainActor func testRejectsOtherDeepLinkNowSubdomainAfterInit() {
        // SDK-31 / SDK-33 (lead decision): after init only the app's own alias and verified
        // custom domains are trusted, not other tenants' *.deeplinknow.com subdomains.
        XCTAssertNil(check("https://another.deeplinknow.com/x"))
        XCTAssertNil(check("https://deeplinknow.com/x"))
        XCTAssertNil(check("https://myapp.deeplink.now/x"))
    }

    @MainActor func test_SDK_40_trimsWhitespaceAndRequiresASingleURL() {
        // SDK-40
        XCTAssertEqual(check("  https://myapp.deeplinknow.com/promo\n"), "https://myapp.deeplinknow.com/promo")
        XCTAssertNil(check("see https://myapp.deeplinknow.com/promo"))
        XCTAssertNil(check("https://myapp.deeplinknow.com/a https://myapp.deeplinknow.com/b"))
    }

    @MainActor func test_IOS_26_hostMatchedCaseInsensitively() {
        // IOS-26: parsed host + SDK-31 rule.
        XCTAssertEqual(check("https://MyApp.DeepLinkNow.com/promo"), "https://MyApp.DeepLinkNow.com/promo")
    }

    func test_IOS_27_checkDeferredDeepLinkUsesRealPasteboardOnce() async throws {
        // IOS-27 / SDK-12 on the real UIPasteboard (Catalyst).
        await MainActor.run { setClipboard("https://myapp.deeplinknow.com/products/9?ref=nl") }
        let link = await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertEqual(link?.source, .clipboard)
        XCTAssertEqual(link?.path, "/products/9")
        XCTAssertEqual(link?.queryParams["ref"], .string("nl"))
        XCTAssertTrue(StubURLProtocol.requests(to: "match").isEmpty, "a clipboard hit must not call /match")
    }

    // MARK: Rejected

    @MainActor func testRejectsEmptyClipboard() {
        XCTAssertNil(check(nil))
    }

    @MainActor func testRejectsPlainText() {
        XCTAssertNil(check("hello world"))
        XCTAssertNil(check(""))
        XCTAssertNil(check("deeplinknow is great"))
    }

    @MainActor func testRejectsForeignDomain() {
        XCTAssertNil(check("https://example.com/promo"))
    }

    @MainActor func testRejectsUnverifiedCustomDomain() async {
        await initializeSDK(initJSON: Fixtures.initUnverifiedCustomDomain)
        XCTAssertNil(check("https://pending.myapp.com/promo"))
    }

    @MainActor func testRejectsDomainOnlyInQueryOrPath() {
        XCTAssertNil(check("https://evil.com/?next=https://myapp.deeplinknow.com/promo"))
        XCTAssertNil(check("https://evil.com/myapp.deeplinknow.com"))
        XCTAssertNil(check("https://myapp.deeplinknow.com@evil.com/promo"))
    }

    @MainActor func test_FLOW_14_clipboardHostMustExactlyEqualAnAppDomain() {
        // FLOW-14: exact host (case-insensitive); lookalikes and other apps' subdomains rejected.
        XCTAssertEqual(check("https://MYAPP.deeplinknow.com/p"), "https://MYAPP.deeplinknow.com/p")
        XCTAssertNil(check("https://evil-deeplinknow.com/p"))
        XCTAssertNil(check("https://deeplinknow.com.evil.io/p"))
        XCTAssertNil(check("https://otherapp.deeplinknow.com/p"))
        XCTAssertNil(check("ftp://myapp.deeplinknow.com/p"))
    }

    @MainActor func testRejectsLookalikeHyphenPrefix() {
        // BUG (DeepLinkNow.swift checkClipboard: host.contains("deeplinknow.com")):
        // substring match accepts attacker-controlled hosts. Intended: host == "deeplinknow.com"
        // or host.hasSuffix(".deeplinknow.com"), or an exact match against validDomains.
        XCTAssertNil(check("https://evil-deeplinknow.com/promo"))
    }

    @MainActor func testRejectsLookalikeSuffixDomain() {
        // BUG: same substring match — "deeplinknow.com.evil.com" is evil.com's zone.
        XCTAssertNil(check("https://myapp.deeplinknow.com.evil.com/promo"))
    }

    @MainActor func testRejectsLookalikeDeeplinkNowTLD() {
        // BUG: host.contains("deeplink.now") also accepts e.g. "notdeeplink.now".
        XCTAssertNil(check("https://notdeeplink.now/promo"))
    }

    @MainActor func testRejectsCustomDomainLookalike() {
        // Custom domains use exact matching — this must stay rejected.
        XCTAssertNil(check("https://links.myapp.com.evil.com/promo"))
    }

    // MARK: hasDeepLinkToken

    @MainActor func testHasDeepLinkTokenForRealLink() {
        setClipboard("https://myapp.deeplinknow.com/promo")
        XCTAssertTrue(DeepLinkNow.hasDeepLinkToken())
    }

    @MainActor func testHasDeepLinkTokenFalseForEmptyClipboard() {
        setClipboard(nil)
        XCTAssertFalse(DeepLinkNow.hasDeepLinkToken())
    }

    @MainActor func test_IOS_25_hasDeepLinkTokenIsAHintNotAVerification() {
        // IOS-25 / SDK-41 (supersedes the first-pass substring test): hasDeepLinkToken() must not
        // read the content, so it cannot tell a DLN link from other text. `true` only means
        // "worth calling checkClipboard()"; checkClipboard() does the verification.
        setClipboard("https://evil.com/?ref=deeplinknow.com")
        XCTAssertTrue(DeepLinkNow.hasDeepLinkToken())
        XCTAssertNil(DeepLinkNow.checkClipboard())
    }
}
