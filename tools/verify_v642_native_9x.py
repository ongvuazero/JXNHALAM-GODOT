#!/usr/bin/env python3
"""Verify four bundled original 9x SPR resources and byte-based path mappings.
Uses Python standard library only; no client PAK access, no Godot runtime.
"""
import json
import struct
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
REGISTRY = json.loads((ROOT/'data/pak/known_hashes.json').read_text(encoding='utf-8'))
SKILLS = {int(s['skill_id']): s for s in json.loads((ROOT/'data/baseline/active_9x_3skills.json').read_text(encoding='utf-8'))}
CHECKS = [
    (322, 'AnimFile4', 2446487682, 'jx90_potian_impact.spr', 8, 1),
    (323, 'AnimFile4', 2667851309, 'jx90_truytinh_impact.spr', 6, 1),
    (325, 'AnimFile2', 3147144842, 'jx90_truyphong_sweep.spr', 320, 32),
    (325, 'AnimFile4', 1313618360, 'jx90_truyphong_impact.spr', 6, 1),
]

def verify_spr(raw, expected_frames, expected_dirs):
    assert raw[:4] == b'SPR\0' and len(raw) >= 40
    width, height = struct.unpack_from('<HH',raw,4)
    total, colors, dirs = struct.unpack_from('<HHH',raw,12)
    assert 0 < width <= 1024 and 0 < height <= 1024
    assert total == expected_frames and dirs == expected_dirs and 0 < colors <= 256
    offset_table = 32 + colors*3
    data_at = offset_table + total*8
    assert data_at < len(raw)
    for i in range(total):
        off, size = struct.unpack_from('<II', raw, offset_table + i*8)
        start = data_at + off
        if start+size>len(raw):start=off
        assert size >= 8 and start+size <= len(raw)
        fw, fh = struct.unpack_from('<HH', raw, start)
        assert 0 < fw <= 1024 and 0 < fh <= 1024
        cursor, num_pixels, end = start+8, 0, start+size
        while num_pixels < fw*fh and cursor+1 < end:
            run, alpha = raw[cursor],raw[cursor+1];cursor+=2
            if run:
                num_pixels += run
                assert num_pixels <= fw*fh
                if alpha:
                    cursor += run
                    assert cursor <= end
        assert num_pixels == fw*fh, (i,num_pixels,fw*fh)

for sid,tag,hid,name,frames,dirs in CHECKS:
    virtual = SKILLS[sid][tag]
    # Hash keys are ASCII-folded only. Unicode lower() corrupts Latin1 raw-byte names.
    folded = ''.join(c.lower() if 'A' <= c <= 'Z' else c for c in virtual)
    assert REGISTRY[folded] == hid, (sid,virtual)
    p=ROOT/'assets/skill90/source_spr'/name
    verify_spr(p.read_bytes(), frames, dirs)
    print('PASS',sid,tag,name,frames,'frames',dirs,'directions')

resolver = (ROOT/'scripts/ClientAssetResolver.gd').read_text(encoding='utf-8')
audit = (ROOT/'scripts/AssetAudit.gd').read_text(encoding='utf-8')
main = (ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
for _,_,hid,name,*_ in CHECKS:
    assert f'{hid}:' in resolver and name in resolver
assert all(key in audit for key in ('BUNDLED_SPR', 'pak_ok','loose_ok','bundled_ok','fallback_ok'))
assert 'bundled SPR:%d' in main
assert '*.spr' in (ROOT/'export_presets.cfg').read_text(encoding='utf-8')
print('PASS 4 native SPR and audit wiring. NOTE: does not prove client PAK contains these files.')
print('LIMIT: Run Godot 4 on Windows to validate actual rendering and resource export.')
