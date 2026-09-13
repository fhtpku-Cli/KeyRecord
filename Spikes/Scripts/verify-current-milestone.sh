#!/usr/bin/env bash
set -euo pipefail
exec ruby - "$@" <<'RUBY'
require 'json'
require 'digest'
require 'pathname'

def require_fact(condition, reason)
  raise ArgumentError, reason unless condition
end

begin
  require_fact(ARGV.length == 1, 'usage: allocation.json')
  document = JSON.parse(File.read(ARGV.fetch(0)))
  require_fact(document.keys.sort == %w[schemaVersion baseline g1 gates requirements evidence].sort, 'document_fields')
  require_fact(document['schemaVersion'] == 1 && document['g1'] == 'BLOCKED', 'g1_not_qualified')
  require_fact(document['baseline'] == '064164e47fe2dfb1957ea8fc601269ecb2c8812e', 'baseline')
  identities = {
    'q19' => '0cafc5023944478dd547b7b9ed16ff2f27a3d94a43f420d713f73c6be9d01bca',
    'q20' => 'd302dc86375c1bfedebb4c706dddb08cc23c22803b36ce54828392f0b3bea962',
    'network' => 'ebf669667b29a8a58c558b9b37461fb5bdee40ec249ef135ce19720c3663104e',
    'q22' => '1afd5fb0bda0c38050dc1b3bf5cf4701c6afa27126c07bbf756f1c2e7dba2551',
    'projection' => '24dbbdc8edcad1db97031571804be9a47c8c9ec57916928ce251b4fcf90e1cb1',
    'plan' => '87842e6a97db39398125307f5f4c864a7c9b4efa04b79ad8e6e91ca382dfcace',
    'history' => '42084571062186bd7746d1b4aed002ef3b6445b98b3053f61854800bdccc4259',
    'prd' => 'd0fcd921f401e9444d984f292e30f7f7f242ef2886a21c82085e8f1f98ba7e1e'
  }
  require_fact(document.fetch('evidence').keys.sort == identities.keys.sort, 'evidence_coverage')
  gates = %w[SP6A capture privacy encryptedPersistence network performanceARM performanceIntel hostedUI signing notarization publicRelease FULL_BACKUP_FINAL_RELEASE KARABINER_STABLE VIA_GENERATION VIAL_BETA]
  require_fact(document.fetch('gates').map { |g| g.fetch('id') }.sort == gates.sort, 'gate_coverage')
  document.fetch('gates').each do |gate|
    require_fact(gate.keys.sort == %w[id status evidence].sort, 'gate_fields')
    require_fact(gate['status'] == 'BLOCKED', "blocked_gate_promoted:#{gate['id']}")
    require_fact(document.fetch('evidence').key?(gate['evidence']), 'gate_evidence')
    puts "BLOCKED_GATE=#{gate['id']}"
  end
  ids = (1..8).map { |n| "FR-C#{n}" } + (1..7).map { |n| "FR-P#{n}" } +
        (1..4).map { |n| "FR-U#{n}" } + (1..3).map { |n| "EK#{n}" } + %w[FR-R1 FR-R2]
  rows = document.fetch('requirements')
  require_fact(rows.map { |row| row.fetch('id') }.sort == ids.sort, 'requirement_coverage')
  rows.each do |row|
    require_fact(row.keys.sort == %w[id implementation tests status gates evidence].sort, 'row_fields')
    retained = %w[FR-P6 FR-R1 FR-R2 FR-U2]
    expected = retained.include?(row['id']) ? 'INDEPENDENT_RETAINED' : 'IMPLEMENTED_HOST_BLOCKED'
    require_fact(row['status'] == expected, "allocation_status:#{row['id']}")
    require_fact(row['gates'].is_a?(Array) && !row['gates'].empty? && (row['gates'] - gates).empty?, 'row_gates')
    require_fact(row['id'] != 'FR-P6' || row['gates'].include?('FULL_BACKUP_FINAL_RELEASE'), 'backup_required')
    %w[implementation tests].each do |field|
      require_fact(row[field].is_a?(Array) && !row[field].empty?, 'missing_file_mapping')
      row[field].each do |path|
        require_fact(path.is_a?(String) && !Pathname.new(path).absolute? && !path.split('/').include?('..'), 'unsafe_path')
        require_fact(File.file?(path) && !File.symlink?(path), "missing_file:#{path}")
      end
    end
    require_fact(row['evidence'].is_a?(Array) && !row['evidence'].empty?, 'missing_evidence')
    row['evidence'].each { |key| require_fact(document.fetch('evidence').key?(key), 'unknown_evidence') }
  end
  document.fetch('evidence').each do |key, item|
    require_fact(item.keys.sort == %w[category path sha256 status].sort, "evidence_fields:#{key}")
    require_fact(%w[PASS BLOCKED REFERENCE].include?(item['status']), 'evidence_status')
    require_fact(item['category'].is_a?(String) && !item['category'].empty?, 'category')
    require_fact(item['sha256'].match?(/\A[0-9a-f]{64}\z/), 'evidence_digest')
    require_fact(item['sha256'] == identities.fetch(key), "unapproved_evidence_identity:#{key}")
    path = item.fetch('path')
    if ENV['MILESTONE_EVIDENCE_ROOT']
      path = File.join(ENV.fetch('MILESTONE_EVIDENCE_ROOT'), item.fetch('sha256'))
    end
    require_fact(File.file?(path) && !File.symlink?(path), "evidence_unavailable:#{key}")
    require_fact(Digest::SHA256.file(path).hexdigest == item['sha256'], "evidence_digest:#{key}")
    if item.fetch('path').end_with?('receipt.json', 'assertion-summary.json')
      receipt = JSON.parse(File.read(path))
      require_fact(receipt['outcome'] == item['status'], "receipt_status:#{key}")
      if item['status'] == 'PASS'
        require_fact(receipt['executed'].is_a?(Integer) && receipt['executed'] > 0 &&
          receipt['failed'] == 0 && receipt['skipped'] == 0 && receipt['childExitStatus'] == 0 &&
          receipt['runnerExitStatus'] == 0 && receipt['code'] == 'assertions_passed', "receipt_assertions:#{key}")
      end
    else
      require_fact(item['status'] == 'REFERENCE', "nonreceipt_pass:#{key}")
    end
  end
  puts "CURRENT_MILESTONE=PASS scope=allocation requirements=#{rows.length} g1=BLOCKED release_claim=false"
rescue JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError, Errno::ENOENT => error
  warn "CURRENT_MILESTONE=FAIL reason=#{error.message}"
  exit 1
end
RUBY
