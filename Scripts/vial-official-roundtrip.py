#!/usr/bin/env python3
"""Run official Vial save/restore and keycode code against an offline port.

The GUI, HID and feature editors are excluded. Upstream save_layout and
restore_layout bodies are compiled without edits; opaque features use a recorder.
Supply a local checkout and its simpleeval dependency, never a real device.
"""
import argparse
import ast
import json
import lzma
from pathlib import Path
import struct
import sys


class OfficialReadCommandError(RuntimeError):
    def __init__(self, request: bytes) -> None:
        super().__init__(f"unexpected official read command: {request.hex()}")


class OfficialMethodsMissingError(RuntimeError):
    def __init__(self, count: int) -> None:
        super().__init__(f"expected three official save/restore/read methods, found {count}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="official vial-gui checkout")
    parser.add_argument("--generate", type=Path, help="write an official synthetic export")
    parser.add_argument("--check", type=Path, help="restore a KeyRecord-patched synthetic export")
    parser.add_argument("--encoders", action="store_true", help="include sparse, bidirectional encoder mappings")
    parser.add_argument("--definition", type=Path, help="write the corresponding independent synthetic XZ definition")
    parser.add_argument("--basic-keycodes", action="store_true", help="exercise official basic, navigation, numpad and ISO names")
    parser.add_argument("--keycode-fixture", type=Path, help="write official basic/special/ISO raw values and declared aliases")
    parser.add_argument("--modifier-keycodes", action="store_true", help="exercise ordinary canonical modifier combinations")
    parser.add_argument("--modifier-fixture", type=Path, help="write actual ordinary modifier names and working aliases")
    parser.add_argument("--layer-tap-keycodes", action="store_true", help="exercise per-keyboard canonical layer taps on a synthetic 16-layer keyboard")
    parser.add_argument("--raw-keycodes", type=Path, help="write independent big-endian matrix then encoder values for the patched KC_C fixture")
    args = parser.parse_args()
    if bool(args.generate) == bool(args.check):
        parser.error("choose exactly one of --generate and --check")
    source = args.source / "src/main/python"
    sys.path.insert(0, str(source))
    from keycodes.keycodes import Keycode, KEYCODES_BASIC, KEYCODES_SPECIAL, KEYCODES_ISO, recreate_keyboard_keycodes
    from kle_serial import Serial
    from protocol.constants import (BUFFER_FETCH_CHUNK, CMD_VIA_KEYMAP_GET_BUFFER,
                                    CMD_VIA_VIAL_PREFIX, CMD_VIAL_GET_ENCODER)
    from types import SimpleNamespace
    layers = 16 if args.layer_tap_keycodes else 2
    recreate_keyboard_keycodes(SimpleNamespace(vial_protocol=6, layers=layers, macro_count=0, tap_dance_count=0,
                                              custom_keycodes=None, midi="disabled", supported_features=set()))
    if args.layer_tap_keycodes:
        for layer in range(layers):
            raw = 0x4000 | layer << 8 | 6
            assert Keycode.serialize(raw) == f"LT{layer}(KC_C)"
            assert Keycode.deserialize(Keycode.serialize(raw), reraise=True) == raw
        print(f"PASS: official per-keyboard initialization generated {layers} canonical layer-tap names")
    if args.modifier_fixture:
        from any_keycode import functions
        from simpleeval import FunctionNotDefined
        entries = []
        for mask in (0x0100, 0x0200, 0x0400, 0x0800, 0x1100, 0x1200, 0x1400, 0x1800,
                     0x0300, 0x0500, 0x0600, 0x0700, 0x0900, 0x0a00, 0x0c00, 0x0d00, 0x0f00, 0x1900):
            canonical = Keycode.serialize(mask | 6)
            prefix = canonical.split("(")[0]
            aliases = [name + "(KC_C)" for name, function in functions.items()
                       if name != prefix and function is functions[prefix]]
            for token in [canonical] + aliases:
                assert Keycode.deserialize(token, reraise=True) == mask | 6
            for key in KEYCODES_SPECIAL + KEYCODES_BASIC + KEYCODES_ISO:
                raw = Keycode.deserialize(key.qmk_id, reraise=True)
                if raw > 1:
                    for token in [canonical] + aliases:
                        assert Keycode.deserialize(token.replace("KC_C", key.qmk_id), reraise=True) == mask | raw
            entries.append({"token": canonical, "raw": mask | 6, "aliases": aliases})
        try:
            Keycode.deserialize("LCS(KC_C)", reraise=True)
        except FunctionNotDefined:
            assert Keycode.deserialize("LCS(KC_C)") == 0
        else:
            raise AssertionError("LCS unexpectedly became a working upstream alias")
        args.modifier_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official ordinary modifiers checked {len(entries)} canonical names and {sum(len(entry['aliases']) for entry in entries)} working aliases; LCS rejected")
    if args.keycode_fixture:
        entries = []
        for key in KEYCODES_SPECIAL + KEYCODES_BASIC + KEYCODES_ISO:
            raw = Keycode.deserialize(key.qmk_id, reraise=True)
            canonical = Keycode.serialize(raw)
            assert canonical == key.qmk_id
            assert Keycode.deserialize(canonical, reraise=True) == raw
            for alias in key.alias:
                assert Keycode.deserialize(alias, reraise=True) == raw
            entries.append({"token": canonical, "raw": raw, "aliases": key.alias[1:]})
        args.keycode_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official serialize/deserialize checked {len(entries)} basic/special/ISO keycodes and their declared aliases")

    tree = ast.parse((source / "protocol/keyboard_comm.py").read_text())
    keyboard = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Keyboard")
    methods = [node for node in keyboard.body if isinstance(node, ast.FunctionDef) and node.name in ("save_layout", "restore_layout", "reload_keymap")]
    if len(methods) != 3:
        raise OfficialMethodsMissingError(len(methods))
    namespace = {"json": json, "struct": struct, "Keycode": Keycode, "BUFFER_FETCH_CHUNK": BUFFER_FETCH_CHUNK,
                 "CMD_VIA_KEYMAP_GET_BUFFER": CMD_VIA_KEYMAP_GET_BUFFER, "CMD_VIA_VIAL_PREFIX": CMD_VIA_VIAL_PREFIX,
                 "CMD_VIAL_GET_ENCODER": CMD_VIAL_GET_ENCODER}
    exec(compile(ast.Module(body=methods, type_ignores=[]), str(source / "protocol/keyboard_comm.py"), "exec"), namespace)

    class Port:
        layers, rows, cols = 2, 2, 4
        keyboard_id = 18446744073709551615
        encoder_count, layout_options, vial_protocol, via_protocol = 0, 0, 6, 9
        settings = {}
        encoder_layout = {}

        def __init__(self):
            self.layers = layers
            self.layout = {(layer, row, col): Keycode.serialize(0)
                           for layer in range(self.layers) for row in range(2) for col in range(4) if (row, col) != (0, 2)}
            self.layout[(0, 0, 0)] = "MO(1)"
            self.layout[(0, 0, 3)] = "KC_ENT"
            self.encoder_count = 3 if args.encoders else 0
            self.encoderpos = {2: True} if args.encoders else {}
            self.encoder_layout = {(0, 2, 0): Keycode.serialize(0x28), (0, 2, 1): Keycode.serialize(0x1106),
                                   (1, 2, 0): Keycode.serialize(6), (1, 2, 1): Keycode.serialize(1)} if args.encoders else {}
            if args.basic_keycodes:
                slots = [slot for slot in self.layout if slot not in ((0, 0, 0), (0, 0, 1))]
                raw = [0x34, 0x31, 0x33, 0x35, 0x29, 0x4e, 0x59, 0x67, 0x65, 0x32, 0x64, 0x85]
                assert len(slots) == len(raw)
                self.layout.update({slot: Keycode.serialize(code) for slot, code in zip(slots, raw)})
                if args.encoders:
                    self.encoder_layout = {(0, 2, 0): Keycode.serialize(0x34), (0, 2, 1): Keycode.serialize(0x1234),
                                           (1, 2, 0): Keycode.serialize(0x85), (1, 2, 1): Keycode.serialize(0x62)}
            if args.modifier_keycodes:
                slots = [slot for slot in self.layout if slot not in ((0, 0, 0), (0, 0, 1))]
                raw = [0x0306, 0x0506, 0x0606, 0x0706, 0x0906, 0x0a06, 0x0c06, 0x0d06, 0x0f06, 0x1906, 0x0a34, 0x1985]
                assert len(slots) == len(raw)
                self.layout.update({slot: Keycode.serialize(code) for slot, code in zip(slots, raw)})
                if args.encoders:
                    self.encoder_layout = {(0, 2, 0): Keycode.serialize(0x0f34), (0, 2, 1): Keycode.serialize(0x1958),
                                           (1, 2, 0): Keycode.serialize(0x0a85), (1, 2, 1): Keycode.serialize(0x0d62)}
            if args.layer_tap_keycodes:
                self.layout[(0, 0, 0)] = Keycode.serialize(0x4158)
                for layer in range(self.layers):
                    self.layout[(layer, 0, 3)] = Keycode.serialize(0x4000 | layer << 8 | 0x34)
                    if args.encoders:
                        self.encoder_layout[(layer, 2, 0)] = Keycode.serialize(0x4000 | layer << 8 | 0x58)
                        self.encoder_layout[(layer, 2, 1)] = Keycode.serialize(0x1906)
            self.rowcol = {(row, col): True for _, row, col in self.layout}
            self.layout_labels = []
            self.dev = 0
            self.queries: list[bytes] = []
            self.opaque = {"macro": [["synthetic opaque macro"]], "tap_dance": [[4, 0, 0, 0, 200]],
                           "combo": [[4, 5, 0, 0, 6]], "key_override": [], "alt_repeat_key": []}

        def set_key(self, layer, row, col, code):
            self.layout[(layer, row, col)] = code

        def set_encoder(self, layer: int, index: int, direction: int, code: str) -> None:
            if index in self.encoderpos:
                self.encoder_layout[(layer, index, direction)] = code

        def usb_send(self, device: int, request: bytes, retries: int) -> bytes:
            self.queries.append(request)
            if request[0] == CMD_VIA_KEYMAP_GET_BUFFER:
                offset, size = struct.unpack(">HB", request[1:4])
                keymap = b"".join(struct.pack(">H", Keycode.deserialize(self.layout.get((layer, row, col), "KC_NO"), reraise=True))
                                  for layer in range(self.layers) for row in range(self.rows) for col in range(self.cols))
                return request + keymap[offset:offset + size] + bytes(28 - size)
            if request[:2] == bytes([CMD_VIA_VIAL_PREFIX, CMD_VIAL_GET_ENCODER]):
                layer, index = request[2:4]
                return b"".join(struct.pack(">H", Keycode.deserialize(self.encoder_layout[(layer, index, direction)], reraise=True))
                                for direction in range(2)) + bytes(28)
            raise OfficialReadCommandError(request)

        def set_layout_options(self, value):
            self.layout_options = value

    Port.save_layout = namespace["save_layout"]
    Port.restore_layout = namespace["restore_layout"]
    Port.reload_keymap = namespace["reload_keymap"]
    for field, method in (("macro", "macros"), ("tap_dance", "tap_dance"), ("combo", "combo"),
                          ("key_override", "key_override"), ("alt_repeat_key", "alt_repeat_key")):
        def save(self, field=field):
            return self.opaque[field]
        def restore(self, value, field=field):
            self.opaque[field] = value
        setattr(Port, "save_" + ("macro" if field == "macro" else method), save)
        setattr(Port, "restore_" + method, restore)
    port = Port()
    if args.definition:
        keys = [f"{row},{col}" for row in range(2) for col in range(4) if (row, col) != (0, 2)]
        if args.encoders:
            keys += [{"a": 0}, "2,1" + "\n" * 9 + "e"]
            for alignment in (0, 4):
                parsed = Serial().deserialize([[{"a": alignment}, "2,1" + "\n" * 9 + "e"]])
                assert parsed.keys[0].labels[4] == "e"
                assert parsed.keys[0].labels[0] == "2,1"
        definition = {"vendorId": "0x1234", "productId": "0x5678", "matrix": {"rows": 2, "cols": 4},
                      "layouts": {"keymap": [keys]}}
        args.definition.write_bytes(lzma.compress(json.dumps(definition).encode()))
    if args.generate:
        args.generate.write_bytes(port.save_layout())
        print("PASS: official save_layout generated decimal UInt64 UID, Vial 6 metadata and -1 holes")
    else:
        patched = args.check.read_bytes()
        port.restore_layout(patched)
        restored = json.loads(port.save_layout())
        expected = json.loads(patched)
        for layer in range(port.layers):
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
    if args.raw_keycodes:
        raw = bytearray()
        for layer in range(port.layers):
            for row in range(port.rows):
                for col in range(port.cols):
                    code = "KC_C" if (layer, row, col) == (0, 0, 1) else port.layout.get((layer, row, col))
                    raw += struct.pack(">H", 0xffff if code is None else Keycode.deserialize(code, reraise=True))
        for slot in sorted(port.encoder_layout):
            raw += struct.pack(">H", Keycode.deserialize(port.encoder_layout[slot], reraise=True))
        args.raw_keycodes.write_bytes(raw)
        print(f"PASS: official deserialize emitted {len(raw)} independent big-endian matrix/encoder bytes")
    before_matrix = {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()}
    before_encoders = {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.encoder_layout.items()}
    port.reload_keymap()
    assert {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()} == before_matrix
    assert {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.encoder_layout.items()} == before_encoders
    encoder_queries = [query for query in port.queries if query[:2] == bytes([CMD_VIA_VIAL_PREFIX, CMD_VIAL_GET_ENCODER])]
    assert encoder_queries == ([bytes([0xfe, 3, layer, 2]) for layer in range(port.layers)] if args.encoders else [])
    print(f"PASS: official reload_keymap issued {len(encoder_queries)} encoder queries and preserved both directions")


if __name__ == "__main__":
    main()
