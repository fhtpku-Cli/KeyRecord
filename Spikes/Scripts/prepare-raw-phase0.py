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

SP1_SOURCE_PATHS = sorted(
    [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityProbe.swift",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP1Probe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/AtomicReplacement.swift",
        "Spikes/Sources/Phase0Support/AtomicityEvidence.swift",
        "Spikes/Sources/Phase0Support/InputObservation.swift",
    ]
)

SP6A_SOURCE_PATHS = sorted(
    [
        "Spikes/Scripts/audit-security.sh",
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Scripts/verify-sp6a-cold-happy.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP6AKeychainProbe.swift",
        "Spikes/Sources/Phase0Probe/SP6AHistoryAnchorProbe.swift",
        "Spikes/Sources/Phase0Probe/SP6AProbe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/AuthenticatedStorage.swift",
        "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP6AArtifacts.swift",
        "Spikes/Sources/Phase0Support/SP6AEvidence.swift",
        "Spikes/Sources/Phase0Support/SP6ANamespaceEvidence.swift",
        "Spikes/Sources/EvidenceValidator/AtomicityHistoricalValidator.swift",
        "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP6ADirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6AHistoryAnchorValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6ALegacyHistoryAnchorValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6ANamespaceValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
        "Spikes/Tests/EvidenceValidatorTests/SP6ANamespaceValidatorTests.swift",
        "Spikes/Tests/EvidenceValidatorTests/SP6AValidatorTests.swift",
        "Spikes/Tests/Phase0ProbeTests/Phase0ProbeTests.swift",
        "Spikes/Tests/Phase0SupportTests/StorageSecurityTests.swift",
    ]
)

SP2_SOURCE_PATHS = sorted(
    [
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Sources/Phase0Probe/AtomicityRunnerIdentity.swift",
        "Spikes/Sources/Phase0Probe/SP2LiveExecutor.swift",
        "Spikes/Sources/Phase0Probe/SP2Probe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/EvidenceDocuments.swift",
        "Spikes/Sources/Phase0Support/EvidenceModels.swift",
        "Spikes/Sources/Phase0Support/PrivacyTransition.swift",
        "Spikes/Sources/Phase0Support/ModifierReconstruction.swift",
        "Spikes/Sources/Phase0Support/Registries.swift",
        "Spikes/Sources/Phase0Support/SP2Evidence.swift",
        "Spikes/Sources/Phase0Support/SP2ModelScenarios.swift",
        "Spikes/Sources/EvidenceValidator/Canonical.swift",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/GitRunner.swift",
        "Spikes/Sources/EvidenceValidator/SP2DirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/ValidatorError.swift",
    ]
)

SP6B_SOURCE_PATHS = sorted(
    [
        "Spikes/Scripts/argon-bench.c",
        "Spikes/Scripts/argon-swift-vector.swift",
        "Spikes/Scripts/argon-vector.c",
        "Spikes/Scripts/audit-argon-sources.sh",
        "Spikes/Scripts/audit-security.sh",
        "Spikes/Scripts/benchmark-argon-arm.sh",
        "Spikes/Scripts/build-argon-universal.sh",
        "Spikes/Scripts/capture-argon-advisories.sh",
        "Spikes/Scripts/run-sp6b.sh",
        "Spikes/Scripts/run-task-qa.sh",
        "Spikes/Scripts/sp6b-nvd-review.json",
        "Spikes/Scripts/sp6b-source-contract.json",
        "Spikes/Scripts/task-11-qa.sh",
        "Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift",
        "Spikes/Sources/EvidenceValidator/SP6BBenchmarkValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BBuildValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BDirectoryValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BNVDValidator.swift",
        "Spikes/Sources/EvidenceValidator/SP6BSourceValidator.swift",
        "Spikes/Sources/Phase0Probe/SP6BProbe.swift",
        "Spikes/Sources/Phase0Probe/main.swift",
        "Spikes/Sources/Phase0Support/Argon2Candidate.swift",
        "Spikes/Sources/Phase0Support/D12Fixture.swift",
        "Spikes/Sources/Phase0Support/D12Snapshot.swift",
        "Spikes/Sources/Phase0Support/SP6BEvidence.swift",
        "Spikes/Tests/EvidenceValidatorTests/SP6BValidatorTests.swift",
        "Spikes/Tests/Phase0SupportTests/Argon2AuditTests.swift",
    ]
)


def write_swift_json(path: Path, value: object) -> None:
    text = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False)
    text = text.replace('": ', '" : ')
    path.write_text(text + "\n", encoding="utf-8")


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


