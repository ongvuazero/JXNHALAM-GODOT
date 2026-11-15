# coding: utf-8
"""Static checks only. NO Godot runtime and no original AT03 SPR pixel bytes required."""
import json, pathlib, hashlib
p=pathlib.Path(__file__).resolve().parents[1]
a=json.loads((p/'data/renderer_audit/blade_004_action_profiles.json').read_text(encoding='utf8'))
b=json.loads((p/'data/renderer_audit/at03_male_raw_draworder.json').read_text(encoding='utf8'))
action=next(x for x in a['actions'] if x['id']=='AT03')
assert action['frames_per_dir']==14 and action['directions']==8
assert len(action['layers'])==6
assert all(len(x['frame_offsets_xywh'])==112 for x in action['layers'])
assert set(range(1,9)).issubset({int(x) for x in b['lines'].keys()})
assert b['sha256_source']
for source in ['V28SPRFrameDecoder.gd','V28AT03LayerComposer.gd','SPRActionAudit.gd','V27AT03Extractor.gd']:
 assert (p/'scripts'/source).is_file()
assert (p/'scenes/v28_at03_layer_composer.tscn').is_file()
audit=(p/'scripts/SPRActionAudit.gd').read_text(encoding='utf8')
assert 'KEY_C: _open_six_layer_composer()' in audit
assert 'res://scenes/v28_at03_layer_composer.tscn' in audit
for source in ['Player.gd','V22MainCombat.gd','V22HitProbe.gd','CTC9XTimeline.gd']:
 assert (p/'scripts'/source).is_file()
print('V28 source QA PASS; six profiles, 112 frame offsets/layer, raw male render-order metadata, scene and C-key path. Godot not executed.')
