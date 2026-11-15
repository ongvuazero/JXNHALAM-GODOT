#!/usr/bin/env python3
"""Offline source-grounded JX1 Lua event manifest (does NOT execute untrusted Lua)."""
from pathlib import Path
import csv,json,re,collections
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'data'/'lua_events'
OUT.mkdir(parents=True,exist_ok=True)

# Only simple numeric, active rows are supported; complex Lua expressions are left unresolved.
def remove_line_comments(source):
    # Latin1 preserves original bytes and ASCII source strings. Keep line offsets.
    return '\n'.join(line.split('--',1)[0] for line in source.splitlines())

def find_brace_span(text, start):
    beg=text.find('{',start)
    if beg<0:return ''
    dep=0; quote=''; esc=False
    for i in range(beg,len(text)):
        c=text[i]
        if quote:
            if esc:esc=False
            elif c=='\\':esc=True
            elif c==quote:quote=''
            continue
        if c in "\"'":quote=c;continue
        if c=='{':dep+=1
        elif c=='}':
            dep-=1
            if dep==0:return text[beg:i+1]
    return ''

def get_table(text,key):
    pat=re.compile(r'(?<![A-Za-z0-9_])'+re.escape(key)+r'\s*=\s*\{')
    m=pat.search(text)
    return find_brace_span(text,m.end()-1) if m else ''

def unpack_curves(text):
    """Find numeric [1] and [3] component arrays or packed single array."""
    if not text: return {}
    result={}
    for group in [1,2,3]:
        mat=re.search(r'\['+str(group)+r'\]\s*=\s*\{',text)
        if mat:
            body=find_brace_span(text,mat.end()-1)
            result[str(group)]=[(int(a),int(b)) for a,b in re.findall(r'\{\s*(\d+)\s*,\s*(-?\d+)\s*\}',body)]
    if not result:
        result['1']=[(int(a),int(b)) for a,b in re.findall(r'\{\s*(\d+)\s*,\s*(-?\d+)\s*\}',text)]
    return result

def at_level(points,lv):
    if not points:return None
    # When a curve defines the same level twice, the last point at that level wins.
    lo=[p for p in points if p[0]<=lv]
    if lo:return lo[-1][1]
    return points[0][1]

with (ROOT/'settings'/'skills.txt').open('rb') as f:
    lines=f.read().decode('latin1').splitlines()
head=lines[0].split('\t'); rows={}
for line in lines[1:]:
    cells=line.split('\t')
    row=dict(zip(head,cells))
    if row.get('SkillId','').isdigit():rows[int(row['SkillId'])]=row
with (ROOT/'settings'/'missles.txt').open('rb') as f:
    lines=f.read().decode('latin1').splitlines()
head_m=lines[0].split('\t'); missile_rows={}
for line in lines[1:]:
    row=dict(zip(head_m,line.split('\t')))
    if row.get('MissleId','').isdigit():missile_rows[int(row['MissleId'])]=row
lua_text={p.stem:remove_line_comments(p.read_bytes().decode('latin1')) for p in (ROOT/'ServerBaseline/script/skill').glob('*.lua')}
EVENTS={'start':('skill_startevent','StartEvent','StartSkillId'), 'fly':('skill_flyevent','FlyEvent','FlySkillId'), 'collide':('skill_collideevent','CollideEvent','CollidSkillId'), 'vanish':('skill_vanishedevent','VanishedEvent','VanishedSkillId')}

SECTS=[p for p in (ROOT/'data/sects').glob('*.json') if p.name!='registry.json']
selections={}
for path in SECTS:
    data=json.loads(path.read_text(encoding='utf-8'))
    for w in data.get('weapons',[]):
        for skill in w.get('skills',[]):
            selections[int(skill['legacy_skill_id'])]=data['id']

