import XCTest
@testable import DeepLinkNow

final class DeepLinkNowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset shared instance before each test
        DeepLinkNow.initialize(apiKey: "test-api-key")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testInitialization() {
        // Test initialization with valid API key
        DeepLinkNow.initialize(apiKey: "valid-api-key")
        XCTAssertNotNil(DeepLinkNow.checkClipboard())
        
        // Test initialization with empty API key
        DeepLinkNow.initialize(apiKey: "")
        XCTAssertNotNil(DeepLinkNow.checkClipboard())
    }
    
    func testClipboardAccess() {
        // Set up test data in clipboard
        UIPasteboard.general.string = "deeplinknow://test/path"
        
        // Test clipboard reading
        let clipboardContent = DeepLinkNow.checkClipboard()
        XCTAssertNotNil(clipboardContent)
        XCTAssertEqual(clipboardContent, "deeplinknow://test/path")
        
        // Test empty clipboard
        UIPasteboard.general.string = ""
        XCTAssertEqual(DeepLinkNow.checkClipboard(), "")
        
        // Test nil clipboard
        UIPasteboard.general.string = nil
        XCTAssertNil(DeepLinkNow.checkClipboard())
    }
    
    func testAPIRequestFormatting() async {
        let config = DLNConfig(apiKey: "test-api-key")
        let dln = DeepLinkNow(config: config)
        
        do {
            // Test valid endpoint
            _ = try await dln.makeAPIRequest(endpoint: "test")
            
            // This will likely fail in real testing since we're not mocking the network call
            // You should mock the URLSession for proper testing
        } catch {
            XCTAssertTrue(error is DLNError)
        }
    }
    
    func testErrorHandling() async {
        let config = DLNConfig(apiKey: "test-api-key")
        let dln = DeepLinkNow(config: config)
        
        do {
            // Test invalid URL
            _ = try await dln.makeAPIRequest(endpoint: "")
            XCTFail("Should throw invalid URL error")
        } catch {
            XCTAssertEqual(error as? DLNError, .invalidURL)
        }
    }
}

// MARK: - Network Mocking Helper

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is unavailable.")
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

// MARK: - Network Testing Extension

extension DeepLinkNowTests {
    func testNetworkRequest() async {
        // Create a mock URL session configuration
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        // Set up the mock request handler
        let expectedData = "Response".data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expectedData)
        }
        
        // Test the request
        let dln = DeepLinkNow(config: DLNConfig(apiKey: "test-api-key"))
        
        do {
            let data = try await dln.makeAPIRequest(endpoint: "test")
            XCTAssertEqual(data, expectedData)
        } catch {
            XCTFail("Network request failed: \(error)")
        }
    }
}
