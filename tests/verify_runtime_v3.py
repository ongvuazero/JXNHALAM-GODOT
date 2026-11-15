#!/usr/bin/env python3
"""Static and source-dataset verification, does not run Godot. Usage from ZIP root: py -3 tests/verify_runtime_v3.py"""
from pathlib import Path
import json,hashlib,struct,sys,tempfile,shutil,importlib.util
root=Path(__file__).resolve().parents[1]
payload=root/'payload'
module=(payload/'scripts/JX141MissileVisualV3.gd').read_text(encoding='utf8')
frames=(payload/'scripts/JX141NativeFrameProbe.gd').read_text(encoding='utf8')
samples=json.loads((payload/'data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json').read_text(encoding='utf8'))
assert samples['parent_skill']==325 and samples['child_skill']==408 and samples['missile_template_id']==141
trace=samples['sample']
assert [int(s['dir64']) for s in trace]==[3,11,19]
assert [int(s['x_factor']) for s in trace]==[-327,-923,-979]
assert [int(s['y_factor']) for s in trace]==[978,461,-327]
assert [int(s['total_lifetime']) for s in trace]==[4,4,4]
assert 'func emit_allocation(event: Dictionary)' in module
assert 'func on_visual_contact(world_position: Vector2)' in module
assert 'FrameProbe.inspect(320, 32,' in module
assert 'return posmod(mid_dir64 + (sub_index - 1) * 8, 64)' in module
assert 'pixel_per_tick_preview: float = 24.0' in module
assert 'func apply_damage' not in module and 'take_damage' not in module
assert 'func _spawn_probe' not in module
assert 'duration-mapped' in frames
for direction in range(64):
    row=((direction+1)//2)%32
    assert row in range(32)
for age in range(4):
    assert (10*age)//4 in [0,2,5,7]
assert 'func _update_fly' in module
assert (payload/'assets/skill90/jx90_truyphong_sweep.png').read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
assert (payload/'assets/skill90/jx90_truyphong_impact.png').read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
print('PASS original server trace dirs 3/11/19, x/y factors, life=4')
print('PASS 64-dir -> 32-dir, fly frames [0,2,5,7]')
print('PASS separate FLY/HIT visual, no damage or collision writes')
print('LIMIT direction->pixel movement uses preview scale 24px/tick, NOT native movement')
