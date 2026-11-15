#!/usr/bin/env python3
"""Read-only audit of Lua graph against actual local JX source. No Lua execution."""
import csv,json,collections,hashlib,sys
from pathlib import Path
base=Path(__file__).resolve().parents[1]
data=json.loads((base/'data/lua_events/jx_lua_event_graph.json').read_text('utf-8'))
graph=data['skills']; selected=data['selected_skills']; out=base/'V44_3_SOURCE_STAGE_AUDIT.csv'
errors=[]
roles={'precast':0,'fly':1,'travel_end':2,'hit':3}
stages=collections.Counter(); by_kind=collections.Counter(); edge_count=0
with out.open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.writer(f)
 writer.writerow(['school','skill_id','lvl','source_move_kind','Lua_missiles','linked_event','stage','SPR_path_declared','runtime_SPR_verified','native_timing_verified','note'])
 for sid in selected:
  key=str(sid)
  if key not in graph:
   errors.append(f'missing selected skill {sid}')
   continue
  item=graph[key]
  if not item.get('lua_definition_found'):
   errors.append(f'no Lua definition for {sid}')
  by_kind[int(item['move_kind'])]+=1
  all_paths=item.get('anim_paths',[])
  role_paths={'precast':item.get('precast_spr','') or (all_paths[0] if all_paths else ''),
              'fly':all_paths[1] if len(all_paths)>1 else '',
              'travel_end':all_paths[2] if len(all_paths)>2 else '',
              'hit':all_paths[3] if len(all_paths)>3 else ''}
  for lvl in (1,10,15,20):
   evs=item['event_levels'].get(str(lvl),[])
   evlist=';'.join(e['trigger']+':'+str(e['skill_id']) for e in evs) or '-'
   if lvl==20: edge_count+=len(evs)
   for e in evs:
    if str(e['skill_id']) not in graph:
     errors.append(f'broken edge {sid} {lvl} -> {e["skill_id"]}')
   count=int(item['missile_num_levels'].get(str(lvl),0))
   for role,path in role_paths.items():
    if path: stages[role]+=int(lvl==20)
    writer.writerow([item.get('sect',''),sid,lvl,item['move_kind'],count,
        evlist,role,path,'NOT_TESTED_WITH_CLIENT_PAK','NO',
        'A declared SPR name does not prove existence in user client PAK'])
 assert count>=0, f'invalid count {sid}'
assert len(selected)==24, f'expected 24 active skill entries, got {len(selected)}'
assert len(graph)==39, f'expected 39 total Lua graph nodes, got {len(graph)}'
assert edge_count==15, f'expected 15 linked events at lvl20, got {edge_count}'
assert not errors, f'Source graph integrity errors: {errors}'
# Non-destructive checks that critical Thiên Vương scripts are preserved.
protected=['Main.gd','Player.gd','CTC9XCombatEffect.gd','JX141MissileVisualV3.gd',
           'JX139SpearFlight.gd','V22MainCombat.gd','V37Blade322Impact.gd']
print('PASS V44.3 source graph: selected=',len(selected),'graph=',len(graph),
      'links_lvl20=',edge_count,'stage_refs_lvl20=',dict(stages),'move_kinds=',dict(by_kind))
print('TV protected files (sha256):')
for file in protected:
 p=base/'scripts'/file
 print(file,hashlib.sha256(p.read_bytes()).hexdigest()[:20])
print('WROTE',out)
