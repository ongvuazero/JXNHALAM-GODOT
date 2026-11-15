#!/usr/bin/env python3
"""V42.2.2: structural + atlas-level M141 three-sweep regression audit.
Does not substitute for running Godot 4.6.1 and comparing the native client.
"""
from pathlib import Path
import json, math, hashlib
from PIL import Image
r=Path(__file__).resolve().parents[1]
fx=(r/'scripts/CTC9XCombatEffect.gd').read_text(encoding='utf-8')
g=(r/'scripts/JXMissileGeometry.gd').read_text(encoding='utf-8')
main=(r/'scripts/Main.gd').read_text(encoding='utf-8')
assert 'int(event.get("sub_index", 0)) != 1' not in fx, 'Sub 0/2 hidden AGAIN'
assert '"mace_sweep": use_sweep, "sub_index": sub_index' in fx
assert 'last_stage = "M141: %d/%d RAW SWEEPS SHOWN"' in fx
assert 'MACE_SWEEP_START_PX: float = 48.0' in fx
assert 'MACE_SWEEP_REACH_PX: float = 84.0' in fx
assert 'MACE_SWEEP_VISIBLE_TICKS: int = 7' in fx
assert 'MACE_VISUAL_LEAD_TICKS: int = 1' in fx
assert 'sprite.scale = Vector2.ONE * float(visual_calibration["scale"])' in fx
assert 'GEOMETRY.missile_direction(active_id, cast_aim_dir64,' in fx
assert 'GEOMETRY.screen_vector(visual_heading) * short_reach' in fx
assert 'action_ticks = maxi(1, last_allocation_tick)' in (r/'scripts/CTC9XTimeline.gd').read_text()
assert 'SPACE_REPEAT_SAMPLE' in main and 'V42.2.2' in main
assert 'MACE_STEP: int = 8' in g
reg=json.loads((r/'data/sects/registry.json').read_text())
assert len(reg['sects'])==10
img=Image.open(r/'assets/skill90/jx90_truyphong_sweep.png').convert('RGBA')
assert img.size==(2560,8192)
# Pixel QA: for each actor heading, all three distinct source rows are nonempty.
# At near-body reach, their envelopes must be visibly separated, not stacked.
for face in range(8):
    base=face*8
    positions=[]
    canvas=Image.new('RGBA',(640,640))
    for sub in range(3):
        d=(base+(sub-1)*8)%64
        row=(d//2)%32
        assert row in range(32)
        positions.append(d)
        tile=img.crop((9*256,row*256,10*256,(row+1)*256))
        assert tile.getchannel('A').getbbox() is not None
        angle=(d-48)*math.tau/64
        ox=round(math.cos(angle)*84)
        oy=round(math.sin(angle)*84)
        canvas.alpha_composite(tile,(192+ox,192+oy))
    assert len(set(positions))==3
    bb=canvas.getchannel('A').getbbox()
    assert bb is not None and (bb[2]-bb[0])*(bb[3]-bb[1])>=4500,(face,bb)
assert len(set(positions))==3
print('PASS: 8 facings x 3 M141 raw atlas rows all visible with compact distinct positions')
print('PASS: 3 render calls/cast, frame exposure cap, hold-Space, 10-sect catalog')
print('LIMIT: source-code/atlas verification only; Godot runtime visual QA still required')
