Pod::Spec.new do |s|
  s.name             = 'DeepLinkNow'
  s.version          = '0.1.0'
  s.summary          = 'A lightweight deep linking SDK for iOS'
  s.description      = <<-DESC
                      DeepLinkNow is a powerful deep linking and attribution SDK for iOS apps.
                      Easily handle deep links, deferred deep links, and track attribution.
                      DESC
  s.homepage         = 'https://github.com/YourUsername/DeepLinkNow-iOS'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Name' => 'your.email@example.com' }
  s.source           = { :git => 'https://github.com/YourUsername/DeepLinkNow-iOS.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  
  s.source_files = 'Sources/DeepLinkNow/**/*'
end 