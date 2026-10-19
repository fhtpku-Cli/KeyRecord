#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'fileutils'
require 'optparse'

class ReleasePackage
  class Failure < StandardError; end
  def initialize(root:, output:, team:, identity:, profile:, runner: nil)
    @root = File.expand_path(root)
    @output = File.expand_path(output)
    @team, @identity, @profile = team, identity, profile
    raise Failure, 'expected a 10-character Apple Team ID' unless team.match?(/\A[A-Z0-9]{10}\z/)
    raise Failure, 'expected a Developer ID Application identity for that team' unless
      identity.start_with?('Developer ID Application: ') && identity.end_with?(" (#{team})") &&
      !identity.match?(/[\r\n\0]/)
    raise Failure, 'expected a named notarytool keychain profile' unless profile.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)
    @runner = runner || lambda do |args|
      text, error, status = Open3.capture3(*args, chdir: @root)
      raise Failure, "#{File.basename(args.first)} failed: #{error}" unless status.success?
      text + error
    end
  end
  def plan
    {product: 'KeyRecord', output: @output, team: @team,
     steps: ['archive universal Release', 'inspect release boundaries', 'verify Developer ID signature',
             'submit to Apple notarization', 'staple and assess', 'create final stapled zip'],
     publishes: false, execution: 'requires --execute and real signing credentials'}
  end
  def run
    Dir.mkdir(@output)
    archive = File.join(@output, 'KeyRecord.xcarchive')
    app = File.join(archive, 'Products/Applications/KeyRecordApp.app')
    call('xcodebuild', '-project', 'KeyRecord.xcodeproj', '-scheme', 'KeyRecordApp',
         '-configuration', 'Release', '-destination', 'generic/platform=macOS',
         '-archivePath', archive, 'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'SKIP_INSTALL=NO',
         'CODE_SIGN_STYLE=Manual', "DEVELOPMENT_TEAM=#{@team}", "CODE_SIGN_IDENTITY=#{@identity}", 'archive')
    raise Failure, 'archive did not produce the application' unless File.directory?(app)
    call('/usr/bin/ruby', File.join(@root, 'Scripts/release-boundary.rb'), 'project', @root)
    call('/usr/bin/ruby', File.join(@root, 'Scripts/release-boundary.rb'), 'bundle', app)
    call('/bin/bash', File.join(@root, 'Scripts/audit-product-network.sh'), '--reviewed-updates',
         File.join(app, 'Contents/MacOS/KeyRecordApp'))
    call('/usr/bin/codesign', '--verify', '--strict', '--verbose=2', app)
    signature = call('/usr/bin/codesign', '-d', '--verbose=4', app)
    raise Failure, 'unexpected signing team or identity' unless
      signature.lines.map(&:strip).include?("TeamIdentifier=#{@team}") &&
      signature.lines.map(&:strip).include?("Authority=#{@identity}") &&
      !signature.include?('Signature=adhoc')
    submission = File.join(@output, 'notary-submission.zip')
    call('/usr/bin/ditto', '-c', '-k', '--keepParent', app, submission)
    result = JSON.parse(call('/usr/bin/xcrun', 'notarytool', 'submit', submission,
                            '--keychain-profile', @profile, '--wait', '--output-format', 'json'))
    raise Failure, 'Apple notarization did not return Accepted' unless result['status'] == 'Accepted'
    call('/usr/bin/xcrun', 'stapler', 'staple', app)
    call('/usr/bin/xcrun', 'stapler', 'validate', app)
    call('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app)
    call('/usr/bin/codesign', '--verify', '--strict', '--verbose=2', app)
    final = File.join(@output, 'KeyRecord.zip')
    call('/usr/bin/ditto', '-c', '-k', '--keepParent', app, final)
    raise Failure, 'final archive was not created' unless File.file?(final) && File.size(final).positive?
    receipt = {product: 'KeyRecord', status: 'signed-notarized-stapled', team: @team,
               notarizationID: result['id'], archive: final, published: false}
    File.write(File.join(@output, 'release-result.json'), JSON.pretty_generate(receipt), mode: 'wx')
    receipt
  rescue Errno::EEXIST
    raise Failure, 'output already exists; choose a new directory, existing copies are never overwritten'
  end
  private
  def call(*args)
    @runner.call(args)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    parser = OptionParser.new do |p|
      p.banner = 'Usage: release-package.rb --output NEW_DIR --team TEAM --identity ID --notary-profile PROFILE [--execute]'
      p.on('--output PATH') { |v| options[:output] = v }
      p.on('--team TEAM') { |v| options[:team] = v }
      p.on('--identity ID') { |v| options[:identity] = v }
      p.on('--notary-profile PROFILE') { |v| options[:profile] = v }
      p.on('--execute') { options[:execute] = true }
    end
    parser.parse!
    raise ReleasePackage::Failure, parser.to_s unless ARGV.empty? &&
      [:output, :team, :identity, :profile].all? { |k| options[k] }
    execute = options.delete(:execute)
    package = ReleasePackage.new(root: File.expand_path('..', __dir__), **options)
    puts JSON.pretty_generate(execute ? package.run : package.plan)
  rescue ReleasePackage::Failure, SystemCallError, JSON::ParserError, OptionParser::ParseError => error
    warn "FAIL release_package: #{error.message}"
    exit 1
  end
end
