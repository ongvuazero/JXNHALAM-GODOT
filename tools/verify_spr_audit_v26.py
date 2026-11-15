# -*- coding: utf-8 -*-
"""JXNHALAM V26: read-only verification of the SPR action audit. Python stdlib."""
from pathlib import Path
import json,hashlib,struct,sys
PROJECT=Path(__file__).resolve().parents[1]
DATA=PROJECT/'data/renderer_audit/blade_004_action_profiles.json'
D=json.loads(DATA.read_text(encoding='utf-8'))
assert D['schema']=='jxnhalam.renderer_audit.v1'
P=D['actions']
assert len(P)==4
assert [(x['id'],x['frames_per_dir']) for x in P]==[('AT02',16),('AT03',14),('ST04',11),('RN02',11)]
assert P[0]['mapped_column']=='MeleeWPuncture' and P[0]['action_id']==10
assert P[1]['mapped_column']=='MeleeWCut' and P[1]['action_id']==9
assert not P[1]['atlas_available'] and not P[1]['composite_atlas']
for action in P:
 assert action['directions']==8 and len(action['layers'])==6
 for layer in action['layers']:
  assert len(layer['frame_offsets_xywh'])==8*action['frames_per_dir']
  assert len(layer['canvas'])==2
 p=action['composite_atlas'].replace('res://','',1)
 if p:
  img=PROJECT/p
  assert img.exists(),img
  header=img.read_bytes()[:24]
  assert header[:8]==bytes.fromhex('89504e470d0a1a0a')
  w,h=struct.unpack('>II',header[16:24]);assert (w,h)==(action['frames_per_dir']*192,8*192)
for script in ['scripts/SPRActionAudit.gd','scripts/SPRMetadataCanvas.gd','scenes/spr_renderer_audit.tscn']:
 assert (PROJECT/script).is_file(),script
main=(PROJECT/'scripts/Main.gd').read_text(encoding='utf-8')
assert 'KEY_O: _open_spr_renderer_audit()' in main
assert 'res://scenes/spr_renderer_audit.tscn' in main
for script in ['scripts/V22MainCombat.gd','scripts/V22HitProbe.gd','scripts/Player.gd']:
 f=PROJECT/script
 assert f.exists(),f
print('V26 VERIFIED: four action maps, 24 x layer frame offsets, PNG geometry, O-key scene wiring.')
print('Status: source pixel SPR AT03 unavailable; runtime selection and Godot launch untested.')
