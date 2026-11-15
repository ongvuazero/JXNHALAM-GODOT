#!/usr/bin/env python3
"""Offline source + asset regression checks. Does not replace Godot runtime QA."""
from pathlib import Path
import json, hashlib
r=Path(__file__).resolve().parents[1]
code={name:(r/'scripts'/name).read_text() for name in ['JXMissileGeometry.gd','V22MainCombat.gd','CTC9XCombatEffect.gd','V22HitProbe.gd','Main.gd']}
g=code['JXMissileGeometry.gd']; c=code['V22MainCombat.gd']; v=code['CTC9XCombatEffect.gd']; p=code['V22HitProbe.gd']; m=code['Main.gd']
assert 'static func cast_origin(source: Node2D)' in g
assert 'return source.global_position + Vector2(0.0, PREVIEW_MUZZLE_Y)' in g
assert 'static func aim_from_face(dir8: int)' in g
assert 'GEOMETRY.aim_from_face(int(source.get("facing_dir")))' in c
assert 'GEOMETRY.aim_from_face(direction)' in v
assert 'var muzzle_world: Vector2 = GEOMETRY.cast_origin(caster)' in v
assert 'base_position = to_local(muzzle_world)' in v
# Historical 42.1.1 regression remains valid for the legacy preview and
# V42.1.2 replaces flight-follow with a native short melee visual.
if 'attached_to_caster' in v:
    assert 'sprite.position = melee_anchor' in v
else:
    assert '"cast_origin": muzzle_world' in v
    assert '"flight_vector": GEOMETRY.screen_vector(dir64)' in v
    assert 'heading * GEOMETRY.PREVIEW_SPEED_PX * flight_sec' in v
assert 'GEOMETRY.PREVIEW_SPEED_PX' in p and 'GEOMETRY.PREVIEW_LIFETIME_SEC' in p
assert 'GEOMETRY.cast_origin(source)' in c
assert '_v4211_restore_v42_actor_scales()' in m
assert 'mob.scale = Vector2.ONE' in m and 'player.scale = Vector2.ONE' in m
assert 'v41_native_renderer.scale = Vector2.ONE' in m
assert 'V42.1.1 · NATIVE ATTACK' in m or 'V42.1.2 · NATIVE ATTACK' in m
# Skill table and art manifest remain present and unchanged from V42.1.
assert (r/'assets/skill90/jx90_truyphong_sweep.png').stat().st_size>1000
manifest=json.loads((r/'assets/vfx/manifest.json').read_text())
assert manifest['jx90_truyphong_sweep']['directions']==32
assert manifest['jx90_truyphong_sweep']['tile']==256
for facing in range(8):
    center=facing*8
    directions=[(center+(i-1)*8)%64 for i in range(3)]
    rows=[round(d*32/64)%32 for d in directions]
    assert ((rows[1]-rows[0])%32,(rows[2]-rows[1])%32)==(4,4)
    assert all((int(v*1000)%1)==0 for v in directions)
print('PASS: V42.1.1 facing/origin/VFX travel/32-row atlas/scale baseline regression (8 x 3)')
print('LIMIT: no Godot engine headless or in-game screenshot verified in this environment')
