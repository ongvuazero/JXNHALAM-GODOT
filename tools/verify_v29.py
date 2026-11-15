# Python 3, source-only check (does not run Godot)
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
a=(r/'scripts/Main.gd').read_text(encoding='utf-8')
b=(r/'scripts/V29AT03LivePreview.gd').read_text(encoding='utf-8')
assert 'KEY_Y: _toggle_at03_live_preview()' in a
assert 'use_at03_in_main: bool = false' in a
for x in ['MeleeWCut','AT03']:
 assert x in (r/'data/renderer_audit/blade_004_action_profiles.json').read_text(encoding='utf-8')
assert 'const EXPECTED_FRAMES: int = 14' in b
assert 'var enabled: bool = false' in b
assert 'str(actor.get("state")) != "attack"' in b
assert 'reference_sprite.visible = false' in b
assert (r/'scripts/V22MainCombat.gd').exists()
print('V29 static entry and original action data: PASS. No runtime certification.')
