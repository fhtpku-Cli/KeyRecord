#!/usr/bin/env bash
set -euo pipefail

output="Spikes/Tests/Fixtures/Evidence"
rm -rf "$output"
mkdir -p "$output/compliant" "$output/valid/blocked" "$output/valid/g0-open" "$output/invalid"
detectors="$(jq -cn '[range(0;13)|{id:("D"+tostring),available:true}]')"
jq -cn --argjson detectors "$detectors" '{fixturePurpose:"synthetic detector fixture; no host or user data",detectors:$detectors}' >"$output/compliant/environment.json"
environment_hash="$(shasum -a 256 "$output/compliant/environment.json" | /usr/bin/cut -d' ' -f1)"
rules="$output/rules.tsv"
cat >"$rules" <<'RULES'
sp1.tap.session.matrix	live	D2
sp1.tap.annotated.matrix	live	D2
sp1.systemShortcut	live	D1
sp1.autoRepeat	synthetic	D1
sp1.productStampedDrop	synthetic	D1
sp1.tapReset	synthetic	D1
sp1.o7Boundary	synthetic	D1
sp2.frontmostKnown	live	D1
sp2.frontmostUnattributable	live	D1
sp2.frontmostIndeterminate	fixture	D0
sp2.secureInput	live	D3
sp2.excludedApp	synthetic	D1
sp2.tapReset	synthetic	D1
sp2.sleepWake	live	D4
sp2.sidedModifiers	fixture	D0
sp2.sidedRecovery	synthetic	D1
sp2.fnRecoveryModel	fixture	D0
sp2.fnRecoveryLive	live	D1
sp3.schemaLint	fixture	D5
sp3.managedBlock	fixture	D0
sp3.atomicity	fixture	D0
sp3.crashRecovery	fixture	D0
sp3.versionSample	live	D5
sp3.reload	live	D2
sp3.disableLatency	live	D2
sp4a.v2Schema	fixture	D0
sp4a.v3Schema	fixture	D0
sp4a.opaqueRoundTrip	fixture	D0
sp4a.bounds	fixture	D0
sp4b.layoutRoundTrip	synthetic	D0
sp4b.deviceProtocol	source	D0
sp4b.keycodeDialect	source	D0
sp4b.importer	live	D6
sp4b.bounds	fixture	D0
sp5a.vilRoundTrip	synthetic	D0
sp5a.uidBinding	synthetic	D0
sp5a.importer	live	D7
sp5a.bounds	fixture	D0
sp5b.whitelistSource	source	D0
sp5b.replay	fixture	D0
sp5b.denyMutation	fixture	D0
sp5b.liveCapture	live	D8
sp6a.envelope	fixture	D0
sp6a.keychainAfterFirstUnlock	live	D9
sp6a.keychainWhenUnlocked	live	D9
sp6a.keychainSelection	live	D9
sp6a.hkdfLocator	fixture	D0
sp6a.pathCanary	fixture	D0
sp6a.atomicity	fixture	D0
sp6a.securityAudit	source	D0
sp6b.phcAudit	source	D12
sp6b.swiftAudit	source	D12
sp6b.vectors	fixture	D0
sp6b.universalBuild	source	D10
sp6b.armTiming	live	D0
sp6b.intelTiming	live	D11
sp6b.securityAudit	source	D12
RULES

identity="$(jq -cn --arg environmentHash "$environment_hash" '{tapType:"session",attemptID:"fixture-attempt",runnerCommitSha:("b"*40),runnerTreeSha:("c"*40),environmentSha256:$environmentHash,tapConfigSha256:("e"*64)}')"
legs='[]'
while IFS=$'\t' read -r id kind detector; do
  verdict=PASS
  tap_identity=null
  if [[ "$id" == "sp1.tap.annotated.matrix" ]]; then verdict=FAIL; fi
  case "$id" in
    sp1.tap.session.matrix|sp1.systemShortcut|sp1.autoRepeat|sp1.productStampedDrop|sp1.tapReset|sp1.o7Boundary) tap_identity="$identity" ;;
  esac
  event=false; stamped=false
  if [[ "$id" == "sp1.productStampedDrop" ]]; then event=true; stamped=true; fi
  artifact_hash="$(printf '%s' "$id" | shasum -a 256 | /usr/bin/cut -d' ' -f1)"
  leg="$(jq -cn --arg id "$id" --arg kind "$kind" --arg detector "$detector" --arg verdict "$verdict" --arg artifactHash "$artifact_hash" --arg environmentHash "$environment_hash" --argjson tap "$tap_identity" --argjson event "$event" --argjson stamped "$stamped" '{legID:$id,verdict:$verdict,evidenceKind:$kind,detectorID:$detector,detectorAvailable:true,environmentSha256:$environmentHash,runnerCommitSha:("b"*40),runnerTreeSha:("c"*40),command:["fixture-run",$id],exitStatus:(if $verdict=="PASS" then 0 else 1 end),artifacts:[{path:("artifacts/"+$id+".json"),sha256:$artifactHash}],blocker:null,tapIdentity:$tap,containsEventLevelData:$event,productStampedSynthetic:$stamped}')"
  legs="$(jq -cn --argjson values "$legs" --argjson value "$leg" '$values+[$value]')"
