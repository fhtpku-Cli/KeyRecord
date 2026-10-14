# Full password backup and restore

Settings exports all committed manifest objects: statistics, preferences, cycles,
mappings, firmware originals and operation records. Capture pauses and flushes before
the snapshot. Local Keychain material is never exported. A new installation decrypts
using only the password, then seals every object under its own local key. Ordinary
mapping exports remain separate and exclude statistics.

Restore accepts only an empty installation, through first-run consent. It never merges
or overwrites existing data. Existing data must first go through the explicit deletion
and recovery-copy review flow. All restored object files precede one atomic manifest
commit; reopening after interruption sees zero or all restored objects. Restored
preferences pause capture and disable login-item intent. No external mapping is applied.
Device references retain the existing compatibility and explicit selection checks.

## Format and dependency review

- Format v1: `KRBACKUP`, five big-endian UInt32 fields (format 1, Argon2 version 0x13,
  memory 524288 KiB, iterations 5, parallelism 4), random 16-byte salt, and CryptoKit
  AES-256-GCM combined nonce/ciphertext/tag. The entire header is authenticated as AAD.
- Payload: object count, then length-prefixed canonical identities and payloads. Unknown
  formats/costs, duplicate identities, manifest injection, truncation and trailing bytes
  fail closed. Limits: 128 MiB archive, 50000 objects, existing 8 MiB object envelope limit,
  1024 password UTF-8 bytes. No compression and no weaker KDF fallback.
- Costs are checked before invoking C; a file cannot choose arbitrary CPU/memory costs.
  Allocation failures propagate. Swift-owned password/plaintext copies are transient,
  not claimed to be reliably zeroized.
- SwiftPM selects PHC revision `f57e61e19229e23c4445b85494dbf7c07de721cb`, matching
  the previous SP-6B source audit. Its six reference C sources have no transitive runtime
  dependency, networking or package plugin. Reviewed raw hash, validation, allocation/free
  and internal wiping paths. The upstream [license](https://github.com/P-H-C/phc-winner-argon2/blob/f57e61e19229e23c4445b85494dbf7c07de721cb/LICENSE)
  offers CC0/Apache-2.0; this integration uses CC0. Official repository advisory API returned
  no published advisories on 2026-10-15; this is not proof of absence of vulnerabilities.
- Existing benchmark compiled against these reference sources with `clang -O3` measured
  429.673, 372.663, 371.739 ms on this Apple Silicon host. Debug builds are slower.
  Intel timing, live Keychain restoration and release qualification remain deferred.

## Verification scope

PHC raw vector; Unicode password round-trip; randomness; wrong password; header/salt/tag
tampering; malformed payloads; bounds; independent local-key restoration; populated-store
refusal; locked reads; injected I/O failures and real process kills at data/manifest
durability boundaries. Product composition uses temporary stores, independent in-memory
Keychains and synthetic capture to check counts survive, capture/login stay stopped,
file collisions preserve earlier backups and privacy revocation prevents publication.
English and Chinese native export buttons execute the flow and produce screenshots.

No new hash, frozen contract, baseline or gate. Deletion-time recovery verification is
unchanged. Verification deletes only disposable fixtures, never real user data.
