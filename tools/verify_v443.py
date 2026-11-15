#!/usr/bin/env python3
"""Check-only V44.3 safety and Lua-graph consistency; never changes game assets."""
from pathlib import Path
import hashlib,json,re,sys
root=Path(__file__).resolve().parents[1]
check=0

def ok(condition,msg):
 global check
 check+=1
 if not condition:
  raise RuntimeError(f'FAIL ({check}) {msg}')

m=json.loads((root/'V44_3_INTEGRITY_MANIFEST.json').read_text('utf-8'))
for name,sha in m['protected_tv_scripts'].items():
 path=root/'scripts'/name
 ok(path.is_file(), f'missing TV file {name}')
 ok(hashlib.sha256(path.read_bytes()).hexdigest()==sha, f'TV modified unexpectedly: {name}')
for name in m['modified_source_scripts']:
 p=root/'scripts'/name
 ok(p.is_file(),f'missing changed source file {name}')
 ok(len(p.read_text('utf-8'))>800, f'partial/truncated source {name}')
script=(root/'scripts/JXLuaEventVFX.gd').read_text('utf-8')
linked=(root/'scripts/JXLuaLinkedVisual.gd').read_text('utf-8')
parent=(root/'scripts/JXSectSkillPreview.gd').read_text('utf-8')
for match in ['chain.size() >= max_depth + 1','skipped_duplicate_events','missing_visual_links',
              'linked_events_allocated','event_log']:
 ok(match in script,f'Lua dispatcher missing {match}')
for match in ['"precast"','"fly"','"travel_end"','"hit"','_emit_collision_once',
              '_valid_collision_at','_finish','visual_available', 'DIRECTION.row_from_vector']:
 ok(match in linked,f'Linked renderer missing {match}')
ok('displayed_count = 1' in parent,'unverified formation stacking is still enabled')
ok('if visual_contact and source_stages.has("travel_end")' in parent,
   'travel_end can be fabricated at destination after missed shot')
# Direct Lua graph inspection: 24 selected + 15 active event edges at lv20 + 39 nodes.
graph=json.loads((root/'data/lua_events/jx_lua_event_graph.json').read_text('utf-8'))
skills=graph['skills'];selected=graph['selected_skills']
ok(len(selected)==24,'24 selected skill count')
ok(len(skills)==39,'39 Lua event nodes')
ok(sum(len(skills[str(i)]['event_levels']['20']) for i in selected)==15,
   'level 20 event linkage count')
for i in selected:
 item=skills[str(i)]
 ok(item.get('lua_definition_found') is True,f'missing original Lua {i}')
 for lvl in range(1,21):
  for event in item['event_levels'][str(lvl)]:
   ok(str(event['skill_id']) in skills,f'unresolved event {i} lvl {lvl}')
# No new global class registrations; only local preload scripts.
for f in m['modified_source_scripts']:
 ok(not re.search(r'^\s*class_name\s+', (root/'scripts'/f).read_text(),re.M),
    f'new duplicate Godot class may be registered in {f}')
print('V44.3 STATIC PASS:',check,'checks, protected TV byte-identical, 24 selected / 39 graph nodes')
print('IMPORTANT: Static checks do not replace Godot F5/--headless parser tests.')
