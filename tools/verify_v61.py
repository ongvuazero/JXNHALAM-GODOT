#!/usr/bin/env python3
"""Regression checks for V6.1 SPR sentinel correction. Does not execute Godot."""
import zipfile,struct,sys
from pathlib import Path
project=Path(__file__).resolve().parent.parent

def decode_layout(raw):
    assert raw[:4]==b'SPR\0'
    width,height=struct.unpack_from('<HH',raw,4)
    frames,colors,directions=struct.unpack_from('<HHH',raw,12)
    table=32+colors*3
    data_start=table+frames*8
    assert 0<data_start<=len(raw)
    keep=frames
    trimmed=0
    if frames%directions:
        assert frames%directions==1
        o,size=struct.unpack_from('<II',raw,table+(frames-1)*8)
        start=data_start+o
        if start+size>len(raw): start=o
        assert size==10 and start>=data_start and start+size<=len(raw)
        assert struct.unpack_from('<HH',raw,start)==(1,1)
        assert raw[start+8:start+10]==b'\x01\x00'
        keep-=1;trimmed=1
    assert keep%directions==0
    # Decode a 1x1/real frame end-to-end to ensure no bad offsets.
    for i in range(keep):
        off,sz=struct.unpack_from('<II',raw,table+i*8)
        start=data_start+off
        if start+sz>len(raw):start=off
        assert sz>=8 and start+sz<=len(raw)
        w,h,ox,oy=struct.unpack_from('<HHhh',raw,start)
        assert 0<w<=1024 and 0<h<=1024
        pos=start+8;end=start+sz;pixel=0
        while pixel<w*h and pos+1<end:
            count,alpha=raw[pos:pos+2];pos+=2
            if count:
                assert pixel+count<=w*h
                if alpha: pos+=count;assert pos<=end
                pixel+=count
        assert pixel==w*h, (i,pixel,w*h)
    return frames,keep,directions,trimmed

sample=(project/'tests/fixtures/DEMO_SPR_17FRAME_SENTINEL.bin').read_bytes()
assert decode_layout(sample)==(17,16,16,1)
print('PASS: 17-frame synthetic SPR correctly trimmed to 16 directions')
if len(sys.argv)>1:
    with zipfile.ZipFile(sys.argv[1]) as z:
        name=next(n for n in z.namelist() if n.endswith('sl_150_daotian_zd.spr'))
        raw=z.read(name)
        assert len(raw)==212762
        assert decode_layout(raw)==(17,16,16,1)
    print('PASS: real Thien Vuong DAO flying SPR, 212762 bytes, 16/16 visible frames + 1 transparent marker')
print('NOTE: Godot headless still required to verify rendering and Windows runtime.')
