#!/usr/bin/env python3
"""Execute official dynamic GET/reload/save methods with synthetic reports; no HID."""
import argparse
import ast
import json
import struct
import sys
from pathlib import Path
from types import SimpleNamespace

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = args.source / "src/main/python"
sys.path.insert(0, str(source))
from keycodes.keycodes import Keycode, recreate_keyboard_keycodes
from protocol import constants

recreate_keyboard_keycodes(SimpleNamespace(vial_protocol=6, layers=1, macro_count=0,
    tap_dance_count=1, custom_keycodes=None, midi="disabled", supported_features={"repeat_key"}))
namespace = {"struct": struct, "Keycode": Keycode}
namespace.update(vars(constants))
for name in ["base_protocol", "dynamic", "tap_dance", "combo", "key_override", "alt_repeat_key"]:
    tree = ast.parse((source / f"protocol/{name}.py").read_text())
    classes = ast.Module(body=[node for node in tree.body if isinstance(node, ast.ClassDef)], type_ignores=[])
    exec(compile(classes, str(source / f"protocol/{name}.py"), "exec"), namespace)

names = ["ProtocolDynamic", "ProtocolTapDance", "ProtocolCombo", "ProtocolKeyOverride", "ProtocolAltRepeatKey"]
Keyboard = type("OfflineKeyboard", tuple(namespace[name] for name in names), {})
keyboard = Keyboard()
keyboard.vial_protocol = 6
keyboard.dev = None
payloads = {1: struct.pack("<HHHHH", 4, 5, 6, 7, 200),
            3: struct.pack("<HHHHH", 4, 5, 6, 7, 8),
            5: struct.pack("<HHHBBBB", 4, 5, 255, 1, 2, 3, 128),
            7: struct.pack("<HHBB", 4, 5, 3, 8)}
requests = []
def exchange(device, request, **kwargs):
    assert device is None and request[:2] == bytes([0xfe, 0x0d])
    requests.append(list(request))
    if request[2] == 0:
        return bytes([1, 1, 1, 1]) + bytes(28)
    assert request[2] in payloads and request[3] == 0
    return bytes([0]) + payloads[request[2]] + bytes(31 - len(payloads[request[2]]))
keyboard.usb_send = exchange
keyboard.reload_dynamic()
sections = {}
for name in ["tap_dance", "combo", "key_override", "alt_repeat_key"]:
    getattr(keyboard, f"reload_{name}")()
    sections[name] = getattr(keyboard, f"save_{name}")()
assert len(requests) == 5
args.output.write_text(json.dumps({"sections": sections, "requests": requests,
    "payloads": {str(key): list(value) for key, value in payloads.items()}}, indent=2) + "\n")
print("PASS: four official dynamic GET/reload/save protocols executed; five read-only requests")
