#!/usr/bin/env python3
import argparse
import ast
import json
import struct
import sys
from collections import defaultdict
from pathlib import Path
from types import ModuleType, SimpleNamespace

parser = argparse.ArgumentParser(description="Execute official configuration readers against synthetic reports; no HID")
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = args.source / "src/main/python"
sys.path.insert(0, str(source))
from keycodes.keycodes import Keycode, recreate_keyboard_keycodes
from macro import macro_action
from protocol import constants

recreate_keyboard_keycodes(SimpleNamespace(vial_protocol=6, layers=1, macro_count=2,
    tap_dance_count=0, custom_keycodes=None, midi="disabled", supported_features=set()))
namespace = {"struct": struct, "Keycode": Keycode, "defaultdict": defaultdict, "json": json}
namespace.update(vars(constants))
namespace.update(vars(macro_action))
for name in ["base_protocol", "macro"]:
    path = source / f"protocol/{name}.py"
    tree = ast.parse(path.read_text())
    nodes = [n for n in tree.body if isinstance(n, (ast.ClassDef, ast.FunctionDef))]
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), "exec"), namespace)

def load_methods(path, class_name, methods):
    tree = ast.parse(path.read_text())
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == class_name)
    selected = ast.ClassDef(name=class_name, bases=[], keywords=[],
        body=[n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name in methods], decorator_list=[])
    module = ast.fix_missing_locations(ast.Module(body=[selected], type_ignores=[]))
    exec(compile(module, str(path), "exec"), namespace)
    return namespace[class_name]

settings_class = load_methods(source / "editor/qmk_settings.py", "QmkSettings",
    ["initialize", "is_qsid_supported", "qsid_serialize", "qsid_deserialize"])
settings_class.initialize(SimpleNamespace(get_resource=lambda name: str(args.source / "src/main/resources/base" / name)))
module = ModuleType("editor.qmk_settings")
module.QmkSettings = settings_class
sys.modules["editor.qmk_settings"] = module
reader = load_methods(source / "protocol/keyboard_comm.py", "Keyboard", ["reload_keymap", "reload_settings"])
Keyboard = type("OfflineKeyboard", (namespace["ProtocolMacro"], reader), {})
keyboard = Keyboard()
keyboard.vial_protocol = 6
keyboard.dev = None
keyboard.layers = keyboard.rows = keyboard.cols = 0
keyboard.rowcol = keyboard.encoderpos = {}
keyboard.layout_labels = ["fixture"]
macro = [[ ["text", "a" * 27], ["tap", "KC_A", "TO(0)"], ["down", "KC_LSHIFT"],
    ["up", "KC_LSHIFT"], ["delay", 65024] ], []]
actions = []
classes = {c.tag: c for c in [macro_action.ActionText, macro_action.ActionTap,
    macro_action.ActionDown, macro_action.ActionUp, macro_action.ActionDelay]}
for entry in macro:
    row = []
    for action in entry:
        obj = classes[action[0]]()
        obj.restore(action)
        row.append(obj)
    actions.append(row)
keyboard.macro_count = 2
wire = keyboard.macros_serialize(actions)
widths = {key: fields[0].get("width", 1) for key, fields in settings_class.qsid_fields.items()}
values = {key: (1 << (width * 8)) - key for key, width in widths.items()}
requests = []
def exchange(device, request, **kwargs):
    assert device is None
    requests.append(list(request))
    reply = bytearray(32)
    if request[0] == 0x0c:
        reply[:2] = bytes([0x0c, 2])
    elif request[0] == 0x0d:
        reply[:3] = bytes([0x0d, 0, 96])
    elif request[0] == 0x0e:
        offset, size = struct.unpack(">HB", request[1:4])
        reply[:4] = request
        reply[4:4+size] = (wire + bytes(96))[offset:offset+size]
    elif request == bytes([2, 2]):
        reply[:6] = bytes([2, 2, 1, 2, 3, 4])
    elif request[:2] == bytes([0xfe, 9]):
        cursor = int.from_bytes(request[2:4], "little")
        ids = [key for key in sorted(widths) if key > cursor][:16]
        reply = b"".join(key.to_bytes(2, "little") for key in ids + [65535] * (16-len(ids)))
    elif request[:2] == bytes([0xfe, 10]):
        key = int.from_bytes(request[2:4], "little")
        data = settings_class.qsid_serialize(key, values[key])
        reply[1:1+len(data)] = data
    else:
        raise AssertionError(f"Unexpected or mutating request: {request!r}")
    return bytes(reply)
keyboard.usb_send = exchange
keyboard.reload_macros()
assert keyboard.save_macro() == macro, (keyboard.save_macro(), macro)
keyboard.reload_keymap()
keyboard.reload_settings()
assert keyboard.settings == values and keyboard.layout_options == 0x01020304
args.output.write_text(json.dumps({"macro": macro, "macro_buffer": list(wire),
    "layout_options": keyboard.layout_options, "settings": keyboard.settings,
    "widths": widths, "requests": requests}, indent=2) + "\n")
print("PASS: official macro serialize/read/save, layout read and all 27 QMK setting reads executed without HID")
