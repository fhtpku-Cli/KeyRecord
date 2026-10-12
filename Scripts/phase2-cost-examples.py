#!/usr/bin/env python3
"""Offline design examples only; no product score, configuration or device I/O."""

from dataclasses import dataclass
from itertools import combinations
from math import hypot, isfinite


@dataclass(frozen=True)
class Position:
    name: str
    x: float
    y: float
    frame: str = "board"


@dataclass(frozen=True)
class Mapping:
    before: tuple[str, ...]
    after: tuple[str, ...]


@dataclass(frozen=True)
class Link:
    kind: str
    status: str
    mappings: tuple[Mapping, ...]


@dataclass(frozen=True)
class Evidence:
    positions: tuple[Position, ...]
    links: tuple[Link, ...]
    single_device: bool = True


@dataclass(frozen=True)
class Cost:
    presses: int
    diameter: float


def resolve(tokens: tuple[str, ...], evidence: Evidence) -> tuple[Cost | None, str]:
    # These fixture strings denote exact ordered actions, not a firmware language.
    if not evidence.single_device:
        return None, "multi-device-uncertain"
    if tuple(link.kind for link in evidence.links) != ("firmware", "software", "macos"):
        return None, "missing-link"
    for link in evidence.links:
        if link.status != "verified":
            return None, f"{link.kind}:{link.status}"
    positions = {position.name: position for position in evidence.positions}
    if len(positions) != len(evidence.positions):
        return None, "duplicate-position"
    if not all(isfinite(p.x) and isfinite(p.y) for p in evidence.positions):
        return None, "invalid-coordinate"
    paths = {tokens}
    for link in reversed(evidence.links):
        paths = {mapping.before for mapping in link.mappings if mapping.after in paths}
        # Conservative: never let a later filter erase an intermediate ambiguity.
        if len(paths) != 1:
            return None, "no-action" if not paths else "ambiguous"
    actions = next(iter(paths))
    if not actions or any(action not in positions for action in actions):
        return None, "missing-position"
    used = [positions[action] for action in actions]
    if len({p.frame for p in used}) != 1:
        return None, "unknown-relative-geometry"
    diameter = max((hypot(a.x - b.x, a.y - b.y) for a, b in combinations(used, 2)), default=0.0)
    # Do not deduplicate: two downs at one position are two presses.
    return Cost(len(actions), diameter), "physical"


def compare(source: tuple[str, ...], target: tuple[str, ...], evidence: Evidence,
            logical_counts: tuple[int, int]) -> tuple[str, int, float | None, str]:
    source_cost, source_reason = resolve(source, evidence)
    target_cost, target_reason = resolve(target, evidence)
    if source_cost is None or target_cost is None:
        return "logical", logical_counts[0] - logical_counts[1], None, f"source={source_reason}; target={target_reason}"
    return "physical", source_cost.presses - target_cost.presses, target_cost.diameter - source_cost.diameter, "complete"


def example_evidence(source_actions: tuple[str, ...], target_actions: tuple[str, ...],
                     positions: tuple[Position, ...]) -> Evidence:
    # Identity on both system links is EXPLICIT SYNTHETIC evidence, never inferred.
    return Evidence(positions, (
        Link("firmware", "verified", (Mapping(source_actions, ("hid:source",)), Mapping(target_actions, ("hid:target",)))),
        Link("software", "verified", (Mapping(("hid:source",), ("software:source",)), Mapping(("hid:target",), ("software:target",)))),
        Link("macos", "verified", (Mapping(("software:source",), ("observed:source",)), Mapping(("software:target",), ("observed:target",)))),
    ))


def main() -> None:
    source, target = ("observed:source",), ("observed:target",)
    positions = (Position("cmd", 0, 0), Position("shift", 0, 1), Position("c", 2, 0),
                 Position("near", 1, 0), Position("far", 8, 0), Position("f1", 12, 4),
                 Position("layer", 0, 2))
    examples = (
        ("A subset", ("cmd", "shift", "c"), ("cmd", "c"), (3, 2)),
        ("B fewer but wider", ("cmd", "near", "c"), ("cmd", "far"), (3, 2)),
        ("C single remote key", ("cmd", "shift", "c"), ("f1",), (3, 1)),
        ("D same presses", ("cmd", "c"), ("cmd", "near"), (2, 2)),
        ("E layer entry", ("cmd", "c"), ("layer", "near"), (2, 1)),
        ("F repeated position", ("cmd", "c"), ("near", "near"), (2, 1)),
    )
    print("SYNTHETIC ONLY; diameter in key-pitch units; positive span delta means wider")
    print("example | source presses/span | target presses/span | basis | saved | span delta")
    evidence_by_name = {}
    for name, source_actions, target_actions, logical in examples:
        evidence = example_evidence(source_actions, target_actions, positions)
        evidence_by_name[name] = evidence
        a, _ = resolve(source, evidence)
        b, _ = resolve(target, evidence)
        assert a is not None and b is not None
        basis, saved, delta, _ = compare(source, target, evidence, logical)
        print(f"{name} | {a.presses}/{a.diameter:.3f} | {b.presses}/{b.diameter:.3f} | {basis} | {saved} | {delta:+.3f}")

    subset = evidence_by_name["A subset"]
    assert compare(source, target, subset, (3, 2))[1:3] == (1, 2 - hypot(2, 1))
    wider = evidence_by_name["B fewer but wider"]
    assert compare(source, target, wider, (3, 2))[1:3] == (1, 6.0)
    assert compare(source, target, evidence_by_name["E layer entry"], (2, 1))[1] == 0
    assert resolve(target, evidence_by_name["F repeated position"])[0].presses == 2

    failures = [
        ("missing firmware", Evidence(positions, subset.links[1:]), "missing-link"),
        ("changed software", Evidence(positions, (subset.links[0], Link("software", "externally-changed", subset.links[1].mappings), subset.links[2])), "software:externally-changed"),
        ("multi device", Evidence(positions, subset.links, False), "multi-device-uncertain"),
        ("missing geometry", Evidence(positions[:1], subset.links), "missing-position"),
        ("unknown split gap", Evidence(tuple(Position(p.name, p.x, p.y, "right" if p.name == "c" else "left") for p in positions), subset.links), "unknown-relative-geometry"),
        ("ambiguous firmware", Evidence(positions, (Link("firmware", "verified", subset.links[0].mappings + (Mapping(("near",), ("hid:source",)),)), *subset.links[1:])), "ambiguous"),
        ("no target action", Evidence(positions, (Link("firmware", "verified", subset.links[0].mappings[:1]), *subset.links[1:])), "no-action"),
        ("duplicate position", Evidence(positions + (positions[0],), subset.links), "duplicate-position"),
        ("nonfinite coordinate", Evidence((Position("cmd", float("nan"), 0), *positions[1:]), subset.links), "invalid-coordinate"),
    ]
    for name, evidence, expected in failures:
        basis, saved, delta, reason = compare(source, target, evidence, (3, 2))
        assert basis == "logical" and saved == 1 and delta is None and expected in reason
        print(f"fallback {name}: {reason}")

    # Neither tuple dominates the other; a weighted score needs an unapproved exchange rate.
    assert (1 - 0.1 * 6) > (0 - 0.1 * -1)
    assert (1 - 0.2 * 6) < (0 - 0.2 * -1)
    print("All six calculations, nine fallback cases and weight-reversal checks passed.")


if __name__ == "__main__":
    main()
