import XCTest
@testable import DeepLinkNow

/// `findDeferredUser()` against web/app/api/v1/sdk/match/route.ts
/// (RequestSchema / FingerprintSchema for the payload, ResponseSchema for decoding).
final class FindDeferredUserContractTests: DLNTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await initializeSDK()
        clearCapturedRequests()
    }

    private func sentFingerprint() throws -> [String: Any] {
        let captured = try XCTUnwrap(StubURLProtocol.requests(to: "match").last, "no /match request was sent")
        let json = try XCTUnwrap(captured.json, "match body is not a JSON object")
        return try XCTUnwrap(json["fingerprint"] as? [String: Any], "body.fingerprint missing")
    }

    // MARK: Request contract

    func testMatchRequestMethodPathAndHeaders() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()

        let request = try XCTUnwrap(StubURLProtocol.requests(to: "match").first?.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://deeplinknow.com/api/v1/sdk/match")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Self.apiKey)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // SDK-21
    func testFingerprintContainsAllFieldsRequiredByServerSchema() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()
        let fp = try sentFingerprint()

        // z.string() — required, non-null
        for key in ["user_agent", "os_version", "device_model", "language", "timezone"] {
            XCTAssertNotNil(fp[key] as? String, "\(key) must be a string")
            XCTAssertFalse((fp[key] as? String ?? "").isEmpty, "\(key) must not be empty")
        }
        // z.enum(['ios','android'])
        XCTAssertEqual(fp["platform"] as? String, "ios")
        // z.string().nullable() — key must be present (null or string). Missing key = zod 400.
        for key in ["device_id", "advertising_id", "vendor_id", "hardware_fingerprint"] {
            XCTAssertTrue(fp.keys.contains(key), "\(key) must be present (nullable, not optional)")
            XCTAssertTrue(fp[key] is String || fp[key] is NSNull, "\(key) must be string or null")
        }
        // No snake/camel drift: none of the Swift property names should leak.
        for camel in ["userAgent", "osVersion", "deviceModel", "installedAt", "lastOpenedAt",
                      "deviceId", "advertisingId", "vendorId", "hardwareFingerprint", "ipAddress"] {
            XCTAssertNil(fp[camel], "camelCase key \(camel) leaked into payload")
        }
    }

    func testTimestampsMatchZodDatetime() async throws {
        // z.string().datetime() with default options only accepts UTC "Z" timestamps,
        // e.g. 2024-03-20T10:30:00Z or 2024-03-20T10:30:00.123Z (no offsets like +01:00).
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()
        let fp = try sentFingerprint()
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$"#
        for key in ["installed_at", "last_opened_at"] {
            let value = try XCTUnwrap(fp[key] as? String, "\(key) missing")
            XCTAssertNotNil(value.range(of: pattern, options: .regularExpression), "\(key)=\(value) is not a zod datetime")
        }
    }

    // IOS-21 / SDK-22
    func testScreenDimensionsSentAtTopLevelAsNumbers() async throws {
        // Fallback matching (no IP match) uses screensMatch() on top-level screen_width/height/pixel_ratio.
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()
        let fp = try sentFingerprint()

        let width = try XCTUnwrap(fp["screen_width"] as? NSNumber)
        let height = try XCTUnwrap(fp["screen_height"] as? NSNumber)
        let ratio = try XCTUnwrap(fp["pixel_ratio"] as? NSNumber)
        XCTAssertEqual(width.intValue, Int(UIScreen.main.bounds.width), "logical (CSS) pixels expected")
        XCTAssertEqual(height.intValue, Int(UIScreen.main.bounds.height))
        XCTAssertEqual(ratio.doubleValue, Double(UIScreen.main.scale), accuracy: 0.01)
    }

    func testMetadataFieldsAreValidForServerSchema() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()
        let fp = try sentFingerprint()
        let metadata = try XCTUnwrap(fp["metadata"] as? [String: Any])

        // z.number().optional() — absent is fine, null is a 400.
        for key in ["screen_width", "screen_height", "pixel_ratio", "color_depth", "cpu_cores", "device_memory"] {
            if let value = metadata[key] {
                XCTAssertTrue(value is NSNumber && !(value is NSNull), "metadata.\(key) must be a number when present, got \(value)")
            }
        }
        if let isTablet = metadata["is_tablet"] { XCTAssertTrue(isTablet is NSNumber) }
        XCTAssertEqual(metadata["source"] as? String, "mobile")
    }

    func testDeviceModelUsesWebDeviceClass() async throws {
        // Server fallback query filters .eq('device_model', deviceClass(...)) which is "iPhone"/"iPad".
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.findDeferredUser()
        let fp = try sentFingerprint()
        XCTAssertTrue(["iPhone", "iPad"].contains(fp["device_model"] as? String ?? ""))
    }

    // MARK: Response decoding

    func testZeroMatches() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertTrue(response.matches.isEmpty)
        XCTAssertEqual(response.ttlSeconds, 3600)
    }

    func testSingleServerShapedMatchDecodes() async throws {
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched, "server-shaped match response failed to decode")

        XCTAssertEqual(response.ttlSeconds, 3600)
        let match = try XCTUnwrap(response.matches.first)
        XCTAssertEqual(match.confidenceScore, 87)
        XCTAssertTrue(match.matchDetails.ipMatch.matched)
        XCTAssertEqual(match.matchDetails.ipMatch.score, 40)
        XCTAssertEqual(match.matchDetails.timeProximity.score, 19.986118876, accuracy: 1e-9)
        XCTAssertEqual(match.matchDetails.timeProximity.timeDifferenceMinutes, 2)
        XCTAssertFalse(match.matchDetails.deviceMatch.components.hardwareFingerprint)
        XCTAssertTrue(match.matchDetails.localeMatch.components.language)
        XCTAssertFalse(match.matchDetails.localeMatch.components.timezone)

        let deeplink = try XCTUnwrap(match.deeplink)
        XCTAssertEqual(deeplink.id, "3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f")
        XCTAssertEqual(deeplink.targetUrl, "/promo?code=SAVE20&debug")
        XCTAssertNil(deeplink.campaignId, "server omits campaign_id when unset")
        XCTAssertEqual(deeplink.metadata["source"]?.value as? String, "newsletter")
        XCTAssertTrue(deeplink.metadata["nullable"]?.value is NSNull)
        XCTAssertFalse(deeplink.matchedAt.isEmpty)
        XCTAssertFalse(deeplink.expiresAt.isEmpty)
    }

    func testDeeplinkExposesQueryParamsAndFullPath() async throws {
        // IOS-16 / SDK-20. Was a CONTRACT MISMATCH: the server returns deeplink.query_params and deeplink.full_path
        // (the preserved deferred context, e.g. {code: "SAVE20", debug: true}), but
        // DeeplinkMatch has no such properties, so they are silently dropped during decoding.
        // Round-tripping through the SDK's own Codable model shows what survives.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        let deeplink = try XCTUnwrap(response.matches.first?.deeplink)

        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(deeplink)) as? [String: Any]
        XCTAssertNotNil(reencoded?["query_params"], "deeplink.query_params is dropped by the SDK model")
        XCTAssertNotNil(reencoded?["full_path"], "deeplink.full_path is dropped by the SDK model")
    }

    func testMatchWithoutDeeplinkDecodes() async throws {
        // ResponseSchema: deeplink is .optional() and JSON.stringify omits undefined keys.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(includeDeeplink: false)]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertEqual(response.matches.count, 1)
        XCTAssertNil(response.matches[0].deeplink)
    }

    func testDeeplinkWithoutOptionalFieldsDecodes() async throws {
        // Older fingerprints: no query_params / full_path keys at all.
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(extraDeeplinkFields: "")]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertNotNil(response.matches.first?.deeplink)
    }

    func testCampaignIdDecodesWhenPresent() async throws {
        let json = Fixtures.match(extraDeeplinkFields: #""campaign_id": "0d7c7e1a-9a1b-4b6f-8f7e-1c2d3e4f5a6b","#)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([json]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertEqual(response.matches.first?.deeplink?.campaignId, "0d7c7e1a-9a1b-4b6f-8f7e-1c2d3e4f5a6b")
    }

    // SDK-20
    func testManyMatchesPreserveServerOrder() async throws {
        let matches = [
            Fixtures.match(id: "00000000-0000-4000-8000-000000000001", confidence: 92, quality: "HIGH"),
            Fixtures.match(id: "00000000-0000-4000-8000-000000000002", confidence: 61, quality: "MEDIUM"),
            Fixtures.match(id: "00000000-0000-4000-8000-000000000003", confidence: 31, quality: "LOW"),
        ]
        StubURLProtocol.stub("match", json: Fixtures.matchResponse(matches))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertEqual(response.matches.map { $0.confidenceScore }, [92, 61, 31])
        XCTAssertEqual(response.matches.map { $0.deeplink?.id ?? "" },
                       ["00000000-0000-4000-8000-000000000001",
                        "00000000-0000-4000-8000-000000000002",
                        "00000000-0000-4000-8000-000000000003"])
        XCTAssertEqual(Set(response.matches.map { $0.id }).count, 3, "Identifiable ids must be unique")
    }

    func testClientDoesNotFilterOrReorder() async throws {
        // Documents current behaviour: expiry (1h TTL) and the 30% confidence floor are enforced
        // server-side only. The SDK returns exactly what the server sent, including an already
        // expired match (e.g. a delayed/replayed response). Consumers must check expiresAt.
        let expired = Fixtures.match(id: "00000000-0000-4000-8000-0000000000ee",
                                     expiresAt: Date().addingTimeInterval(-60))
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([expired]))
        let fetched = await DeepLinkNow.findDeferredUser()
        let response = try XCTUnwrap(fetched)
        XCTAssertEqual(response.matches.count, 1)
    }

    // IOS-17
    func testFractionalTimeDifferenceDecodes() async throws {
        // Defensive: time_difference_minutes is z.number(); the scorer uses Math.ceil today so it is
        // an integer, but other numeric fields are floats. Ensure integral floats like 3.0 decode.
        let json = Fixtures.match().replacingOccurrences(of: #""time_difference_minutes": 2"#,
                                                          with: #""time_difference_minutes": 3.0"#)
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([json]))
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertEqual(response?.matches.first?.matchDetails.timeProximity.timeDifferenceMinutes, 3)
    }

    // MARK: Failure handling — always nil, never a crash (SDK-50 / SDK-51)

    func testMalformedJSONReturnsNil() async {
        StubURLProtocol.stub("match", json: #"{"matches": [ {"confidence_score": 87, "#)
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(response)
    }

    func testWrongShapeReturnsNil() async {
        // Legacy/alternate shape { match: {...} } is not what the server returns.
        StubURLProtocol.stub("match", json: #"{"match": {"confidence_score": 95}, "ttl_seconds": 3600}"#)
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(response)
    }

    func testTestKeyDefaultBodyReturnsNil() async {
        StubURLProtocol.stub("match", json: Fixtures.testKeyDefault)
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(response)
    }

    func testHTTPErrorsReturnNil() async {
        for (status, body) in [(400, Fixtures.errorZod), (401, Fixtures.errorInvalidKey),
                               (403, Fixtures.errorAccountInactive), (429, Fixtures.errorRateLimited),
                               (500, Fixtures.errorInternal), (502, "<html>Bad Gateway</html>")] {
            StubURLProtocol.reset()
            StubURLProtocol.stub("match", status: status, json: body)
            let response = await DeepLinkNow.findDeferredUser()
            XCTAssertNil(response, "HTTP \(status) should yield nil")
        }
    }

    func testTransportErrorReturnsNil() async {
        StubURLProtocol.stub("match", error: URLError(.timedOut))
        let response = await DeepLinkNow.findDeferredUser()
        XCTAssertNil(response)
    }
}
