from pathlib import Path
import csv, json, sys
root=Path(__file__).resolve().parent.parent
report=root/'reports/v44_8/V44_8_SKILL_STYLE_AUDIT.csv'
evidence=root/'data/combat/v448_native_style_evidence.json'
with report.open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
info=json.loads(evidence.read_text(encoding='utf-8'))
assert len(rows)==24, 'Expected 24 selected combat skills'
row318=next(r for r in rows if r['skill_id']=='318')
row342=next(r for r in rows if r['skill_id']=='342')
assert row318['form_category']=='melee' and row318['melee_form']=='ManyAttack'
assert row342['form_category']=='missile' and row342['form']=='2'
print('V44.8 SOURCE AUDIT PASS')
print('Selected skills:',len(rows), '| 318: Melee_ManyAttack / form12 / single HELIX QA trace')
print('342: Spread 5 rollback missiles; contact & original-SPR HIT per projectile')
print('Source: settings/skills.txt, settings/missles.txt, Unity eMissleMoveKind.cs')
print('Runtime F5 test: NOT done here. Launch Godot and verify visuals manually.')
print('Report:',report)
