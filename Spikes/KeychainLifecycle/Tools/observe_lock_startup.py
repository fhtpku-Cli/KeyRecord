"""Observe fresh diagnostic processes; never lock, unlock, or open Keychain."""
import argparse
import json
import platform
import signal
import subprocess
import time
from pathlib import Path


def sample(probe, timeout):
    result = subprocess.run([str(probe)], capture_output=True, text=True,
                            check=True, timeout=timeout)
    observation = json.loads(result.stdout)
    expected = {"available", "onConsole", "currentUserMatches", "screenLocked"}
    if set(observation) != {"before", "after", "consoleLocked"}:
        raise ValueError("Unexpected probe fields")
    for key in ("before", "after"):
        if set(observation[key]) != expected:
            raise ValueError("Unexpected session fields")
        if not all(value in ("true", "false", "unknown")
                   for value in observation[key].values()):
            raise ValueError("Unexpected session values")
    if observation["consoleLocked"] not in ("true", "false", "unknown"):
        raise ValueError("Unexpected console value")
    return observation


def observe(probe, duration):
    stopped = False

    def stop(_signal, _frame):
        nonlocal stopped
        stopped = True

    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
    started = time.monotonic()
    count = 0
    reason = "duration"
    try:
        print(json.dumps({"kind": "start", "macOS": platform.mac_ver()[0],
                          "architecture": platform.machine(), "duration": duration,
                          "scope": "fresh diagnostic process inputs; no qualification"}), flush=True)
        while not stopped and time.monotonic() - started < duration:
            remaining = duration - (time.monotonic() - started)
            try:
                value = sample(probe, max(0.001, min(2.0, remaining)))
            except Exception as error:
                reason = type(error).__name__
                return 1
            count += 1
            print(json.dumps({"kind": "sample", "index": count,
                              "elapsed": round(time.monotonic() - started, 3),
                              "inputs": value}), flush=True)
            remaining = duration - (time.monotonic() - started)
            if remaining > 0 and not stopped:
                time.sleep(min(1.0, remaining))
        if stopped:
            reason = "operatorStop"
        return 0
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        print(json.dumps({"kind": "end", "samples": count, "reason": reason,
                          "elapsed": round(time.monotonic() - started, 3),
                          "qualification": "not_assessed"}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--duration", type=int, default=60, choices=range(1, 61))
    args = parser.parse_args()
    if not args.probe.is_absolute() or not args.probe.is_file():
        parser.error("probe must be an existing absolute executable path")
    raise SystemExit(observe(args.probe, args.duration))
