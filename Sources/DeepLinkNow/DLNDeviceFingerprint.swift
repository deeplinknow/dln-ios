public struct DLNDeviceFingerprint {
    let deviceModel: String
    let systemVersion: String
    let screenResolution: String
    let timezone: String
    let language: String
    let carrier: String?
    let ipAddress: String?
    let advertisingIdentifier: String?
    
    static func generate() -> DLNDeviceFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main
        
        return DLNDeviceFingerprint(
            deviceModel: device.model,
            systemVersion: device.systemVersion,
            screenResolution: "\(screen.bounds.width)x\(screen.bounds.height)",
            timezone: TimeZone.current.identifier,
            language: Locale.current.languageCode ?? "",
            carrier: CTTelephonyNetworkInfo().serviceSubscriberCellularProviders?.values.first?.carrierName,
            ipAddress: DLNDeviceFingerprint.getIPAddress(),
            advertisingIdentifier: ASIdentifierManager.shared().advertisingIdentifier.uuidString
        )
    }
    
    private static func getIPAddress() -> String? {
        // Implementation for getting IP address
        // ...
    }
} 