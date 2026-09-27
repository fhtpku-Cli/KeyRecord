# Network observation preparation — 2026-09-27

Base: PR #13 merge `6257b03b40f618fd976c6cbcc77dc83d374c59bb`.
This is tool preparation, not a product network receipt or Phase 1 acceptance.
The existing `Scripts/phase1-network-qa.sh` remains BLOCKED. No KeyRecord launch,
external network request, privileged capture helper installation,
TCC change, real-store or Keychain operation was performed for the initial nettop experiments. Subsequent capture results are recorded below.

## Latest state: synthetic delegated loopback observed by owner report

After the receiver-cleanup fix, the owner reported a successful eight-second
delegated loopback control. Four synthetic datagrams were sent and received;
the observer counted four outbound records with the sender as `proc` and the
target as `eproc`, plus four inbound receiver records. It reported eight
captured packets, zero drops, and no unparsed packet or unknown stderr line.
This establishes the prewritten control for one explicit `SO_DELEGATED` socket
pattern on this host. It is not a KeyRecord product observation or a general
delegated-process coverage guarantee. The aggregate counts are recorded below.

## Earlier bounded synthetic observer result

The owner supplied a third 20-second PKTAP pilot result after the metadata-only
line-shape revision. It reports observer readiness and exit 0, 20.07 seconds,
12 synthetic datagrams sent, receiver counts [4,4,4], 16 captured records and
zero kernel drops. All 16 packet lines parsed: each selected flow had four
outbound and four inbound observations, with zero unknown attribution or
unexpected parsed flow. The 17th output line was a complete whitespace-only line;
`packet_like`, `other`, and unterminated unparsed counts were all zero. These
values meet the prewritten bounded synthetic-observer criteria below. This is
owner-reported output; the agent did not operate privileged capture or retain
raw tcpdump text, and no shell transcript of the pre-sudo checks was supplied.
The earlier run's unidentified line remains unidentified, because its original
text was not retained. The new whitespace-only line does not retrospectively explain it.

The script still reports `outcome: inconclusive-attribution-not-validated` and
`product_pass: false` by design; it has no automatic PASS path. The assessment
above is a manual, bounded conclusion for two owned IPv4 loopback UDP flows on
this host and script revision. The aggregate counts do not prove one-to-one
packet pairing or coverage of other protocols, interfaces, process descendants,
or unattributed traffic. No KeyRecord network observation or zero-egress result
exists. The existing product wrapper remains BLOCKED. A future product round
needs a separately approved all-interface/process-scope controller; Phase 1,
Release and Intel qualification remain open. No immediate repeat of the same
synthetic pilot is warranted solely to revisit the historical missing line.

## Executed synthetic control

Run `ruby Scripts/fixtures/network-observer-control.rb --self-check` on macOS.
`--help` and no arguments only print help; other arguments fail before creating
processes or sockets. Arbitrary target PIDs are deliberately unsupported.

The script creates a receiver on an OS-assigned IPv4 loopback port, a synthetic
sender, and a separate idle process. It observes only the two owned PIDs through
`nettop -n -P -x -L 7 -s 1 -p PID -J bytes_in,bytes_out`. Both processes use the
same executable name, making PID distinction material. After two seconds the
sender writes 1,048,576 synthetic bytes and retains its socket while nettop exits.
A private temporary directory retains CSV and stderr for these processes, plus a
summary. It never logs socket destinations or payload bytes. Cleanup targets only
unreaped children owned by this invocation; the evidence directory is retained.

On macOS 27.0 (26A428), native arm64, the exploratory run and retained script both
produced the following observation:

| Control | Observed result | Interpretation |
| --- | --- | --- |
| Sender with known traffic | Receiver consumed 1,048,576 bytes; sender PID maximum bytes_out was 1,048,576 | Positive PID attribution worked for this long-lived loopback TCP socket |
| Idle process, no sockets | CSV contained headers but no process row | **Inconclusive**, not zero traffic proof |
| Monitor completion | Both nettop commands exited 0, stderr empty | Command success alone does not establish observation coverage |
| Invalid CLI argument | Nonzero exit before experiment | No implicit product/host mode |

A fresh run during this closeout again received 1,048,576 bytes and observed
1,048,576 sender bytes_out; the idle CSV still had no row. Both nettop exits
were 0. This repeats only the synthetic long-lived TCP control.

The script always reports `product_pass: false`. It rejects missed positive
traffic and rows attributed to another PID; an absent idle row is represented as
`no-row-inconclusive`. It does not claim periodic counters detect every short-lived
flow, all protocols, delegated network activity, or unknown attribution. The current
experiment establishes a limitation and a positive control, not a general monitor.
Raw self-check output is also retained locally under `.build/network-prep/`.

## Why nettop alone is insufficient

The no-socket control and a silently unobserved target could both produce no rows.
Therefore a future KeyRecord run with an empty CSV cannot pass zero-egress acceptance.
Static scanning is complementary but does not repair that observation gap. No zero
result is fabricated and the unavailable qualification wrapper is not enabled.

The installed `man tcpdump` documents PKTAP process metadata: `-k` supports process
name (N), PID (P), direction (D), and UUID (U); metadata filters have `pid`/`epid`.
It also says `pktap,all` includes loopback and tunnel interfaces. These are local
manual capabilities, not capabilities verified in a live capture. Merely filtering
by PID risks hiding packets whose attribution is missing, so absence after that
filter must not be promoted to whole-product proof.

## Pilot design recorded before the owner runs

First validate PKTAP with synthetic processes, **not KeyRecord**:

