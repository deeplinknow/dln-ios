#
#  DeepLinkNow iOS SDK podspec.
#  Validate with: pod spec lint DeepLinkNow.podspec
#  Keep the pod version in sync with DeepLinkNow.sdkVersion (Sources/DeepLinkNow/DeepLinkNow.swift).
#

Pod::Spec.new do |s|
  s.name             = 'DeepLinkNow'
  s.version          = '1.1.0'
  s.summary          = 'DeepLinkNow iOS SDK: privacy-first deferred deep linking'

  s.description      = <<-DESC
                      DeepLinkNow gets users to the right place in your app after install.
                      It returns the deferred deep link the user tapped (pasteboard handoff first,
                      fingerprint matching as a backup) and parses Universal Links on your
                      DeepLinkNow domains. No analytics, no advertising identifiers, no ATT prompt.
                      DESC

  s.homepage         = 'https://github.com/deeplinknow/dln-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE.txt' }
  s.author           = { 'DeepLinkNow' => 'support@deeplink.now' }

  s.source           = {
    :git => 'https://github.com/deeplinknow/dln-ios.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '13.0'
  s.swift_versions = ['5.5']

  s.source_files = 'Sources/DeepLinkNow/**/*.swift'
  s.resource_bundles = {
    'DeepLinkNow_Privacy' => ['Sources/DeepLinkNow/Resources/PrivacyInfo.xcprivacy']
  }

  # Only UIKit and Foundation. No AdSupport, AppTrackingTransparency or CoreTelephony (IOS-02).
  s.frameworks = ['UIKit', 'Foundation']

  s.static_framework = true
end
