import XCTest
@testable import DeepLinkNow

/// Behaviour before `initialize` has ever been called (state is reset in DLNTestCase.setUp).
final class AAA_PreInitializationTests: DLNTestCase {

    @MainActor func testPublicAPIIsSafeBeforeInitialize() async throws {
        // SDK-04 / SDK-05: nothing initialized, no network.
        XCTAssertFalse(DeepLinkNow.isInitialized)
        let match = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(match)

        // SDK-37: provisional rule before init: a non-reserved {alias}.deeplinknow.com is accepted,
        // custom domains, the apex, reserved subdomains and deeplink.now are not.
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("links.myapp.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("www.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("myapp.deeplink.now"))
        XCTAssertEqual(DeepLinkNow.parseDeepLink(URL(string: "https://myapp.deeplinknow.com/promo")!)?.path, "/promo")
        XCTAssertNil(DeepLinkNow.createDeepLink(path: "/promo"), "IOS-29: nil before init")

        // Both return before touching UIPasteboard when uninitialized, so no paste prompt here.
        XCTAssertNil(DeepLinkNow.checkClipboard())
        XCTAssertFalse(DeepLinkNow.hasDeepLinkToken())
        XCTAssertEqual(fakePasteboard.reads, 0)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no network traffic before initialize")
    }

    func test_SDK_37_provisionalRuleBeforeInit() {
        // SDK-37
        XCTAssertTrue(DeepLinkNow.isValidDomain("MyApp.DeepLinkNow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("a.b.deeplinknow.com"))
        for reserved in ["www", "app", "api", "docs", "m", "mail"] {
            XCTAssertFalse(DeepLinkNow.isValidDomain("\(reserved).deeplinknow.com"), reserved)
        }
        XCTAssertFalse(DeepLinkNow.isValidDomain("go.myapp.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("x.deeplink.now"))
    }
}