done <"$rules"

o4_ids='["karabiner.configSchema","karabiner.managedBlock","karabiner.atomicReplace","karabiner.reload","karabiner.disableLatency","via.definitionSchema","via.deviceProtocol","via.layoutBackupFormat","via.keycodeDialect","via.officialImporterCompatibility","vial.definitionSchema","vial.deviceProtocol","vial.layoutBackupFormat","vial.keycodeDialect","vial.officialImporterCompatibility"]'
spikes='["SP-1","SP-2","SP-3","SP-4A","SP-4B","SP-5A","SP-5B","SP-6A","SP-6B"]'
jq -cn --argjson identity "$identity" --argjson legs "$legs" --argjson o4 "$o4_ids" --argjson spikes "$spikes" '{schemaVersion:1,fixturePurpose:"synthetic validator contract; contains no observed user or device data",selectedTapIdentity:$identity,legs:$legs,o4Rows:[$o4[]|{id:.,evidencePaths:[("fixture/o4/"+.+".json")],blocker:null}],spikeResults:[$spikes[]|{spikeID:.,verdict:"PASS",downstreamBlockIDs:[]}],dispositions:[{id:"O1",status:"DEFERRED",evidencePaths:["fixture/dispositions/O1.json"],blockerIDs:[]},{id:"O2",status:"NO_PUBLIC_ACTION",evidencePaths:[],blockerIDs:["policy.no-public-action"]},{id:"O3",status:"FUTURE_REAL_DEVICE",evidencePaths:[],blockerIDs:["input.future-device"]},{id:"O4",status:"EVIDENCE_OR_BLOCKED",evidencePaths:["fixture/o4/registry.json"],blockerIDs:[]},{id:"O5",status:"REPRESENTED",evidencePaths:["fixture/spikes/index.json"],blockerIDs:[]},{id:"O6",status:"RESOLVED",evidencePaths:["fixture/sp2/conclusion.json"],blockerIDs:[]},{id:"O7",status:"CONSERVATIVE",evidencePaths:["fixture/sp1/o7.json"],blockerIDs:[]}],downstreamBlocks:[{id:"policy.no-public-action",blockedCapability:"public runnable prototype",causedBy:["O2"],unblockAction:"complete separate license review"},{id:"input.future-device",blockedCapability:"real-device compatibility claims",causedBy:["O3"],unblockAction:"run approved physical-device matrix"}],g0:{status:"PASSED",sp1Verdict:"PASS",sp2Verdict:"PASS",blockingLegIDs:[]}}' >"$output/compliant/evidence.json"

make_invalid() {
  local name="$1" code="$2" filter="$3"
  local dir="$output/invalid/$name"
  mkdir -p "$dir"
  jq -c "$filter" "$output/compliant/evidence.json" >"$dir/evidence.json"
  cp "$output/compliant/environment.json" "$dir/environment.json"
  printf '%s\n' "$code" >"$dir/expected-error.txt"
}

make_invalid_environment() {
  local name="$1" code="$2" filter="$3"
  local dir="$output/invalid/$name"
  mkdir -p "$dir"
  cp "$output/compliant/evidence.json" "$dir/evidence.json"
  jq -c "$filter" "$output/compliant/environment.json" >"$dir/environment.json"
  printf '%s\n' "$code" >"$dir/expected-error.txt"
}

