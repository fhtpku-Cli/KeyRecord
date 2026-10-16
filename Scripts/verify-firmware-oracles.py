#!/usr/bin/env python3
"""Execute official offline methods and the Swift transaction against synthetic data."""
import argparse
import base64
import json
import lzma
import os
from pathlib import Path
import subprocess
import sys


def compare_fixture(actual_path, expected_path):
    actual = json.loads(actual_path.read_text())
    expected = json.loads(expected_path.read_text())
    # XZ encoders may emit different containers for identical definition bytes.
    if actual_path.name == "vial6-definition-topology.json":
        for document in (actual, expected):
            for case in document["cases"]:
                case["compressed"] = lzma.decompress(base64.b64decode(case["compressed"])).decode()
    if actual != expected:
        raise AssertionError(f"Official result differs from the Swift test fixture: {expected_path.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vial-source", type=Path, required=True)
    parser.add_argument("--via-source", type=Path, required=True)
    parser.add_argument("--reader", type=Path, required=True)
    parser.add_argument("--via-store-dependencies", type=Path,
                        help="node_modules containing the official store's Redux and TypeScript dependencies; defaults beside reader")
    parser.add_argument("--simpleeval-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    fixtures = root / "evidence/phase4/fixtures/synthetic"
    environment = os.environ.copy()
    environment["PYTHONPATH"] = str(args.simpleeval_source.resolve())
    environment.pop("PYTHONOPTIMIZE", None)
    environment.pop("PYTHONSTARTUP", None)

    def run(name, command):
        print(f"Running {name}", flush=True)
        with (output / f"{name}.log").open("w") as log:
            result = subprocess.run([str(part) for part in command], cwd=root, env=environment,
                                    stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            print((output / f"{name}.log").read_text(), file=sys.stderr)
            raise subprocess.CalledProcessError(result.returncode, command)

    def oracle(script, filename):
        run(script, [sys.executable, root / "Scripts" / f"{script}.py", "--source",
                     args.vial_source.resolve(), "--output", output / filename])
        compare_fixture(output / filename, fixtures / filename)

    oracle("vial-dynamic-oracle", "vial6-dynamic-entries.json")
    oracle("vial-configuration-oracle", "vial6-configuration.json")
    oracle("vial-official-definition", "vial6-definition-topology.json")
    run("via-definition-oracle", ["node", root / "Scripts/via-definition-oracle.cjs",
        args.reader.resolve(), args.via_source.resolve(), output / "via-compiled-definitions.json"])
    compare_fixture(output / "via-compiled-definitions.json", fixtures / "via-compiled-definitions.json")
    store_dependencies = args.via_store_dependencies or args.reader.resolve().parent.parent
    run("via-session-oracle", ["node", root / "Scripts/via-session-oracle.cjs",
                              args.via_source.resolve(), store_dependencies.resolve()])
    run("via-keycode-oracle", ["node", root / "Scripts/via-keycode-oracle.cjs",
                              args.via_source.resolve(), store_dependencies.resolve(), args.reader.resolve()])

    modes = ["basic", "modifier", "modifier-tap", "one-shot", "persistent-layer", "static-layer", "to",
             "layer-tap", "layer-mod"]
    for mode in modes:
        common = [sys.executable, root / "Scripts/vial-official-roundtrip.py", "--source",
                  args.vial_source.resolve(), f"--{mode}-keycodes", "--encoders"]
        original, patched = output / f"{mode}-original.vil", output / f"{mode}-patched.vil"
        definition, raw = output / f"{mode}-definition.xz", output / f"{mode}-raw.bin"
        fixture = f"vial6-{mode}-keycodes.json"
        fixture_option = "--keycode-fixture" if mode == "basic" else f"--{mode}-fixture"
        options = [] if mode in ("layer-tap", "layer-mod") else [fixture_option, output / fixture]
        run(f"{mode}-generate", common + ["--generate", original, "--definition", definition,
                                        "--raw-keycodes", raw] + options)
        if options:
            compare_fixture(output / fixture, fixtures / fixture)
        run(f"{mode}-transaction", ["swift", "run", "KeyRecordFirmwareIntegrationProbe",
                                   original, patched, definition, raw])
        run(f"{mode}-restore", common + ["--check", patched])
    print("PASS: 11 official fixtures, 10 active-source scenarios, 10 VIA Fn keycode round trips and 9 official/Swift encrypted transaction round trips", flush=True)


if __name__ == "__main__":
    main()