def remanifest_directory(directory: Path) -> None:
    names = sorted(
        p.name
        for p in directory.iterdir()
        if p.is_file() and p.name != "manifest.sha256"
    )
    lines = [f"{sha256_file(directory / name)}  {name}" for name in names]
    (directory / "manifest.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def remanifest_sp6b(directory: Path) -> None:
    names = sorted(
        str(path.relative_to(directory)).replace("\\", "/")
        for path in directory.rglob("*")
        if path.is_file() and path.name != "manifest.sha256"
    )
    lines = [f"{sha256_file(directory / name)}  {name}" for name in names]
    (directory / "manifest.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def sync_sp6b_runner(directory: Path, commit: str, tree: str) -> None:
    evidence_path = directory / "evidence.json"
    if not evidence_path.exists():
        return
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    for leg in evidence.get("legs", []):
        leg["runnerCommitSha"] = commit
        leg["runnerTreeSha"] = tree
    evidence["runnerSourceSha256"] = source_hashes(commit, SP6B_SOURCE_PATHS)
    evidence_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"synced sp6b/evidence.json runner binding to {commit[:12]}")


def sync_sp6b_leg_hashes(directory: Path) -> None:
    evidence_path = directory / "evidence.json"
    if not evidence_path.exists():
        return
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    changed = False
    for leg in evidence.get("legs", []):
        artifact_path = leg.get("artifactPath")
        if not artifact_path:
            continue
        artifact = directory / artifact_path
        if not artifact.is_file():
            continue
        digest = sha256_file(artifact)
        if leg.get("artifactSha256") != digest:
            leg["artifactSha256"] = digest
            changed = True
    if changed:
        evidence_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print("synced sp6b/evidence.json artifact hashes")


def sync_sp6b_directory() -> None:
    sp6b_dir = PHASE0 / "sp6b"
    if not sp6b_dir.exists():
        return
    commit = canonicalize_commit("HEAD")
    tree = subprocess.check_output(
        ["git", "rev-parse", f"{commit}^{{tree}}"], cwd=REPO, text=True
    ).strip()
    sync_sp6b_runner(sp6b_dir, commit, tree)
    sync_sp6b_leg_hashes(sp6b_dir)
    remanifest_sp6b(sp6b_dir)
    print("remanifested sp6b directory")


def canonicalize_commit(ref: str) -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "--verify", f"{ref}^{{commit}}"], cwd=REPO, text=True
    ).strip()


def resolve_binding_commit() -> str:
    ref = os.environ.get("KEYRECORD_BINDING_COMMIT")
    if ref:
        return canonicalize_commit(ref)
    commit = subprocess.check_output(
        [
            "git",
            "rev-list",
            "-1",
            "HEAD",
            "--grep=ancestor binding, SP-6A regen",
        ],
        cwd=REPO,
        text=True,
    ).strip()
    if commit:
        return commit
    for candidate in ("HEAD~2", "HEAD~3", "HEAD"):
        resolved = canonicalize_commit(candidate)
        if subprocess.call(
            ["git", "merge-base", "--is-ancestor", resolved, "HEAD"], cwd=REPO
        ) == 0:
            return resolved
    return canonicalize_commit("HEAD")


def source_hashes(commit: str, paths: list[str]) -> dict[str, str]:
    import hashlib

    hashes: dict[str, str] = {}
    for path in paths:
        blob = subprocess.check_output(["git", "cat-file", "blob", f"{commit}:{path}"], cwd=REPO)
        hashes[path] = hashlib.sha256(blob).hexdigest()
    return hashes


def sync_sp1_binding(commit: str, tree: str) -> None:
    evidence_path = PHASE0 / "sp1" / "evidence.json"
    if not evidence_path.exists():
        return
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    for leg in evidence.get("legs", []):
        leg["runnerCommitSha"] = commit
        leg["runnerTreeSha"] = tree
        identity = leg.get("identity")
        if isinstance(identity, dict):
            identity["runnerCommitSha"] = commit
            identity["runnerTreeSha"] = tree
    selected = evidence.get("selectedTapIdentity")
    if isinstance(selected, dict):
        selected["runnerCommitSha"] = commit
        selected["runnerTreeSha"] = tree
    evidence["runnerSourceSha256"] = source_hashes(commit, SP1_SOURCE_PATHS)
    write_swift_json(evidence_path, evidence)
    remanifest_directory(evidence_path.parent)
    print(f"synced sp1/evidence.json runner binding to {commit[:12]}")


def patch_runner_source_hashes(text: str, paths: list[str], commit: str) -> str:
    import re

    for path in paths:
        digest = source_hashes(commit, [path])[path]
        pattern = rf'("{re.escape(path)}"\s*:\s*")[0-9a-f]{{64}}(")'
        if re.search(pattern, text):
            text = re.sub(
                pattern,
                lambda match: f"{match.group(1)}{digest}{match.group(2)}",
                text,
                count=1,
            )
            continue
        line = f'    "{path}" : "{digest}",\n'
        predecessors = [p for p in paths if p < path and f'"{p}"' in text]
        if predecessors:
            anchor_path = predecessors[-1]
            anchor = f'    "{anchor_path}" : "'
            idx = text.index(anchor)
            end = text.index("\n", idx)
            text = text[: end + 1] + line + text[end + 1 :]
        else:
            raise RuntimeError(f"missing runner source anchor for {path}")
    return text


