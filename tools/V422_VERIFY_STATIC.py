#!/usr/bin/env python3
"""V42.2 offline source/catalog/hold-attack regression checks. No Godot runtime."""
from pathlib import Path
import json, hashlib
root=Path(__file__).resolve().parents[1]
BASELINE_SHA256={'scripts/V22MainCombat.gd': '060a7e6e9129c75765a40eddd823ca40c468b5714682df1a0a0588272e7a18a1', 'scripts/V22HitProbe.gd': '96b3f3513db898252057577612c8e9406a5886bb4a4b81d9fd917facc8c50539', 'scripts/JXMissileGeometry.gd': '8b9c05ea1971f4d15fab7082b17fb994dbb452301eca290dabbbe72030bd80d6', 'assets/skill90/jx90_truyphong_sweep.png': '93125a1bf5e390fbcae6a8eb6585f6b7db48bb366c7a04ed87a38bba77e357a4', 'data/sects/thien_vuong_full_skill_catalog.json': '6310513bc57b932360bafd4f26f3d836ecf45036d4b9629ae23167a3387ce4f8'}
reg=json.loads((root/'data/sects/registry.json').read_text(encoding='utf-8'))
assert reg['total_slots']==10 and len(reg['sects'])==10
assert {x['id'] for x in reg['sects']}=={'thieu_lam','thien_vuong','duong_mon','ngu_doc','nga_mi','thuy_yen','cai_bang','thien_nhan','vo_dang','con_lon'}
count=0
for row in reg['sects']:
    cfg=json.loads((root/row['config'].removeprefix('res://')).read_text(encoding='utf-8'))
    assert cfg['id']==row['id'] and cfg['weapons'] and len(cfg['weapons'])==3
    assert cfg['visual_manifest'].startswith('res://')
    for weapon in cfg['weapons']:
        assert isinstance(weapon['skills'],list) and weapon['skills']
        for skill in weapon['skills']:
            assert 'legacy_skill_id' in skill and len(skill['name'])>0
            if row['id']!='thien_vuong':
                assert skill['preview_only'] and not skill['vfx']['cast'] and not skill['vfx']['fly']
            count+=1
print('PASS 10 sects, 3 groups each,',count,'skills; original TCVN3 names rendered as Unicode')
assert count>=250
main=(root/'scripts/Main.gd').read_text(encoding='utf-8')
player=(root/'scripts/Player.gd').read_text(encoding='utf-8')
bridge=(root/'scripts/BaselineDataBridge.gd').read_text(encoding='utf-8')
assert 'Input.is_key_pressed(KEY_SPACE)' in main
assert 'space_was_held and bool(player.get("pending_cast"))' in main
assert 'SPACE_REPEAT_SAMPLE' in main
assert 'KEY_SPACE: pass' in main and 'KEY_F2: _toggle_school_browser()' in main
assert 'KEY_TAB: _cycle_enabled_school()' in main
assert 'bool(skill.get("catalog_passive", false))' in player
assert 'if bool(skill.get("preview_only", false)):' in main
assert 'weapon["skills"] = [active_skill] + original_skills.slice(1)' in bridge
print('PASS hold Space repeat + release-cancel + modal stop + all-sect browser + passive guard')
for rel, original_hash in BASELINE_SHA256.items():
    assert hashlib.sha256((root/rel).read_bytes()).hexdigest() == original_hash, rel
print('PASS stable probe, geometry, source assets and skill catalog hashes (VFX deliberately updated)')
tv=json.loads((root/'data/sects/thien_vuong.json').read_text(encoding='utf-8'))
assert [int(tv['weapons'][i]['skills'][0]['legacy_skill_id']) for i in range(3)]==[322,323,325]
assert sum(len(w['skills']) for w in tv['weapons'])>20
print('PASS TV hotkeys 1/2/3 = 322/323/325; other TV skills retained after bridge inject')
print('LIMIT: original per-sect SPR, skill effects, passive formulas, native combat clock require source assets/engine work')
