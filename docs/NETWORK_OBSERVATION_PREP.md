# Network observation preparation — 2026-09-27

Base: PR #13 merge `6257b03b40f618fd976c6cbcc77dc83d374c59bb`.
This is tool preparation, not a product network receipt or Phase 1 acceptance.
The existing `Scripts/phase1-network-qa.sh` remains BLOCKED. No KeyRecord launch,
external network request, privileged capture helper installation,
TCC change, real-store or Keychain operation was performed for the initial nettop experiments. Subsequent capture results are recorded below.

## Latest state and remaining decision

The second owner-run 20-second PKTAP pilot observed 16 packet records with the
expected PID, direction and destination-port counts for two owned loopback flows.
The receiver got all 12 sent datagrams, including four to the excluded decoy port.
No kernel drops were reported. One additional output line was not retained and
cannot be classified retrospectively. The newer metadata-only line-shape counters
passed offline checks but have not been exercised in an administrator-run capture.
The script intentionally has no product PASS path. The exact earlier results and
subsequent offline change are preserved chronologically below.

The next useful observation is one final, bounded synthetic run with the revised
reducer. It requires owner authentication because ordinary access to `/dev/bpf`
is denied on this host. The run must stay on the two owned IPv4 loopback UDP
ports, with the third owned port excluded; it neither launches KeyRecord nor
observes the machine's external traffic. See the criteria and command at the end.
A validated synthetic observer would still leave product process identity,
all-interface scope, unknown attribution and Release qualification open.

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

## Final synthetic observer check

The unprivileged controller path was run again during closeout: tcpdump exited
1 with permission denied before readiness, zero control packets sent, zero
receiver packets, and all owned PIDs reaped. No packet was captured. The local
manual confirms `-k PD` selects PID and direction metadata. Offline reducer
tests, CLI syntax/help/invalid arguments, and the nettop positive control have
been rerun. The one remaining diagnostic is a privileged bounded capture with
the current line-shape counters.

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
