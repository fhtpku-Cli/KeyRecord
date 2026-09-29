# Short formal performance preparation

Source `a604ad535` implements the owner-requested formal protocol: typing and
idle once each, 30 seconds warmup plus 120 seconds measurement per window, with
a two-second drain tail. No live performance App has been launched.

## Prepared artifacts

- Dedicated bundle: `com.keyrecord.trial.performance.mvp20260929`.
- Display name: `KeyRecord Performance Trial`; required-isolation marker true.
- Team for local development signing: `P3W62C39TN`.
- Unsigned arm64 App build succeeded at
  `/private/tmp/keyrecord-performance-a604ad535/unsigned-build/Build/Products/Debug/KeyRecordApp.app`.
  Both loader and Debug product dylib are arm64. This artifact is not runnable
  qualification evidence and will not be used for permission or Keychain trials.
- Current controller and sampler builds passed; binaries are under the isolated
  worktree's `.build/out/Products/Debug` directory.
- Fresh empty, owner-only 0700 session directory:
  `/private/tmp/keyrecord-performance-20260929-a604ad535`, with `typing-1` and
  `idle-1` children. No store or Keychain item has been created by this preparation.
- The existing installed MVP Trial and all sleep-round data are unchanged.

## Actual signing blocker

A signed build using existing local assets, with no provisioning updates,
failed with Xcode exit 65: no Mac App Development profile exists for
`com.keyrecord.trial.performance.mvp20260929`. Log:
`/private/tmp/keyrecord-performance-a604ad535/local-signing-build.log`.
The only local profile inspected authorizes
`P3W62C39TN.com.keyrecord.trial.mvp20260929`, not the performance bundle.
An unchanged dedicated-performance identity check prevents substituting the
MVP App or weakening profile checks to launch an unusable package.

The next account operation needs owner authorization: one Xcode attempt, at
most 120 seconds, using the existing developer account to register the dedicated
trial identifier if needed and obtain/create its matching development profile,
then build. Stop on account login, payment/subscription prompts or signing
errors. Do not launch a product, change TCC or create trial statistics as part
of that operation. The earlier one-time account authorization covered the MVP
identifier only and is not reused here. This is local Debug provisioning, not
distribution signing or notarization.

After successful signing, verify the package and both empty window directories
with `KeyRecordPerformanceTrial --check`. Only then prepare installation and
the separately approved/readied live sequence: first typing, then idle, each
starting with owner Start/consent and ending with normal Quit and summary review.
Unexpected permissions, Keychain or restart prompts stop the round. Keep the
computer unlocked and do not prevent sleep. No physical typing is required.

## Evidence limits

The preceding 35 package tests, hostless product replay/store test and two tool
self-checks passed, but no native performance result exists. Both fresh windows
must complete and retain accepted-event/durable-total and raw-sample evidence.
Current controller/evaluator identity, full endpoint, sleep/session, budget and
normal-exit checks remain in force. Fixed replay omits actual system event-tap
cost; five-minute measurement is not a claim about long-term endurance.

At this checkpoint the push CI job for `a604ad535` passed in 4m30s; its PR CI job
was still pending. The unsigned build log is adjacent to the signing log as
`unsigned-build.log`; it does not establish signing or runtime Keychain access.
