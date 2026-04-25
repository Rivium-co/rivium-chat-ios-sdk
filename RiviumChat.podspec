Pod::Spec.new do |s|
  s.name             = 'RiviumChat'
  s.version          = '0.1.0'
  s.summary          = 'Real-time messaging SDK for iOS'
  s.description      = <<-DESC
    RiviumChat is a real-time messaging SDK for iOS with WebSocket-based
    messaging, read receipts, typing indicators, presence, reactions,
    and push notification support.
  DESC

  s.homepage         = 'https://rivium.co/cloud/rivium-chat'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rivium' => 'support@rivium.co' }
  s.documentation_url = 'https://rivium.co/cloud/rivium-chat/docs/quick-start'

  s.source           = { :git => 'https://github.com/Rivium-co/rivium-chat-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'

  s.source_files = 'RiviumChat/Sources/**/*.swift'

  s.dependency 'SwiftCentrifuge', '~> 0.5'

  s.frameworks = 'Foundation'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
