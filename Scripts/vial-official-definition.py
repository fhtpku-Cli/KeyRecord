#!/usr/bin/env python3
"""Generate synthetic topology expectations with unmodified upstream layout parsing.

Loads kle_serial and only the reload_layout method from a supplied vial-gui checkout.
The sideload path and inert protocol methods prevent HID access or GUI initialization.
"""
import argparse
import ast
import base64
import json
import lzma
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source / "src/main/python"
    sys.path.insert(0, str(source))
    from kle_serial import Serial

    tree = ast.parse((source / "protocol/keyboard_comm.py").read_text())
    methods = [node for cls in tree.body if isinstance(cls, ast.ClassDef)
               for node in cls.body if isinstance(node, ast.FunctionDef) and node.name == "reload_layout"]
    if len(methods) != 1:
        raise RuntimeError("Expected one upstream reload_layout method")
    namespace = {"KleSerial": Serial}
    exec(compile(ast.Module(body=methods, type_ignores=[]), "official_reload_layout", "exec"), namespace)

    class Port:
        def __init__(self):
            self.rowcol, self.encoderpos, self.encoder_count = {}, {}, 0

        def reload_via_protocol(self):
            pass

        def check_protocol_version(self):
            pass

    Port.reload_layout = namespace["reload_layout"]
    cases = []
    for alignment in range(8):
        # The decal and alignment cross the row boundary; only decal resets after a key.
        cases.append((f"alignment-{alignment}", [
            [{"a": alignment, "d": True}], ["Legend", "Caption" if alignment not in (0, 4) else "0,2"],
            [{"a": 0}, "0,2", "2,1" + "\n" * 9 + "e"]]))
    cases += [
        ("decal-coordinate-and-reset", [[{"d": True}, "0,2", "0,1", "0,0"]]),
        ("decal-explicit-false", [[{"d": True}, {"d": False}, "0,2"]]),
        ("decal-reset-before-centered-caption", [[{"d": True}, "0,2", {"a": 7}, "Caption", {"a": 0}, "0,2"]]),
        ("encoder-precedes-decal", [["0,0", {"a": 0, "d": True}, "2,1" + "\n" * 9 + "e"]]),
        ("layout-options-and-duplicates", [[{"a": 0}, "0,0\n\n\n0,0", "0,0\n\n\n0,1", "0,2"]]),
        ("leading-metadata", [{"name": "Synthetic"}, ["0,0", "0,2"]]),
    ]
    fixtures = []
    for name, keys in cases:
        definition = {"vendorId": "0x1234", "productId": "0x5678", "matrix": {"rows": 1, "cols": 3},
                      "layouts": {"keymap": keys}}
        port = Port()
        port.reload_layout(sideload_json=definition)
        encoded = json.dumps(definition, separators=(",", ":"))
        fixtures.append({"name": name, "definition": encoded,
                         "compressed": base64.b64encode(lzma.compress(encoded.encode())).decode(),
                         "positions": sorted(map(list, port.rowcol)),
                         "encoders": sorted({(key.encoder_idx, key.encoder_dir) for key in port.encoders})})
    revision = subprocess.check_output(["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip()
    args.output.write_text(json.dumps({"sourceRevision": revision, "cases": fixtures}, indent=2) + "\n")
    print(f"PASS: upstream reload_layout and KLE parsing generated {len(fixtures)} offline topology cases ({revision})")


if __name__ == "__main__":
    main()
