#!/usr/bin/env python3
"""Update phase0 evidence environmentSha256 bindings and remanifest affected dirs."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

OLD = "6b3288f5983cbce231295762d3f8381b8467d6dbe2e74fff0e17a1aebf7215f4"
NEW = "c67cd660c318012dd04613a0c598198fa15aec6ce3cb905314be2946e130e77f"
REPO = Path(__file__).resolve().parents[2]
PHASE0 = REPO / "evidence" / "phase0"

SPIKE_JSON = [
    "sp3/evidence.json",
    "sp4a/evidence.json",
    "sp4b/evidence.json",
    "sp5a/evidence.json",
    "sp5b/evidence.json",
    "sp6a/evidence.json",
    "sp6b/evidence.json",
    "sp6b/arm-benchmark.json",
]


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_env_in_text(text: str) -> tuple[str, int]:
    return text.replace(OLD, NEW), text.count(OLD)


def write_json_pretty(path: Path, obj: object) -> None:
    text = json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text, encoding="utf-8")


def attempt_id(input_bytes: list[int], runner: dict, generated_at_utc: str) -> str:
    prefix = b"sp6a-namespace-attempt-v1\x00"
    body = (
        f"\0{runner['commitSha']}\0{runner['treeSha']}\0{runner['environmentSha256']}\0{generated_at_utc}"
    ).encode()
    data = prefix + bytes(input_bytes) + body
    return hashlib.sha256(data).hexdigest()


def fix_receipt(receipt: dict) -> None:
    receipt["runner"]["environmentSha256"] = NEW
    receipt["attemptID"] = attempt_id(
        receipt["inputBytes"], receipt["runner"], receipt["generatedAtUTC"]
    )


def fix_sp6a_keychain(path: Path) -> None:
    obj = json.loads(path.read_text(encoding="utf-8"))
    for receipt in obj.get("attemptHistory", {}).get("attempts", []):
        fix_receipt(receipt)
    if "generationReceipt" in obj:
        gen = obj["generationReceipt"]
        for receipt in obj["attemptHistory"]["attempts"]:
            if receipt.get("service") == gen.get("service"):
                obj["generationReceipt"] = receipt
                break
    write_json_pretty(path, obj)


def fix_sp6a_history(path: Path) -> None:
    obj = json.loads(path.read_text(encoding="utf-8"))
    for receipt in obj.get("attempts", []):
        fix_receipt(receipt)
    write_json_pretty(path, obj)


def remanifest_dir(directory: Path) -> None:
    names = sorted(
        p.name
        for p in directory.iterdir()
        if p.is_file() and p.name != "manifest.sha256"
    )
    lines = [f"{sha256_file(directory / name)}  {name}" for name in names]
    (directory / "manifest.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def remanifest_root() -> None:
    names = sorted(
        p.name
        for p in PHASE0.iterdir()
        if p.is_file() and p.name != "manifest.sha256"
    )
    lines = [f"{sha256_file(PHASE0 / name)}  {name}" for name in names]
    (PHASE0 / "manifest.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    changed = 0
    for rel in SPIKE_JSON:
        path = PHASE0 / rel
        if not path.exists():
            print(f"skip missing {rel}", file=sys.stderr)
            continue
        text = path.read_text(encoding="utf-8")
        updated, count = replace_env_in_text(text)
        if count:
            path.write_text(updated, encoding="utf-8")
            changed += count
            print(f"updated {rel} ({count} replacements)")

    # sp6a keychain attempt history is git-anchored; only evidence legs get env rebinding here.

    for child in [
        "shared-atomicity",
        "sp3",
        "sp4a",
        "sp4b",
        "sp5a",
        "sp5b",
        "sp6a",
        "sp6b",
    ]:
        remanifest_dir(PHASE0 / child)
        print(f"remanifested {child}")

    remanifest_root()
    print("remanifested phase0 root")
    print(f"total string replacements: {changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
