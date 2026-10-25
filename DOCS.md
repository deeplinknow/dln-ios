# DeepLinkNow iOS SDK Documentation

## Overview

DeepLinkNow (DLN) is a privacy-first deferred deep linking SDK. It does two jobs:

1. **Initialize**: validate your API key and account, and learn your app's link domains.
2. **Return the deferred deep link**: the path and query the user tapped before installing, with where the answer came from (`source`) and how sure DLN is (`confidenceScore`, `matchQuality`).

It also parses Universal Links that open the installed app, with the same rules, so deferred and direct opens route the same way.

DLN is not an analytics or attribution SDK. It never reads the IDFA, never triggers the App Tracking Transparency prompt, and hands the result to your app to forward to whatever analytics you use.

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Universal Links setup](#universal-links-setup)
- [Initializing the SDK](#initializing-the-sdk)
- [The deferred deep link](#the-deferred-deep-link)
- [Universal Links (installed app)](#universal-links-installed-app)
- [Link domains](#link-domains)
- [Query parameters](#query-parameters)
- [Low-level APIs](#low-level-apis)
- [Errors](#errors)
- [Threading](#threading)
- [Privacy](#privacy)
- [Migrating from 1.0.x](#migrating-from-10x)
- [Testing tips](#testing-tips)
- [Support](#support)
- [License](#license)

## Requirements

- iOS 13.0+
- Swift 5.5+ (async/await)
- Xcode 13.2+

## Installation

### CocoaPods

```ruby
pod 'DeepLinkNow', '~> 1.4'
```

### Swift Package Manager

In Xcode choose **File > Add Package Dependencies...** and enter `https://github.com/deeplinknow/dln-ios`, or add it to `Package.swift`:

```swift
.package(url: "https://github.com/deeplinknow/dln-ios.git", from: "1.4.0")
```

The SDK links only UIKit and Foundation. No `Info.plist` keys are required (iOS has no usage-description key for the pasteboard).

## Universal Links setup

1. In the dashboard, set the app's **Team ID / App ID prefix** and **Bundle ID**. DLN serves `https://<alias>.deeplinknow.com/.well-known/apple-app-site-association` (and the same for a verified custom domain) from those values. Changes can take up to 5 minutes to propagate.
2. In Xcode, **Signing & Capabilities → Associated Domains**, add `applinks:<alias>.deeplinknow.com`, plus `applinks:<custom-domain>` if you have one.
3. Pass incoming URLs to `DeepLinkNow.parseLink(_:)` (see [Universal Links](#universal-links-installed-app)).

## Initializing the SDK

Use your app's **public** API key. The `/api/v1/sdk/*` endpoints reject private keys.

```swift
import DeepLinkNow

let config = DLNConfig(
    apiKey: "your-public-api-key",
    enableLogs: false,      // debug logs, prefixed [DeepLinkNow]; the key is never logged
    baseUrl: nil,           // default https://deeplinknow.com; a trailing "/" is fine
    timeout: nil,           // default 10 s per request
    retryAttempts: nil      // default 2 retries for transient failures (clamped to 0...5)
)

do {
    let app = try await DeepLinkNow.initializeThrowing(config: config)
    // app.alias, app.linkDomains, app.primaryDomain, app.accountStatus, app.creditsRemaining
} catch let error as DeepLinkNowError {
    print(error.code, error.statusCode ?? 0, error.message ?? "")
}
```

- One call makes one `POST /api/v1/sdk/init` (plus retries). The key is sent in the `x-api-key` header, never in the URL.
- Transport errors, timeouts, 5xx and 429 are retried up to `retryAttempts` times (at most 5) with exponential backoff (0.5 s, 1 s, 2 s, 4 s, then 5 s), honouring `Retry-After` up to 5 s. 400/401/403/404/410 are never retried.
- A failed init leaves `DeepLinkNow.isInitialized == false` and sets `DeepLinkNow.initializationError`. Calling initialize again atomically replaces the previous configuration. Concurrent calls with the same key share one request.
- Init never reads the pasteboard and never blocks the main thread.
- `baseUrl` must be https; `http://localhost`, `127.0.0.1` and `10.0.2.2` are allowed for development. An invalid `baseUrl` throws `.invalidConfiguration` instead of crashing.

The non-throwing `await DeepLinkNow.initialize(config:urlSession:)` never throws; it logs a warning on failure and sets `initializationError` and `lastError`. Calls made while initialization is in flight wait for it.

## The deferred deep link

Call once at startup, after initializing:

```swift
if let link = await DeepLinkNow.checkDeferredDeepLink() {
    route(path: link.path, query: link.queryParams)
}
// No link? Carry on to your normal start screen.
```

`checkDeferredDeepLink` never throws. `nil` means "no link" or "the check failed"; a failure is logged as a warning and kept in `DeepLinkNow.lastError` (see [Errors](#errors)). To get the error thrown instead:

```swift
do {
    if let link = try await DeepLinkNow.checkDeferredDeepLinkThrowing() {
        route(path: link.path, query: link.queryParams)
    }
} catch let error as DeepLinkNowError {
    // .notInitialized (error.cause holds the init failure), .network, .server, .rateLimited, …
}
```

### The chain

1. **Pasteboard** (when `useClipboard` is `true`, the default). The DLN landing page copies the tapped link (e.g. `https://myapp.deeplinknow.com/products/123?ref=nl`) before opening the App Store.
   - The SDK first asks iOS whether the pasteboard probably holds a web URL (`detectPatterns`, iOS 14+). That check does not show the paste prompt. If there is no web URL, the pasteboard is not read.
   - Otherwise it reads the pasteboard once. On iOS 16+ the user may see "*App* would like to paste from Safari". "Don't Allow" counts as "nothing found".
   - If the text is exactly one URL on your link domains, it is returned with `source: .clipboard`, `confidenceScore: 100`, `matchQuality: .high`, and **no** match request is made.
2. **Fingerprint** (`POST /api/v1/sdk/match`). The server returns up to 10 candidates from the last hour, sorted by confidence. The SDK returns the first candidate that has a deep link and passes `minConfidence`, with the server's score and label (HIGH ≥ 75, MEDIUM ≥ 50, LOW ≥ 30). The SDK never re-scores or reorders.

### Options

```swift
DLNDeferredOptions(
    minConfidence: nil,  // Double?; nil (default) = every candidate is eligible. Fingerprint only.
    useClipboard: true,  // false = no pasteboard access, no paste prompt
    force: false         // true = ignore the first-launch flag
)
```

DLN does not pick a threshold for you. iCloud Private Relay masks IP addresses, so honest scores vary; choose what suits your app (for example, only auto-route on `.high` and show a "continue where you left off" prompt otherwise).

Apps that want no system prompt can pass `useClipboard: false`, or show their own "Paste your link" button with `UIPasteControl` (iOS 16+) and pass the pasted URL to `parseLink`.

### The result: `DLNDeferredDeepLink` (alias `DeferredDeepLink`)

| Field | Type | Meaning |
|---|---|---|
| `path` | `String` | `fullPath` up to the first `?`, not decoded, starts with `/` |
| `queryParams` | `[String: DLNQueryValue]` | Query parameters (see [Query parameters](#query-parameters)) |
| `fullPath` | `String` | Path and query as received |
| `url` | `String` | Absolute https URL of the link |
| `source` | `DLNDeferredSource` | `.clipboard` or `.fingerprint` (`.referrer` exists for Android parity) |
| `confidenceScore` | `Double` | 0–100; 100 for the clipboard |
| `matchQuality` | `ConfidenceLevel` | `.high` / `.medium` / `.low`; `.high` for the clipboard |
| `deeplinkId`, `targetUrl`, `campaignId`, `metadata`, `matchedAt`, `expiresAt` | optional | From the server (fingerprint only) |
| `matchDetails` | `MatchDetails?` | Score breakdown (fingerprint only) |
| `parameters` | `[String: Any]` | `queryParams` as `String` / `true` / `[String]` |

### First launch only

After a **definitive** outcome (a link was returned, or the pasteboard had no DLN link and `/match` returned no eligible candidate) the SDK stores `com.deeplinknow.deferredCheckCompleted` in `UserDefaults`. Later calls return `nil` with no network or pasteboard access unless `force: true`. `UserDefaults` is removed on uninstall, so a reinstall from a fresh click works.

Errors (not initialized, offline, timeout, 429, 5xx, invalid response) do **not** set the flag, so the next call tries again. The pasteboard is read at most once per install (also stored in `UserDefaults`), so users are not asked to allow pasting twice.

`DeepLinkNow.resetDeferredDeepLink()` clears both flags (useful in development). Concurrent calls in one process share one run and get the same result.

## Universal Links (installed app)

```swift
// SwiftUI
.onOpenURL { url in
    guard let link = DeepLinkNow.parseLink(url) else { return }
    route(path: link.path, query: link.queryParams)
}
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    if let url = activity.webpageURL, let link = DeepLinkNow.parseLink(url) {
        route(path: link.path, query: link.queryParams)
    }
}

// UIKit (AppDelegate, or scene(_:continue:) in a SceneDelegate)
func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                 restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL,
          let link = DeepLinkNow.parseLink(url) else { return false }
    route(path: link.path, query: link.queryParams)
    return true
}
```

`parseLink(_:) -> DLNParsedLink?` is synchronous and side-effect free. It returns `path`, `queryParams`, `fullPath` and `url`, or `nil` when the URL is not an http(s) link on your link domains. The fragment is ignored.

`parseDeepLink(_:) -> (path: String, parameters: [String: Any])?` returns the same data as a tuple (`String`, `true` or `[String]` values).

## Link domains

After a successful init, a host is accepted only if it **exactly equals**, ignoring case, a trailing `.` and any port, one of:

- `<alias>.deeplinknow.com`
- each custom domain the server reports as verified

Rejected: other apps' `*.deeplinknow.com`, the apex `deeplinknow.com`, DLN's own subdomains (`www`, `app`, `api`, `docs`, `m`, `mail`), any `*.deeplink.now` host (not a DLN domain), and lookalikes such as `deeplinknow.com.evil.com`, `evil-deeplinknow.com`, `https://evil.com/?u=x.deeplinknow.com` or `https://a.deeplinknow.com@evil.com/`. Validation always uses the parsed host.

Before init has succeeded, `parseLink`, `parseDeepLink` and `isValidDomain` provisionally accept any non-reserved `<alias>.deeplinknow.com` host (custom domains are not known yet). `checkClipboard` returns `nil` before init, and `checkDeferredDeepLink` always waits for init, so the pasteboard step always uses the exact rule.

`DeepLinkNow.isValidDomain(_ host: String) -> Bool` applies this rule.

## Query parameters

Parsed exactly like the server (`URLSearchParams`):

| URL | `queryParams` |
|---|---|
| `?code=SAVE20` | `["code": .string("SAVE20")]` |
| `?code=SAVE+20` | `["code": .string("SAVE 20")]` |
| `?name=Jo%C3%A9` | `["name": .string("Joé")]` |
| `?debug` or `?debug=` | `["debug": .flag]` |
| `?tag=a&tag=b` | `["tag": .list(["a", "b"])]` |

Keys are case-sensitive. `DLNQueryValue` offers `stringValue` (first value, `nil` for a flag), `stringValues` and `anyValue`, and is `Codable` as `string | true | [string]`.

## Low-level APIs

| API | Notes |
|---|---|
| `findDeferredUserThrowing() async throws -> MatchResponse` | The full `/match` response: every candidate with `confidenceScore`, `matchQuality`, `matchDetails` and `deeplink` (incl. `queryParams`, `fullPath`), plus `ttlSeconds`. Not filtered or reordered. Zero matches is an empty response. |
| `findDeferredUser() async -> MatchResponse?` | Same, `nil` on any error or before init (the error is kept in `lastError`). |
| `checkClipboard() -> String?` | Reads the pasteboard (may show the paste prompt). Returns the trimmed text only if it is a single URL on your link domains. |
| `hasDeepLinkToken() -> Bool` | `hasURLs || hasStrings`. Never reads the content, never prompts. `true` means "worth calling `checkClipboard()`", not "verified". |
| `hasDeepLinkTokenAsync() async -> Bool` | Uses `detectPatterns(for: [.probableWebURL])` on iOS 14+. Never reads the content. |
| `createDeepLink(path:customParameters:) -> URL?` | `https://<primary domain><path>?<params>` (primary = first verified custom domain, else `<alias>.deeplinknow.com`). Keys are sorted and strictly encoded, so `parseLink` returns the same path and parameters. `nil` before init. |
| `isInitialized`, `initializationError`, `appInfo` | Init state. |
| `lastError: DeepLinkNowError?` | The last failure of `initialize`, `checkDeferredDeepLink` or `findDeferredUser` (either variant); cleared by the next successful call of the same kind. |
| `sdkVersion` | `"1.4.0"`. |

```swift
let url = DeepLinkNow.createDeepLink(
    path: "/product/123",
    customParameters: DLNCustomParameters(["referrer": "social_share", "discount": 20])
)
// https://myapp.deeplinknow.com/product/123?discount=20&referrer=social_share
```

## Errors

The everyday calls (`initialize`, `checkDeferredDeepLink`, `findDeferredUser`) never throw: a failure returns `nil`, logs a warning and is kept in `DeepLinkNow.lastError` until the next successful call of the same kind. The opt-in throwing variants (`initializeThrowing`, `checkDeferredDeepLinkThrowing`, `findDeferredUserThrowing`) throw the same error. Either way it is a `DeepLinkNowError` (`code`, `statusCode`, `message`, `underlying`, `cause`). Codes are shared with the Android and React Native SDKs:

```swift
if await DeepLinkNow.checkDeferredDeepLink() == nil, let error = DeepLinkNow.lastError {
    print("Deferred check failed:", error.code)   // e.g. .network; the next launch tries again
}
```


| Code | When |
|---|---|
| `notInitialized` | No successful init. `cause` is the init error, if there was one. |
| `invalidApiKey` | HTTP 401 |
| `accountInactive` | HTTP 403 "Account is not active" |
| `noCredits` | HTTP 403 "No credits remaining" |
| `rateLimited` | HTTP 429 |
| `badRequest` | HTTP 400 (and other unexpected 4xx) |
| `server` | HTTP 5xx |
| `network` | Transport error, timeout, offline |
| `invalidResponse` | Unparseable or unexpected body (e.g. a captive-portal HTML page) |
| `invalidConfiguration` | Invalid `DLNConfig` (iOS only) |

The legacy `DLNError` enum is unchanged for source compatibility; the new APIs do not throw it.

## Threading

- All public APIs can be called from any thread or actor. Async APIs return on the caller's context.
- SDK state is lock-protected. `UIScreen`, `UIDevice` and `UIPasteboard` are only touched on the main thread.
- The SDK never crashes the host app: failures surface as `nil` plus `lastError`, or as a thrown `DeepLinkNowError` from the `…Throwing` variants.

## Privacy

`PrivacyInfo.xcprivacy` is bundled (SPM resource; CocoaPods `DeepLinkNow_Privacy` bundle):

- `NSPrivacyTracking`: `false`; no tracking domains.
- Collected data: **Device ID** (`identifierForVendor`), purpose App Functionality, not linked to the user's identity, not used for tracking.
- Required-reason API: `UserDefaults`, reason `CA92.1`.

What the match request sends: a Safari-style user agent, platform `ios`, OS version, device class (`iPhone`/`iPad`), the user's preferred language (`fr-FR` form, from `Locale.preferredLanguages`, so it matches what the browser reported on the link page), IANA time zone, screen width/height in points and scale, CPU core count, install/open timestamps, the IDFV as `device_id`/`vendor_id` (or `null`), `advertising_id: null`, and an informational hash of those values. No IP address is sent (the server sees the connection), and nothing is stored on the device except the first-launch state and the 24-hour `/init` cache. App Store privacy label: "Device ID — App Functionality — not linked — not used for tracking".

## Migrating from 1.0.x

Everything from 1.0.x still compiles. Changes in behaviour:

- `parseDeepLink` / `isValidDomain` / `checkClipboard`: `<alias>.deeplink.now` and other apps' `*.deeplinknow.com` hosts are no longer accepted; host matching ignores case.
- `parseDeepLink`: `path` is no longer percent-decoded; `+` decodes to a space; `?flag` maps to `true`; repeated keys map to `[String]`.
- `createDeepLink` returns an https link on your link domain instead of `deeplinknow://app/…`.
- `hasDeepLinkToken()` no longer reads the pasteboard (no paste prompt); it is a hint, not a verification.
- The SDK no longer reads the IDFA or links AdSupport / CoreTelephony.
- `Match.matchQuality`, `DeeplinkMatch.queryParams` and `DeeplinkMatch.fullPath` are new. `ConfidenceLevel.low.threshold` is now 30 (the server floor).
- Deprecated: `handleUniversalLink(_:)` (now returns `parseLink(url)`), `handleCustomScheme(_:)` (custom schemes are not supported; does nothing).

Recommended: replace hand-rolled "clipboard, then findDeferredUser, then threshold" code with `checkDeferredDeepLink()`.

## Testing tips

- Call `DeepLinkNow.resetDeferredDeepLink()` to re-run the first-launch flow.
- On the Simulator, the Mac's clipboard can sync into the simulator pasteboard.
- `enableLogs: true` logs each step of `checkDeferredDeepLink` (pasteboard result, match score, error code).

## Support

- Email: support@deeplinknow.com

## License

DeepLinkNow is available under the MIT license. See [LICENSE.txt](LICENSE.txt).
