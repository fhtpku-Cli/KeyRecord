# Lock-state source investigation and next observation

## Coordinated observation completed

Subsequent product evidence now includes the
[fresh-install locked startup](PRODUCT_LOCKED_STARTUP_PREP_20260930.md) and
[existing-store separate-process restart](PRODUCT_LOCKED_RESTART_PREP_20261001.md).
Both bounded scenarios pass on their stated signed candidates. The source
observation and API support limits below retain their independent scope.

The owner confirmed readiness, then explicitly confirmed seeing the lock screen
and normally unlocking. The reviewed 60-second observer completed with shell exit
0 in 60.005 seconds. Its 58 fresh diagnostic processes recorded:

| Interval (seconds after start) | Samples | Console lock | Session lock, before/after |
| --- | ---: | --- | --- |
| 0.098-36.389 | 36 | false | unknown / unknown |
| 37.412-49.875 | 13 | true | true / true |
| 50.898-59.138 | 9 | false | unknown / unknown |

All samples reported an available session, on-console true and current-user match
both before and after the console query. The interval endpoints are sample times,
not exact transition times. The host is native arm64 macOS 27.0. Output:
`/private/tmp/keyrecord-lock-source-20260930/manual-round-1.jsonl`.
The sub-agent independently checked all rows and the bounded scope in
`/private/tmp/.omo/evidence/lock-startup-manual-result-code-review.md`.

This establishes a bounded observed sequence including processes first launched
while the owner-reported lock screen was active. It does not establish an atomic
lock-state API, product restart safety, real locked Keychain protection or Release
qualification. No App, Keychain, input capture or system-setting operation ran.
The next preparation is a product locked-startup test using actual lock inputs,
with no Keychain pre-read during the locked interval. Do not repeat this source
observation solely to obtain another passing sequence.

## Original preparation and scope

The unlocked full-product Keychain scenario has passed. The next unresolved
question is whether a newly started process can observe an already locked console
without having received the earlier lock notification. Repeating the completed
performance, sleep or simulated composition scenario cannot answer that question.

## Source findings

The current Debug `SystemSessionLockProvider` brackets a registry-root
`IOConsoleLocked` query with current-session eligibility reads. It also observes
distributed lock notifications. It is excluded from Release; no macOS version is
listed in `ObservedLockSignals.qualifiedLiveVersions`.

Apple's [window-server session properties](https://developer.apple.com/documentation/coregraphics/window-server-session-properties)
and the installed SDK's `CoreGraphics.framework/Headers/CGSession.h` expose user,
on-console and login-complete properties, but do not define a screen-lock key.
The two lock keys currently used by the Debug diagnostic appear in Apple's
[private IOKit header](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/IOKitKeysPrivate.h).
They are observable implementation details, not a documented public lock-state
API guarantee. This research has not established a supported replacement.
The open-source main branch is not proof of this host's exact kernel implementation.

The current host's unlocked readiness check returned `console=unlocked` while the
session screen-lock key was absent. Absence alone must not mean unlocked. The
existing eligibility and fail-closed checks remain in place. A passing read-only
observation will not by itself promote these inputs into a production authority.

## Prepared bounded observation

`Spikes/KeychainLifecycle/Tools/LockStateSample.swift` is a standalone diagnostic.
It emits only coarse state values from before/after session queries and the
console query; it never emits user IDs, names or key/input data. The Python runner
starts a fresh copy for each sample, about once per second, for at most 60 seconds.
Each child has a two-second timeout and is killed/reaped on timeout. SIGINT/SIGTERM
stop further launches; stdout carries observations rather than an automatic PASS.

Compile to a new private temporary directory with `xcrun swiftc`, then run:

```sh
python3 Spikes/KeychainLifecycle/Tools/observe_lock_startup.py \
  --probe /private/tmp/keyrecord-lock-source-20260930/LockStateSample --duration 60
```

First perform independent review and a one-second unlocked smoke observation.
For the manual observation, wait for owner readiness before starting the timer.
Then ask the owner to use Control-Command-Q, visually confirm the lock screen,
wait about 10 seconds, normally unlock, and report whether the lock screen was
actually visible. No App launch, input capture, Keychain operation, system setting
change or sleep is part of this observation. Stop after the one bounded interval.

Compare fresh-process samples during the owner-reported locked interval and after
unlock. Unknown, disagreement or lack of a confirmed lock-screen interval remains
unqualified. Record observations only: this is not a product-process restart test,
real locked Keychain test, continuous privacy proof or Release authorization.
Afterward use the result to choose the smallest product-host scenario; do not
repeat this observation merely to collect more passing samples.

## Preparation checks

Independent review passed for compilation and the one-second read-only smoke:
`/private/tmp/.omo/evidence/lock-source-observer-code-review.md`. The unnecessary
comment implying immediate child termination on operator interruption was removed;
the actual bound remains up to two seconds for an in-flight child.
Swift compilation and Python AST validation passed without installing an LSP.

The one-second runner exited 0 in 1.005 seconds and emitted one fresh-process
sample on native arm64 macOS 27.0. At that time both session reads and the console
property reported locked, with eligible current-user/on-console flags. This was
later than the successful unlocked Keychain round. The artifact filename
`/private/tmp/keyrecord-lock-source-20260930/unlocked-smoke.jsonl` reflects the
planned readiness, not the observed state: it is a locked observation, not an
unlocked PASS. It has no independently reported visible lock-screen interval and
does not qualify a production detector. The coordinated observation has not run;
wait for owner readiness before starting its timer.
