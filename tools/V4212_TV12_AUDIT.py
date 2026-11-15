#!/usr/bin/env python3
"""Audit 12 canonical TV skills from the bundled authoritative CTC snapshot.

Optional (for developer only): --v5 PATH_TO_CSV --v4 PATH_TO_CSV
Runtime observations are kept separate from table declarations. No damage formulas.
"""
import argparse
import csv
import io
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS = (
    ('DAO', '1x', 34), ('DAO', '3x', 37), ('DAO', '6x', 32), ('DAO', '9x', 322),
    ('THUONG', '1x', 30), ('THUONG', '3x', 35), ('THUONG', '6x', 41), ('THUONG', '9x', 323),
    ('CHUY', '1x', 29), ('CHUY', '3x', 31), ('CHUY', '6x', 324), ('CHUY', '9x', 325),
)

def run(v4=None, v5=None, output=None):
    data = json.loads((ROOT/'data/baseline/gameplay_runtime.json').read_text(encoding='utf-8'))
    baseline, manifest = data['skills'], json.loads((ROOT/'assets/vfx/manifest.json').read_text(encoding='utf-8'))
    catalogue = json.loads((ROOT/'data/sects/thien_vuong_full_skill_catalog.json').read_text(encoding='utf-8'))
    catalog_by_id = {int(s['id']): s for s in catalogue['skills']}
    counts = {}
    for name, path in [('V4', v4), ('V5', v5)]:
        if path:
            with open(path, encoding='utf-8-sig', newline='') as stream:
                groups = {}
                for row in csv.DictReader(stream):
                    k = row.get('parent_skill', '')
                    if k.isdigit():
                        groups.setdefault(int(k), Counter())[row['event']] += 1
                counts[name] = groups
    rows=[]
    for branch, tier, sid in SKILLS:
        parent = baseline.get(str(sid), {})
        assert parent, f'Original skill {sid} absent'
        child_id = int(parent.get('ChildSkillId') or 0)
        child = baseline.get(str(child_id), {})
        missile_id = int(child.get('ChildSkillId') or 0)
        missile_num = int(child.get('ChildSkillNum') or 0)
        child_num = int(parent.get('ChildSkillNum') or 0)
        assert child and child_num > 0 and missile_num > 0, f'Broken cast graph {sid}'
        assert missile_id == int(catalog_by_id[sid]['missile_ids']), f'Original missile mismatch {sid}'
        assert int(parent.get('MisslesForm') or 0)==12, f'Dispatch changed {sid}'
        if sid == 324:
            m140=data['missiles']['140']; m141=data['missiles']['141']
            assert m140['AnimFile2'] == m141['AnimFile2']
            assert m140['AnimFile4'] == m141['AnimFile4']
        if tier == '9x':
            assert int(sid in (322,323,325)) == 1
            assert {322:(1,3),323:(5,1),325:(1,3)}[sid]==(child_num,missile_num)
        elif tier == '6x' and sid == 324:
            assert (child_num, missile_num)==(1,1)
        log = 'V4' if tier == '9x' else 'V5'
        detail = counts.get(log, {}).get(sid)
        log_parent = detail.get('PARENT_CAST', 0) if detail else ''
        log_child = detail.get('CHILD_CAST', 0) if detail else ''
        log_spawn = detail.get('MISSILE_SPAWN', 0) if detail else ''
        if detail:
            assert log_child == log_parent * child_num, (sid, 'child count mismatch', detail)
            assert log_spawn == log_child * missile_num, (sid, 'spawn count mismatch', detail)
        rows.append({
            'branch':branch,'tier':tier,'skill_id':sid,'name':catalog_by_id[sid]['name'],
            'child_skill_id':child_id,'missile_template_id':missile_id,
            'children_per_cast':child_num,'missiles_per_child':missile_num,
            'missiles_per_cast_declared':child_num*missile_num,
            'parent_form':int(parent.get('MisslesForm') or 0),
            'parent_wait_ticks_raw':int(parent.get('WaitTime') or 0),
            'runtime_log_reference':log,
            'observed_parent_casts':log_parent,'observed_child_casts':log_child,'observed_spawn_calls':log_spawn,
            'source_asset_status':(
                '9x VFX available; actor SPR V42' if tier=='9x' else
                'M140 and M141 share AnimFile2/4 source; candidate reuse; QA pending' if sid==324 else
                'M63 hit-stage original SPR not bundled in this V42 pack'),
            'visual_implemented':'MAIN playable 9x (preview)' if tier=='9x' else 'NOT YET: needs original-tier visual QA',
            'hp_formula_implemented':'NO',
        })
    # Never overwrite the bundled V4/V5 proof with an unverified metadata-only pass.
    p = output or (ROOT/'notes/V4212_TV12_SOURCE_AUDIT.csv' if v4 and v5
                   else ROOT/'notes/V4212_TV12_METADATA_ONLY.csv')
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open('w', encoding='utf-8-sig', newline='') as stream:
        writer=csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    print('PASS: %d source-derived TV skills, %s. 9 lower-tier skills are audit-only (not falsely playable).' % (len(rows), p))
    return rows

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--v4',type=Path)
    parser.add_argument('--v5',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    run(args.v4,args.v5,args.output)
