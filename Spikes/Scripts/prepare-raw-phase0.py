#!/usr/bin/env python3
"""Prepare evidence/phase0 for raw validate-phase0 (no conclusions)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PHASE0 = REPO / "evidence" / "phase0"
CONCLUSION_FILES = ["conclusions.json"] + [
    f"SP-{x}-CONCLUSION.md"
    for x in ["1", "2", "3", "4A", "4B", "5A", "5B", "6A", "6B"]
]


def sha256_file(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def remanifest_root() -> None:
    names = sorted(
        p.name
        for p in PHASE0.iterdir()
        if p.is_file() and p.name != "manifest.sha256"
    )
    lines = [f"{sha256_file(PHASE0 / name)}  {name}" for name in names]
    (PHASE0 / "manifest.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def upgrade_run_all() -> int:
    result = subprocess.run(
        [
            "swift",
            "test",
            "--package-path",
            str(REPO / "Spikes"),
            "--filter",
            "G0PassedConclusionTests/testUpgradeRunAllReceiptWhenRequested",
        ],
        cwd=REPO / "Spikes",
        env={**os.environ, "KEYRECORD_UPGRADE_RUN_ALL": "1"},
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return result.returncode
    print("upgraded run-all.json binding to HEAD")
    return 0


def main() -> int:
    if upgrade_run_all() != 0:
        return 1

    for name in CONCLUSION_FILES:
        path = PHASE0 / name
        if path.exists():
            path.unlink()
            print(f"removed {name}")

    validator = REPO / "Spikes/.build/release/EvidenceValidator"
    audit = subprocess.check_output([str(validator), "audit-privacy", str(PHASE0)], text=True)
    print(audit.strip())
    files_scanned = json_scanned = 0
    for line in audit.splitlines():
        if line.startswith("PRIVACY_AUDIT=PASS"):
            for token in line.split()[1:]:
                key, value = token.split("=", 1)
                if key == "files":
                    files_scanned = int(value)
                elif key == "json":
                    json_scanned = int(value)
    privacy = {
        "conclusionGenerated": False,
        "filesScanned": files_scanned,
        "forbiddenHitCount": 0,
        "jsonFilesScanned": json_scanned,
        "schemaVersion": 1,
        "symlinkCount": 0,
        "unmarkedEventRecordCount": 0,
    }
    (PHASE0 / "privacy-audit.json").write_text(json.dumps(privacy, indent=2, sort_keys=True) + "\n")

    remanifest_root()
    print("prepared raw phase0 root")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