cp "$output/compliant/environment.json" "$output/valid/blocked/environment.json"
jq -c '(.legs[]|select(.detectorID=="D5")) |= (.verdict="BLOCKED"|.detectorAvailable=false|.command=[]|.exitStatus=null|.artifacts=[]|.blocker={blocked_by:"D5",detect_command:["fixture-detector","D5"],prerequisite:"supported karabiner_cli",unblock_action:"rerun on approved host"})|(.spikeResults[]|select(.spikeID=="SP-3"))|=(.verdict="BLOCKED"|.downstreamBlockIDs=["block.sp3"])|.downstreamBlocks += [{id:"block.sp3",blockedCapability:"Karabiner support",causedBy:["sp3.schemaLint","sp3.versionSample"],unblockAction:"rerun D5"}]' "$output/compliant/evidence.json" >"$output/valid/blocked/evidence.json"
jq -c '(.detectors[]|select(.id=="D5")|.available)=false' "$output/compliant/environment.json" >"$output/valid/blocked/environment.json"
blocked_environment_hash="$(shasum -a 256 "$output/valid/blocked/environment.json" | /usr/bin/cut -d' ' -f1)"
jq -c --arg hash "$blocked_environment_hash" '(.legs[]|.environmentSha256)=$hash|.selectedTapIdentity.environmentSha256=$hash|(.legs[]|select(.tapIdentity != null)|.tapIdentity.environmentSha256)=$hash' "$output/valid/blocked/evidence.json" >"$output/valid/blocked/evidence.tmp"
mv "$output/valid/blocked/evidence.tmp" "$output/valid/blocked/evidence.json"

cp "$output/compliant/environment.json" "$output/valid/g0-open/environment.json"
jq -c '(.detectors[]|select(.id=="D3")|.available)=false' "$output/compliant/environment.json" >"$output/valid/g0-open/environment.json"
open_environment_hash="$(shasum -a 256 "$output/valid/g0-open/environment.json" | /usr/bin/cut -d' ' -f1)"
jq -c --arg hash "$open_environment_hash" '(.legs[]|.environmentSha256)=$hash|.selectedTapIdentity.environmentSha256=$hash|(.legs[]|select(.tapIdentity != null)|.tapIdentity.environmentSha256)=$hash|(.legs[]|select(.legID=="sp2.secureInput"))|=(.verdict="BLOCKED"|.detectorAvailable=false|.command=[]|.exitStatus=null|.artifacts=[]|.blocker={blocked_by:"D3",detect_command:["fixture-detector","D3"],prerequisite:"Secure Input helper",unblock_action:"rerun on approved host"})|(.spikeResults[]|select(.spikeID=="SP-2"))|=(.verdict="BLOCKED"|.downstreamBlockIDs=["block.sp2"])|(.dispositions[]|select(.id=="O6"))|=(.status="OPEN"|.evidencePaths=[]|.blockerIDs=["block.sp2"])|.downstreamBlocks += [{id:"block.sp2",blockedCapability:"G0",causedBy:["sp2.secureInput"],unblockAction:"rerun D3"}]|.g0={status:"OPEN",sp1Verdict:"PASS",sp2Verdict:"BLOCKED",blockingLegIDs:["sp2.secureInput"]}' "$output/compliant/evidence.json" >"$output/valid/g0-open/evidence.json"

