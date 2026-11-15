#!/usr/bin/env python3
from pathlib import Path
import csv,struct,collections,sys,importlib.util,re,tempfile,subprocess,hashlib,shutil
HERE=Path(__file__).resolve().parent.parent
BASE=Path('/mnt/data') if Path('/mnt/data/game.exe').is_file() else HERE
exe=BASE/'game.exe'
if not exe.is_file():
 print('SKIP raw EXE cross check (not packaged); table self-check follows')
 b=None
else:b=exe.read_bytes()
with (HERE/'NATIVE_64DIR_TABLE.csv').open(encoding='utf-8-sig') as f:table=list(csv.DictReader(f))
assert len(table)==64
assert [int(x['dir64']) for x in table]==list(range(64))
if b:
 for x in table:
  for col,offset in [('client_exe_x','offset_x_table'),('client_exe_y','offset_y_table')]:
   addr=int(x[offset],16);off=0x27c000+(addr-0x67c000)
   assert struct.unpack_from('<i',b,off)[0]==int(x[col]),(x,col)
print('PASS 64/64 integer factor lookup entries')
for d,v in [(0,(0,1024)),(16,(-1024,0)),(32,(0,-1024)),(48,(1024,0))]:
 assert (int(table[d]['client_exe_x']),int(table[d]['client_exe_y']))==v
with (HERE/'NATIVE_M141_FACTOR_VARIANTS.csv').open(encoding='utf-8-sig') as f:variants=list(csv.DictReader(f))
assert len(variants)==45
n=sum(int(x['log_rows']) for x in variants)
matched=sum(int(x['log_rows']) for x in variants if x['exact_lut_match']=='1')
assert (n,matched)==(523,288),(n,matched)
assert any(x['dir64']=='3' and x['log_x']=='-327' for x in variants)
print('PASS 523 log samples, 288 exact table matches and 235 verified non-LUT samples')
tpl=(HERE/'JX141NativeDirectionLUT.gd.txt').read_text()
assert 'class_name ' not in tpl.split('##')[0]
assert tpl.count('static func resolve(')==1
assert tpl.count('static func direction_from_factors(')==1
xs=[int(x) for x in re.search(r'const X_FACTORS = \[(.*?)\]',tpl,re.S).group(1).replace('\n','').split(',') if x.strip()]
ys=[int(x) for x in re.search(r'const Y_FACTORS = \[(.*?)\]',tpl,re.S).group(1).replace('\n','').split(',') if x.strip()]
assert len(xs)==64 and len(ys)==64
assert [(xs[i],ys[i]) for i in range(64)]==[(int(t['client_exe_x']),int(t['client_exe_y'])) for t in table]
print('PASS LUT GDScript template matches CSV')
import math
with (HERE/'NATIVE_M141_FACTOR_VARIANTS.csv').open(encoding='utf-8-sig') as f:
 observed=list(csv.DictReader(f))
for v in observed:
 x,y,d=(int(v[k]) for k in ['log_x','log_y','dir64'])
 r=int((y*1024.0)/math.hypot(x,y))
 h=min(range(33),key=lambda k:abs(ys[k]-r))
 predicted=(64-h)%64 if x>=0 else h
 assert d==predicted,(d,x,y,predicted)
print('PASS native factor->direction for all 45 unique tuples (523 log records)')
loader=importlib.util.spec_from_file_location('v4install',HERE/'INSTALL_M141_V4.py')
mod=importlib.util.module_from_spec(loader);loader.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as temp:
 root=Path(temp);(root/'scripts').mkdir();(root/'project.godot').write_text('[application]\n')
 before=(HERE/'tests'/'fixture_v3_script.txt').read_text(encoding='utf-8')
 (root/mod.TARGET).write_text(before)
 checksum=hashlib.sha256((root/mod.TARGET).read_bytes()).hexdigest()
 mod.install(root)
 new=(root/mod.TARGET).read_text();assert mod.MARKER in new
 assert 'native_info' in new and 'pixel_per_tick_preview' in new
 assert (root/mod.NEW_SCRIPT).is_file()
 mod.install(root)
 mod.rollback(root)
 assert (root/mod.TARGET).read_text()==before
 assert hashlib.sha256((root/mod.TARGET).read_bytes()).hexdigest()==checksum
 assert not (root/mod.NEW_SCRIPT).exists()
 print('PASS V3->V4 install, repeat-install, rollback with byte-exact V3 restoration')
print('NOT VERIFIED: actual Godot compile, motion/screen projection/native hit timing')
