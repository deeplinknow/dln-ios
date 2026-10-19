import XCTest
@testable import DeepLinkNow

/// `parseDeepLink(_:)` — domain validation and path/query extraction.
/// Query handling is compared with how the web landing page builds `query_params`
/// for the deferred flow (components/universal-links.tsx uses URLSearchParams and maps
/// empty values to `true`), so that a direct universal link and a deferred match for the
/// same URL produce the same parameters.
final class ParseDeepLinkTests: DLNTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
    }

    private func parse(_ string: String) -> (path: String, parameters: [String: Any])? {
        DeepLinkNow.parseDeepLink(URL(string: string)!)
    }

    // MARK: Domain validation

    func testAcceptsAliasDomain() throws {
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/promo?code=SAVE20"))
        XCTAssertEqual(result.path, "/promo")
        XCTAssertEqual(result.parameters["code"] as? String, "SAVE20")
        XCTAssertEqual(result.parameters.count, 1)
    }

    func testAcceptsVerifiedCustomDomain() throws {
        let result = try XCTUnwrap(parse("https://links.myapp.com/products/42?ref=email"))
        XCTAssertEqual(result.path, "/products/42")
        XCTAssertEqual(result.parameters["ref"] as? String, "email")
    }

    func testRejectsForeignAndLookalikeDomains() {
        XCTAssertNil(parse("https://example.com/promo"))
        XCTAssertNil(parse("https://otherapp.deeplinknow.com/promo"))
        XCTAssertNil(parse("https://deeplinknow.com/promo"))
        XCTAssertNil(parse("https://evil-deeplinknow.com/promo"))
        XCTAssertNil(parse("https://myapp.deeplinknow.com.evil.com/promo"))
        XCTAssertNil(parse("https://links.myapp.com.evil.com/promo"))
        XCTAssertNil(parse("https://myapp.deeplinknow.com@evil.com/promo"))
    }

    func testRejectsUnverifiedCustomDomain() async {
        await initializeSDK(initJSON: Fixtures.initUnverifiedCustomDomain)
        XCTAssertNil(parse("https://pending.myapp.com/promo"))
    }

    func testHostMatchingIsCaseInsensitive() {
        // SDK-31. Was a BUG: validDomains.contains(components.host) is case-sensitive, but hostnames are not
        // (RFC 3986 §3.2.2). A link typed/shared as "MyApp.DeepLinkNow.com" opens the app via
        // Universal Links yet parseDeepLink returns nil.
        XCTAssertNotNil(parse("https://MyApp.DeepLinkNow.com/promo"))
    }

    func testPortDoesNotAffectHostValidation() {
        XCTAssertNotNil(parse("https://myapp.deeplinknow.com:443/promo"))
    }

    // MARK: Path extraction

    func testTrailingSlashPreserved() throws {
        XCTAssertEqual(try XCTUnwrap(parse("https://myapp.deeplinknow.com/promo/")).path, "/promo/")
    }

    func testRootPath() throws {
        // SDK-34: an empty path becomes "/".
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com"))
        XCTAssertEqual(result.path, "/")
        XCTAssertTrue(result.parameters.isEmpty)
    }

    func testPercentEncodedPathIsNotDecoded() throws {
        // SDK-34 / FLOW-52 (supersedes the first-pass "decoded" expectation): path is not decoded,
        // so a direct open and a deferred result for the same URL have the same path.
        XCTAssertEqual(try XCTUnwrap(parse("https://myapp.deeplinknow.com/products/caf%C3%A9")).path, "/products/caf%C3%A9")
    }

    func testFragmentIsNotPartOfPathOrParameters() throws {
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/docs/intro?tab=a#section-2"))
        XCTAssertEqual(result.path, "/docs/intro")
        XCTAssertEqual(result.parameters["tab"] as? String, "a")
        XCTAssertEqual(result.parameters.count, 1)
    }

    // MARK: Query extraction

    func testPercentEncodedQueryValuesAreDecoded() throws {
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/p?name=John%20Doe&amp=a%26b&emoji=%F0%9F%98%80&eq=a%3Db"))
        XCTAssertEqual(result.parameters["name"] as? String, "John Doe")
        XCTAssertEqual(result.parameters["amp"] as? String, "a&b")
        XCTAssertEqual(result.parameters["emoji"] as? String, "😀")
        XCTAssertEqual(result.parameters["eq"] as? String, "a=b")
    }

    func testRepeatedKeysBecomeAListLikeServer() throws {
        // SDK-35 / FLOW-53 (supersedes last-wins): repeated keys map to an array in order.
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/p?tag=a&tag=b"))
        XCTAssertEqual(result.parameters["tag"] as? [String], ["a", "b"])
    }

    func testPlusIsDecodedAsSpaceLikeServer() throws {
        // SDK-35. Was a MISMATCH: the web side parses the same URL with URLSearchParams, which decodes "+" as a
        // space, so the deferred match returns query_params.code == "SAVE 20" while a direct
        // universal link through parseDeepLink yields "SAVE+20". The two paths should agree.
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/p?code=SAVE+20"))
        XCTAssertEqual(result.parameters["code"] as? String, "SAVE 20")
    }

    func testValuelessFlagIsKept() throws {
        // MISMATCH: "?debug" (no "=") produces a URLQueryItem with a nil value, which parseDeepLink
        // discards. The web side stores it as `true` in query_params, so the deferred path keeps
        // the flag while the direct universal-link path loses it. ("?debug=" is kept as "".)
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/p?debug&code=X"))
        XCTAssertEqual(result.parameters["debug"] as? Bool, true, "SDK-35: valueless flag maps to true")
        XCTAssertEqual(result.parameters["code"] as? String, "X")
    }

    func testEmptyValueIsKept() throws {
        let result = try XCTUnwrap(parse("https://myapp.deeplinknow.com/p?empty="))
        XCTAssertEqual(result.parameters["empty"] as? Bool, true, "SDK-35: ?k= maps to true")
    }

    // MARK: createDeepLink round trip

    func testCreateDeepLinkOutputIsParseable() throws {
        // IOS-29. Was a BUG: createDeepLink builds "deeplinknow://app/<path>", whose host "app" is never in
        // validDomains, so the SDK cannot parse links it generated itself.
        let url = try XCTUnwrap(DeepLinkNow.createDeepLink(path: "/promo", customParameters: DLNCustomParameters(["code": "SAVE20"])))
        let result = DeepLinkNow.parseDeepLink(url)
        XCTAssertEqual(result?.path, "/promo")
        XCTAssertEqual(result?.parameters["code"] as? String, "SAVE20")
    }
}
