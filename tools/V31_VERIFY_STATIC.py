# -*- coding: utf-8 -*-
"""JXNHALAM V31 source-only QA. No Godot runtime, no client EXE invocation."""
from pathlib import Path
import json,csv,hashlib,statistics
R=Path(__file__).resolve().parents[1]
meta=json.loads((R/'data/renderer_audit/blade_004_action_profiles.json').read_text(encoding='utf8'))
a=next((x for x in meta['actions'] if x['id']=='AT03'),None)
assert a and a['mapped_column']=='MeleeWCut' and a['frames_per_dir']==14 and a['directions']==8
assert len(a['layers'])==6 and [x['layer'] for x in a['layers']]==['BD_001','LH_001','RH_001','HD_001','LW_000','RW_004']
b=next(x for x in a['layers'] if x['layer']=='BD_001')
assert len(b['frame_offsets_xywh'])==112
for i,xywh in enumerate(b['frame_offsets_xywh']):
 assert len(xywh)==4 and all(isinstance(x,int) for x in xywh),(i,xywh)
assert {v[1]+v[3] for v in b['frame_offsets_xywh'][6*14:7*14]}=={202}
order=json.loads((R/'data/renderer_audit/at03_male_raw_draworder.json').read_text(encoding='utf8'))
assert len(order['lines'])==15 and all(len(v)==13 for v in order['lines'].values())
assert order['lines']['7']==[11,14,16,13,1,4,6,5,8,7,0,9,12]
with (R/'data/renderer_audit/V31_AT03_112_FRAMES_SOURCE_BBOX.csv').open(encoding='utf-8-sig',newline='') as f:
 rows=list(csv.DictReader(f))
assert len(rows)==112
for row in rows:
 di=int(row['direction_index']);fr=int(row['frame_index']);p=b['frame_offsets_xywh'][di*14+fr]
 assert [int(row[k]) for k in ['body_x','body_y','body_width','body_height','body_bbox_bottom_y']]==p+[p[1]+p[3]]
with (R/'data/renderer_audit/V31_MELEEWCUT_RAW_15_ROWS.csv').open(encoding='utf-8-sig',newline='') as f:
 raw_rows=list(csv.DictReader(f))
assert len(raw_rows)==15
for i,r in enumerate(raw_rows,1):
 assert r['original_section']=='MeleeWCut' and r['line_number']==f'Line{i}'
 assert r['raw_13_numeric_codes']==','.join(map(str,order['lines'][str(i)]))
comp=(R/'scripts/V28AT03LayerComposer.gd').read_text(encoding='utf8')
guide=(R/'scripts/V31AT03AnchorGuides.gd').read_text(encoding='utf8')
for token in ['V31_GUIDES','V31BodyBBoxAnchorMarkers','func _toggle_floor_lock()','func _save_qa_report()','func _select_raw_row(index: int)','source_row_button.add_item','BODY_BBOX','KEY_S: _save_qa_report()']:
 assert token in comp,token
for token in ['extends Node2D','func update_bbox','func _draw()','body_xywh','bottom_center']:
 assert token in guide,token
assert 'func _on_skill_started' not in comp and 'main_combat' not in comp
assert 'res://scenes/v28_at03_layer_composer.tscn' in (R/'scripts/SPRActionAudit.gd').read_text(encoding='utf8')
assert 'V31' in (R/'project.godot').read_text(encoding='utf8')
print('V31 STATIC PASS: 112 original body BBOX frames, 15 untouched raw rows, overlay + report wiring.')
print('IMPORTANT: source rule enum -> six-layer mapping and EXE action selection UNVERIFIED.')
print('This test does not parse GDScript or execute Godot.')
