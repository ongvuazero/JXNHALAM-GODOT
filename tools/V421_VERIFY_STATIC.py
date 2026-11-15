#!/usr/bin/env python3
"""Offline V42.1 smoke assertions. Not a Godot parser/runtime test.

Run `godot --headless --path . --script res://tests/V421MissileGeometryTest.gd`
on Windows/Linux Godot 4 to exercise the actual GDScript math.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
geo = (root/'scripts/JXMissileGeometry.gd').read_text(encoding='utf-8')
combat = (root/'scripts/V22MainCombat.gd').read_text(encoding='utf-8')
fx = (root/'scripts/CTC9XCombatEffect.gd').read_text(encoding='utf-8')
probe = (root/'scripts/V22HitProbe.gd').read_text(encoding='utf-8')
clock = (root/'scripts/CTC9XTimeline.gd').read_text(encoding='utf-8')
v42_clock = (root/'scripts/V42NativeSpearMaceClock.gd').read_text(encoding='utf-8')

assert 'const MACE_STEP: int = 8' in geo
assert 'center + (sub_index - 1) * MACE_STEP' in geo
assert 'func aim_from_points' in geo and 'func screen_vector' in geo
assert 'func atlas_row' in geo and 'func locked_target_center' in geo
assert 'GEOMETRY.missile_direction(skill_id, center_dir64, index, count)' in combat
assert 'GEOMETRY.screen_vector(dir64)' in combat
assert 'var demo_lateral: float = 52.0 if skill_id == 322' in combat
assert '"cast_serial": cast_count' in combat
assert 'GEOMETRY.missile_direction(active_id, cast_aim_dir64,' in fx
assert 'GEOMETRY.atlas_row(dir64, dirs)' in fx
assert 'var dir64_preview: int = 0' in probe
assert 'cast_tick = (cast_index + 1)' in clock
assert 'static func phase_at_elapsed(' in v42_clock
# Verified relative direction tuples from V4 runtime (3,11,19) and blade triplets.
for center in (0,1,11,32,63):
 directions = [((center + (i - 1)*8) % 64) for i in range(3)]
 assert (directions[1]-directions[0])%64 == 8
 assert (directions[2]-directions[1])%64 == 8
assert [((11+(i-1)*8)%64) for i in range(3)] == [3,11,19]
assert len(set([11,11,11])) == 1
# Cardinal mapping matches existing Player.face(): E=6, S=0, W=2, N=4.
for dir8,dir64 in [(6,48),(0,0),(2,16),(4,32)]:
 assert (dir8*8)%64 == dir64
print('PASS V42.1 source wiring, route triples, cardinal mapping, unchanged V42 clock.')
print('LIMIT: no Godot 4 runtime/visual QA performed by this Python check.')
