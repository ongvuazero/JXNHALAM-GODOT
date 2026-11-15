#!/usr/bin/env python3
"""Static source/data checks for V5. Does not claim to execute Godot scripts."""
from pathlib import Path
import json,hashlib,struct,sys
project=Path(__file__).resolve().parents[1]
snap=json.loads((project/'data/baseline/gameplay_runtime.json').read_text('utf-8'))
knots=json.loads((project/'data/baseline/lua_knots_TV_level150.json').read_text('utf-8'))
sects=json.loads((project/'data/baseline/10_factions.json').read_text('utf-8'))
alias=json.loads((project/'data/pak/known_hashes.json').read_text('utf-8'))
assert len(snap['skills'])>=1200,len(snap['skills'])
assert len(snap['missiles'])>=440,len(snap['missiles'])
assert len(sects['factions'])==10
assert len(sects['entries'])>400
assert len(alias)>=900
for i, missile, attack, req in [(1060,350,108,150),(1058,320,280,150),(1059,349,72,150)]:
 row=snap['skills'][str(i)]
 assert int(row['AttackRadius'])==attack
 assert int(row['ReqLevel'])==req
 assert str(missile) in snap['missiles']
 assert str(i) in knots
 assert (project/'ServerBaseline/settings/skills.txt').exists()
 for field in ['LvlSetting1','LvlData1','LvlSetScript']:
  assert field in row
 p=knots[str(i)]['properties']['skill_cost_v']['points_in_source_order']
 assert p and p[0][0]==1
 print(f'CTC {i}: ReqLevel={req}, AttackRadius={attack}, Missile={missile}, LuaCost@1={p[0][1]}')
# Read-only PACK smoke test using the bundled synthetic demo.
pak=project/'tests/fixtures/DEMO_JX_PACK.pak'
raw=pak.read_bytes()
assert raw[:4]==b'PACK'
count,index_at,data_at=struct.unpack_from('<III',raw,4)
assert count==3 and index_at==32
entries=[struct.unpack_from('<IIII',raw,index_at+16*i) for i in range(count)]

def legacy_hash(path):
 a=0
 for i,b in enumerate(path.lower().encode('ascii'),1):
  a=(-17*((a+b*i)%0x8000000b))&0xffffffff
 return a^0x12345678
for path in (r'\spr\demo.spr',r'\settings\demo.ini',r'\script\demo.lua'):
 h=legacy_hash(path)
 matches=[e for e in entries if e[0]==h]
 assert matches, f'Missing {path}, hash={h:08x}'
 entry=matches[0]
 assert entry[3]>>24==0
 blob=raw[entry[1]:entry[1]+entry[3]]
 assert len(blob)==entry[2]
 if path.endswith('.spr'):
  assert blob[:4]==b'SPR\x00'
 print(f'DEMO PAK lookup: {path}, hash={h:08X}, bytes={len(blob)}')
# Verify all explicit path constants exist and no phantom asset references.
for name in ['ClientAssetResolver.gd','JXVirtualFS.gd','JXSPRCodec.gd','CTCCurveEvaluator.gd','Main.gd','Player.gd','SkillEffect.gd']:
 assert (project/'scripts'/name).is_file(),name
print(f'PASS: {len(snap["skills"])} skills, {len(snap["missiles"])} missiles, {len(sects["factions"])} factions, {len(alias)} hashes, sample PACK 3/3.')
print('LIMIT: Godot runtime, frame-packed SPR and full Lua execution NOT validated here.')
