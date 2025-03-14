import XCTest
@testable import DeepLinkNow

final class DeepLinkNowTests: XCTestCase {
    var mockURLSession: MockURLSession!
    let testApiKey = "test_api_key"
    
    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession()
        URLProtocol.registerClass(MockURLProtocol.self)
    }
    
    override func tearDown() {
        mockURLSession = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async throws {
        // Setup mock response
        let mockResponse = """
        {
            "app": {
                "id": "test_app_id",
                "name": "Test App",
                "timezone": "UTC",
                "android_package_name": null,
                "android_sha256_cert": null,
                "ios_bundle_id": "com.test.app",
                "ios_app_store_id": "123456789",
                "ios_app_prefix": "test",
                "custom_domains": [
                    {
                        "domain": "test.com",
                        "verified": true
                    }
                ]
            },
            "account": {
                "status": "active",
                "credits_remaining": 1000,
                "rate_limits": {
                    "matches_per_second": 10,
                    "matches_per_day": 1000
                }
            }
        }
        """
        MockURLProtocol.mockData = mockResponse.data(using: .utf8)
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://deeplinknow.com/api/v1/sdk/init")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Test initialization
        await DeepLinkNow.initialize(apiKey: testApiKey)
        
        // Verify domain was added
        XCTAssertTrue(DeepLinkNow.isValidDomain("test.com"))
    }
    
    // MARK: - Fingerprint Tests
    
    func testFingerprintGeneration() async {
        await DeepLinkNow.initialize(apiKey: testApiKey)
        
        let fingerprint = await DeepLinkNow.findDeferredUser()?.match.fingerprint
        
        XCTAssertNotNil(fingerprint)
        XCTAssertTrue(fingerprint?.userAgent.contains("DLN-iOS/"))
        XCTAssertEqual(fingerprint?.platform, "ios")
        XCTAssertNotNil(fingerprint?.installedAt)
        XCTAssertNotNil(fingerprint?.lastOpenedAt)
        
        // Verify ISO8601 format with +00:00
        XCTAssertTrue(fingerprint?.installedAt.hasSuffix("+00:00") ?? false)
        XCTAssertTrue(fingerprint?.lastOpenedAt.hasSuffix("+00:00") ?? false)
    }
    
    // MARK: - Deep Link Tests
    
    func testValidDomainCheck() async {
        await DeepLinkNow.initialize(apiKey: testApiKey)
        
        XCTAssertTrue(DeepLinkNow.isValidDomain("deeplinknow.com"))
        XCTAssertTrue(DeepLinkNow.isValidDomain("deeplink.now"))
        XCTAssertFalse(DeepLinkNow.isValidDomain("invalid.com"))
    }
    
    func testDeepLinkParsing() async {
        await DeepLinkNow.initialize(apiKey: testApiKey)
        
        let url = "https://deeplinknow.com/test/path?param1=value1&param2=value2"
        let result = DeepLinkNow.parseDeepLink(URL(string: url)!)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/test/path")
        XCTAssertEqual(result?.parameters["param1"], "value1")
        XCTAssertEqual(result?.parameters["param2"], "value2")
    }
    
    // MARK: - Match Response Tests
    
    func testFindDeferredUser() async {
        // Setup mock response
        let mockResponse = """
        {
            "match": {
                "deeplink": {
                    "id": "test_id",
                    "target_url": "https://example.com",
                    "metadata": {
                        "campaign": "test_campaign"
                    },
                    "campaign_id": "campaign_123",
                    "matched_at": "2024-01-01T00:00:00+00:00",
                    "expires_at": "2024-01-02T00:00:00+00:00"
                },
                "confidence_score": 0.95,
                "ttl_seconds": 86400
            }
        }
        """
        MockURLProtocol.mockData = mockResponse.data(using: .utf8)
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://deeplinknow.com/api/v1/sdk/match")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let result = await DeepLinkNow.findDeferredUser()
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.match.deeplink?.id, "test_id")
        XCTAssertEqual(result?.match.deeplink?.targetUrl, "https://example.com")
        XCTAssertEqual(result?.match.confidenceScore, 0.95)
        XCTAssertEqual(result?.match.ttlSeconds, 86400)
    }
}

// MARK: - Mock Classes

class MockURLSession: URLSession {
    override func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        return (Data(), URLResponse())
    }
}

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        if let response = MockURLProtocol.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        
        if let data = MockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}
