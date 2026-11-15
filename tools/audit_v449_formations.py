from pathlib import Path
import json,csv,sys
root=Path(__file__).resolve().parent.parent
settings=root/'settings/skills.txt'; missiles=root/'settings/missles.txt'
with settings.open(encoding='latin1',newline='') as f:
 sk={int(x['SkillId']):x for x in csv.DictReader(f,delimiter='\t') if x.get('SkillId','').isdigit()}
with missiles.open(encoding='latin1',newline='') as f:
 ms={int(x['MissleId']):x for x in csv.DictReader(f,delimiter='\t') if x.get('MissleId','').isdigit()}
p=json.loads((root/'data/combat/jx_formations_v449.json').read_text(encoding='utf8'))
for sid in (321,336,355,368):
 r=sk[sid];m=ms[int(r['ChildSkillId'])];d=p[str(sid)]
 tests=[d['form']==int(r['MisslesForm']),d['count']==int(r['ChildSkillNum']),d['missile_id']==int(r['ChildSkillId']),d['move_kind']==int(m['MoveKind'])==1,
        d['generate_style']==int(r['MslsGenerate']),d['generate_step_ticks']==int(r['MslsGenerateData']),d['wait_ticks']==int(r['WaitTime']),
        d['life_ticks']==int(m['LifeTime']),d['speed_raw']==int(m['Speed'])]
 if not all(tests):
  print('SOURCE MISMATCH',sid, tests);sys.exit(1)
 print('PASS',sid,'form',d['form'],'count',d['count'],'generate style',d['generate_style'])
assert str(318) not in p and str(342) not in p
print('V44.9 4/4 profiles match edition-specific settings/skills.txt and missles.txt.')
print('Sprite orientation, native scale and F5 runtime remain unverified.')
