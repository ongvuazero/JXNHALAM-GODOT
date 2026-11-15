#!/usr/bin/env python3
"""Source-level V44 tests. Not a substitute for Godot --headless --editor --quit."""
from pathlib import Path
import json, hashlib, re, csv
P=Path(__file__).resolve().parent.parent
src=P/'scripts'
passes=[]
def check(label,condition):
    if not condition: raise SystemExit('FAIL: '+label)
    passes.append(label)
# 1. 21+3 skill data retained
known=[]
for f in (P/'data/sects').glob('*.json'):
    data=json.loads(f.read_text(encoding='utf-8'))
    for w in data.get('weapons',[]):
        for skill in w.get('skills',[]):
            known.append((data.get('id',''),int(skill.get('legacy_skill_id',0)),skill))
check('24 distinct native skill ids',len(known)==24 and len({s[1] for s in known})==24)
check('9 other sects + TV',len({s[0] for s in known})==10)
check('Cai Bang two source skill branches', sorted(s[1] for s in known if s[0]=='cai_bang')==[357,359])
check('Nga Mi two source skill branches', sorted(s[1] for s in known if s[0]=='nga_mi')==[328,380])
# 2. 24 range rows
rows=list(csv.DictReader((P/'V44_SKILL_RANGE_PREVIEW.csv').open(encoding='utf-8-sig')))
check('24 range audit records',len(rows)==24)
for row in rows:
    old=float(row['old_Godot_px']);new=float(row['V44_QA_px']);raw=float(row['raw_JX'])
    if row['sect']=='thien_vuong': check('TV range unchanged '+str(row['skill_id']),new==max(48.0,old))
    elif raw>0:check('new range derived from source raw '+str(row['skill_id']),abs(new-max(48.0,min(600.0,raw*0.55)))<0.001)
# 3. Three 64-way -> 8/16/32-way cardinal conversions independently
import math
for dirs in [8,16,32,64]:
    for (x,y),expected_dir64 in [((0,1),0),((-1,0),16),((0,-1),32),((1,0),48)]:
        d=round(math.atan2(y,x)*64/(2*math.pi))+48
        row=round((d%64)*dirs/64)%dirs
        expected=round(expected_dir64*dirs/64)%dirs
        check(f'cardinal x={x} y={y} dirs={dirs}',row==expected)
# 4. TV core script byte fidelity
for file,sha in json.loads((P/'V44_TV_BASELINE_SHA256.json').read_text()).items():
    check('TV source sha256: '+file,hashlib.sha256((P/file).read_bytes()).hexdigest()==sha)
# 5. No duplicate globally registered class names
names={}
for p in src.glob('*.gd'):
    for cls in re.findall(r'^class_name\s+(\w+)',p.read_text(encoding='utf-8'),re.M):names.setdefault(cls,[]).append(p.name)
check('no global class duplicate',all(len(v)==1 for v in names.values()))
check('JX141 native probe no class_name', 'class_name JX141NativeFrameProbe' not in (src/'JX141NativeFrameProbe.gd').read_text())
# 6. local static preload path sanity
missing=[]
for p in src.glob('*.gd'):
    for f in re.findall(r'preload\("(res://.*?)"\)',p.read_text(encoding='utf-8')):
        if not (P/f.removeprefix('res://')).exists():missing.append((p.name,f))
check('all GDScript preloads resolved',not missing)
# 7. only generic renderer visual count changed; homing max3 retained
sect=(src/'JXSectSkillPreview.gd').read_text()
homing=(src/'JXHomingSkillPreview.gd').read_text()
check('generic renderer does not use ChildSkillNum for visual count', 'displayed_count = GEOMETRY.visible_sprite_limit(skill)' in sect)
check('generic renderer still has all source stages',all(f'"{role}"' in sect for role in ['precast','fly','travel_end','hit']))
check('Cai Bang follow still capped 3', 'clampi(int(profile.get("max_visible_projectiles", 1)), 1, 3)' in homing)
check('Cai Bang keeps current target homing', '_current_target() - pos' in homing)
check('Cai Bang uses contact heading at impact', '_spawn_hit(destination, true, heading)' in homing)
check('unified 64 dir reused by both renderers',all('JXSPRDirection.gd' in (src/name).read_text() for name in ['JXSectSkillPreview.gd','JXHomingSkillPreview.gd']))
print('PASS:',len(passes),'checks; no runtime compilation claimed.')
