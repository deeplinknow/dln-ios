# Changelog

All notable changes to the DeepLinkNow iOS SDK (CocoaPods `DeepLinkNow`, Swift Package Manager `dln-ios`). iOS, Android and React Native share one major.minor version (SDK-84).

## 1.3.0 (2026-10-21)

- **Version re-sync.** iOS, Android and React Native all ship as 1.3.0, so one number names one feature set again (React Native had moved to 1.2.1 on its own). React Native 1.3.0 adds an Expo Router helper and pins `DeepLinkNow ~> 1.3.0`.
- No API or behaviour changes from 1.2.0. `DeepLinkNow.sdkVersion` is `"1.3.0"`, so `/init` reports `ios/1.3.0` (FP-21).
- `LICENSE.txt` now names the copyright holder.

## 1.2.0 (2026-10-19)

- `checkDeferredDeepLink` never throws (SDK-85); `checkDeferredDeepLinkThrowing` and `lastError` added. Preferred-language locale in `/match`, bounded retries, and any 401/403-inactive clears the init cache. See `DOCS.md`.

## 1.1.0 (2026-10-19)

- `checkDeferredDeepLink(options)` runs the pasteboard and fingerprint chain in one call. See `DOCS.md`.
