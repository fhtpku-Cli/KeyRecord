#!/usr/bin/env python3
"""Run official Vial save/restore and keycode code against an offline port.

The GUI, HID and feature editors are excluded. Upstream save_layout and
restore_layout bodies are compiled without edits; opaque features use a recorder.
Supply a local checkout and its simpleeval dependency, never a real device.
"""
import argparse
import ast
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="official vial-gui checkout")
    parser.add_argument("--generate", type=Path, help="write an official synthetic export")
    parser.add_argument("--check", type=Path, help="restore a KeyRecord-patched synthetic export")
    args = parser.parse_args()
    if bool(args.generate) == bool(args.check):
        parser.error("choose exactly one of --generate and --check")
    source = args.source / "src/main/python"
    sys.path.insert(0, str(source))
    from keycodes.keycodes import Keycode
    Keycode.protocol = 6

    tree = ast.parse((source / "protocol/keyboard_comm.py").read_text())
    keyboard = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Keyboard")
    methods = [node for node in keyboard.body if isinstance(node, ast.FunctionDef) and node.name in ("save_layout", "restore_layout")]
    if len(methods) != 2:
        raise RuntimeError("official save/restore methods missing")
    namespace = {"json": json, "Keycode": Keycode}
    exec(compile(ast.Module(body=methods, type_ignores=[]), str(source / "protocol/keyboard_comm.py"), "exec"), namespace)

    class Port:
        layers, rows, cols = 2, 2, 4
        keyboard_id = 18446744073709551615
        encoder_count, layout_options, vial_protocol, via_protocol = 0, 0, 6, 9
        settings = {}
        encoder_layout = {}

        def __init__(self):
            self.layout = {(layer, row, col): Keycode.serialize(0)
                           for layer in range(2) for row in range(2) for col in range(4) if (row, col) != (0, 2)}
            self.layout[(0, 0, 0)] = "MO(1)"
            self.layout[(0, 0, 3)] = "KC_ENT"
            self.opaque = {"macro": [["synthetic opaque macro"]], "tap_dance": [[4, 0, 0, 0, 200]],
                           "combo": [[4, 5, 0, 0, 6]], "key_override": [], "alt_repeat_key": []}

        def set_key(self, layer, row, col, code):
            self.layout[(layer, row, col)] = code

        def set_encoder(self, *args):
            raise RuntimeError("fixture has no encoders")

        def set_layout_options(self, value):
            self.layout_options = value

    Port.save_layout = namespace["save_layout"]
    Port.restore_layout = namespace["restore_layout"]
    for field, method in (("macro", "macros"), ("tap_dance", "tap_dance"), ("combo", "combo"),
                          ("key_override", "key_override"), ("alt_repeat_key", "alt_repeat_key")):
        def save(self, field=field):
            return self.opaque[field]
        def restore(self, value, field=field):
            self.opaque[field] = value
        setattr(Port, "save_" + ("macro" if field == "macro" else method), save)
        setattr(Port, "restore_" + method, restore)
    port = Port()
    if args.generate:
        args.generate.write_bytes(port.save_layout())
        print("PASS: official save_layout generated decimal UInt64 UID, Vial 6 metadata and -1 holes")
    else:
        patched = args.check.read_bytes()
        port.restore_layout(patched)
        restored = json.loads(port.save_layout())
        expected = json.loads(patched)
        for layer in range(2):
            for row in range(2):
                for col in range(4):
                    before, after = expected["layout"][layer][row][col], restored["layout"][layer][row][col]
                    if before == -1:
                        assert after == -1
                    else:
                        assert Keycode.deserialize(before, reraise=True) == Keycode.deserialize(after, reraise=True)
        assert Keycode.deserialize(restored["layout"][0][0][1], reraise=True) == 6
        for field in ("uid", "version", "via_protocol", "vial_protocol", "macro", "encoder_layout", "layout_options",
                      "tap_dance", "combo", "key_override", "alt_repeat_key", "settings"):
            assert restored[field] == expected[field], field
        print("PASS: official restore_layout accepted patched KC_C; official save_layout preserved holes, UID and opaque fixture fields")


if __name__ == "__main__":
    main()
