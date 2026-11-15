#!/usr/bin/env python3
"""Static-source tests for V44.2, not a substitute for Godot F5."""
import json, pathlib, sys, re, hashlib, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'data/lua_events/jx_lua_event_graph.json').read_text(encoding='utf-8'))
SK=DATA['skills']
checks=[]
def ck(name,condition):
 checks.append((name,bool(condition)))

ck('has 24 selected skills',len(DATA['selected_skills'])==24)
ck('has 39 active linked graph records',len(SK)>=39)
ck('all 10 Lua files',len(list((ROOT/'ServerBaseline/script/skill').glob('*.lua')))==10)
ck('all selected Lua definitions parsed',all(SK[str(i)]['lua_definition_found'] for i in DATA['selected_skills']))
ck('all selected Lua line numbers',all(SK[str(i)]['lua_line']>0 for i in DATA['selected_skills']))
ck('all levels 1..20',all(all(str(l) in SK[str(i)]['event_levels'] for l in range(1,21)) for i in DATA['selected_skills']))
ck('every event maps to existing linked skill',all(str(e['skill_id']) in SK for i in DATA['selected_skills'] for e in SK[str(i)]['events']))
ck('no visual bonus events',all(e['trigger'] in ('start','fly','collide','vanish') for i in DATA['selected_skills'] for e in SK[str(i)]['events']))
ck('Lua active 20 events found',sum(len(SK[str(i)]['events']) for i in DATA['selected_skills'])==15)

def events(n,l):return {(e['trigger'],e['skill_id']) for e in SK[str(n)]['event_levels'][str(l)]}
for n,lv,evt in [
 (357,1,('collide',389)),(357,20,('collide',389)),(328,1,('start',329)),(328,20,('start',329)),
 (339,1,('collide',340)),(339,20,('collide',340)),(380,20,('start',331)),(368,20,('start',371)),(368,20,('collide',162))]:
 ck(f'skill {n} level {lv} has event {evt}: {lv==20}',(evt in events(n,lv))==(lv==20))
ck('357 Lua missile count lvl1',SK['357']['missile_num_levels']['1']==1)
ck('357 Lua missile count lvl20',SK['357']['missile_num_levels']['20']==4)
ck('359 Lua missile count lvl20',SK['359']['missile_num_levels']['20']==3)
ck('359 no new Lua events lvl20',not SK['359']['events'])
ck('357 damage refs not events',[x['skill_id'] for x in SK['357']['passive_synergies_not_spawn']]==[1073,1101])
ck('325 no new Lua event',not SK['325']['events'])
ck('Lua graph includes child 389 with missile SPR',bool(SK['389']['anim_paths'][1]))
ck('Lua graph includes event child 340 SPR',bool(SK['340']['anim_paths'][1]))
for name in ['JXLuaEventVFX','JXLuaLinkedVisual','JXSectSkillPreview','JXHomingSkillPreview']:
 script=ROOT/'scripts'/f'{name}.gd'
 ck(name+' script exists',script.is_file())
 src=script.read_text(encoding='utf-8')
 ck(name+' no conflicting global class','class_name ' not in src)
 ck(name+' extends Godot type',src.startswith('extends '))
 ck(name+' every preload path exists',all((ROOT/p).is_file() for p in re.findall(r'preload\("res://([^"\n]+)"\)',src)))
 ck(name+' no malformed indent',all(len(line)-len(line.lstrip(' '))>=0 for line in src.splitlines()))
for path in ['data/lua_events/jx_lua_event_graph.json','data/lua_events/preview_settings.json']:
 ck(path+' valid JSON',isinstance(json.loads((ROOT/path).read_text(encoding='utf-8')),dict))
ck('no linked visual native damage', 'take_damage(' not in (ROOT/'scripts/JXLuaEventVFX.gd').read_text() and 'take_damage(' not in (ROOT/'scripts/JXLuaLinkedVisual.gd').read_text())
ck('homing source count read from Lua', 'source_child_count_at_level' in (ROOT/'scripts/JXHomingSkillPreview.gd').read_text())
ck('nine-sect reader calls Lua event', 'emit_parent' in (ROOT/'scripts/JXSectSkillPreview.gd').read_text())
ck('no Main.gd modified by new logic','JXLuaEventVFX' not in (ROOT/'scripts/Main.gd').read_text())
print('\n'.join(('PASS ' if okay else 'FAIL ')+name for name,okay in checks))
print(f'RESULT {sum(ok for _,ok in checks)}/{len(checks)} STATIC tests PASS; Godot runtime NOT tested')
sys.exit(0 if all(ok for _,ok in checks) else 1)
