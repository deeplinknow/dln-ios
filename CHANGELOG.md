# Changelog

All notable changes to the DeepLinkNow iOS SDK (CocoaPods `DeepLinkNow`, Swift Package Manager `dln-ios`). iOS, Android and React Native share one major.minor version (SDK-84).

## 1.4.0 (2026-10-25)

- **One link object for every open** (SDK-86…91). `DeepLinkNow.onLink(options:_:)` delivers a `DLNLink` for the deferred link and for every Universal Link the app passes to the new `DeepLinkNow.handle(_:) -> Bool`, with `type` (`.deferred` / `.direct`) and `source`. A late handler gets the latest undelivered link, a URL handed in twice within 3 seconds is delivered once, and a handler registered before `initialize` runs its deferred check after it. `hold` with `pendingLink`, `pendingLinks`, `releasePendingLink()` and `clearPendingLink()` hold links until the app is ready (the latest deferred and direct link, delivered deferred first). `resolve` and `resolveLink(_:)` look direct opens up with `GET /api/v1/sdk/resolve` (off by default). `handle(_:)` also accepts the app's own URL schemes (`DLNLinkOptions.schemes`, else Info.plist's `CFBundleURLSchemes`) as `source: .scheme`, never resolved.
- **Clipboard hits are claimed** (SDK-92, SDK-93). A copied link with `#dln=<click id>` is claimed through `GET /api/v1/sdk/referrer-lookup?fp_id=…&source=clipboard&device_id=…` (the IDFV, so a retry after a lost response is answered 200 again) before it is delivered: a 200 adds `deeplinkId`, `targetUrl`, `campaignId`, `metadata`, `matchedAt` and `expiresAt`; a 404 or 410 skips the stale link and goes on to `/match`; any other failure delivers the copied link as before. Parsing strips the `dln` fragment parameter from `url`. Links without the fragment behave exactly as in 1.3.0.
- Additive only: `checkDeferredDeepLink`, `parseLink` and every other 1.3.0 call are unchanged. `DLNDeferredSource` keeps its three cases.

## 1.3.0 (2026-10-21)

- **Version re-sync.** iOS, Android and React Native all ship as 1.3.0, so one number names one feature set again (React Native had moved to 1.2.1 on its own). React Native 1.3.0 adds an Expo Router helper and pins `DeepLinkNow ~> 1.3.0`.
- No API or behaviour changes from 1.2.0. `DeepLinkNow.sdkVersion` is `"1.3.0"`, so `/init` reports `ios/1.3.0` (FP-21).
- `LICENSE.txt` now names the copyright holder.

## 1.2.0 (2026-10-19)

- `checkDeferredDeepLink` never throws (SDK-85); `checkDeferredDeepLinkThrowing` and `lastError` added. Preferred-language locale in `/match`, bounded retries, and any 401/403-inactive clears the init cache. See `DOCS.md`.

## 1.1.0 (2026-10-19)

- `checkDeferredDeepLink(options)` runs the pasteboard and fingerprint chain in one call. See `DOCS.md`.
