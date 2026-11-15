#!/usr/bin/env python3
"""V6 data regression; Python emulates logic but does NOT execute Godot runtime."""
import struct,sys,zipfile
from pathlib import Path
P=Path(__file__).resolve().parents[1]

def hashpath(path):
 a=0
 for i,b in enumerate(path.lower().encode('ascii'),1):a=(-17*((a+i*b)%0x8000000b))&0xffffffff
 return a^0x12345678

def reassemble_framepacked(blob):
 assert blob[:4]==b'SPR\0'
 frames, colors=struct.unpack_from('<HH',blob,12)
 table=32+colors*3
 at=table+frames*8
 out=bytearray(blob[:table]);frame_offset=0;fr=[]
 for i in range(frames):
  psize,ssize=struct.unpack_from('<Ii',blob,table+i*8)
  assert psize>0 and ssize<0 and -ssize==psize
  data=blob[at:at+psize];assert len(data)==psize
  at+=psize;fr.append(data)
  out+=struct.pack('<II',frame_offset,len(data));frame_offset+=len(data)
 for f in fr:out+=f
 return bytes(out)

packed=(P/'tests/fixtures/DEMO_FRAME_PACKED.pak').read_bytes()
assert packed[:4]==b'PACK'
count,idx,_=struct.unpack_from('<III',packed,4);assert count==1
h,at,raw,info=struct.unpack_from('<IIII',packed,idx)
assert h==hashpath(r'\spr\demo_framepacked.spr'),hex(h)
assert (info&0xff000000)==0x10000000
actual=reassemble_framepacked(packed[at:at+(info&0xffffff)])
assert actual==(P/'tests/fixtures/DEMO_SPR_CANONICAL.bin').read_bytes()
print('PASS synthetic frame-packed SPR -> exact standard SPR')
root=P/'tests/fixtures/priority_client'
assert (root/'settings/priority.ini').read_bytes()==b'PRIORITY_LOOSE_OVER_PAK'
import re
ini=(root/'package.ini').read_text()
assert re.search(r'0=patch\.pak',ini) and re.search(r'1=base\.pak',ini)
for pakname,expected in [('patch.pak',b'PRIORITY_PATCH_0'),('base.pak',b'PRIORITY_BASE_1')]:
 b=(root/'data'/pakname).read_bytes();h2,o,sz,info=struct.unpack_from('<IIII',b,32)
 assert h2==hashpath(r'\settings\priority.ini')
 assert b[o:o+(info&0xffffff)]==expected
print('PASS package.ini ordered PAK and loose fixtures')
# Optional privately uploaded JX sprite data test (not bundled in result).
if len(sys.argv)>1:
 z=zipfile.ZipFile(sys.argv[1]); item=next(n for n in z.namelist() if n.endswith('MA_BD_001_RN03.spr'))
 source=z.read(item);assert source[:4]==b'SPR\0'
 frames,colors=struct.unpack_from('<HH',source,12); pos=32+colors*3
 bfr=[];base=pos+frames*8
 for i in range(frames):
  offset,size=struct.unpack_from('<II',source,pos+i*8)
  bfr.append(source[base+offset:base+offset+size])
 framepack=source[:pos]+b''.join(struct.pack('<Ii',len(f),-len(f)) for f in bfr)+b''.join(bfr)
 assert reassemble_framepacked(framepack)==source
 print(f'PASS real JX client SPR {item}: {frames} frames, 8 directions, reassembly exactly equal')
print('Limit: Only uncompressed frame payloads tested; UCL / Godot GDScript runtime requires Godot headless.')