make_invalid unknown-leg unknown_leg_id '.legs[-1].legID="sp9.unknown"'
make_invalid unknown-field malformed_evidence '.unexpected="hostile but inert"'
make_invalid unknown-verdict malformed_evidence '(.legs[]|select(.legID=="sp3.schemaLint")|.verdict)="MAYBE"'
make_invalid missing-leg missing_leg_id 'del(.legs[-1])'
make_invalid duplicate-leg duplicate_leg_id '.legs += [.legs[0]]'
make_invalid unsupported-pass unsupported_pass '(.legs[]|select(.legID=="sp3.schemaLint")|.artifacts)=[]'
make_invalid incomplete-blocker incomplete_blocker '(.legs[]|select(.legID=="sp3.schemaLint")) |= (.verdict="BLOCKED"|.detectorAvailable=false|.command=[]|.exitStatus=null|.artifacts=[]|.blocker={blocked_by:"",detect_command:[],prerequisite:"",unblock_action:""})'
make_invalid evidence-kind-substitution wrong_evidence_kind '(.legs[]|select(.legID=="sp2.frontmostKnown")|.evidenceKind)="fixture"'
make_invalid live-substitution wrong_evidence_kind '(.legs[]|select(.legID=="sp3.schemaLint")|.evidenceKind)="live"'
make_invalid mixed-sp1-identity mixed_sp1_identity '(.legs[]|select(.legID=="sp1.autoRepeat")|.tapIdentity.attemptID)="other-attempt"'
make_invalid event-level-live live_event_data_forbidden '(.legs[]|select(.legID=="sp2.frontmostKnown")|.containsEventLevelData)=true'
make_invalid wrong-detector wrong_detector_id '(.legs[]|select(.legID=="sp3.schemaLint")|.detectorID)="D9"'
make_invalid invalid-verdict invalid_verdict_semantics '(.legs[]|select(.legID=="sp3.schemaLint")) |= (.verdict="BLOCKED"|.blocker={blocked_by:"missing",detect_command:["detect"],prerequisite:"tool",unblock_action:"install"})'
make_invalid inconclusive-disallowed inconclusive_not_allowed '(.legs[]|select(.legID=="sp3.schemaLint")|.verdict)="INCONCLUSIVE"'
make_invalid unmarked-event event_data_not_product_stamped '(.legs[]|select(.legID=="sp1.autoRepeat")|.containsEventLevelData)=true'
make_invalid false-product-stamp event_data_not_product_stamped '(.legs[]|select(.legID=="sp2.frontmostKnown")|.productStampedSynthetic)=true'
make_invalid reused-sp1-evidence reused_sp1_evidence '(.legs[]|select(.legID=="sp1.autoRepeat")|.artifacts[0].path)="artifacts/sp1.systemShortcut.json"'
make_invalid reused-sp1-bytes reused_sp1_evidence '(.legs[]|select(.legID=="sp1.autoRepeat")|.artifacts[0].sha256)=(.legs[]|select(.legID=="sp1.systemShortcut")|.artifacts[0].sha256)'
make_invalid unknown-o4 unknown_o4_id '.o4Rows[-1].id="unknown.axis"'
make_invalid missing-o4 missing_o4_id 'del(.o4Rows[-1])'
make_invalid duplicate-o4 duplicate_o4_id '.o4Rows += [.o4Rows[0]]'
make_invalid invalid-o4-xor invalid_o4_semantics '.o4Rows[0].blocker={blocked_by:"missing",detect_command:["detect"],prerequisite:"tool",unblock_action:"install"}'
make_invalid spike-aggregate spike_aggregate_mismatch '(.spikeResults[]|select(.spikeID=="SP-3")|.verdict)="FAIL"'
make_invalid duplicate-spike duplicate_spike_result '.spikeResults += [.spikeResults[0]]'
make_invalid missing-spike spike_result_set_mismatch 'del(.spikeResults[-1])'
make_invalid missing-downstream missing_downstream_block '(.legs[]|select(.legID=="sp3.schemaLint")|.verdict)="FAIL"|(.spikeResults[]|select(.spikeID=="SP-3")|.verdict)="FAIL"'
make_invalid incomplete-downstream incomplete_downstream_block '(.legs[]|select(.legID=="sp3.schemaLint")|.verdict)="FAIL"|(.spikeResults[]|select(.spikeID=="SP-3"))|=(.verdict="FAIL"|.downstreamBlockIDs=["block.sp3"])|.downstreamBlocks += [{id:"block.sp3",blockedCapability:"",causedBy:[],unblockAction:""}]'
make_invalid disposition-set disposition_set_mismatch 'del(.dispositions[-1])'
make_invalid invalid-disposition invalid_disposition '(.dispositions[]|select(.id=="O7")|.status)="CLOSED"'
make_invalid g0-mismatch g0_mismatch '.g0.status="OPEN"'
make_invalid invalid-provenance invalid_provenance '(.legs[]|select(.legID=="sp3.schemaLint")|.environmentSha256)="bad"'
make_invalid environment-binding environment_binding_mismatch '(.legs[]|select(.legID=="sp3.schemaLint")|.environmentSha256)=("a"*64)'
make_invalid detector-state detector_state_mismatch '(.legs[]|select(.legID=="sp3.schemaLint")|.detectorAvailable)=false'
make_invalid_environment detector-set detector_set_mismatch 'del(.detectors[-1])'
make_invalid hostile-path invalid_provenance '(.legs[]|select(.legID=="sp3.schemaLint")|.artifacts[0].path)="../../escape"'

mkdir -p "$output/invalid/malformed-json" "$output/invalid/missing-environment"
printf '{\n' >"$output/invalid/malformed-json/evidence.json"
cp "$output/compliant/environment.json" "$output/invalid/malformed-json/environment.json"
printf 'malformed_evidence\n' >"$output/invalid/malformed-json/expected-error.txt"
cp "$output/compliant/evidence.json" "$output/invalid/missing-environment/evidence.json"
printf 'missing_environment_manifest\n' >"$output/invalid/missing-environment/expected-error.txt"

rm "$rules"
