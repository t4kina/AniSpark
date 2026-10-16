# Adds the "Up next" home-screen widget (ios/UpNextWidget) to Runner.xcodeproj
# as an app extension embedded in the app.
#
# The project is edited without Xcode (there's no Mac here), so Codemagic's
# ios-release-widget workflow runs this before building. It does nothing when
# the target is already there. Needs the xcodeproj gem, which CocoaPods uses.
# The widget needs iOS 17; the app itself keeps its own minimum.
require 'xcodeproj'

NAME = 'UpNextWidget'
IOS_DIR = File.expand_path('..', __dir__)

project = Xcodeproj::Project.open(File.join(IOS_DIR, 'Runner.xcodeproj'))
if project.targets.any? { |target| target.name == NAME }
  puts "#{NAME} is already in the project"
  exit
end
runner = project.targets.find { |target| target.name == 'Runner' } or abort 'No Runner target'
flutter_group = project.main_group['Flutter'] or abort 'No Flutter group'

widget = project.new_target(:app_extension, NAME, :ios, '17.0', nil, :swift)

group = project.main_group.new_group(NAME, NAME)
sources = Dir.glob(File.join(IOS_DIR, NAME, '*.swift')).sort.map do |path|
  group.new_reference(File.basename(path))
end
abort "No Swift sources in ios/#{NAME}" if sources.empty?
widget.add_file_references(sources)
group.new_reference('Info.plist')
widget.add_system_frameworks(%w[WidgetKit SwiftUI])

# The Flutter group has no folder of its own: its files are named Flutter/...
xcconfig = flutter_group.new_reference('Flutter/WidgetExtension.xcconfig')
xcconfig.name = 'WidgetExtension.xcconfig'

widget.build_configurations.each do |config|
  runner_config = runner.build_configurations.find { |c| c.name == config.name } || runner.build_configurations.first
  # An extension's bundle id has to start with its app's.
  app_id = runner_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  config.base_configuration_reference = xcconfig
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{app_id}.#{NAME}",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => "#{NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SKIP_INSTALL' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)'
  )
end

runner.add_dependency(widget)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Ahead of Flutter's "Thin Binary" script, or Xcode reports a build cycle.
thin_binary = runner.shell_script_build_phases.find { |phase| phase.name == 'Thin Binary' }
runner.build_phases.move(embed, runner.build_phases.index(thin_binary)) if thin_binary

project.save
puts "Added #{NAME} to the project (#{widget.build_configurations.map(&:name).join(', ')})"
