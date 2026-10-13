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
    args = parser.parse_args()
    if bool(args.generate) == bool(args.check):
        parser.error("choose exactly one of --generate and --check")
    source = args.source / "src/main/python"
    sys.path.insert(0, str(source))
    from keycodes.keycodes import Keycode, KEYCODES_BASIC, KEYCODES_SPECIAL, KEYCODES_ISO
    from kle_serial import Serial
    from protocol.constants import (BUFFER_FETCH_CHUNK, CMD_VIA_KEYMAP_GET_BUFFER,
                                    CMD_VIA_VIAL_PREFIX, CMD_VIAL_GET_ENCODER)
    Keycode.protocol = 6
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
            self.layout = {(layer, row, col): Keycode.serialize(0)
                           for layer in range(2) for row in range(2) for col in range(4) if (row, col) != (0, 2)}
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
    before_matrix = {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()}
    before_encoders = {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.encoder_layout.items()}
    port.reload_keymap()
    assert {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()} == before_matrix
    assert {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.encoder_layout.items()} == before_encoders
    encoder_queries = [query for query in port.queries if query[:2] == bytes([CMD_VIA_VIAL_PREFIX, CMD_VIAL_GET_ENCODER])]
    assert encoder_queries == ([bytes([0xfe, 3, 0, 2]), bytes([0xfe, 3, 1, 2])] if args.encoders else [])
    print(f"PASS: official reload_keymap issued {len(encoder_queries)} encoder queries and preserved both directions")


if __name__ == "__main__":
    main()