1. Prepare a 20-second, IPv4-loopback-only pilot using an OS-assigned port and
   owned sender/receiver. Retain the assigned PIDs and process start identities.
   Keep both alive for the observation; process exit/reuse or sleep interrupts it.
2. Restrict capture to loopback and the exact synthetic port(s). Within those
   flows retain unknown/missing PID metadata rather than discarding it with a PID
   filter. Add an owned decoy flow on a separate port to check exclusion, plus a
   short-lived synthetic flow to test whether attribution survives socket close.
3. Use fixed synthetic payload only. Do not write a raw pcap. A bounded controller
   must reduce observations to packet count, direction, PID/UUID presence and
   control association; retain capture drop/error counters. Do not persist payload,
   unrelated traffic, hostnames or user activity. tcpdump still inspects packets
   in memory, so this step is genuine capture and needs approval.
4. Establish observer readiness before sending; failure to see either positive
   control, missing process metadata, unexpected flow, observer failure, packet
   drops or incomplete cleanup makes the pilot invalid/inconclusive, never PASS.
5. Stop the owned observer normally at 20 seconds and verify its exit. Close/reap
   synthetic processes and sockets. No network filter installation, system
   configuration change, sleep prevention, KeyRecord launch or ambient input.
   Do not automatically invoke sudo; any needed system authentication stays with
   the owner and only occurs after the capture scope is approved.

The controller was subsequently implemented and owner-approved; see chronological results below. These design requirements are not all validated capabilities.

## Eventual product round, conditional on a valid observer

Only after attribution controls succeed, prepare one separate isolated, signed,
marked Debug trial and a short launch → idle → permitted input → Quit sequence.
Publish the exact build, process/descendant scope, observation interval, expected
owner actions and restart branch first; obtain explicit approval for product capture
and any Keychain/permission operations. User replies should be needed only at the
end or on a documented exceptional branch.

A bounded result can say “no attributed outbound packets observed in this interval”
only with valid controls and no drop/error/identity gaps. Unattributed or delegated
traffic needs separate accounting and cannot silently become zero. Debug results
cannot qualify Release, and universal compilation cannot qualify native Intel.
Do not schedule another long performance or permission round as part of this work.

## Approved pilot attempt — blocked by system capture permission

After owner approval, `Scripts/fixtures/pktap-loopback-pilot.rb --run` attempted
only `pktap,lo0`, IPv4 UDP, both loopback endpoints and two ephemeral destination
ports reserved by the synthetic receivers. The decoy destination is excluded.
Limits: 20 seconds after readiness, 512 packets, 256-byte snapshot, 64 KiB combined
observer output budget; no raw pcap or tcpdump text persisted. It never invokes
sudo. Output is aggregate JSON, always `product_pass:false`; PID mentions are
exploratory, not validated attribution. There is deliberately no PASS exit path.

The host denied capture access: observer exit 1, readiness false, zero observed
lines, no capture interval. The first attempt exposed an EOF bug in synthetic
control cleanup (pipe closure could trigger send); that attempt is invalid and its
zero `packets_sent` field must not be relied upon. Send now requires an explicit
`send` command. On the corrected permission-denied attempt all three receiver
counts were zero, stdout had zero lines and all owned children were reaped.
Evidence: `.build/network-prep/pktap-pilot.json` (invalid initial cleanup) and
`pktap-pilot-retry.json` (permission-blocked corrected attempt).

No administrator elevation, device permission change or KeyRecord launch occurred.
At that point the privileged capture path was unexecuted; the owner subsequently ran it as recorded below. An owner-run administrator command
is needed to continue the already-approved bounded scope; do not change /dev/bpf
permissions or install a persistent helper. A successful capture alone would still
need output/attribution assessment before it can support any product trial.

## Owner-reported capture and offline follow-up

The owner supplied a 20.03-second pilot result: observer ready, exit 0, 12 packets
sent, receivers [4,4,4], captured 16, kernel drops 0, output lines 17, numeric PID
mentions [4,4,0]. PIDs: 16560/16574/16579; destination ports: 57786/58092/49310.
This is owner-reported evidence, not an agent rerun. Outcome remains
`inconclusive-attribution-not-validated`, `product_pass:false`. The old search
matched numbers anywhere, not actual PID fields. No raw stdout was retained;
the extra observations/line cannot now be explained or reclassified.

The revised pilot requests `-k PD` only. `pktap-attribution.rb` checks actual
`proc` PID (not `eproc`), exactly one direction, complete loopback UDP lines,
expected destination ports and the fixed 17-byte length. Outbound PID must match
the corresponding sender; inbound PID must match the receiver. Missing/ambiguous
metadata, unexpected flows and unparsed lines have separate counts. Observations
are never silently deduplicated into datagrams. No packet text is serialized and
there is still no PASS path, even when aggregate counts look correct.

