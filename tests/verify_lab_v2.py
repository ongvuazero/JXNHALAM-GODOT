import csv,io,json,struct,zipfile
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
data=json.loads((root/'data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json').read_text(encoding='utf8'))
assert data['parent_skill']==325 and data['child_skill']==408
assert [x['dir64'] for x in data['sample']]==[3,11,19]
assert [x['x_factor'] for x in data['sample']]==[-327,-923,-979]
assert [x['y_factor'] for x in data['sample']]==[978,461,-327]
assert sorted(x['missile_slot'] for x in data['sample'])==[3,7,8]
for kind,frames,dirs,canvas in [('fly',320,32,[240,240]),('impact',6,1,[200,200])]:
 s=data['spr'][kind]
 im=Image.open(root/s['path'].removeprefix('res://')).convert('RGBA')
 assert s['frames']==frames and s['directions']==dirs and s['canvas']==canvas
 assert im.size==((frames//dirs)*256,dirs*256)
 # Divides 64 directions into SPR rows with half-sector rounding.
 for direction in range(64):
  sector=64//dirs
  row=((direction+(32//dirs))//sector)%dirs
  assert 0<=row<dirs
  if kind=='fly':
   for age in range(4):
    local=frames//dirs*age//4
    assert [0,2,5,7][age]==local
    cell=im.crop((local*256,row*256,(local+1)*256,(row+1)*256))
    assert cell.getchannel('A').getbbox() is not None
code=(root/'scripts/JX141VisualLabV2.gd').read_text(encoding='utf8')
assert 'res://data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json' in code
assert 'res://assets/skill90/jx90_truyphong_sweep.png' in code
assert 'res://assets/skill90/jx90_truyphong_impact.png' in code
assert 'queue_redraw()' in code
assert 'func apply_damage' not in code.lower()
assert 'func cast_skill' not in code.lower()
print('PASS — 3 native samples, sprite atlas metadata, direction 64->32, frame subset, lab files')
