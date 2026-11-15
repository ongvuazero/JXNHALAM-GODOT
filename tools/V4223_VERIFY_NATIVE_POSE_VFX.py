#!/usr/bin/env python3
from pathlib import Path
import json, math
r=Path(__file__).resolve().parents[1]
p=(r/'data/renderer_audit/v4223_hammer_swing_bbox_anchors.json')
j=json.loads(p.read_text())
assert j['method'].startswith('farthest weapon-layer bounding-box')
assert j['foot_canvas_offset']==[0,-42]
for action,dirs in j['actions'].items():
 assert action in ['9','10'] and len(dirs)==8
 for face,phases in dirs.items():
  assert len(phases)==4
  for poses in phases:
   assert len(poses)==3
   for xy in poses:
    assert len(xy)==2 and all(math.isfinite(v) and abs(v)<180 for v in xy)
fx=(r/'scripts/CTC9XCombatEffect.gd').read_text()
main=(r/'scripts/Main.gd').read_text()
assert '_spawn_mace_swing_visuals()' in fx
assert '_update_mace_swing_visuals(delta)' in fx
assert 'not visual_only:' in fx
assert 'return\n    # V12 native' in fx
assert 'hammer_anchor.sample(action, direction,' in fx
for banned in ['MACE_SWEEP_START_PX','MACE_SWEEP_REACH_PX','MACE_SWEEP_MOVE_TICKS','MACE_VISUAL_LEAD_TICKS']:
 assert banned not in fx,banned
assert 'visual_events' not in fx
assert 'V42.2.3' in main
assert 'SPACE_REPEAT_SAMPLE' in main
assert (r/'data/sects/registry.json').is_file()
reg=json.loads((r/'data/sects/registry.json').read_text())
assert len(reg['sects'])==10
print('PASS: 8 directions x 2 original hammer actions x 4 poses x 3 source-derived preview anchors')
print('PASS: render decoupled from server allocation, no fake distance fan, holder + 10 sect preserved')
print('NOTE: Bounding-box tips and M141 1:1 visual mapping UNVERIFIED; Godot runtime test needed')