The grammar follows `print_pcap_ng_procinfo` and direction printing in Apple's
[tcpdump source](https://github.com/apple-oss-distributions/tcpdump/blob/main/tcpdump/tcpdump.c).
This source lookup does not validate output from the installed Apple 161 binary.
Unknown output is deliberately not guessed or discarded.

Offline checks: `ruby Scripts/fixtures/pktap-attribution-test.rb` passed 8 tests,
23 assertions. Constructed fixtures cover PID/port confusion, effective PID,
missing and duplicate fields, truncation, foreign flows, decoy and duplicate
observations. These are not a replay of the owner capture. Syntax, help and invalid
CLI arguments were checked without capture. No new product launch, packet capture,
authentication, real statistics or Keychain operation occurred in this follow-up.

At this point in the chronology, native output and actual attribution still needed
a short synthetic run. The subsequent owner-run result appears below. Product
network observation and Phase 1 acceptance remained unavailable.

## Owner-reported field-parser pilot (2026-09-27)

A second owner-run 20.0-second capture reported ready=true, observer exit=0,
12 synthetic datagrams sent and receivers=[4,4,4]. PIDs were
26853/26858/26863; destination ports were 64267/57192/56207.
The observer reported 16 captured records, zero kernel drops and 17 output lines.
The strict reducer parsed 16 packet records: outbound=[4,4], inbound=[4,4],
unknown_attribution=0, unexpected_flow=0, unparsed_lines=1.

This establishes positive PID/direction/port attribution for both selected
synthetic flows in this run, including the sender that closes its socket after
sending. The excluded decoy receiver got four datagrams, with no decoy flow in
the parsed records. The 16 parsed observations have the expected directional
breakdown for eight selected datagrams; this is aggregate consistency, not
individual packet pairing or a general completeness guarantee.

One output line remains unidentified. Its text was not retained, so it cannot
be declared harmless, blank, a warning or an additional malformed packet.
The result remains inconclusive for the complete observer and product_pass=false.
No additional capture was started in response to this report. Next preparation
should classify otherwise-unparsed lines in memory into bounded metadata-only
categories (blank / packet-like / other), without ignoring any category or
persisting packet text. This gap does not justify another immediate owner run.
The product wrapper stays BLOCKED; no KeyRecord zero-egress claim is supported.

## Offline line-shape diagnostics completed

The reducer now adds `unparsed_categories` (blank / packet_like / other), whose
sum equals `unparsed_lines`, plus `unterminated_unparsed_lines` as an overlapping
truncation indicator. Blank requires a complete newline-terminated whitespace
line. Packet-like is a conservative shape hint, not a guarantee that all malformed
packets fall in that category. Other is not assumed harmless. No source text,
substring, payload, address or process name is retained by these new fields.
All unparsed lines remain in the original total; no category grants PASS.

Offline verification: 11 tests / 41 assertions passed, pilot syntax and help
passed, and a direct reducer invocation with one constructed packet plus a blank
line produced one outbound observation and one unparsed blank. No capture ran during that offline change.
The owner-reported historical extra line remains unidentified: these diagnostics
cannot be applied retroactively without its original text. The final bounded
synthetic check below combines the remaining diagnostic needs in one run.

## Final synthetic observer check: procedure and owner result

Before the owner result, the unprivileged controller path was run again: tcpdump exited
1 with permission denied before readiness, zero control packets sent, zero
receiver packets, and all owned PIDs reaped. No packet was captured. The local
manual confirms `-k PD` selects PID and direction metadata. Offline reducer
tests, CLI syntax/help/invalid arguments, and the nettop positive control have
been rerun. At that point, the one remaining diagnostic was a privileged bounded
capture with the line-shape counters; the owner-supplied result is recorded below.

Because `sudo` executes a Ruby file from a writable worktree, first compare
`rev-parse HEAD` with the reviewed commit ID in the handoff and confirm the
following `status` command prints nothing. Run these checks immediately before
the pilot, from the same trusted checkout; if the commit differs or either script
is modified, stop and request a new review of those exact files. This is a
security-boundary check for root execution, not a product acceptance gate.

```sh
git -C /Users/bytedance/.codex/worktrees/secure-input-evidence/KeyRecord rev-parse HEAD
git -C /Users/bytedance/.codex/worktrees/secure-input-evidence/KeyRecord status --short -- Scripts/fixtures/pktap-loopback-pilot.rb Scripts/fixtures/pktap-attribution.rb
sudo /usr/bin/ruby /Users/bytedance/.codex/worktrees/secure-input-evidence/KeyRecord/Scripts/fixtures/pktap-loopback-pilot.rb --run
```

Expected scope: three owned sender processes, three owned loopback receivers,
12 fixed 17-byte UDP datagrams, and a 20-second tcpdump on `pktap,lo0` limited
to the two selected receiver ports. The third port tests exclusion. The script
retains no raw packet line or pcap and never calls sudo itself. It reports
`product_pass:false` and exits nonzero even when the synthetic counts are
consistent, so the JSON must be read rather than treating shell status as a
product result. Administrator authentication is the owner's local terminal step;
no password is needed in the report.

For this pilot to support a *bounded synthetic-observer validation*, require
observer readiness, a full 20-second interval, exit 0, 12 sent and [4,4,4]
received, 16 captured records, zero kernel drops, 16 parsed packets, outbound
[4,4] and inbound [4,4], zero unknown attribution and unexpected parsed flow,
and zero `packet_like`, `other` and unterminated unparsed lines. A complete blank
line may explain the 17th output line, but it is still counted and reported.
Any different result stays inconclusive; do not discard a category, invent a
reason for the historical line, or infer individual packet pairing from totals.
Even a matching result validates only these synthetic flows on this host and
version. The existing product network wrapper remains BLOCKED.

### Owner-supplied run after the line-shape revision (2026-09-27)

The owner returned aggregate JSON with `product_pass:false` and the fixed
`inconclusive-attribution-not-validated` outcome. It reported ready=true,
exit=0, signal=null, permission_denied=false, capture_seconds=20.07,
packets_sent=12, receiver counts=[4,4,4], captured_count=16,
kernel_drop_count=0 and output_lines=17. The reducer reported
parsed_packets=16, outbound=[4,4], inbound=[4,4], unknown_attribution=0,
unexpected_flow=0, unparsed_lines=1, categories blank=1 / packet_like=0 /
other=0, and unterminated_unparsed_lines=0. Thus the one additional line in
**this** run was a complete whitespace-only line; no unparsed packet-like or other line
was reported. The old run's unmatched line has no recoverable classification.
No raw tcpdump output, pcap, password or pre-sudo shell transcript was supplied.

This meets the previously written criteria for bounded synthetic-observer
validation on the two selected IPv4 loopback flows. It does not independently
verify each observed packet against an emitted datagram, prove zero packets
missed outside this filter, or qualify a product observation. The static
`outcome` string remains pessimistic and should not be read as a new automated
PASS. No more owner capture is needed to close this tool-preparation round.

## Product observation candidate prepared after PR #14 merge

Source is `c367a0026c9df0c44d65290121b66d1c3577e774` plus the separate
`codex/product-network-observation` controller change. The product source is
unchanged. A separate arm64 Debug App was built with Apple Development signing at
`/private/tmp/keyrecord-network.7yjmhZ/DerivedData/Build/Products/Debug/KeyRecordApp.app`.
Its bundle ID is `com.keyrecord.trial.network20260927`, and its signed Info.plist
has `KeyRecordRequiresTrialIsolation=true`. The host's normal trust settings
passed strict code-signature verification. `--check` passed without product launch
or capture. This is a prepared candidate, not a network result.

A signed Release negative control from the same Git commit, with the same version
`1`, a `com.keyrecord.trial.*` bundle ID and the same isolation marker, passed the
initial `--check` preflight. It was never launched. Source inspection shows that
Release compiles out the Debug trial selector and uses the production composition.
Git commit, bundle version, bundle ID, signing, ordinary source tests and the
marker therefore do not establish the isolation code selected in the **built**
App. Before any host launch, the controller checks that the executable loads the
Debug dylib containing `DebugTrialIsolation` and `makeTrial`. This narrow build
structure check protects the real-data boundary; it is not a Phase 1 gate or a
claim that future code changes are automatically safe.

`Scripts/product-network-observe.rb` is an owner-started controller with a
75-second deadline beginning when it spawns tcpdump, after local authentication.
Authentication and bounded cleanup add time outside that observation deadline.
Only the system `/usr/sbin/tcpdump` runs through `sudo`; Ruby and the product run
as the normal console user. The controller rejects root execution and clears
inherited dynamic-library injection variables before launching the App. The
exact capture is `pktap,all`, no BPF filter,
`-k PD`, 256-byte snapshots, maximum 50,000 records. The local tcpdump manual
describes `pktap,all` as including loopback and tunnel interfaces. This has not
been verified for this product run. The controller starts capture before the App,
sends and receives four fixed loopback UDP control datagrams, launches the
isolation-marked App directly, leaves ten seconds idle, allows a few agreed
shortcuts in a normal non-sensitive text window, and observes through normal
menu Quit to the fixed deadline. It never blocks sleep. A still-running App is
left for normal manual Quit and the observation is invalid.

The capture necessarily sees packets from other host processes. Tcpdump and Ruby
handle up to 256 bytes of each captured packet and decoded output **in memory**;
no pcap, packet line, payload, address, hostname, process name or other-process
PID is saved. The private `0700` result directory contains a `0600` aggregate
receipt, a dedicated trial statistics store, and the product's numeric Debug
summary. The trial namespace is newly random for each run; ordinary HOME is
retained, `CFFIXED_USER_HOME` and inherited `KEYRECORD_*` preview variables are
cleared. No real store is read or copied by the controller, and no Keychain item
is removed. The App's existing trial selector rejects a missing isolation pair,
including an OS relaunch without the variables.

The output counts all observed packet lines by broad protocol family and counts
product `proc` PID, product `eproc` PID on a different `proc` PID, unknown
PID/direction, and other-process observations separately. The `eproc` count
overlaps the other-process count and must not be added to the packet total.
The App is kept as an unreaped child until capture stops, preventing its PID from
being reused inside the window. An exit before the ten-second idle timer elapses
invalidates the run. The timer is an instruction to the owner, not independent
proof that no input occurred in those ten seconds. A positive loopback control,
observer readiness, complete window, zero kernel drops, complete parse/statistics,
normal product exit, elapsed idle timer and positive aggregate input are required
for a bounded observation. A timeout, sleep, control failure, parse gap, missing summary,
capture error or product startup failure is invalid. There is no automatic
product PASS: even zero attributed outbound observations cannot rule out
unattributed packets, a delegated system request, or capture outside this host,
interface and time window. The script always reports `product_pass:false`.
The Phase 1 network wrapper remains BLOCKED.

The command used for the approved first attempt was:

```sh
ruby /Users/bytedance/.codex/worktrees/product-network-observation/KeyRecord/Scripts/product-network-observe.rb \
  --app /private/tmp/keyrecord-network.7yjmhZ/DerivedData/Build/Products/Debug/KeyRecordApp.app \
  --seconds 75
```

Before starting, the owner should close any running KeyRecordApp and leave a
normal unsaved TextEdit window available. The command checks that no KeyRecordApp
is running, verifies the signed trial identity and isolation marker, then asks
for administrator authentication in the owner's own Terminal. The password is
never sent to the agent. The owner stays in the test flow: wait for the terminal's
idle-complete message, enter a few agreed non-sensitive shortcuts in TextEdit,
then choose **Quit KeyRecord** from the trial menu before the 75-second window
ends. No chat reply is needed mid-run. If macOS prompts for test-App input
permissions or requires restart, stop the run, Quit the trial normally and
report the prompt. A repeat needs fresh approval and a fresh trial store and
namespace. Do not grant broad new permissions, reset TCC/Keychain, or relaunch
the test App without explicit isolation. If any unexpected system dialog
appears, leave the product untouched and report the prompt after the window.
Do not type into password or private-data fields.

The controller does not install a helper, change `/dev/bpf` permissions, alter
filters, intercept TLS, or touch the daily App. This Debug observation will not
qualify Release, Intel, or Phase 1. The first run and its limits are recorded below.

## First approved product attempt: invalid observation (2026-09-27)

The owner ran the approved 75-second command. The private aggregate receipt is
`/private/tmp/keyrecord-network-20260927-82962-yz83r/receipt.json`; no raw packet
capture or decoded packet lines were retained. The observer was ready for 74.99
seconds, completed its window and exited 0. The four loopback controls were each
observed in both directions, 22,797 packet records parsed, and tcpdump reported
zero kernel drops. The trial App exited normally. The reducer recorded 533
unattributed packet observations and 22,256 observations for other processes;
these aggregate counts do not establish delegated-process coverage.

The trial App's numeric summary recorded zero key callbacks, zero normalized
output, zero aggregate delta and no live capture session at termination. Its
trial store was not populated. The owner reported that the App showed **blocked**
before the TextEdit input. This is consistent with the fresh trial remaining
at its first-run consent/Start step; the handoff instructed input after the idle
interval without instructing the owner to confirm **Collecting**. The exact
reason shown in the menu and whether a permission prompt appeared were not
reported. The observer's combined stderr also contained one line
outside the controller's recognized diagnostic categories. Its content was not
retained and cannot be reclassified after the run.

`outcome=invalid` and `product_pass=false` are correct. Zero packets attributed
to the trial PID here do not support a product no-egress claim because the App
did not demonstrate input collection and the observer diagnostic is unresolved.
No Phase 1, Release or Intel gate changes follow from this attempt. A later
product attempt would need a fresh approval and an explicit first-run Start and
consent step, followed by a visible Collecting/live-session check before the
short TextEdit inputs. If a permission or restart prompt appears, stop that
attempt and report it before any repeat.

## Same-scope retest preparation (2026-09-27)

The owner requested a new run after the invalid attempt. The controller now
distinguishes complete whitespace-only tcpdump stderr lines from unrecognized
diagnostics; the latter still invalidate the result. Its launch message now
instructs the owner to choose **Start** in the trial App menu, accept first-run
local aggregation consent, and confirm a visible **Collecting** state. After
Collecting, leave the App idle for ten seconds, enter only the agreed short
non-sensitive shortcuts in TextEdit, and Quit from the App menu within the
75-second capture window. If it stays Blocked, or a permission/restart prompt
appears, stop input, Quit normally and report the status. No raw packet or
diagnostic text is retained. Each invocation creates a new private trial store
and Keychain namespace; the preceding empty trial store is not reused.

The non-launching signed Debug `--check` passed and no KeyRecordApp process was
running at preparation time. These checks do not establish that the next App
launch will collect input or that the observer's unknown diagnostic was blank.
The next receipt must still meet every existing validity condition before any
bounded product network statement can be made.

Before the retest launch, source inspection found that first consent would
otherwise attempt `SMAppService.mainApp.register()` after capture starts. The
dedicated Debug trial now uses a backend that rejects registration and performs
no system unregister action. Ordinary Debug and Release still use the product
login backend. A focused App test failed before this selection was implemented
and then passed 1/1; the existing lifecycle test establishes that rejected
login registration leaves capture in Collecting. The new arm64 Debug trial was
built and signed at the path below. Its isolation marker and `--check` passed;
the host run and its result are recorded below.
The focused test result is retained at
`/private/tmp/keyrecord-network.7yjmhZ/RetestBuild3/Logs/Test/Test-KeyRecordApp-2026.09.27_05-56-00-+0800.xcresult`.

```sh
ruby /Users/bytedance/.codex/worktrees/product-network-observation/KeyRecord/Scripts/product-network-observe.rb \
  --app /private/tmp/keyrecord-network.7yjmhZ/RetestBuild3/Build/Products/Debug/KeyRecordApp.app \
  --seconds 75
```

## Same-scope product retest: invalid observation (2026-09-27)

The owner ran the 75-second command above. The private aggregate receipt is
`/private/tmp/keyrecord-network-20260927-94144-9eo14u/receipt.json`. The
observer was ready for 74.95 seconds, completed its full window and exited 0.
It parsed 17,247 packet records with zero kernel drops and zero unparsed lines.
All four loopback controls were observed in both directions. The trial App
exited 0; its numeric summary showed an aggregate delta of 5 and 7 durable
flushes. These numbers support that this trial recorded input activity, but do
not identify keys. The owner separately confirmed that the App visibly reached
**Collecting** and showed no unusual permission or restart prompt.

The observer counted zero packets attributed to the trial PID in either
direction, 690 unattributed observations and 16,549 observations for other
processes. Delegated-process coverage is still unverified. One nonblank
observer stderr line did not match the controller's recognized diagnostics.
The line was deliberately not retained, so its meaning cannot be determined
afterward. The receipt therefore reports `outcome=invalid` and
`product_pass=false`. The zero attributed outbound count is only an
observation within this capture and cannot qualify the product network gate.
No Phase 1, Release or Intel acceptance status changes follow from this run.

Final review of the controller found a separate fail-closed gap: a nonempty
stderr fragment without a trailing newline was not part of the receipt's
validity check. The controller now records only its byte count and invalidates
such a run. A synthetic test covers this case. This correction does not alter
either historical receipt; both were already invalid from complete nonblank
unclassified diagnostics. The trial-login test now checks the actual
`ProductComposition.systemBoundaries` selection, rather than calling the login
factory alone.
The focused wiring test passed 1/1 after this change; its result is at
`/private/tmp/keyrecord-network.7yjmhZ/RetestBuild4/Logs/Test/Test-KeyRecordApp-2026.09.27_06-08-00-+0800.xcresult`.
The controller's three focused tests passed with 16 assertions.

## Offline stderr diagnosis and third host observation

Both earlier product receipts retained only one unclassified stderr-line count,
so the historical lines cannot be reconstructed. The controller combines stderr
from `sudo` and `/usr/sbin/tcpdump`, so the producer of an unclassified line is
also unknown. The installed `/usr/sbin/tcpdump`
reports version 4.99.1, Apple 161. Its binary contains templates for metadata
filter drops, interface drops, compression statistics and warnings; Apple's
[tcpdump source](https://github.com/apple-oss-distributions/tcpdump/blob/main/tcpdump/tcpdump.c)
shows these can be separate stderr lines after the usual packet totals. None is
proven to be the line emitted in either product run. Treating that line as
harmless would risk overlooking packet loss or a capture warning.

The controller now categorizes these four families in memory and writes only
fixed category counts or the maximum reported drop count to the private
aggregate receipt. It retains no diagnostic text. Any positive category,
unclassified line or unterminated stderr fragment still invalidates the
observation; the existing no-automatic-product-PASS rule remains. Synthetic
stderr tests pass 4 tests and 36 assertions. This was an offline discriminator
for a later run, not a reinterpretation of either historical receipt. No
tcpdump capture, product launch, permission change or Keychain operation was
performed during that diagnostic preparation.

The owner separately approved a third 75-second host observation on
2026-09-28. The private aggregate receipt is
`/private/tmp/keyrecord-network-20260928-21828-o4e8sj/receipt.json`.
The observer was ready, completed 74.99 seconds and exited 0. It parsed 24,090
packet records with zero kernel drops, zero unparsed lines and all four loopback
controls in both directions. The trial App exited 0; its numeric summary showed
an aggregate delta of 6 and 10 durable flushes. This supports that the trial
recorded input activity but does not identify keys or establish a visible UI
state. The observer counted zero packets attributed to the trial PID in either
direction, 516 unattributed observations and 23,566 observations for other
processes. Delegated-process coverage remains unverified.

All four newly recognized diagnostic categories were zero, but one complete
nonblank observer stderr line was still unclassified. Its text was deliberately
not retained, so the cause cannot be recovered from this run. The receipt
correctly reports `outcome=invalid` and `product_pass=false`. No product
zero-egress claim or Phase 1, Release or Intel qualification follows. Another
live attempt would require its own scoped owner approval; the unknown diagnostic
first needs a privacy-preserving way to identify its cause.

## Offline stderr visibility follow-up after the third run

The third receipt ruled out the four guessed tcpdump diagnostic families for
that run, but it did not reveal the unclassified line. The controller also
combines `sudo` and tcpdump stderr, so the line's producer cannot be inferred
from the existing receipts. This offline change involved no fourth host run.

The controller now counts recognized routine stderr status lines and, for
unclassified lines, records only a fixed prefix class (`sudo:`, `tcpdump:`,
`pcap_stats:`, or other) and the phase in which the line was **read** (before
ready, while collecting, or while draining at shutdown). These labels do not
claim which process produced the line or when it was emitted. No diagnostic
text, prefix substring, address, path, or hash is retained. An unknown line
continues to make the receipt invalid, and `product_pass` remains false.
The observer reaches ready only on a complete expected `pktap,all` listening
line; a malformed lookalike stays unknown. Synthetic tests cover canonical
startup/footer status, warnings, unknown prefixes and phases, text nonretention,
and malformed readiness: 7 tests and 52 assertions pass. CLI help and invalid
argument paths were also exercised. This was offline only: no App launch,
sudo, tcpdump, packet capture, or permission operation occurred. The new
metadata can narrow a future investigation but cannot guarantee identification
of arbitrary stderr text; any host diagnostic needs its own reviewed scope.

## Proposed local-only stderr diagnosis (prepared, not run)

`Scripts/fixtures/pktap-stderr-diagnose.rb` prepares one narrower observation
of the `sudo` → tcpdump stderr path. Its safe `--check` does not authenticate or
capture. A separately approved `--run` would be started by the owner in their
Terminal. Ruby remains unprivileged; only system tcpdump is launched through
`sudo`. Authentication through `sudo -v` may print a prompt or diagnostics
directly in Terminal before `REVIEW`, may remain in Terminal scrollback, and
refreshes the user's sudo credential cache. The helper observes `pktap,lo0`
for at most eight seconds after readiness, with a five-second readiness
timeout and a BPF filter limited to
IPv4 UDP from/to 127.0.0.1 and one reserved ephemeral receiver port, a
256-byte snapshot length, and a 64-packet cap. It sends four fixed synthetic
datagrams, starts no KeyRecord App, and does not touch the trial or daily store,
Keychain, TCC, or login items. This is still a real host packet capture and
needs specific owner approval before `--run`.

Decoded packet stdout is counted and discarded in memory. The observer's
combined sudo/tcpdump stderr is held only in memory, capped at 8192 bytes,
and is not written to a file or included in the aggregate JSON printed to
Terminal. After the observer has stopped and
its process is reaped, an interactive owner may type `REVIEW` to display
escaped stderr lines in their **local Terminal only**. Those lines may contain
hostnames, paths or other sensitive details; Terminal scrollback may retain
them. Pressing Return skips display. The owner should share only a reviewed,
redacted description if useful, not the raw lines. The helper has no product
PASS outcome, saves no pcap or packet text, and does not transmit the stderr.

This probe tests the narrower loopback path and may not reproduce a message
specific to `pktap,all` or the longer product run. Even if the same text appears,
the combined pipe cannot conclusively attribute an unprefixed line to `sudo`
or tcpdump. If the line is absent or the owner skips local review, the
historical cause remains unknown; there is no automatic repeat or promotion of
the three invalid product receipts. Offline checks at this commit were:
`ruby -w -c Scripts/fixtures/pktap-stderr-diagnose.rb` → `Syntax OK` (exit 0),
`--help` → usage (exit 0), `--check` → `outcome: prepared` and
`product_pass: false` (exit 0), and `--invalid` → usage (exit 1). At that
preparation point, its `--run` path had not been executed on the host.

## Owner-approved loopback diagnosis: readiness line mismatch

In the separately approved loopback run on 2026-09-28, the owner reviewed
three local observer stderr lines and shared their routine status shapes. The
listening status began with `listening on pktap,lo0` rather than
`tcpdump: listening on pktap,lo0`. The aggregate output reported
`outcome=inconclusive`, `product_pass=false`, `observer_ready=false`, zero
controls sent or received, three stderr lines, zero packet-output bytes, and
`error_type=RuntimeError`. It reported no captured count or kernel-drop count.
The helper's strict readiness expression required the `tcpdump:` prefix, so
it did not recognize the observed listening status and did not send controls.
This run cannot classify product traffic or qualify any gate.

The product observer had the same prefix assumption in its newer, previously
unrun strict-readiness revision. Both expressions now accept the complete
expected listening status with or without `tcpdump:`, while still rejecting
malformed lookalikes. A regression test using the observed status shape failed
before the correction and passed afterward; the focused suite passed 7 tests
and 55 assertions. Ruby syntax and noncapturing CLI checks also passed. At
that point, the corrected `--run` paths remained unverified on the host. The
unprefixed line is a plausible explanation for an unclassified line in the
three earlier product receipts, but their raw stderr was deliberately not
retained. Its historical identity is unproven, and all three receipts remain
invalid.

## Corrected short loopback diagnosis completed

In the separately approved repeat, the owner reported aggregate output from
the corrected `pktap,lo0` helper: `outcome=diagnostic-complete`,
`product_pass=false`, `observer_ready=true`, four controls sent and received,
8.04 seconds after readiness, observer exit 0, eight captured packets and zero
kernel drops. It counted 565 decoded stdout bytes across nine lines and six
observer stderr lines; packet and stderr text were not provided for this
repeat. This verifies that the corrected short helper reached readiness,
exercised its synthetic loopback controls and stopped normally on this host.
The helper did not classify those six stderr lines, so completion does not
establish that all observer diagnostics were routine.
The helper does not parse product PID or delegated-process attribution. No
KeyRecord App was launched, and this result does not validate the corrected
75-second product observer, establish zero egress, or change any of the three
invalid product receipts. A future product observation needs its own scope and
owner approval.

## Offline effective-process attribution review

Apple's [tcpdump source](https://github.com/apple-oss-distributions/tcpdump/blob/main/tcpdump/tcpdump.c)
prints `proc` and `eproc` separately when process metadata is requested. Apple's
[PKTAP header](https://github.com/apple/darwin-xnu/blob/main/bsd/net/pktap.h)
defines the effective PID and a process-delegated flag. The product observer's
`-k PD` output can therefore expose a candidate relationship in which the
packet's `proc` differs from the product's `eproc`. Previously the reducer
accepted but ignored `eproc`, so such an observed outbound packet could have
been reported as only another-process traffic.

The reducer now counts that relationship separately by direction, using only
aggregate counts in the receipt. An outbound `eproc` match gets the explicit
`effective-product-outbound-metadata-observed` outcome if there is no direct
product `proc` outbound observation. `product_pass` remains false. The
`delegated_process_coverage` field remains `unverified`: an absent `eproc`
match cannot prove that all delegated traffic was observable or attributable.
The source scan in `PrivacyEgressTests.swift` covers product Swift files under
`Sources` and `App/KeyRecordApp`; it found no explicit network or process API
in those files, but cannot establish how system services attribute all traffic.

Offline verification: `ruby Scripts/product-network-observe-test.rb` passed
9 tests and 64 assertions; `ruby -w -c Scripts/product-network-observe.rb`
reported `Syntax OK`; `git diff --check` passed. These are reducer checks, not
a host packet capture or a product network result. The next product trial still
requires a separately approved bounded run with visible Collecting state and
valid observer and input aggregates.

The proposed two-process loopback control has a privilege boundary. Apple's
[socket header](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/socket.h)
defines `SO_DELEGATED`, and its
[socket implementation](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/uipc_socket.c)
requires `PRIV_NET_PRIVILEGED_SOCKET_DELEGATE` to set a different effective
PID. A normal-user sender cannot be assumed to create this control. The
previous owner approval elevated only tcpdump, so it does not authorize an
elevated sender. No delegation option, new privilege, or capture was tried in
this review. The product source scan found no existing XPC/network sender to
reuse as a natural delegated control. A separately reviewed privileged sender
would widen the scope of a future synthetic test; even a successful control
would validate only that specific mechanism, not complete system-service
attribution. A zero product `eproc` count therefore leaves delegated coverage
unverified.

The noncapturing `Scripts/fixtures/pktap-effective-metadata-offline.rb` check
generates one fake Ethernet/IPv4/UDP packet in a temporary PCAPNG file with
Apple process-information blocks for two fixed synthetic PIDs. It invokes the
installed tcpdump with `-r -k PD`, then feeds the decoded line to the product
reducer. The temporary file is removed on exit; neither sudo nor a live
network interface is used. On this host it reported tcpdump exit 0, the
expected distinct `proc`/`eproc` fields, one parsed outbound effective-PID
observation, and zero unparsed lines. This establishes the installed printer
and reducer's format compatibility for synthetic metadata. It cannot test
whether the kernel labels any real delegated flow, whether a normal process
may set `SO_DELEGATED`, or whether system services cover all traffic.

## Delegated loopback control: host runs

`Scripts/fixtures/pktap-delegated-loopback.rb --check` reports `prepared`
without sudo, sockets, capture or product launch. Its separately approved
`--run` path authenticates the owner in Terminal, keeps a normal-user
target process alive, and elevates **two** fixed programs: system tcpdump and
`Scripts/fixtures/pktap-delegated-sender.rb` under system Ruby. The sender
sets `SO_DELEGATED` to that target PID and sends four fixed 17-byte UDP
datagrams to one ephemeral receiver bound to 127.0.0.1. The observer
captures only IPv4 UDP on `pktap,lo0` with both endpoints 127.0.0.1 and that
destination port, for eight seconds after readiness, with 256-byte snapshots
and a 64-packet cap. No KeyRecord App, trial store, Keychain, TCC or external
endpoint participates. This is a root sender plus a real host packet capture.

The owner ran the approved command once and supplied a terminal traceback:
`finish` called `recv_nonblock` on an already closed receiver socket, raising
`IOError: closed stream`. The controller closed the receiver before invoking
`finish`. No aggregate JSON was emitted, so this round is inconclusive; it
does not establish that the sender ran, any packets were captured, or any
delegated metadata was observed. The controller now closes the receiver after
`finish`, including if finalization raises. An offline test exercises that
cleanup order with a fake socket and no sudo or network.

The owner then ran the fixed script once and supplied the aggregate JSON.
It reported `outcome=synthetic-delegation-observed` and `product_pass=false`.
The observer reached readiness, completed 8.05 seconds after readiness and
exited 0; the sender exited 0. Four controls were sent and received. Among
eight parsed packet lines, `delegated_out=4`, `receiver_in=4`, and
`other_packet_lines=0`. The observer reported eight captured packets and zero
kernel drops. It counted one complete blank line, six classified stderr lines,
zero unparsed lines, zero unknown stderr lines, and zero unterminated packet
bytes. The agent did not operate tcpdump or receive raw packet or stderr text.
These aggregate values meet the prewritten synthetic criteria for this one
explicit socket-delegation path. They do not validate the product observer,
establish zero egress, qualify all delegated system traffic, or change the
three invalid product receipts.

The controller retains decoded packet lines and sudo/tcpdump diagnostics in
bounded memory, then emits only counts and error types. It writes no raw
capture, packet text, address, port or PID to the result. A successful
synthetic outcome requires four matching `proc=sender`/`eproc=target`
outbound observations, four receiver-side inbound observations, four received
controls, a complete window, zero drops and no unparsed or unknown lines.
Whitespace-only output lines are counted separately from packet records.
It always reports `product_pass:false`; even a successful run would validate
only this explicit socket-delegation path. Sudo authentication may print to
Terminal and refresh the credential cache. A denial of `SO_DELEGATED` is
reported as a blocked synthetic control, not as product evidence.

Offline checks: Ruby syntax passed for both scripts; the controller's
`--check` reported `prepared` without capture; three tests passed with
16 assertions, including the receiver cleanup regression; the sender's
`--help` and invalid-argument paths behaved as expected; `git diff --check`
passed. The fixed root sender and live capture path has one owner-reported
successful aggregate result; product attribution remains unverified.

## Current product preflight after delegated control (2026-09-28)

Before proposing another product run, the existing controller passed its nine
offline tests with 64 assertions. The original `DerivedData` App path in the
first-run instructions above now fails strict host signature verification with
`invalid Info.plist (plist or signature have been modified)`; its current
`--check` result is `invalid`. The `RetestBuild4` App verifies on disk but lacks
`KeyRecordRequiresTrialIsolation`, so its `--check` also fails. No product
capture was started during these checks.

The existing `RetestBuild3` Debug App verifies under host trust settings and
passes the controller's `--check` without sudo, capture, or launch. The check
reports `outcome=prepared`, bundle ID `com.keyrecord.trial.network20260927`,
and `product_pass=false`. It checks the signed isolation marker and loaded
Debug trial code. This is a prepared candidate only. A separately approved
product round would use:

```sh
ruby /Users/bytedance/.codex/worktrees/product-network-observation/KeyRecord/Scripts/product-network-observe.rb \
  --app /private/tmp/keyrecord-network.7yjmhZ/RetestBuild3/Build/Products/Debug/KeyRecordApp.app \
  --seconds 75
```

The trial's own fresh namespace and store remain isolated from ordinary
statistics. The control result does not alter the three invalid historical
product receipts, establish zero egress, or change Phase 1 and Release gates.
