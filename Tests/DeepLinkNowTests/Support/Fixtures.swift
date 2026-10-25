import Foundation

/// JSON fixtures mirroring what the web server actually returns.
/// Sources:
///  - web/app/api/v1/sdk/init/route.ts   (InitResponseSchema + response construction)
///  - web/app/api/v1/sdk/match/route.ts  (ResponseSchema + deeplinkObject construction)
///  - web/utils/auth.ts / middleware.ts  (API key + rate limit error bodies)
enum Fixtures {

    // MARK: - /api/v1/sdk/init

    /// App with a verified custom domain. Note the server also sends
    /// `android_sha256_certificates` (array), which the SDK model does not declare.
    static let initWithVerifiedCustomDomain = """
    {
      "app": {
        "id": "8b0e7b0a-1c1d-4e4f-9a6b-2f6a0c9d1e11",
        "alias": "myapp",
        "name": "My App",
        "timezone": "America/New_York",
        "android_package_name": "com.myapp.android",
        "android_sha256_cert": "AA:BB:CC",
        "android_sha256_certificates": ["AA:BB:CC", "11:22:33"],
        "ios_bundle_id": "com.myapp.ios",
        "ios_app_store_id": "123456789",
        "ios_app_prefix": "ABCDE12345",
        "custom_domains": [{ "domain": "links.myapp.com", "verified": true }]
      },
      "account": {
        "status": "active",
        "credits_remaining": 1000,
        "rate_limits": { "matches_per_second": 1, "matches_per_day": 333 }
      }
    }
    """

    /// What the server sends when the app has NO custom domain: it still emits one
    /// entry with `domain: null, verified: false`, and nullable platform fields as null.
    static let initNoCustomDomain = """
    {
      "app": {
        "id": "8b0e7b0a-1c1d-4e4f-9a6b-2f6a0c9d1e11",
        "alias": "myapp",
        "name": "My App",
        "timezone": "UTC",
        "android_package_name": null,
        "android_sha256_cert": null,
        "android_sha256_certificates": [],
        "ios_bundle_id": null,
        "ios_app_store_id": null,
        "ios_app_prefix": null,
        "custom_domains": [{ "domain": null, "verified": false }]
      },
      "account": {
        "status": "active",
        "credits_remaining": 5,
        "rate_limits": { "matches_per_second": 1, "matches_per_day": 333 }
      }
    }
    """

    static let initUnverifiedCustomDomain = initWithVerifiedCustomDomain
        .replacingOccurrences(of: #"{ "domain": "links.myapp.com", "verified": true }"#,
                              with: #"{ "domain": "pending.myapp.com", "verified": false }"#)

    /// zod schema allows `verified: null`.
    static let initNullVerified = initWithVerifiedCustomDomain
        .replacingOccurrences(of: #"{ "domain": "links.myapp.com", "verified": true }"#,
                              with: #"{ "domain": "links.myapp.com", "verified": null }"#)

    // MARK: - Error bodies (utils/auth.ts, init/route.ts, match/route.ts)

    static let errorInvalidKey = #"{ "error": "Invalid API key" }"#
    static let errorAccountInactive = #"{ "error": "Account is not active", "status": "suspended" }"#
    static let errorNoCredits = #"{ "error": "No credits remaining" }"#
    static let errorRateLimited = #"{ "error": "Rate limit exceeded. Maximum 60 requests per minute." }"#
    static let errorZod = #"{ "error": "Invalid request data", "details": [{ "code": "invalid_type", "path": ["fingerprint", "platform"], "message": "Required" }] }"#
    static let errorInternal = #"{ "error": "Internal server error" }"#
    /// middleware.ts: test API key with no test_data row returns this with HTTP 200.
    static let testKeyDefault = #"{ "message": "Test API key default response", "path": "/api/v1/sdk/match", "method": "POST" }"#

    // MARK: - /api/v1/sdk/match

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date) // same shape as JS Date.toISOString()
    }

    /// One server-shaped match. Scores are produced by utils/scoring.ts:
    /// component scores are floats, confidence_score is Math.round(total),
    /// time_difference_minutes is Math.ceil(...) (integer).
    static func match(
        id: String = "3f1c2d4e-5a6b-4c7d-8e9f-0a1b2c3d4e5f",
        confidence: Int = 87,
        quality: String = "HIGH",
        targetURL: String = "/promo?code=SAVE20&debug",
        expiresAt: Date = Date().addingTimeInterval(3000),
        includeDeeplink: Bool = true,
        extraDeeplinkFields: String = #""query_params": { "code": "SAVE20", "debug": true }, "full_path": "/promo?code=SAVE20&debug","#
    ) -> String {
        let deeplink = includeDeeplink ? """
        ,
          "deeplink": {
            "id": "\(id)",
            "target_url": "\(targetURL)",
            "metadata": { "source": "newsletter", "nested": { "a": [1, 2.5, null, "x"] }, "nullable": null },
            \(extraDeeplinkFields)
            "matched_at": "\(iso(Date()))",
            "expires_at": "\(iso(expiresAt))"
          }
        """ : ""
        return """
        {
          "confidence_score": \(confidence),
          "match_quality": "\(quality)",
          "match_details": {
            "ip_match": { "matched": true, "score": 40 },
            "device_match": {
              "matched": true,
              "score": 24,
              "components": { "platform": true, "os_version": true, "device_model": true, "hardware_fingerprint": false }
            },
            "time_proximity": { "score": 19.986118876, "time_difference_minutes": 2 },
            "locale_match": {
              "matched": true,
              "score": 3.5,
              "components": { "language": true, "timezone": false }
            }
          }\(deeplink)
        }
        """
    }

    static func matchResponse(_ matches: [String], ttl: Int = 3600) -> String {
        """
        { "matches": [\(matches.joined(separator: ","))], "ttl_seconds": \(ttl) }
        """
    }

    static let matchEmpty = matchResponse([])

    // MARK: - /api/v1/sdk/referrer-lookup (§2.5, API-SDK-45) and /api/v1/sdk/resolve (§2.8, API-SDK-74)

    static let referrerLookupOK = """
    {
      "success": true,
      "deeplink": {
        "id": "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00",
        "target_url": "products/9?ref=nl",
        "metadata": { "source": "newsletter" },
        "campaign_id": "3e0b8a51-1c7d-4a2e-b6f9-0d5c4e3b2a19",
        "matched_at": "2026-10-18T09:20:00.000Z",
        "expires_at": "2026-10-18T10:20:00.000Z",
        "query_params": { "ref": "nl" },
        "full_path": "/products/9?ref=nl"
      }
    }
    """

    static let resolveOK = """
    {
      "deeplink": {
        "id": "b2a4f0c6-8d0e-4b4f-a7c1-6c9e3f2d1a00",
        "target_url": "https://yourapp.com/invite/8Fk2",
        "metadata": { "fdl": { "short_link": "https://links.yourapp.com/abc123" } },
        "campaign_id": "3e0b8a51-1c7d-4a2e-b6f9-0d5c4e3b2a19",
        "matched_at": "2026-10-18T09:20:00.000Z",
        "expires_at": "2026-10-18T10:20:00.000Z",
        "full_path": "/abc123?a=b+c&utm_source=x",
        "query_params": { "a": "b c", "utm_source": "x" }
      }
    }
    """
}
