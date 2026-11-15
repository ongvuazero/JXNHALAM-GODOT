# -*- coding: utf-8 -*-
"""V27 structural audit & reference hash test; no Godot 4 runtime is available here."""
from pathlib import Path
import json,struct
ROOT=Path(__file__).resolve().parents[1]
profile=json.loads((ROOT/'data/renderer_audit/blade_004_action_profiles.json').read_text(encoding='utf8'))
action=next(x for x in profile['actions'] if x['id']=='AT03')
expected=['MA_BD_001_AT03.spr','MA_LH_001_AT03.spr','MA_RH_001_AT03.spr','MA_HD_001_AT03.spr','MA_LW_000_AT03.spr','MA_RW_004_AT03.spr']
assert action['frames_per_dir']==14 and action['directions']==8
assert [x['source_spr'] for x in action['layers']]==expected
assert all(len(x['frame_offsets_xywh'])==112 for x in action['layers'])
assert not action['composite_atlas']
assert len(json.loads((ROOT/'data/renderer_audit/V27_MELEEWCUT_RENDER_ORDER_RAW.json').read_text(encoding='utf-8'))['entries_verbatim'])>=14
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf8')
ui=(ROOT/'scripts/SPRActionAudit.gd').read_text(encoding='utf8')
code=(ROOT/'scripts/V27AT03Extractor.gd').read_text(encoding='utf8')
vfs=(ROOT/'scripts/JXVirtualFS.gd').read_text(encoding='utf8')
assert 'KEY_O: _open_spr_renderer_audit()' in main
for needle in ['KEY_T: _choose_client_folder()','FileDialog.FILE_MODE_OPEN_DIR','AT03_EXTRACTOR.new()', 'func _extract_client_at03']:
 assert needle in ui,needle
for needle in ['fs.configure(root)','fs.locate(virtual_path)','fs.read_bytes(virtual_path)','DirAccess.make_dir_recursive_absolute','_validate_raw_spr','EXISTING_VALID','NOT_FOUND','BAD_PAYLOAD','sha']:
 assert needle in code,needle
assert '0x12345678' in vfs and 'METHOD_FRAME' in vfs and '_decode_ucl' in vfs
# Test against shipped known-hash and 3-entry reference PAK: verifies hash
# arithmetic and index lookup independently of Godot execution.
known=json.loads((ROOT/'data/pak/known_hashes.json').read_text(encoding='utf-8'))
pak=(ROOT/'tests/fixtures/DEMO_JX_PACK.pak').read_bytes()
magic,count,index_at,data_at=struct.unpack_from('<4sIII',pak)
assert magic==b'PACK' and 0<count<=10000
pak_ids={struct.unpack_from('<I',pak,index_at+16*i)[0] for i in range(count)}
def path_hash(path):
 h=0
 for idx,b in enumerate(path.lower().encode('ascii')):
  h=(-17*((h+(idx+1)*b)%0x8000000b))&0xffffffff
 return h ^0x12345678
assert path_hash('\\script\\demo.lua')==known['\\script\\demo.lua']
assert path_hash('\\script\\demo.lua') in pak_ids
assert (ROOT/'scenes/spr_renderer_audit.tscn').is_file()
for n in ['scripts/V22MainCombat.gd','scripts/V22HitProbe.gd','scripts/CTC9XTimeline.gd']:
 assert (ROOT/n).is_file()
assert not any((ROOT/'data/spr/npcres/man'/n).exists() for n in expected), 'Do not bundle JX1 original sprites without the user-supplied client'
print('V27 STATIC PASS — six AT03 paths, 112 offsets per layer, pack hash/index fixture, UI extraction wiring and no fabricated sprites.')
print('GODOT_RUNTIME_NOT_TESTED — run F5 -> O -> T on Windows with real client folder.')
