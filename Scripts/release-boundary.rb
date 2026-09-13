require 'json'
require 'open3'
require 'find'

class BoundaryFailure < StandardError; end

module ReleaseBoundary
  TOKENS = /KEYRECORD_(?:FLOW|QA|TEST|DEBUG)|FlowTestComposition|FlowPreview|FlowFixture|FileFixturePreferences|JournalingKeyAndFlush|JournalingCapture|FixedReadiness|ConfiguredLogin|FixedCycleID|Fake[A-Z]\w*|Phase1QARunner|XCTest|XCUITest|KeyRecordTestSupport|task\d+-qa\.sh/
  ENTITLEMENTS = /com\.apple\.security\.(?:network\.|device\.|files\.|temporary-exception\.|personal-information\.|automation\.|cs\.)/
  SPAWN = /\b(?:Process|NSTask|URLSession|URLRequest|NWConnection|NWListener)\s*[.(]|\b(?:posix_spawn\w*|execve|fork|popen|getenv)\s*\(|(?<!\.)(?<!func )\bsystem\s*\(|\bCommandLine\b|\/bin\/(?:sh|bash)|\bimport\s+(?:Network|CFNetwork)\b/

  def self.require_boundary(condition, message)
    raise BoundaryFailure, message unless condition
  end

  def self.command(*args)
    output, error, status = Open3.capture3(*args)
    require_boundary(status.success?, "tool failed: #{args.first}: #{error}")
    output
  end

  def self.plist(path)
    JSON.parse(command('/usr/bin/plutil', '-convert', 'json', '-o', '-', path))
  end

  def self.clean(text, path)
    require_boundary(!text.b.match?(TOKENS), "test-only token #{text.b[TOKENS]}: #{path}")
    require_boundary(!text.b.match?(ENTITLEMENTS), "forbidden entitlement: #{path}")
  end

  def self.bundle(app)
    require_boundary(File.directory?(app), 'missing app')
    macos = File.join(app, 'Contents/MacOS')
    require_boundary(Dir.children(macos) == ['KeyRecordApp'], 'extra executable or missing product')
    executable = File.join(macos, 'KeyRecordApp')
    require_boundary(File.executable?(executable), 'product is not executable')
    info = plist(File.join(app, 'Contents/Info.plist'))
    require_boundary(info['LSUIElement'] == true && info['CFBundleExecutable'] == 'KeyRecordApp', 'invalid agent plist')
    architectures = command('/usr/bin/lipo', '-archs', executable).split.sort
    require_boundary(architectures == %w[arm64 x86_64], "not Universal: #{architectures}")
    architectures.each do |arch|
      symbols = command('/usr/bin/nm', '-arch', arch, executable)
      clean(symbols, "nm/#{arch}")
      require_boundary(!symbols.match?(/\b_(?:posix_spawn\w*|execve|fork|popen|system|socket|connect)\b/), "spawn/network import: #{arch}")
    end
    count = 0
    Find.find(app) do |path|
      require_boundary(!File.symlink?(path), "unexpected symlink: #{path}")
      relative = path.delete_prefix(app)
      clean(relative, relative)
      require_boundary(!relative.match?(/\.xctest|LaunchAgents|LaunchDaemons|HelperTools|LoginItems|\.xpc|\.appex|\.framework|\/PlugIns(?:\/|$)/i), "embedded helper/test: #{relative}")
      next unless File.file?(path)
      require_boundary(path == executable || !File.executable?(path), "extra executable: #{relative}")
      raw = File.binread(path)
      clean(raw, relative)
      clean(command('/usr/bin/strings', '-a', path), "strings/#{relative}")
      clean(plist(path).to_json, relative) if %w[.plist .entitlements .strings].include?(File.extname(path))
      count += 1
    end
    puts "PASS unsigned-build-only architectures=#{architectures.join(',')} nm=2 strings_files=#{count} forbidden_tokens=0 executable_files=1 helpers=0; runtime_spawn_count=UNVERIFIED"
  end

  def self.project(root)
    objects = plist(File.join(root, 'KeyRecord.xcodeproj/project.pbxproj')).fetch('objects')
    targets = objects.values.select { |v| v['isa'] == 'PBXNativeTarget' }
    products = targets.reject { |v| %w[com.apple.product-type.bundle.unit-test com.apple.product-type.bundle.ui-testing].include?(v['productType']) }
    require_boundary(products.size == 1 && products.first['name'] == 'KeyRecordApp' &&
      products.first['productType'] == 'com.apple.product-type.application', 'extra non-test product target')
    require_boundary(objects.values.none? { |v| %w[PBXLegacyTarget PBXAggregateTarget PBXShellScriptBuildPhase PBXCopyFilesBuildPhase].include?(v['isa']) }, 'unexpected build execution/copy phase')
    product = products.first
    configs = objects.fetch(product.fetch('buildConfigurationList')).fetch('buildConfigurations')
      .map { |id| objects.fetch(id) }.select { |c| c['name'] == 'Release' }
    require_boundary(configs.size == 1, 'missing Release configuration')
    settings = configs.first.fetch('buildSettings')
    require_boundary(settings['ENABLE_HARDENED_RUNTIME'] == 'YES', 'hardened runtime disabled')
    require_boundary(settings['ENABLE_APP_SANDBOX'] == 'NO', 'unexpected sandbox contract')
    require_boundary(plist(File.join(root, settings.fetch('INFOPLIST_FILE')))['LSUIElement'] == true, 'LSUIElement not true')
    objects.values.select { |v| v['isa'] == 'XCBuildConfiguration' && v['name'] == 'Release' }.each do |config|
      build = config.fetch('buildSettings')
      clean(build.to_json, 'Release settings')
      require_boundary(!build.fetch('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').include?('DEBUG'), 'Release DEBUG enabled')
      if build['CODE_SIGN_ENTITLEMENTS']
        clean(plist(File.join(root, build['CODE_SIGN_ENTITLEMENTS'])).to_json, 'configured entitlements')
      end
    end
    sources = product.fetch('buildPhases').flat_map do |id|
      phase = objects.fetch(id)
      next [] unless phase['isa'] == 'PBXSourcesBuildPhase'
      phase.fetch('files').map { |file| objects.fetch(objects.fetch(file).fetch('fileRef')).fetch('path') }
    end
    require_boundary(!sources.empty?, 'missing product sources')
    paths = sources.map { |path| File.join(root, path) } + Dir.glob(File.join(root, 'Sources/**/*.swift'))
    paths.uniq.each do |path|
      require_boundary(!path.match?(/Tests\/|TestSupport\/|QARunner/), "test source compiled: #{path}")
      # unifdef understands nested preprocessor blocks and keeps unknown Swift platform guards.
      code, error, status = Open3.capture3('/usr/bin/unifdef', '-UDEBUG', path)
      require_boundary([0, 1].include?(status.exitstatus), "unifdef: #{error}")
      clean(code, path)
      require_boundary(!code.b.match?(SPAWN), "spawn/network/CLI source: #{path}")
    end
    Dir.glob(File.join(root, '{App,Sources,KeyRecord.xcodeproj}/**/*.{entitlements,pbxproj}')).each do |path|
      require_boundary(!File.binread(path).match?(ENTITLEMENTS), "entitlement source: #{path}")
    end
    puts "PASS Release sources=#{paths.uniq.size} non_test_products=1 app=KeyRecordApp hardened_runtime=YES LSUIElement=true network_entitlements=0"
  end
end

begin
  raise BoundaryFailure, 'usage: bundle APP | project ROOT' unless ARGV.size == 2
  mode, path = ARGV
  case mode
  when 'bundle' then ReleaseBoundary.bundle(path)
  when 'project' then ReleaseBoundary.project(path)
  else raise BoundaryFailure, 'unknown mode'
  end
rescue BoundaryFailure, JSON::ParserError, KeyError, SystemCallError, TypeError => error
  warn "FAIL release_boundary: #{error.message}"
  exit 1
end
