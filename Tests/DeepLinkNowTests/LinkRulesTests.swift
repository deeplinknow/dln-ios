import XCTest
@testable import DeepLinkNow

/// Host rule, parseLink / parseDeepLink and createDeepLink (SDK-30…38, IOS-26, IOS-28, IOS-29, IOS-31).
final class LinkRulesTests: DLNTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        clearCapturedRequests()
    }

    private func link(_ string: String) -> DLNParsedLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLinkNow.parseLink(url)
    }

    // MARK: SDK-30

    func test_SDK_30_parseIsSynchronousAndSideEffectFree() throws {
        // SDK-30: no network, no clipboard; returns path, queryParams, fullPath, url.
        let parsed = try XCTUnwrap(link("https://myapp.deeplinknow.com/products/123?ref=nl"))
        XCTAssertEqual(parsed.path, "/products/123")
        XCTAssertEqual(parsed.queryParams, ["ref": .string("nl")])
        XCTAssertEqual(parsed.fullPath, "/products/123?ref=nl")
        XCTAssertEqual(parsed.url, "https://myapp.deeplinknow.com/products/123?ref=nl")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(fakePasteboard.reads, 0)
    }

    // MARK: SDK-31 / SDK-33 / SDK-38 / IOS-28 host rule

    func test_SDK_31_exactHostAfterInitCaseInsensitivePortAndTrailingDot() {
        // SDK-31 / FLOW-41: after init only the app's alias subdomain or verified custom domain
        // (exact, case-insensitive); path per FLOW-52, params per FLOW-53 (see SDK-34/35 tests).
        XCTAssertNotNil(link("https://myapp.deeplinknow.com/a"))
        XCTAssertNotNil(link("https://MYAPP.DEEPLINKNOW.COM/a"))
        XCTAssertNotNil(link("https://links.myapp.com/a"))
        XCTAssertNotNil(link("https://Links.MyApp.com:8443/a"))
        XCTAssertNotNil(link("https://myapp.deeplinknow.com./a"))
        XCTAssertNil(link("https://otherapp.deeplinknow.com/a"))
        XCTAssertNil(link("https://deeplinknow.com/a"))
        XCTAssertNil(link("https://www.deeplinknow.com/a"))
        XCTAssertNil(link("https://api.deeplinknow.com/a"))
        XCTAssertNil(link("https://myapp.deeplink.now/a"))
        XCTAssertNil(link("https://deeplink.now/a"))
    }

    func test_IOS_28_deeplinkNowIsNeverTrusted() {
        // IOS-28: {alias}.deeplink.now is not added to the trusted domains.
        XCTAssertFalse(DeepLinkNow.isValidDomain("myapp.deeplink.now"))
        XCTAssertFalse(DeepLinkNow.appInfo?.linkDomains.contains { $0.hasSuffix("deeplink.now") } ?? true)
    }

    func test_SDK_32_onlyHttpAndHttpsSchemes() {
        // SDK-32
        XCTAssertNotNil(link("http://myapp.deeplinknow.com/a"))
        XCTAssertNil(link("deeplinknow://myapp.deeplinknow.com/a"))
        XCTAssertNil(link("myapp://promo"))
        XCTAssertNil(link("mailto:hi@myapp.deeplinknow.com"))
        XCTAssertNil(link("/promo?code=1"))
        XCTAssertNil(link("myapp.deeplinknow.com/promo"))
    }

    func test_SDK_33_lookalikesRejectedByParsedHost() {
        // SDK-33
        for bad in [
            "https://deeplinknow.com.evil.com/",
            "https://evil-deeplinknow.com/",
            "https://evildeeplinknow.com/",
            "https://evil.com/?u=x.deeplinknow.com",
            "https://evil.com#a.deeplinknow.com",
            "https://a.deeplinknow.com@evil.com/",
            "https://go.myapp.com.evil.com/",
            "https://links.myapp.com.evil.com/",
            "https://myapp.deeplink.now/",
            "https://otherapp.deeplinknow.com/",
        ] {
            XCTAssertNil(link(bad), bad)
            if let host = URLComponents(string: bad)?.host {
                XCTAssertFalse(DeepLinkNow.isValidDomain(host), host)
            }
        }
    }

    func test_SDK_38_isValidDomainAppliesTheSameRule() {
        // SDK-38
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("MyApp.DeepLinkNow.com"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com:443"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com."))
        XCTAssertFalse(DeepLinkNow.isValidDomain("otherapp.deeplinknow.com"))
        XCTAssertFalse(DeepLinkNow.isValidDomain(""))
    }

    // MARK: SDK-34 / SDK-36 path and fullPath

    func test_SDK_34_pathUndecodedTrailingSlashKeptFragmentDropped() throws {
        // SDK-34
        XCTAssertEqual(link("https://myapp.deeplinknow.com/a%20b/c%2Fd")?.path, "/a%20b/c%2Fd")
        XCTAssertEqual(link("https://myapp.deeplinknow.com/promo/")?.path, "/promo/")
        XCTAssertEqual(link("https://myapp.deeplinknow.com")?.path, "/")
        XCTAssertEqual(link("https://myapp.deeplinknow.com/")?.path, "/")
        let withFragment = try XCTUnwrap(link("https://myapp.deeplinknow.com/docs?tab=a#frag"))
        XCTAssertEqual(withFragment.path, "/docs")
        XCTAssertEqual(withFragment.fullPath, "/docs?tab=a")
        XCTAssertEqual(withFragment.queryParams, ["tab": .string("a")])
    }

    func test_SDK_36_fullPathExactlyAsInURL() throws {
        // SDK-36: no decoding, no re-encoding, no reordering, "+" kept.
        let parsed = try XCTUnwrap(link("https://myapp.deeplinknow.com/p%C3%A9?z=1&a=SAVE+20&e=%26&flag"))
        XCTAssertEqual(parsed.fullPath, "/p%C3%A9?z=1&a=SAVE+20&e=%26&flag")
        XCTAssertEqual(link("https://myapp.deeplinknow.com")?.fullPath, "/")
    }

    func test_SDK_36_malformedInputReturnsNilWithoutCrashing() {
        // SDK-36 / IOS-12
        XCTAssertNil(link("https://"))
        XCTAssertNil(link("https:///promo"))
        XCTAssertNil(DeepLinkNow.parseDeepLink(URL(string: "about:blank")!))
        XCTAssertNil(DeepLinkNow.parseDeepLink(URL(fileURLWithPath: "/tmp/x")))
    }

    // MARK: SDK-35 query semantics

    func test_SDK_35_queryParamsFollowURLSearchParams() throws {
        // SDK-35 / FLOW-53
        let parsed = try XCTUnwrap(link("https://myapp.deeplinknow.com/p?code=SAVE+20&name=Jo%C3%A9&flag&empty=&tag=a&tag=b&tag=c&Case=1&case=2"))
        XCTAssertEqual(parsed.queryParams["code"], .string("SAVE 20"))
        XCTAssertEqual(parsed.queryParams["name"], .string("Joé"))
        XCTAssertEqual(parsed.queryParams["flag"], .flag)
        XCTAssertEqual(parsed.queryParams["empty"], .flag)
        XCTAssertEqual(parsed.queryParams["tag"], .list(["a", "b", "c"]))
        XCTAssertEqual(parsed.queryParams["Case"], .string("1"))
        XCTAssertEqual(parsed.queryParams["case"], .string("2"))
        XCTAssertEqual(parsed.queryParams.count, 7)
        // Invalid escapes are kept literally (URL(string:) would re-encode them, so test the parser directly).
        XCTAssertEqual(LinkParsing.parseQuery("bad=%ZZ&ok=%41").0, ["bad": .string("%ZZ"), "ok": .string("A")])
    }

    func test_SDK_35_keysKeepFirstAppearanceOrder() {
        // SDK-35
        let (_, order) = LinkParsing.parseQuery("b=1&a=2&b=3&c")
        XCTAssertEqual(order, ["b", "a", "c"])
    }

    func test_SDK_35_legacyTupleCarriesTheSameValues() throws {
        // SDK-35 via the tuple API: String, true, [String].
        let tuple = try XCTUnwrap(DeepLinkNow.parseDeepLink(URL(string: "https://myapp.deeplinknow.com/p?a=1&f&t=x&t=y")!))
        XCTAssertEqual(tuple.parameters["a"] as? String, "1")
        XCTAssertEqual(tuple.parameters["f"] as? Bool, true)
        XCTAssertEqual(tuple.parameters["t"] as? [String], ["x", "y"])
    }

    func test_SDK_35_queryValueCodableMatchesWireShape() throws {
        // SDK-35: string | true | string[]
        let json = #"{"a":"x","b":true,"c":["1","2"]}"#
        let decoded = try JSONDecoder().decode([String: DLNQueryValue].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, ["a": .string("x"), "b": .flag, "c": .list(["1", "2"])])
        let reencoded = try JSONDecoder().decode([String: DLNQueryValue].self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reencoded, decoded)
    }

    // MARK: IOS-29 createDeepLink

    func test_IOS_29_createDeepLinkIsHttpsOnPrimaryDomainAndRoundTrips() throws {
        // IOS-29 / SDK-18: primary domain = first verified custom domain.
        let params = DLNCustomParameters(["code": "SAVE 20", "plus": "a+b", "amp": "x&y=z", "emoji": "😀"])
        let url = try XCTUnwrap(DeepLinkNow.createDeepLink(path: "/promo/summer", customParameters: params))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "links.myapp.com")
        let parsed = try XCTUnwrap(DeepLinkNow.parseLink(url))
        XCTAssertEqual(parsed.path, "/promo/summer")
        XCTAssertEqual(parsed.queryParams["code"], .string("SAVE 20"))
        XCTAssertEqual(parsed.queryParams["plus"], .string("a+b"))
        XCTAssertEqual(parsed.queryParams["amp"], .string("x&y=z"))
        XCTAssertEqual(parsed.queryParams["emoji"], .string("😀"))
    }

    func test_IOS_29_aliasDomainWhenNoCustomDomain() async throws {
        // IOS-29
        StubURLProtocol.reset()
        await initializeSDK(initJSON: Fixtures.initNoCustomDomain)
        let url = try XCTUnwrap(DeepLinkNow.createDeepLink(path: "promo"))
        XCTAssertEqual(url.absoluteString, "https://myapp.deeplinknow.com/promo")
    }

    // MARK: IOS-31

    @available(*, deprecated)
    func test_IOS_31_handleUniversalLinkBehavesAsParseLink() {
        // IOS-31: no public no-op. handleUniversalLink returns the parsed link; handleCustomScheme
        // is documented as unsupported (deprecated) and must not crash.
        let url = URL(string: "https://myapp.deeplinknow.com/promo?code=1")!
        XCTAssertEqual(DeepLinkNow.handleUniversalLink(url), DeepLinkNow.parseLink(url))
        XCTAssertNil(DeepLinkNow.handleUniversalLink(URL(string: "https://evil.com/")!))
        DeepLinkNow.handleCustomScheme(URL(string: "myapp://promo")!)
    }
}
