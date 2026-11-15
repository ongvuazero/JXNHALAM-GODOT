#!/usr/bin/env python3
"""Source-only regression checker. Does not run Godot or declare gameplay runtime success."""
from __future__ import annotations
from pathlib import Path
import json, hashlib, re
import struct
try:
    from PIL import Image  # Optional: richer validation on authoring machine
except ImportError:
    Image = None
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts"
ASSET = ROOT / "assets" / "character" / "blade_attack.png"
source = {name: (SRC / name).read_text(encoding="utf-8") for name in [
    "Main.gd", "Player.gd", "CTC9XCombatEffect.gd", "Blade322Afterimages.gd",
    "V22MainCombat.gd", "V22HitProbe.gd", "CTC9XTimeline.gd", "JX9XVerifiedRoute.gd"]}
checked = 0
def check(value: bool, reason: str):
    global checked
    if not value: raise AssertionError(reason)
    checked += 1
check('var blade322_echo_enabled: bool = true' in source["Main.gd"], "echo default ON")
check('KEY_G: _toggle_blade322_echo()' in source["Main.gd"], "G toggle")
check('blade_shadow_button.pressed.connect' in source["Main.gd"], "shadow button")
check('main_combat_status.visible = show_main_combat_debug' in source["Main.gd"], "debug status hidden")
check('main_combat_details.visible = show_main_combat_debug' in source["Main.gd"], "debug panel hidden")
check('var show_main_combat_debug: bool = false' in source["Main.gd"], "debug default hidden")
check('const BLADE322_NATIVE_VISUAL_SECONDS: float = 0.48' in source["Player.gd"], "source visual timing marked preview")
check('blade322_combo_duration = BLADE322_NATIVE_VISUAL_SECONDS if' in source["Player.gd"], "visual timing assigned only to blade322")
check('blade322_combo_duration' in source["CTC9XCombatEffect.gd"], "visual shadow uses same clock")
check('const MAX_ACTIVE_ECHOES: int = 3' in source["Blade322Afterimages.gd"], "visual snapshot cap, not missile count")
check('current_region == last_region' in source["Blade322Afterimages.gd"], "echo snapshots only on frame change")
check('echo_sprite.global_transform = source_sprite.global_transform' in source["Blade322Afterimages.gd"], "no echo movement")
check('const TEST_DAMAGE: int = 10' in source["V22MainCombat.gd"], "HP demo explicit")
check('"missiles_per_child": 3' in source["JX9XVerifiedRoute.gd"], "verified allocations")
check('const TICK_PROVEN: bool = false' in source["CTC9XTimeline.gd"], "preview not claimed proven")
check('"combat_delivery"' in (ROOT/"data"/"sects"/"thien_vuong.json").read_text(encoding="utf-8") or '"ctc_9x_many_attack"' in (ROOT/"data"/"sects"/"thien_vuong.json").read_text(encoding="utf-8"), "thien vuong config still present")
head = ASSET.read_bytes()[:24]
check(head[:8] == bytes.fromhex("89504e470d0a1a0a"), "PNG signature")
check(struct.unpack(">II",head[16:24]) == (3072,1536), "native composite atlas 16x8 192px")
check((ROOT/"scenes"/"main.tscn").exists(), "main scene")
if Image is not None:
    im = Image.open(ASSET)
    for row in range(8):
        for col in range(16):
            roi = im.crop((col*192,row*192,(col+1)*192,(row+1)*192))
            check(roi.getbbox() is not None, f'empty atlas frame dir{row},frame{col}')
visual_duration = 0.48
seq = [min(15,int(min(0.999999, t/visual_duration)*16)) for t in [i*visual_duration/160 for i in range(161)]]
check(seq[0]==0 and seq[-1]==15, "frame mapping starts at0 ends at15")
check(all(a<=b for a,b in zip(seq,seq[1:])), "frames monotonic")
check(set(seq)==set(range(16)), "all 16 frames reachable in monotonic visual presentation")
sha={name:hashlib.sha256((SRC/name).read_bytes()).hexdigest() for name in source}
print('V23 SOURCE VERIFICATION PASS',checked,'checks',('(including 128 nonempty atlas cells).' if Image is not None else '(PNG cell-level check optional: pip install Pillow).'))
print('Original V22 combat/HIT probe files must also be compared to the V22 baseline; see manifest SHA check.')
for name in ('V22MainCombat.gd','V22HitProbe.gd','CTC9XTimeline.gd','JX9XVerifiedRoute.gd'):
    print('unchanged-proof',name,sha[name])
print('This is static/data QA, NOT a Godot headless test.')