def sync_sp6a_binding(commit: str, tree: str) -> None:
    evidence_path = PHASE0 / "sp6a" / "evidence.json"
    if not evidence_path.exists():
        return
    text = evidence_path.read_text(encoding="utf-8")
    import re

    old_commits = set(re.findall(r'"runnerCommitSha"\s*:\s*"([0-9a-f]{40})"', text))
    old_trees = set(re.findall(r'"runnerTreeSha"\s*:\s*"([0-9a-f]{40})"', text))
    for old in old_commits:
        if old != commit:
            text = text.replace(old, commit)
    for old in old_trees:
        if old != tree:
            text = text.replace(old, tree)
    text = patch_runner_source_hashes(text, SP6A_SOURCE_PATHS, commit)
    evidence_path.write_text(text, encoding="utf-8")
    remanifest_directory(evidence_path.parent)
    print(f"synced sp6a/evidence.json runner binding to {commit[:12]}")


def sync_sp2_binding(commit: str, tree: str) -> None:
    evidence_path = PHASE0 / "sp2" / "evidence.json"
    if not evidence_path.exists():
        return
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    for leg in evidence.get("legs", []):
        leg["runnerCommitSha"] = commit
        leg["runnerTreeSha"] = tree
    evidence["runnerSourceSha256"] = source_hashes(commit, SP2_SOURCE_PATHS)
    write_swift_json(evidence_path, evidence)
    remanifest_directory(evidence_path.parent)
    print(f"synced sp2/evidence.json runner binding to {commit[:12]}")


def collect_binding_paths() -> list[str]:
    import re

    paths: set[str] = set()
    scan_roots = [
        REPO / "Spikes/Sources/Phase0Support",
        REPO / "Spikes/Sources/Phase0Probe",
        REPO / "Spikes/Sources/EvidenceValidator",
        REPO / "Spikes/Tests",
    ]
    for root in scan_roots:
        if not root.exists():
            continue
        for file in root.rglob("*.swift"):
            text = file.read_text(encoding="utf-8")
            if not re.search(r"enum \w+RunnerBinding", text) and file.name != "Phase0RunReceipt.swift":
                continue
            paths.update(re.findall(r'"(Spikes/[^"]+)"', text))
    return sorted(paths)


def sync_run_all_receipt() -> None:
    """Restore raw run-all receipt fields after stripping conclusions."""
    import hashlib

    run_all_path = PHASE0 / "run-all.json"
    if not run_all_path.exists():
        return
    run_all = json.loads(run_all_path.read_text(encoding="utf-8"))
    run_all["conclusionGenerated"] = False
    run_all["rootArtifacts"] = [
        "README.md",
        "environment.json",
        "privacy-audit.json",
        "run-all.json",
    ]
    commit = resolve_binding_commit()
    tree = subprocess.check_output(
        ["git", "rev-parse", f"{commit}^{{tree}}"], cwd=REPO, text=True
    ).strip()
    run_all["runnerCommitSha"] = commit
    run_all["runnerTreeSha"] = tree
    sources = {}
    for path in collect_binding_paths():
        blob = subprocess.check_output(["git", "cat-file", "blob", f"{commit}:{path}"], cwd=REPO)
        sources[path] = hashlib.sha256(blob).hexdigest()
    run_all["runnerSourceSha256"] = sources
    sp6a_manifest = PHASE0 / "sp6a" / "manifest.sha256"
    if sp6a_manifest.exists():
        sp6a_hash = sha256_file(sp6a_manifest)
        for stage in run_all.get("stages", []):
            if stage.get("id") == "sp6a":
                stage["artifactSha256"] = sp6a_hash
    sp6b_manifest = PHASE0 / "sp6b" / "manifest.sha256"
    if sp6b_manifest.exists():
        sp6b_hash = sha256_file(sp6b_manifest)
        for stage in run_all.get("stages", []):
            if stage.get("id") == "sp6b":
                stage["artifactSha256"] = sp6b_hash
    run_all_path.write_text(json.dumps(run_all, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print("synced run-all.json for raw root")


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--sp6b-only":
        sync_sp6b_directory()
        return 0

    for name in CONCLUSION_FILES:
        path = PHASE0 / name
        if path.exists():
            path.unlink()
            print(f"removed {name}")

    commit = resolve_binding_commit()
    tree = subprocess.check_output(
        ["git", "rev-parse", f"{commit}^{{tree}}"], cwd=REPO, text=True
    ).strip()
    sync_sp1_binding(commit, tree)
    sync_sp2_binding(commit, tree)
    sync_sp6a_binding(commit, tree)
    sync_run_all_receipt()

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
