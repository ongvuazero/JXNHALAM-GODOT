#!/usr/bin/env python3
"""V42.1.2 targeted melee VFX and 12-skill audit static regression.
This check does NOT replace a real Godot 4.6.1 visual/runtime test.
"""
from pathlib import Path
from collections import Counter
import csv,json,hashlib
r=Path(__file__).resolve().parents[1]
fx=(r/'scripts/CTC9XCombatEffect.gd').read_text(encoding='utf-8')
probe=(r/'scripts/V22MainCombat.gd').read_text(encoding='utf-8')
geometry=(r/'scripts/JXMissileGeometry.gd').read_text(encoding='utf-8')
main=(r/'scripts/Main.gd').read_text(encoding='utf-8')
assert '"attached_to_caster": attached_to_caster' in fx
assert 'sprite.position = melee_anchor + Vector2(' in fx
assert 'GEOMETRY.cast_origin(caster)' in fx
assert 'particle.get("attached_to_caster", false)' in fx
assert 'GEOMETRY.PREVIEW_SPEED_PX * flight_sec' not in fx, 'VFX must not translate at probe speed'
assert 'sprite.scale = Vector2.ONE * float(visual_calibration["scale"])' in fx
assert 'GEOMETRY.missile_direction(active_id, cast_aim_dir64,' in fx
assert 'GEOMETRY.missile_direction(skill_id, center_dir64, index, count)' in probe
assert 'GEOMETRY.screen_vector(dir64)' in probe, 'collision probe remains independent'
assert 'var demo_lateral: float = 52.0 if skill_id == 322 and count > 1 else 0.0' in probe
assert 'V42.1.2 · NATIVE ATTACK' in main
assert '_v4211_restore_v42_actor_scales()' in main
assert 'player.scale = Vector2.ONE' in main
assert 'v41_native_renderer.scale = Vector2.ONE' in main
# Three rows of 32-dir atlas are spaced exactly four row indices in all 8 poses.
manifest=json.loads((r/'assets/vfx/manifest.json').read_text(encoding='utf-8'))
assert manifest['jx90_truyphong_sweep']['directions']==32
assert manifest['jx90_truyphong_sweep']['frames_per_direction']==10
for face in range(8):
    dirs=[(face*8 + (i-1)*8) % 64 for i in range(3)]
    rows=[round(d*0.5)%32 for d in dirs]
    assert [(rows[i+1]-rows[i])%32 for i in range(2)]==[4,4]
# Validate source-derived 12 skills; preserve V4/V5 provenance in audit CSV.
with (r/'notes/V4212_TV12_SOURCE_AUDIT.csv').open(encoding='utf-8-sig',newline='') as f:
    routes=list(csv.DictReader(f))
assert len(routes)==12
assert Counter(x['tier'] for x in routes)=={'1x':3,'3x':3,'6x':3,'9x':3}
assert {int(x['skill_id']):int(x['missiles_per_cast_declared']) for x in routes}=={
    34:1,37:1,32:1,322:3,30:2,35:3,41:4,323:5,29:1,31:1,324:1,325:3}
for x in routes:
    assert int(x['observed_parent_casts'])>0
    assert int(x['observed_child_casts']) == int(x['observed_parent_casts'])*int(x['children_per_cast'])
    assert int(x['observed_spawn_calls']) == int(x['observed_child_casts'])*int(x['missiles_per_child'])
    assert x['visual_implemented'].startswith('MAIN playable') == (x['tier']=='9x')
print('PASS: 325 VFX attached near caster, independent probe, V42 actor scale preserved, 8x3 atlas directions')
print('PASS: 12 skills source + V4/V5 runtime parent/child/spawn audit; only 9x marked playable')
print('LIMIT: Godot renderer output & JX1 exact size/timing still require in-game comparison')
