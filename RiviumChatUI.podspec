Pod::Spec.new do |s|
  s.name             = 'RiviumChatUI'
  s.version          = '0.1.0'
  s.summary          = 'Pre-built UI components for RiviumChat iOS SDK'
  s.description      = <<-DESC
    RiviumChatUI provides ready-to-use SwiftUI components for chat applications
    including message bubbles, input fields, typing indicators, presence dots,
    reaction pickers, read receipts, and more.
  DESC

  s.homepage         = 'https://rivium.co/cloud/rivium-chat'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rivium' => 'support@rivium.co' }
  s.documentation_url = 'https://rivium.co/cloud/rivium-chat/docs/quick-start'

  s.source           = { :git => 'https://github.com/Rivium-co/rivium-chat-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'

  s.source_files = 'RiviumChatUI/Sources/**/*.swift'

  s.dependency 'RiviumChat', '~> 0.1'
  s.dependency 'SDWebImageSwiftUI', '~> 3.0'

  s.frameworks = 'SwiftUI'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
