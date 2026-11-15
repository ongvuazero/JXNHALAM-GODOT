#!/usr/bin/env python3
"""V44.1 source QA only. Does NOT compile or execute Godot GDScript."""
import csv
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
checks=[]

def check(condition, description):
    checks.append((bool(condition),description))
    print(('PASS' if condition else 'FAIL')+' | '+description)

# Compare protected TV files against recorded byte-for-byte V44.0 baselines.
base=json.loads((root/'V44_TV_BASELINE_SHA256.json').read_text(encoding='utf8'))
for rel,hexdigest in sorted(base.items()):
    data=(root/rel).read_bytes()
    check(hashlib.sha256(data).hexdigest()==hexdigest, 'TV protected bytes '+rel)

# Ensure 9 sect routes are left intact; only this standalone renderer may change.
meta=list(csv.DictReader((root/'V44_1_ROUTE_AND_SPR_AUDIT.csv').open(encoding='utf-8-sig',newline='')))
check(len(meta)==21,'21 non-TV skills in source inventory')
for mode,number in [('stationary_QA',8),('straight_QA',10),('homing_CaiBang',2),('unsupported_keep_stationary',1)]:
    check(sum(x['co_che_v44_1']==mode for x in meta)==number,'motion route '+mode)
check(all(int(x['child_skill_num'])>=1 for x in meta),'ChildSkillNum retained')
check(all(x['damages']=='DEMO_ONLY' for x in meta),'No false native damage claim')

motion=(root/'scripts/JXMissileMotion.gd').read_text(encoding='utf-8')
generic=(root/'scripts/JXSectSkillPreview.gd').read_text(encoding='utf-8')
homing=(root/'scripts/JXHomingSkillPreview.gd').read_text(encoding='utf-8')
main=(root/'scripts/Main.gd').read_text(encoding='utf-8')
geo=(root/'scripts/JXCombatGeometry.gd').read_text(encoding='utf-8')
check('segment_hits_circle' in motion and 'closest_point_on_segment' in motion,'swept collision helper exists')
check('visual_contact' in generic and '_has_live_target()' in generic,'generic hit is contact-gated')
check('MOTION.motion_point' in generic,'generic animation routed through JXMissileMotion')
check('"follow_external"' in motion and 'return start' in motion,'follow/unknown cannot borrow fake linear movement')
check('"qa_flight_speed_px_s"' not in generic,'no magic pixels/sec from raw JX table')
check('source_child_skill_num' in homing and 'max_visible_projectiles' in homing,'Cai Bang 3-visible cap preserved')
check('FOLLOW_PREVIEW_CODE if follow_by_source' in main,'Main dispatch still follows MoveKind5')
check('flight_speed_px_s_by_skill' in geo,'per skill QA speed calibration')
check('hit_radius_px_by_skill' in geo,'per skill QA collision radius calibration')
check('class_name JX141NativeFrameProbe' not in (root/'scripts/JX141NativeFrameProbe.gd').read_text(),'duplicate global class mitigation preserved')

# All preload("res://...") paths should exist, at least in changed files.
for rel in ['scripts/JXSectSkillPreview.gd','scripts/JXMissileMotion.gd','tests/TestJXMissileMotion.gd']:
    text=(root/rel).read_text(encoding='utf-8')
    for path in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)',text):
        check((root/path).exists(),rel+' loads '+path)

# Simple typo prevention, not a GDScript parser.
for rel in ['scripts/JXSectSkillPreview.gd','scripts/JXMissileMotion.gd']:
    lines=(root/rel).read_text(encoding='utf-8').splitlines()
    check(lines[0]=='extends Node2D' if 'JXSect' in rel else lines[0]=='extends RefCounted',rel+' extends correct Node')
    check(len(re.findall(r'^(?:static )?func ', '\n'.join(lines), flags=re.M))>=4,rel+' source functions are present')

fails=[name for ok,name in checks if not ok]
print(f'STATIC QA RESULT: {len(checks)-len(fails)}/{len(checks)} passed. NOTE: Godot F5 NOT run.')
if fails:raise SystemExit(1)
