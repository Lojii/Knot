#
# Be sure to run `pod lib lint ActiveSQLite.Swift.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'ActiveSQLite'
  s.version          = '0.5.3'
  s.summary          = 'ActiveSQLite is an helper of SQLite.Swift. It can let you use SQLite.swift easily.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
ActiveSQLite is an helper of SQLite.Swift. It can let you use SQLite.swift easily..
                       DESC

  s.homepage         = 'https://github.com/KevinZhouRafael/ActiveSQLite'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'zhoukai' => 'wumingapie@gmail.com' }
  s.source           = { :git => 'https://github.com/KevinZhouRafael/ActiveSQLite.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.swift_versions = ['5.0','5.1','5.2','5.3']
  s.ios.deployment_target = '8.0'

  s.source_files = 'ActiveSQLite/Classes/**/*'
  
  # s.resource_bundles = {
  #   'ActiveSQLite.Swift' => ['ActiveSQLite.Swift/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'SQLite.swift' , '~> 0.12.0'
  s.dependency 'SQLite.swift' , '0.12.2'
  # s.dependency 'SQLite.swift/standalone' , '~> 0.12.0'
  # s.dependency 'CocoaLumberjack/Swift'
end
