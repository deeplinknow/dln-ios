import XCTest
import UIKit
@testable import DeepLinkNow

/// Privacy, logging, packaging and parity
/// (SDK-21, SDK-22, SDK-60…66, SDK-70…72, SDK-80, SDK-82, IOS-01…03, IOS-08, IOS-20…22, IOS-30).
final class PrivacyAndPackagingTests: DLNTestCase {

    // MARK: Helpers

    /// Package root, derived from this file's path (works on Catalyst and the Simulator).
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relative: String) throws -> String {
        let url = packageRoot.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("cannot read \(url.path) from the test process")
        }
        return text
    }

    private func allSourceText() throws -> String {
        let dir = packageRoot.appendingPathComponent("Sources/DeepLinkNow")
        guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot list \(dir.path)")
        }
        return files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func sentFingerprint(enableLogs: Bool = false) async throws -> [String: Any] {
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: enableLogs))
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = try await DeepLinkNow.findDeferredUserThrowing()
        let json = try XCTUnwrap(StubURLProtocol.requests(to: "match").last?.json)
        return try XCTUnwrap(json["fingerprint"] as? [String: Any])
    }

    // MARK: IOS-01 / IOS-02 / IOS-03 / IOS-30 packaging

    func test_IOS_01_podspecAndSourceVersionsMatch() throws {
        // IOS-01: SPM and CocoaPods ship the same version and sources, iOS 13+.
        let podspec = try read("DeepLinkNow.podspec")
        XCTAssertTrue(podspec.contains("s.version          = '\(DeepLinkNow.sdkVersion)'"), "podspec version != sdkVersion")
        XCTAssertTrue(podspec.contains("s.source_files = 'Sources/DeepLinkNow/**/*.swift'"))
        XCTAssertTrue(podspec.contains("s.ios.deployment_target = '13.0'"))
        let manifest = try read("Package.swift")
        XCTAssertTrue(manifest.contains(".iOS(.v13)"))
        XCTAssertEqual(DeepLinkNow.sdkVersion, "1.4.0")
        // deeplink.now is not a DLN domain (SDK-31); the pod author contact must be one we own.
        XCTAssertTrue(podspec.contains("admin@deeplinknow.com"))
        XCTAssertFalse(podspec.contains("deeplink.now"))
    }

    func test_IOS_02_noAdSupportATTOrCoreTelephony() throws {
        // IOS-02 / SDK-61 / SDK-62
        let forbidden = ["AdSupport", "AppTrackingTransparency", "CoreTelephony"]
        let podspec = try read("DeepLinkNow.podspec")
        let manifest = try read("Package.swift")
        let sources = try allSourceText()
        for name in forbidden {
            XCTAssertFalse(podspec.contains("'\(name)'") || podspec.contains("-framework \(name)"), "podspec links \(name)")
            XCTAssertFalse(manifest.contains("\"\(name)\""), "Package.swift links \(name)")
            XCTAssertFalse(sources.contains("import \(name)"), "sources import \(name)")
        }
        XCTAssertFalse(sources.contains("ASIdentifierManager"))
        XCTAssertFalse(sources.contains("ATTrackingManager"))
    }

    func test_IOS_03_docsStateAssociatedDomainsAndNoPasteboardPlistKey() throws {
        // IOS-03
        for doc in ["README.md", "DOCS.md"] {
            let text = try read(doc)
            XCTAssertTrue(text.contains("applinks:"), "\(doc) must document the Associated Domains entitlement")
            XCTAssertFalse(text.contains("NSPasteboardUsageDescription"), "\(doc) must not ask for a pasteboard plist key")
            XCTAssertFalse(text.contains("- `<your-alias>.deeplink.now`"), "\(doc) must not list deeplink.now as a link domain")
            XCTAssertFalse(text.split(separator: "\n").contains { $0.contains("applinks:") && $0.contains("deeplink.now") })
        }
    }

    func test_IOS_30_privacyManifestDeclaresNoTrackingAndIDFVOnly() throws {
        // IOS-30 / SDK-66
        let url: URL
        if let bundled = SDKResources.privacyManifestURL {
            url = bundled
        } else {
            url = packageRoot.appendingPathComponent("Sources/DeepLinkNow/Resources/PrivacyInfo.xcprivacy")
        }
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        let collected = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected.first?["NSPrivacyCollectedDataType"] as? String, "NSPrivacyCollectedDataTypeDeviceID")
        XCTAssertEqual(collected.first?["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
        XCTAssertEqual(collected.first?["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(collected.first?["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(apis.first?["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryUserDefaults")
        XCTAssertEqual(apis.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        let podspec = try read("DeepLinkNow.podspec")
        XCTAssertTrue(podspec.contains("PrivacyInfo.xcprivacy"), "CocoaPods must ship the manifest too")
    }

    // MARK: IOS-20 / IOS-21 / IOS-22 / SDK-21 / SDK-22 / SDK-60 fingerprint body

    func test_IOS_20_advertisingIdIsAlwaysNull() async throws {
        // IOS-20 / SDK-61
        let fp = try await sentFingerprint()
        XCTAssertTrue(fp["advertising_id"] is NSNull)
    }

    func test_IOS_22_deviceAndVendorIdAreIDFVOrNullNeverEmpty() async throws {
        // IOS-22 / SDK-21
        let fp = try await sentFingerprint()
        for key in ["device_id", "vendor_id"] {
            let value = try XCTUnwrap(fp[key], "\(key) must be present")
            if let string = value as? String {
                XCTAssertNotNil(UUID(uuidString: string), "\(key) must be the IDFV")
            } else {
                XCTAssertTrue(value is NSNull)
            }
        }
        XCTAssertEqual(fp["device_id"] as? String, fp["vendor_id"] as? String)
    }

    func test_IOS_21_screenInPointsAndWebDeviceClass() async throws {
        // IOS-21 / SDK-22
        let fp = try await sentFingerprint()
        let (width, scale): (Int, Double) = await MainActor.run { (Int(UIScreen.main.bounds.width), Double(UIScreen.main.scale)) }
        XCTAssertEqual((fp["screen_width"] as? NSNumber)?.intValue, width)
        XCTAssertEqual((fp["pixel_ratio"] as? NSNumber)?.doubleValue ?? 0, scale, accuracy: 0.01)
        XCTAssertTrue(["iPhone", "iPad"].contains(fp["device_model"] as? String ?? ""))
    }

    func test_SDK_22_localeValuesComparableWithWeb() async throws {
        // SDK-22: BCP-47 with hyphen, IANA timezone.
        let fp = try await sentFingerprint()
        let language = try XCTUnwrap(fp["language"] as? String)
        XCTAssertFalse(language.contains("_"))
        XCTAssertEqual(fp["timezone"] as? String, TimeZone.current.identifier)
        XCTAssertEqual(fp["platform"] as? String, "ios")
    }

    func test_SDK_22_languageIsTheUsersPreferredLanguageNotTheAppLocalization() {
        // An English-only app on a French device: Locale.current is en_FR, the browser says fr-FR.
        let appLocale = Locale(identifier: "en_FR")
        XCTAssertEqual(DeviceFingerprint.language(preferred: ["fr-FR", "en-US"], current: appLocale), "fr-FR")
        XCTAssertEqual(DeviceFingerprint.language(preferred: ["zh-Hans-CN"], current: appLocale), "zh-Hans-CN")
        XCTAssertEqual(DeviceFingerprint.language(preferred: ["pt_BR@calendar=gregorian"], current: appLocale), "pt-BR")
        // Fallbacks: the current locale, then en-US.
        XCTAssertEqual(DeviceFingerprint.language(preferred: [], current: appLocale), "en-FR")
        XCTAssertEqual(DeviceFingerprint.language(preferred: [" "], current: Locale(identifier: "de_DE")), "de-DE")
        XCTAssertEqual(DeviceFingerprint.language(preferred: [], current: Locale(identifier: "")), "en-US")
        // The default reads Locale.preferredLanguages.
        if let first = Locale.preferredLanguages.first {
            XCTAssertEqual(DeviceFingerprint.language(), first.replacingOccurrences(of: "_", with: "-"))
        }
    }

    func test_SDK_21_nullableKeysAlwaysPresent() async throws {
        // SDK-21
        let fp = try await sentFingerprint()
        for key in ["device_id", "advertising_id", "vendor_id", "hardware_fingerprint"] {
            XCTAssertTrue(fp.keys.contains(key), key)
        }
        for key in ["installed_at", "last_opened_at"] {
            XCTAssertTrue((fp[key] as? String ?? "").hasSuffix("Z"), key)
        }
    }

    func test_SDK_60_onlyDocumentedFieldsAndNoIPAddress() async throws {
        // SDK-60 / SDK-62
        let fp = try await sentFingerprint()
        let allowed: Set<String> = [
            "user_agent", "platform", "os_version", "device_model", "language", "timezone",
            "installed_at", "last_opened_at", "device_id", "advertising_id", "vendor_id",
            "hardware_fingerprint", "screen_width", "screen_height", "pixel_ratio", "metadata",
        ]
        XCTAssertEqual(Set(fp.keys).subtracting(allowed), [])
        XCTAssertNil(fp["ip_address"])
        let metadata = try XCTUnwrap(fp["metadata"] as? [String: Any])
        let allowedMetadata: Set<String> = ["screen_width", "screen_height", "pixel_ratio", "color_depth", "is_tablet", "cpu_cores", "source", "connection_type", "device_memory"]
        XCTAssertEqual(Set(metadata.keys).subtracting(allowedMetadata), [])
    }

    func test_SDK_61_noAdvertisingIdentifierApis() throws {
        // SDK-61
        let sources = try allSourceText()
        XCTAssertFalse(sources.contains("advertisingIdentifier"))
        XCTAssertFalse(sources.contains("requestTrackingAuthorization"))
    }

    func test_SDK_62_noLocationCarrierOrHardwareIds() throws {
        // SDK-62
        let sources = try allSourceText()
        for api in ["CoreLocation", "CTTelephonyNetworkInfo", "Contacts", "serialNumber"] {
            XCTAssertFalse(sources.contains(api), api)
        }
    }

    func test_SDK_65_persistsOnlyTheFirstLaunchState() async throws {
        // SDK-65: nothing but the namespaced first-launch keys and the /init cache (SDK-83);
        // no fingerprint or device identifier stored locally.
        fakePasteboard.content = "https://example.com"
        await initializeSDK()
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        _ = await DeepLinkNow.checkDeferredDeepLink()
        let keys = Set(defaults.persistentDomain(forName: Self.defaultsSuite)?.keys.map { $0 } ?? [])
        XCTAssertEqual(keys.subtracting([DeepLinkNow.deferredCompletedKey, DeepLinkNow.clipboardCheckedKey, InitCache.defaultsKey]), [])
        let cache = try XCTUnwrap(defaults.data(forKey: InitCache.defaultsKey))
        let cacheText = String(decoding: cache, as: UTF8.self)
        if let idfv = await MainActor.run(body: { UIDevice.current.identifierForVendor?.uuidString }) {
            XCTAssertFalse(cacheText.contains(idfv), "SDK-65: no device identifier in the cache")
        }
        for field in ["device", "fingerprint", "ip", "locale", "model"] {
            XCTAssertNil((try JSONSerialization.jsonObject(with: cache) as? [String: Any])?[field], field)
        }
    }

    func test_SDK_66_privacyIsDocumented() throws {
        // SDK-66: README documents what is collected and why.
        let readme = try read("README.md")
        XCTAssertTrue(readme.contains("PrivacyInfo.xcprivacy"))
        XCTAssertTrue(readme.lowercased().contains("identifierforvendor") || readme.contains("IDFV"))
    }

    // MARK: IOS-08 / SDK-63 / SDK-70 / SDK-71 / SDK-72 logging

    func test_SDK_63_apiKeyNeverLoggedEvenWithLogsOn() async throws {
        // SDK-63 / IOS-08 / SDK-71
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match()]))
        _ = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        StubURLProtocol.stub("init", status: 401, json: Fixtures.errorInvalidKey)
        await DeepLinkNow.initialize(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true), urlSession: makeSession())
        XCTAssertFalse(logs.lines.isEmpty, "logs were captured")
        XCTAssertFalse(logs.joined.contains(Self.apiKey))
        XCTAssertFalse(logs.joined.contains("0123456789abcdef"))
        XCTAssertEqual(Logger.mask(Self.apiKey), "dln_…cdef")
    }

    func test_IOS_08_initDoesNotLogConfigOrRawResponse() async {
        // IOS-08
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
        XCTAssertFalse(logs.joined.contains("DLNConfig"))
        XCTAssertFalse(logs.joined.contains("credits_remaining"))
        XCTAssertFalse(logs.joined.contains("ABCDE12345"), "raw init response must not be logged")
    }

    func test_SDK_70_debugLogsOnlyWithEnableLogsAndPrefixed() async throws {
        // SDK-70
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: false))
        StubURLProtocol.stub("match", json: Fixtures.matchEmpty)
        _ = await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(useClipboard: false))
        XCTAssertTrue(logs.lines.isEmpty, "no debug output with enableLogs off: \(logs.lines)")

        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
        XCTAssertFalse(logs.lines.isEmpty)
        XCTAssertTrue(logs.lines.allSatisfy { $0.hasPrefix("[DeepLinkNow]") })
    }

    func test_SDK_72_eachDeferredStepLogsItsOutcome() async throws {
        // SDK-72
        await initializeSDK(config: DLNConfig(apiKey: Self.apiKey, enableLogs: true))
        fakePasteboard.content = "https://example.com/x"
        StubURLProtocol.stub("match", json: Fixtures.matchResponse([Fixtures.match(confidence: 61, quality: "MEDIUM")]))
        _ = await DeepLinkNow.checkDeferredDeepLink()
        XCTAssertTrue(logs.joined.contains("clipboard has no DLN link"))
        XCTAssertTrue(logs.joined.contains("fingerprint match 61"))
    }

    // MARK: SDK-80 / SDK-82 parity

    func test_SDK_80_canonicalApiSurfaceExists() {
        // SDK-80: canonical names with Swift idioms. SDK-82: behavioural rules covered by ID-tagged tests.
        let _: (DLNConfig, URLSessionProtocol) async throws -> DLNAppInfo = DeepLinkNow.initializeThrowing(config:urlSession:)
        let _: (DLNConfig, URLSessionProtocol) async -> Void = DeepLinkNow.initialize(config:urlSession:)
        let _: Bool = DeepLinkNow.isInitialized
        let _: (DLNDeferredOptions) async -> DeferredDeepLink? = DeepLinkNow.checkDeferredDeepLink
        let _: (DLNDeferredOptions) async throws -> DeferredDeepLink? = DeepLinkNow.checkDeferredDeepLinkThrowing
        let _: DeepLinkNowError? = DeepLinkNow.lastError
        let _: () async -> MatchResponse? = DeepLinkNow.findDeferredUser
        let _: () async throws -> MatchResponse = DeepLinkNow.findDeferredUserThrowing
        let _: () -> String? = DeepLinkNow.checkClipboard
        let _: () -> Bool = DeepLinkNow.hasDeepLinkToken
        let _: (URL) -> DLNParsedLink? = DeepLinkNow.parseLink
        let _: (URL) -> (path: String, parameters: [String: Any])? = DeepLinkNow.parseDeepLink
        let _: (String) -> Bool = DeepLinkNow.isValidDomain
        let _: () -> Void = DeepLinkNow.resetDeferredDeepLink
        let _: (String, DLNCustomParameters?) -> URL? = DeepLinkNow.createDeepLink(path:customParameters:)
        XCTAssertEqual(DLNDeferredSource.allRawValues, ["referrer", "clipboard", "fingerprint"])
    }
}

private extension DLNDeferredSource {
    static var allRawValues: [String] { [DLNDeferredSource.referrer, .clipboard, .fingerprint].map { $0.rawValue } }
}
