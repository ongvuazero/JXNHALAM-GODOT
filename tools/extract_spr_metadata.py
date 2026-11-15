"""Read (not extract) native SPR frame dimensions and original offsets.
Usage: python tools/extract_spr_metadata.py ClientData.zip output.json
Metadata is not a license for the underlying artwork.
"""
from pathlib import Path
from zipfile import ZipFile
import json
import struct
import sys


def get_metadata(data):
    if len(data)<40 or data[:4]!=b'SPR\0':
        return None
    w,h,cx,cy,frames,colors,dirs,interval=struct.unpack_from('<HHhhHHHH', data,4)
    if not(0<frames<3000 and 0<colors<=256 and 0<dirs<=32):return None
    table=32+colors*3; start=table+frames*8
    if start>len(data):return None
    out=[]
    for n in range(frames):
        off,size=struct.unpack_from('<II',data,table+n*8)
        pos=start+off
        if pos+size>len(data):pos=off
        if pos+size>len(data) or size<8: return None
        fw,fh,ox,oy=struct.unpack_from('<HHhh',data,pos)
        out.append([int(ox),int(oy),int(fw),int(fh)])
    return {'canvas':[w,h],'pivot':[cx,cy], 'frames':frames,'directions':dirs,
            'stored_interval':interval,'frame_offsets_xywh':out}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('Usage: python extract_spr_metadata.py ClientData.zip output.json')
    d={}
    with ZipFile(sys.argv[1]) as z:
        for info in z.infolist():
            if info.filename.lower().endswith('.spr'):
                meta=get_metadata(z.read(info))
                if meta:d[info.filename]=meta
    Path(sys.argv[2]).write_text(json.dumps(d,ensure_ascii=False,indent=None),encoding='utf-8')
    print('Native SPR metadata files:',len(d))
