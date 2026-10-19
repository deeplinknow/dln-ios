import XCTest
@testable import DeepLinkNow

/// Legacy smoke tests, updated to the current public API (`initialize(config:urlSession:)`,
/// `MatchResponse.matches`). The detailed contract tests live in the other files.
final class DeepLinkNowTests: DLNTestCase {

    // MARK: - Initialization

    func testInitialization() async throws {
        await initializeSDK(initJSON: Fixtures.initWithVerifiedCustomDomain)
        XCTAssertTrue(DeepLinkNow.isValidDomain("links.myapp.com"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("myapp.deeplinknow.com"))
    }

    // MARK: - Fingerprint / match

    func testFingerprintGeneration() async throws {
        await initializeSDK()
        let matchJSON = """
        {
            "matches": [{
                "confidence_score": 0.0,
                "match_details": {
                    "ip_match": { "matched": false, "score": 0.0 },
                    "device_match": {
                        "matched": true, "score": 1.0,
                        "components": { "platform": true, "os_version": true, "device_model": true, "hardware_fingerprint": false }
                    },
                    "time_proximity": { "score": 0.0, "time_difference_minutes": 0 },
                    "locale_match": {
                        "matched": true, "score": 1.0,
                        "components": { "language": true, "timezone": true }
                    }
                },
                "deeplink": null
            }],
            "ttl_seconds": 0
        }
        """
        StubURLProtocol.stub("match", json: matchJSON)

        let result = await DeepLinkNow.findDeferredUser()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.matches.count, 1)
        XCTAssertEqual(result?.matches[0].confidenceScore, 0.0)
        XCTAssertTrue(result?.matches[0].matchDetails.deviceMatch.components.deviceModel ?? false)
        XCTAssertNil(result?.matches[0].deeplink)
    }

    // MARK: - Parse

    func testParseDeepLink() async throws {
        await initializeSDK()
        let url = URL(string: "https://myapp.deeplinknow.com/test/path?param1=value1&param2=value2")!
        let result = DeepLinkNow.parseDeepLink(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/test/path")
        XCTAssertEqual(result?.parameters["param1"] as? String, "value1")
        XCTAssertEqual(result?.parameters["param2"] as? String, "value2")
    }

    // MARK: - Match response

    func testFindDeferredUser() async throws {
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([
            Fixtures.match(id: "test_id", confidence: 95, targetURL: "/promo"),
        ], ttl: 3600))

        let result = await DeepLinkNow.findDeferredUser()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.matches.first?.deeplink?.id, "test_id")
        XCTAssertEqual(result?.matches.first?.deeplink?.targetUrl, "/promo")
        XCTAssertEqual(result?.matches.first?.confidenceScore, 95)
        XCTAssertEqual(result?.ttlSeconds, 3600)
    }
}
