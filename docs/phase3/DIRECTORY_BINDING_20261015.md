# Karabiner configuration directory binding

This offline increment starts from main `95e67652a9a156ddd715368702691b025c964443`.
Renaming and replacing a selected configuration directory could redirect an existing
session into the replacement directory. Identical configuration bytes passed the
content check. If the replacement also contained the same temporary basename, the
old pathname-based rename published that file and left the original temporary behind.

Two temporary-directory reproductions failed with seven assertions before the fix.
One replaces the parent between operations; the other replaces it during the final
runtime check and copies the pending temporary file into the replacement directory.
The reproduction log is `/private/tmp/keyrecord-directory-binding-red.log`.

The file port now holds an open parent-directory descriptor for its lifetime and
checks that the selected parent still identifies that directory. Reads use `openat`
and `fstatat`; a descriptor-relative atomic commit uses `openat`, `renameat`, `unlinkat`
and directory `fsync`. Failure cleanup stays in the originally opened directory.
If the parent moves after the final check, the commit still cannot publish or clean
up in the replacement directory. Normal atomic editor replacements of the file
within the selected directory remain supported.

Runtime context checks also validate the directory, withdrawing apply/manage
eligibility without waiting for the filesystem watcher. Native refresh checks the
connection even when no rules have been applied, so an invalid target produces an
error instead of silently refreshing an empty ledger.

## Validation

- Eight file transaction tests pass, including four new cases for directory
  replacement, pre-rename replacement and cleanup, descriptor anchoring after the
  last validation, and legitimate file-only replacement. Existing real-process
  SIGKILL durability tests remain enabled and pass.
- The focused package run passes 56 tests covering mappings, privacy, product
  boundaries and related reference parsing:
  `/private/tmp/keyrecord-directory-binding-core-final.log`.
- The unsigned arm64 native test build and all 71 mapping workflow tests pass, including a
  prepared operation after directory replacement; both original and replacement
  configurations must remain unchanged. Logs are
  `/private/tmp/keyrecord-directory-binding-native-final-build.log` and
  `/private/tmp/keyrecord-directory-binding-native.log`.
- Self-review covers descriptor ownership and closure, path aliases, filename
  validation, regular-file checks, cleanup location, durability injection points,
  ordinary editor compatibility and the native error path.

This is an operating-system directory handle and ordinary identity check at a file
write boundary, not a new hash, persisted baseline, frozen contract or gate. Content
equality and the existing transaction alone cannot distinguish two directories with
identical contents. Existing privacy, support, before-image, readback and deletion
review protections remain. This does not promise exclusion against an arbitrary
concurrent writer changing the target file after the last content check.

All configurations, stores and keys used here are temporary or synthetic. Production
support remains empty; real devices, real Keychain restore, uninstall and G3/G4
qualification remain deferred. Final-head push/PR CI and post-merge main CI are
verified separately from local results.
