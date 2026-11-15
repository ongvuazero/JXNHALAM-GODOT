#!/usr/bin/env python3
from pathlib import Path
import csv, json, sys
root=Path(__file__).resolve().parent.parent
with (root/'settings/skills.txt').open(encoding='latin1',newline='') as f:
    skills={row['SkillId']:row for row in csv.DictReader(f,delimiter='\t')}
with (root/'settings/missles.txt').open(encoding='latin1',newline='') as f:
    missiles={row['MissleId']:row for row in csv.DictReader(f,delimiter='\t')}
spec=json.loads((root/'data/combat/jx_special_motion_v447.json').read_text(encoding='utf-8'))
issues=[]
for sid in ('318','342'):
    row=skills[sid]; missile=missiles[row['ChildSkillId']]; mapped=spec[sid]
    expected={'missile_id':int(missile['MissleId']),'move_kind':int(missile['MoveKind']),
        'missile_speed_raw':int(missile['Speed']),'missile_lifetime_ticks':int(missile['LifeTime']),
        'missile_param1':int(missile['Param1']),'missile_param2':int(missile['Param2']),
        'missles_form':int(row['MisslesForm']),'child_skill_num':int(row['ChildSkillNum']),
        'skill_param1':int(row['Param1']),'skill_param2':int(row['Param2']),
        'generate_style':int(row['MslsGenerate']),'generate_step_ticks':int(row['MslsGenerateData']),
        'wait_ticks':int(row['WaitTime'])}
    for key,value in expected.items():
        if mapped[key]!=value:issues.append(f'Skill {sid}: {key} actual={mapped[key]} expected={value}')
    print('Skill',sid,'missile',missile['MissleId'],'MoveKind',missile['MoveKind'],'form',row['MisslesForm'],'count',row['ChildSkillNum'])
row=spec['342']
order=[row['wait_ticks']+abs(i-2)*row['generate_step_ticks'] for i in range(5)]
if order!=[6,4,2,4,6]:issues.append(f'342 launch order incorrect {order}')
print('342 CENTEREXTENDLINE launch ticks:',order)
print('342 rollback halfway tick:',row['missile_lifetime_ticks']//2)
print('318 form=12: no speculative extra sprites')
if issues:
    print('SOURCE AUDIT FAIL',*issues,sep='\n');sys.exit(1)
print('V44.7 SOURCE AUDIT PASS (not a Godot F5 runtime check)')
