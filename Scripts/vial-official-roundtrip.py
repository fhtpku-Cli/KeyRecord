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
    parser.add_argument("--scope-probe", action="store_true", help="prove official restore changes opaque sections without changing the keymap")
    parser.add_argument("--definition", type=Path, help="write the corresponding independent synthetic XZ definition")
    parser.add_argument("--basic-keycodes", action="store_true", help="exercise official basic, navigation, numpad and ISO names")
    parser.add_argument("--keycode-fixture", type=Path, help="write official basic/special/ISO raw values and declared aliases")
    parser.add_argument("--modifier-keycodes", action="store_true", help="exercise ordinary canonical modifier combinations")
    parser.add_argument("--modifier-fixture", type=Path, help="write actual ordinary modifier names and working aliases")
    parser.add_argument("--modifier-tap-keycodes", action="store_true", help="exercise static canonical modifier taps with basic children")
    parser.add_argument("--modifier-tap-fixture", type=Path, help="write actual static modifier-tap names and working aliases")
    parser.add_argument("--one-shot-keycodes", action="store_true", help="exercise static canonical one-shot modifier names")
    parser.add_argument("--one-shot-fixture", type=Path, help="write actual canonical one-shot modifier names and raw values")
    parser.add_argument("--persistent-layer-keycodes", action="store_true", help="exercise canonical persistent default layers on a synthetic 32-layer keyboard")
    parser.add_argument("--persistent-layer-fixture", type=Path, help="write actual canonical persistent default layer names and raw values")
    parser.add_argument("--static-layer-keycodes", action="store_true", help="exercise canonical static layer actions on a synthetic four-layer keyboard")
    parser.add_argument("--static-layer-fixture", type=Path, help="write actual static layer action names and raw values")
    parser.add_argument("--to-keycodes", action="store_true", help="exercise canonical TO names on a synthetic 32-layer keyboard")
    parser.add_argument("--to-fixture", type=Path, help="write official canonical TO names and raw values")
    parser.add_argument("--layer-tap-keycodes", action="store_true", help="exercise per-keyboard canonical layer taps on a synthetic 16-layer keyboard")
    parser.add_argument("--layer-mod-keycodes", action="store_true", help="exercise protected layer modifiers with official hexadecimal serialization on 16 layers")
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
    layers = 32 if args.persistent_layer_keycodes or args.to_keycodes else (16 if args.layer_tap_keycodes or args.layer_mod_keycodes else (4 if args.static_layer_keycodes else 2))
    features = {"persistent_default_layer"} if args.persistent_layer_keycodes else set()
    if args.static_layer_keycodes:
        features.add("layer_lock")
    recreate_keyboard_keycodes(SimpleNamespace(vial_protocol=6, layers=layers, macro_count=0, tap_dance_count=0,
                                              custom_keycodes=None, midi="disabled", supported_features=features))
    if args.to_fixture:
        from keycodes.keycodes import KEYCODES_LAYERS
        entries = []
        for key in KEYCODES_LAYERS:
            if key.qmk_id.startswith("TO("):
                raw = Keycode.deserialize(key.qmk_id, reraise=True)
                assert Keycode.serialize(raw) == key.qmk_id
                entries.append({"token": key.qmk_id, "raw": raw})
        assert {entry["raw"] for entry in entries} == set(range(0x5200, 0x5200 + layers))
        assert Keycode.deserialize("TO(1)", reraise=True) == 0x5201
        assert Keycode.deserialize(" TO(1)", reraise=True) == 0x5211
        args.to_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official TO checked {len(entries)} canonical names; expression whitespace has different encoding")
    if args.layer_mod_keycodes:
        for layer in range(16):
            for mask in range(32):
                raw = Keycode.deserialize(f"LM({layer},{mask})", reraise=True)
                assert raw == 0x5000 | (layer << 5) | mask
                assert Keycode.serialize(raw) == f"0x{raw:04x}"
                assert Keycode.deserialize(Keycode.serialize(raw), reraise=True) == raw
        print("PASS: official LM checked all 512 layer/mask encodings and canonical hexadecimal round trips")
    if args.static_layer_fixture:
        from keycodes.keycodes import KEYCODES_LAYERS
        from simpleeval import NameNotDefined
        entries = []
        for key in KEYCODES_LAYERS:
            if key.qmk_id not in ("FN_MO13", "FN_MO23", "QK_LAYER_LOCK"):
                continue
            raw = Keycode.deserialize(key.qmk_id, reraise=True)
            assert Keycode.serialize(raw) == key.qmk_id
            assert Keycode.deserialize(Keycode.serialize(raw), reraise=True) == raw
            if key.qmk_id == "QK_LAYER_LOCK":
                assert key.requires_feature == "layer_lock" and "QK_LLCK" in key.alias
            entries.append({"token": key.qmk_id, "raw": raw, "aliases": []})
        assert {entry["raw"] for entry in entries} == {0x7c77, 0x7c78, 0x7c7b}
        try:
            Keycode.deserialize("QK_LLCK", reraise=True)
        except NameNotDefined:
            assert Keycode.deserialize("QK_LLCK") == 0
        else:
            raise AssertionError("QK_LLCK unexpectedly became a registered upstream alias")
        args.static_layer_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official static layer actions checked {len(entries)} canonical names; QK_LLCK is not registered")
    if args.persistent_layer_fixture:
        from keycodes.keycodes import KEYCODES_LAYERS
        from any_keycode import functions
        from simpleeval import FunctionNotDefined
        entries = []
        for key in KEYCODES_LAYERS:
            if not key.qmk_id.startswith("PDF("):
                continue
            raw = Keycode.deserialize(key.qmk_id, reraise=True)
            assert Keycode.serialize(raw) == key.qmk_id
            assert Keycode.deserialize(Keycode.serialize(raw), reraise=True) == raw
            assert key.requires_feature == "persistent_default_layer"
            entries.append({"token": key.qmk_id, "raw": raw, "aliases": []})
        assert {entry["raw"] for entry in entries} == set(range(0x52e0, 0x52e0 + layers))
        assert "PDF" not in functions
        for token in ("PDF(32)", "PDF(0x1)", "PDF (1)", " PDF(1)", "PDF(USER00)"):
            try:
                Keycode.deserialize(token, reraise=True)
            except FunctionNotDefined:
                pass
            else:
                raise AssertionError(f"{token} unexpectedly became an upstream function")
        args.persistent_layer_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official persistent default layers checked {len(entries)} canonical names; PDF is not an expression function")
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

    if args.modifier_tap_fixture:
        from any_keycode import functions
        from simpleeval import FunctionNotDefined
        entries = []
        for mask in (0x2200, 0x2100, 0x2400, 0x2800, 0x3200, 0x3100, 0x3400, 0x3800,
                     0x2300, 0x2500, 0x2900, 0x2600, 0x2c00, 0x2a00, 0x2d00, 0x3900, 0x3d00, 0x2700, 0x2f00):
            canonical = Keycode.serialize(mask | 6)
            prefix = canonical.split("(")[0]
            aliases = [name + "(KC_C)" for name, function in functions.items()
                       if name != prefix and function is functions[prefix]]
            for key in KEYCODES_SPECIAL + KEYCODES_BASIC + KEYCODES_ISO:
                raw = Keycode.deserialize(key.qmk_id, reraise=True)
                assert Keycode.serialize(mask | raw) == canonical.replace("KC_C", key.qmk_id)
                for token in [canonical] + aliases:
                    for child in key.alias:
                        assert Keycode.deserialize(token.replace("KC_C", child), reraise=True) == mask | raw
            entries.append({"token": canonical, "raw": mask | 6, "aliases": aliases})
        try:
            Keycode.deserialize("LCS_T(KC_C)", reraise=True)
        except FunctionNotDefined:
            pass
        else:
            raise AssertionError("LCS_T unexpectedly became a working upstream alias")
        for token, raw in (("RSA_T(KC_C)", 0x3606), ("RCS_T(KC_C)", 0x3306)):
            assert Keycode.deserialize(token, reraise=True) == raw
            assert Keycode.serialize(raw) == f"0x{raw:04x}"
        assert Keycode.deserialize("KC_SFTENT", reraise=True) == 0x7c1e
        assert Keycode.serialize(0x7c1e) == "KC_SFTENT"
        args.modifier_tap_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official static modifier taps checked {len(entries)} canonical names and {sum(len(entry['aliases']) for entry in entries)} working aliases; LCS_T rejected; RSA_T/RCS_T serialize as hex; KC_SFTENT is a separate action")

    if args.one_shot_fixture:
        from keycodes.keycodes import KEYCODES_MODIFIERS
        entries = []
        for key in KEYCODES_MODIFIERS:
            if not key.qmk_id.startswith("OSM("):
                continue
            raw = Keycode.deserialize(key.qmk_id, reraise=True)
            assert Keycode.serialize(raw) == key.qmk_id
            assert Keycode.deserialize(Keycode.serialize(raw), reraise=True) == raw
            entries.append({"token": key.qmk_id, "raw": raw, "aliases": []})
        assert {entry["raw"] for entry in entries} == set(range(0x52a1, 0x52b0)) | set(range(0x52b1, 0x52c0))
        assert Keycode.serialize(Keycode.deserialize("OSM(0x40)", reraise=True)) == "PDF(0)"
        assert Keycode.serialize(Keycode.deserialize("OSM(MOD_LCTL|MOD_RCTL)", reraise=True)) == "OSM(MOD_RCTL)"
        args.one_shot_fixture.write_text("[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n")
        print(f"PASS: official one-shot modifiers checked {len(entries)} canonical names; numeric OSM can serialize as PDF and mixed sides collapse to right")

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
        encoder_count, layout_options, vial_protocol, via_protocol = 0, -1, 6, 9
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
            if args.modifier_tap_keycodes:
                slots = [slot for slot in self.layout if slot not in ((0, 0, 0), (0, 0, 1))]
                raw = [0x2206, 0x2106, 0x2406, 0x2806, 0x3206, 0x3106, 0x3406, 0x3806, 0x2306, 0x2506, 0x2906, 0x2606]
                assert len(slots) == len(raw)
                self.layout.update({slot: Keycode.serialize(code) for slot, code in zip(slots, raw)})
                if args.encoders:
                    self.encoder_layout = {(0, 2, 0): Keycode.serialize(0x2f34), (0, 2, 1): Keycode.serialize(0x3958),
                                           (1, 2, 0): Keycode.serialize(0x2a85), (1, 2, 1): Keycode.serialize(0x2d62)}
            if args.one_shot_keycodes:
                slots = [slot for slot in self.layout if slot not in ((0, 0, 0), (0, 0, 1))]
                raw = list(range(0x52a1, 0x52ad))
                assert len(slots) == len(raw)
                self.layout.update({slot: Keycode.serialize(code) for slot, code in zip(slots, raw)})
                if args.encoders:
                    self.encoder_layout = {(0, 2, 0): Keycode.serialize(0x52ad), (0, 2, 1): Keycode.serialize(0x52ae),
                                           (1, 2, 0): Keycode.serialize(0x52af), (1, 2, 1): Keycode.serialize(0x52bf)}
            if args.persistent_layer_keycodes:
                for layer in range(self.layers):
                    self.layout[(layer, 0, 3)] = Keycode.serialize(0x52e0 + layer)
                    if args.encoders:
                        self.encoder_layout[(layer, 2, 0)] = Keycode.serialize(0x52e0 + layer)
                        self.encoder_layout[(layer, 2, 1)] = Keycode.serialize(0x52ff - layer)
            if args.to_keycodes:
                self.layout[(0, 0, 0)] = Keycode.serialize(0x5201)
                for layer in range(self.layers):
                    self.layout[(layer, 0, 3)] = Keycode.serialize(0x5200 + layer)
                    if args.encoders:
                        self.encoder_layout[(layer, 2, 0)] = Keycode.serialize(0x5200 + layer)
                        self.encoder_layout[(layer, 2, 1)] = Keycode.serialize(0x521f - layer)
            if args.static_layer_keycodes:
                actions = (0x7c77, 0x7c78, 0x7c7b)
                for layer in range(self.layers):
                    for col, raw in enumerate(actions):
                        self.layout[(layer, 1, col)] = Keycode.serialize(raw)
                    if args.encoders:
                        self.encoder_layout[(layer, 2, 0)] = Keycode.serialize(actions[layer % 3])
                        self.encoder_layout[(layer, 2, 1)] = Keycode.serialize(actions[(layer + 1) % 3])
            if args.layer_mod_keycodes:
                for layer in range(self.layers):
                    for col, mask in enumerate((0, 1, 31)):
                        self.layout[(layer, 1, col)] = Keycode.serialize(Keycode.deserialize(f"LM({layer},{mask})", reraise=True))
                    if args.encoders:
                        for direction, mask in enumerate((1, 31)):
                            self.encoder_layout[(layer, 2, direction)] = Keycode.serialize(Keycode.deserialize(f"LM({layer},{mask})", reraise=True))
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
    if args.scope_probe:
        saved = port.save_layout()
        expected = json.loads(saved)
        before = {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()}
        port.opaque = {field: ["different synthetic content"] for field in port.opaque}
        port.layout_options = 1
        port.restore_layout(saved)
        after = json.loads(port.save_layout())
        for field in ("macro", "tap_dance", "combo", "key_override", "alt_repeat_key", "layout_options"):
            assert after[field] == expected[field], field
        assert {slot: Keycode.deserialize(code, reraise=True) for slot, code in port.layout.items()} == before
        print("PASS: official restore changed six opaque/layout sections while every keymap value stayed identical")
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
