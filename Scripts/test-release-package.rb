require 'minitest/autorun'
require 'tmpdir'
require_relative 'release-package'

class ReleasePackageTests < Minitest::Test
  def with_package(reject: nil, wrong_team: false)
    Dir.mktmpdir('keyrecord-package-test') do |temp|
      output = File.join(temp, 'release')
      calls = []
      runner = lambda do |args|
        calls << args
        raise ReleasePackage::Failure, 'simulated command failure' if reject == args.first
        if args.first == 'xcodebuild'
          FileUtils.mkdir_p(File.join(output, 'KeyRecord.xcarchive/Products/Applications/KeyRecordApp.app'))
        elsif args.include?('notarytool')
          next JSON.generate(status: reject == 'notary' ? 'Invalid' : 'Accepted', id: 'simulated')
        elsif args.first == '/usr/bin/codesign' && args.include?('-d')
          next "TeamIdentifier=#{wrong_team ? 'OTHER12345' : 'ABCDE12345'}\nAuthority=Developer ID Application: Example (ABCDE12345)\n"
        elsif args.first == '/usr/bin/ditto'
          File.write(args.last, 'simulated zip')
        end
        ''
      end
      package = ReleasePackage.new(root: File.expand_path('..', __dir__), output: output,
        team: 'ABCDE12345', identity: 'Developer ID Application: Example (ABCDE12345)',
        profile: 'release-profile', runner: runner)
      yield package, output, calls
    end
  end
  def test_plan_is_read_only
    with_package do |package, output, calls|
      assert_equal false, package.plan[:publishes]
      refute File.exist?(output)
      assert_empty calls
    end
  end
  def test_final_zip_follows_staple_and_assessment
    with_package do |package, output, calls|
      result = package.run
      assert_equal false, result[:published]
      assert File.file?(File.join(output, 'release-result.json'))
      final_index = calls.index { |a| a.last == File.join(output, 'KeyRecord.zip') }
      assert_operator final_index, :>, calls.index { |a| a.include?('staple') }
      assert_operator final_index, :>, calls.index { |a| a.include?('--assess') }
      previous = calls.size
      assert_raises(ReleasePackage::Failure) { package.run }
      assert_equal previous, calls.size
    end
  end
  def test_failures_cannot_emit_ready_receipt_or_final_zip
    ['xcodebuild', 'notary', '/usr/sbin/spctl', '/usr/bin/codesign'].each do |failure|
      with_package(reject: failure) do |package, output, _|
        assert_raises(ReleasePackage::Failure) { package.run }
        refute File.exist?(File.join(output, 'release-result.json'))
        refute File.exist?(File.join(output, 'KeyRecord.zip'))
      end
    end
  end
  def test_wrong_team_prevents_notarization
    with_package(wrong_team: true) do |package, _, calls|
      assert_raises(ReleasePackage::Failure) { package.run }
      refute calls.any? { |a| a.include?('notarytool') }
    end
  end
end
