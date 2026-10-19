import Foundation

enum SDKResources {
    /// The bundled privacy manifest (IOS-30). SPM only; CocoaPods ships it in `DeepLinkNow_Privacy.bundle`.
    static var privacyManifestURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        #else
        return nil
        #endif
    }
}