def skill_row(n,lv):
    row=rows.get(n)
    if not row:return None
    lua_path=row.get('LvlSetScript','').replace('\\','/').rsplit('/',1)[-1].replace('.lua','')
    linked_names=[row.get('LvlData'+str(i),'') for i in range(1,21)]
    lua_key=next((name for name in linked_names if name), '')
    lua_source=lua_text.get(lua_path,'')
    lua_entry=get_table(lua_source,lua_key) if lua_key else ''
    name_match=re.search(r'^\t'+re.escape(lua_key)+r'\s*=\s*\{',lua_source,re.MULTILINE) if lua_key else None
    lua_line=lua_source.count('\n',0,name_match.start())+1 if name_match else 0
    if not lua_entry and lua_key:
        # a few source scripts have case/spacing quirks; record instead of guessing
        pass
    ev=[]; lua_evidence={}
    for trigger,(attr,enabled_field,id_field) in EVENTS.items():
        curve=unpack_curves(get_table(lua_entry,attr))
        # Only get the curve if the skill's LvlSetting binds this Lua field; otherwise table defaults.
        bound=attr in [row.get('LvlSetting'+str(i),'') for i in range(1,21)]
        lua_on=at_level(curve.get('1',[]),lv) if bound else None
        lua_id=at_level(curve.get('3',[]),lv) if bound else None
        on=int(lua_on) if lua_on is not None else int(row.get(enabled_field,'0') or 0)
        linked_id=int(lua_id) if lua_id is not None else int(row.get(id_field,'0') or 0)
        evidence='lua_curve' if bound and lua_on is not None else 'skills_txt'
        lua_evidence[attr]={'bound':bound,'curve':curve,'effective_flag':on,'effective_skill_id':linked_id,'evidence':evidence}
        if on>0 and linked_id>0:
            ev.append({'trigger':trigger,'skill_id':linked_id,'source':evidence,'lua_field':attr,'level':lv,'verified_visual_timing':False})
    miss_count=int(row.get('ChildSkillNum','0') or 0)
    mcurve=unpack_curves(get_table(lua_entry,'skill_misslenum_v'))
    if 'skill_misslenum_v' in [row.get('LvlSetting'+str(i),'') for i in range(1,21)] and mcurve.get('1'):
        miss_count=at_level(mcurve['1'],lv)
    child=int(row.get('ChildSkillId','0') or 0)
    missile_id=child if child in missile_rows else 0
    child_row=rows.get(child)
    if not missile_id and child_row:
        candidate=int(child_row.get('ChildSkillId','0') or 0)
        missile_id=candidate if candidate in missile_rows else 0
    missile=missile_rows.get(missile_id,{})
    paths=[missile.get('AnimFile'+str(i),'') for i in (1,2,3,4)]
    inf=[missile.get('AnimFileInfo'+str(i),'') for i in (1,2,3,4)]
    fly_timing=lua_evidence['skill_flyevent']['curve'].get('2', [])
    fly_event_time=at_level(fly_timing,lv) if fly_timing else None
    if fly_event_time is None:
        fly_event_time=int(row.get('FlyEventTime','0') or 0)
    passive=[]
    for i in range(1,21):
        field=row.get('LvlSetting'+str(i),'')
        if not field.startswith('addskilldamage'):continue
        curve=unpack_curves(get_table(lua_entry,field))
        subject=at_level(curve.get('1',[]),lv)
        value=at_level(curve.get('3',[]),lv)
        if subject is not None:
            passive.append({'skill_id':subject,'bonus_at_level':value,'kind':'damage_reference_not_visual_event', 'field':field})
    return {
        'skill_id':n,'level':lv,'skill_name_raw_latin1':row.get('SkillName','').strip(),
        'lua_script':'ServerBaseline/script/skill/'+lua_path+'.lua' if lua_path else '',
        'lua_key':lua_key,'lua_line':lua_line,'lua_definition_found':bool(lua_entry),
        'attack_radius_raw':int(row.get('AttackRadius','0') or 0),
        'radius_lua_curve':unpack_curves(get_table(lua_entry,'skill_attackradius')),
        'child_skill_id':child, 'child_skill_num_table':int(row.get('ChildSkillNum','0') or 0),
        'missile_count_lua_level':miss_count,'missile_id':missile_id,
        'move_kind':int(missile.get('MoveKind','-1') or -1),
        'follow_kind':int(missile.get('FollowKind','0') or 0),
        'anim_paths':paths,'anim_infos':inf,'precast_spr':row.get('PreCastSpr',''),'fly_event_time_raw':fly_event_time,
        'events':ev,'event_evidence':lua_evidence,'passive_synergies_not_spawn':passive,
        'is_selected_combat_skill':n in selections,'sect':selections.get(n,''),
    }

levels=list(range(1,21))
# Include the entire linked graph to depth two so event-children may have their own events.
selected=sorted(selections)
work=set(selected)
for depth in range(2):
    for k in list(work):
        for ev in (skill_row(k,20) or {}).get('events',[]):
            if ev['skill_id'] in rows: work.add(ev['skill_id'])
graph={}
for n in sorted(work):
    if n not in rows:continue
    d=skill_row(n,20)
    d['event_levels']={str(l):skill_row(n,l)['events'] for l in levels}
    d['missile_num_levels']={str(l):skill_row(n,l)['missile_count_lua_level'] for l in levels}
    d['fly_event_ticks_levels']={str(l):skill_row(n,l)['fly_event_time_raw'] for l in levels}
    graph[str(n)]=d
manifest={
  'format':'JXNHALAM_LUA_EVENT_GRAPH_V44_2',
  'sources':{'skill_table':'settings/skills.txt','missile_table':'settings/missles.txt','lua_dir':'ServerBaseline/script/skill/'},
  'not_executable_lua':True,
  'semantics':'active events only; addskilldamage refs MUST NOT spawn visuals',
  'level_assumption':'QA uses level 20 unless runtime supplies specific value',
  'selected_skills':selected,
  'skills':graph
}
(OUT/'jx_lua_event_graph.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
with (OUT/'jx_lua_event_audit.csv').open('w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f)
    w.writerow(['sect','skill_id','lua_key','level_20_event_chain','level_1_event_chain','max_events','missiles_1','missiles_20','damage_bonus_references','lua_definition_found','source_lua','source_lua_line'])
    for n in selected:
        d=graph[str(n)]
        evt=lambda lvl:';'.join(x['trigger']+':'+str(x['skill_id']) for x in d['event_levels'][str(lvl)]) or '-'
        w.writerow([d['sect'],n,d['lua_key'],evt(20),evt(1),len(d['events']),d['missile_num_levels']['1'],d['missile_num_levels']['20'], ';'.join(str(x['skill_id']) for x in d['passive_synergies_not_spawn']),d['lua_definition_found'],d['lua_script'],d['lua_line']])
print('selected',len(selected),'graph',len(graph),'active_ev20',sum(len(graph[str(n)]['events']) for n in selected),'lua definitions',sum(bool(graph[str(n)]['lua_definition_found']) for n in selected))
for n in [357,359,328,380,339,368,325]:
 d=graph[str(n)];print(n,d['lua_key'],'missiles',d['missile_num_levels']['1'],d['missile_num_levels']['20'],'events LV1/20',d['event_levels']['1'],d['events'],'passive refs',[e['skill_id'] for e in d['passive_synergies_not_spawn']])
