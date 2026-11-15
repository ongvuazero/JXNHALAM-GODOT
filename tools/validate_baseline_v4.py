#!/usr/bin/env python3
"""Offline integrity test: server-authoritative data, 3 TV VFX chains, 10 factions.
Does not execute Lua, server binaries or Windows executables.
"""
from pathlib import Path
import hashlib,json,sys
here=Path(__file__).resolve().parent.parent
j=lambda p:json.loads((here/p).read_text(encoding='utf8'))
server=j('data/baseline/gameplay_runtime.json')
groups=j('data/baseline/10_factions.json')
knots=j('data/baseline/lua_knots_TV_level150.json')
manifest=j('assets/vfx/manifest.json')
assert server['source_archive']=='Jx_Linux_6.0 CTC(20121991).zip'
assert server['skill_rows_total']==1207 and len(server['skills'])==1206
assert len(server['duplicate_skill_ids'])==1 and server['duplicate_skill_ids'][0]['id']=='521'
assert server['missile_rows_total']==441 and len(server['missiles'])==441
assert len(groups['factions'])==10 and len(groups['entries'])==478
for name,checksum in server['sha256'].items():
    path=here/'ServerBaseline'/name
    assert path.exists(),path
    assert hashlib.sha256(path.read_bytes()).hexdigest()==checksum,path
expected={1060:(1088,350,108,150,3),1058:(1084,320,280,150,1),1059:(1087,349,72,150,4)}
for sid,(child,mid,rad,level,weapon) in expected.items():
    skill=server['skills'][str(sid)]
    assert int(skill['ChildSkillId'])==child
    assert int(server['skills'][str(child)]['ChildSkillId'])==mid
    assert int(skill['AttackRadius'])==rad
    assert int(skill['ReqLevel'])==level and int(skill['EqtLimit'])==weapon
    m=server['missiles'][str(mid)]
    for key in ('AnimFile2','AnimFile4'):
        fx=m[key].replace('\\','/').split('/')[-1].removesuffix('.spr')
        assert fx in manifest and (here/manifest[fx]['file'].replace('res://','')).exists(),(sid,key,fx)
    assert str(sid) in knots and knots[str(sid)]['properties']
assert 'JX_LINUX_6' not in (here/'scripts/ClientDataBridge.gd').read_text() # old adapter untouched
assert 'BaselineDataBridge.gd' in (here/'scripts/Main.gd').read_text()
assert 'F4' in (here/'scripts/Main.gd').read_text()
print('PASS: 10 factions, 478 mapped skills, 1207 baseline rows, 441 missiles, 3 TV real VFX links, SHA256 original files')
print('NOTE: Godot Editor and actual Windows runtime were not exercised.')
