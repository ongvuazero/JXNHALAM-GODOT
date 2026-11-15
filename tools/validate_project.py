"""Offline, read-only checks of the 10-sect Godot V2 vertical slice.
Usage: pip install pillow; python tools/validate_project.py
"""
from pathlib import Path
from PIL import Image
import json
import math
import sys

ROOT = Path(__file__).resolve().parents[1]
errors=[]
def chk(ok,msg):
    print(('PASS' if ok else 'FAIL'), msg)
    if not ok: errors.append(msg)
def load(rel):return json.loads((ROOT/rel).read_text(encoding='utf-8'))
def local_res(path):
    if not path.startswith('res://'): return None
    return ROOT/path[6:]

reg=load('data/sects/registry.json')
sects=reg['sects']; chk(len(sects)==10,'exactly 10 sects registered')
chk(len({s['id'] for s in sects})==10,'10 distinct sect IDs')
chk(len([s for s in sects if s['status']=='playable_prototype'])==1,'only Thiên Vương playable until nine other packs arrive')
tv=load('data/sects/thien_vuong.json')
chk(len(tv['weapons'])==3,'Thiên Vương 3 weapon branches')
hero=load('assets/character/manifest.json')
fx=load('assets/vfx/manifest.json')
for branch in tv['weapons']:
    b_id=branch['visual_id']; visual=hero.get(b_id,{})
    chk(len(visual)>=4,f'{b_id}: stand/run/attack/cast metadata')
    for state in ('stand','run','attack','cast'):
        info=visual.get(state,{})
        img=local_res(info.get('file',''))
        if img is None or not img.exists():
            chk(False,f'{b_id}/{state}: atlas exists');continue
        with Image.open(img) as im:
            expected=(info.get('frames_per_direction',0)*192,info.get('directions',0)*192)
            chk(im.size==expected, f'{b_id}/{state}: atlas {im.size} == {expected}')
    for skill in branch['skills']:
        for phase in ('cast','fly','hit','end'):
            key=skill['vfx'][phase]
            resource=fx.get(key, {})
            atlas=local_res(resource.get('file',''))
            chk(atlas is not None and atlas.exists(),f"{skill['id']} / {phase}: {key} present")
for vec,expected in [((0,1),0),((-1,1),1),((-1,0),2),((-1,-1),3),((0,-1),4),((1,-1),5),((1,0),6),((1,1),7)]:
    got=(round(math.atan2(vec[1],vec[0])/(math.pi/4))+6)%8
    chk(got==expected,f'native SPR direction {vec} = {expected}')
idx=load('data/sects/thien_vuong_full_skill_catalog.json')
chk(len(idx['skills'])>=20,'full skill index available for gradual migration')
print('\nRESULT:', 'PASS' if not errors else f'{len(errors)} FAILURE(S)')
sys.exit(1 if errors else 0)
