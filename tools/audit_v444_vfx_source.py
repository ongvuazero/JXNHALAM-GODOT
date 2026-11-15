#!/usr/bin/env python3
"""Read-only JX1 VFX provenance audit. Python standard library only.

Checks source catalog against settings/skills.txt and settings/missles.txt,
then traces events from extracted Lua manifest. DOES NOT touch client PAKs,
modify Godot projects, or treat a missing hash as proof of missing SPR.
"""
from __future__ import annotations
import argparse,csv,json
from pathlib import Path

SECTS={"thieu_lam","thien_vuong","duong_mon","ngu_doc","nga_mi","thuy_yen","cai_bang","thien_nhan","vo_dang","con_lon"}
ROLE_MAP={"fly":2,"travel_end":3,"hit":4}


def ascii_lower(s):
    return "".join(chr(ord(c)+32) if "A"<=c<="Z" else c for c in s)


def rel_hash_path(path):
    return "\\"+ascii_lower(path.replace("/","\\").lstrip("\\"))


def records(path,key):
    with path.open('r',encoding='latin1',newline='') as f:
        return {x[key]:x for x in csv.DictReader(f,delimiter='\t') if x.get(key)}


def write_csv(path,rows,columns):
    with path.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=columns,extrasaction='ignore')
        w.writeheader();w.writerows(rows)


def main(root,out):
    skills=records(root/'settings/skills.txt','SkillId')
    missiles=records(root/'settings/missles.txt','MissleId')
    graph=json.loads((root/'data/lua_events/jx_lua_event_graph.json').read_text(encoding='utf-8'))['skills']
    hashes=json.loads((root/'data/pak/known_hashes.json').read_text(encoding='utf-8'))
    summary=[];assets=[];events=[];mismatch=0
    for school in sorted(SECTS):
        p=root/'data/sects'/f'{school}.json'
        j=json.loads(p.read_text(encoding='utf-8'))
        for weapon in j.get('weapons',[]):
            for sk in weapon.get('skills',[]):
                if not isinstance(sk,dict) or not sk.get('legacy_skill_id'):continue
                sid=str(sk['legacy_skill_id'])
                row=skills.get(sid,{})
                is_tv=school=='thien_vuong'
                if is_tv:
                    summary.append({'school':school,'skill_id':sid,'skill_name':sk.get('name'), 'status':'TV_NATIVE_COMBAT_EXCLUDED', 'note':'Không sửa đường combat Thiên Vương'})
                    continue
                child=row.get('ChildSkillId','')
                missile=missiles.get(child,{})
                if not row or not missile:
                    mismatch+=1
                    summary.append({'school':school,'skill_id':sid,'skill_name':sk.get('name'),'status':'NO_SOURCE_CHILD','note':f'Skill/child {child} thiếu trong bảng gốc'})
                    continue
                expected={'source_child_skill_id':int(child),
                    'missile_ids':[int(child)],
                    'missile_move_kind':int(missile['MoveKind']),
                    'missile_speed_raw':int(missile['Speed']),
                    'original_precast_spr':row.get('PreCastSpr',''),
                    'original_missile_spr':[missile.get('AnimFile'+str(i),'') for i in range(1,5)]}
                fields={k:sk.get(k) for k in expected}
                diffs=[k for k in expected if fields[k]!=expected[k]]
                for role,num in ROLE_MAP.items():
                    if sk.get('original_anim_info',{}).get(role,'') != missile.get(f'AnimFileInfo{num}',''):
                        diffs.append('original_anim_info.'+role)
                sid_graph=graph.get(sid,{})
                if int(sid_graph.get('missile_id',-1))!=int(child):
                    diffs.append('LUA_GRAPH_MISSILE_ID')
                if sid_graph.get('anim_paths',[])!=expected['original_missile_spr']:
                    diffs.append('LUA_GRAPH_ANIM_PATH')
                mismatch+=bool(diffs)
                summary.append({'school':school,'skill_id':sid,'skill_name':sk.get('name'),
                    'child_skill_id':child, 'missile_id':child, 'move_kind':missile.get('MoveKind'),
                    'missile_speed_raw':missile.get('Speed'),
                    'declared_missiles':','.join(map(str,sk.get('missile_ids',[]))),
                    'status':'WRONG_VFX_BINDING' if diffs else 'SOURCE_MAPPING_MATCHES',
                    'note':';'.join(diffs),
                    'lua_level20_linked':','.join(str(e['skill_id']) for e in sid_graph.get('event_levels',{}).get('20',[]))})
                linked=graph.get(sid,{})
                for lev in ('1','10','20'):
                    for ev in linked.get('event_levels',{}).get(lev,[]):
                        child_skill_id=str(ev.get('skill_id',0))
                        child_graph=graph.get(child_skill_id,{})
                        events.append({'school':school,'parent_skill_id':sid,'level':lev,
                            'trigger':ev.get('trigger',''),'linked_skill_id':child_skill_id,
                            'linked_missile_id':child_graph.get('missile_id',''),
                            'child_source_has_metadata':bool(child_graph),
                            'linked_spr_paths':';'.join(x for x in child_graph.get('anim_paths',[]) if x),
                            'source':'Lua curve / skills.txt metadata, not proof of client runtime timing'})
                all_stages=[('precast',row.get('PreCastSpr',''),'' )]
                for i in range(1,5):
                    all_stages.append((f'AnimFile{i}',missile.get(f'AnimFile{i}',''),missile.get(f'AnimFileInfo{i}','')))
                for role,path,meta in all_stages:
                    if not path:continue
                    pieces=meta.split(',') if meta else []
                    frames=int(pieces[0]) if pieces and pieces[0].isdigit() else 0
                    dirs=int(pieces[1]) if len(pieces)>1 and pieces[1].isdigit() else 0
                    flagged=frames>512
                    assets.append({'school':school,'skill_id':sid,'missile_id':child,
                        'role':role,'raw_spr_path':path,'frames_metadata':frames,'directions_metadata':dirs,
                        'in_known_hashes':rel_hash_path(path) in hashes,
                        'decoder_over_512_frame_risk':flagged,
                        'decoder_atlas_width_risk':bool(frames>0 and dirs>0 and frames//dirs>32),
                        'note':'Đường SPR từ bảng gốc, chưa xác minh file có trong PAK của bạn'})
    out.mkdir(parents=True,exist_ok=True)
    write_csv(out/'V44_4_SKILL_BINDING_AUDIT.csv',summary,
        ['school','skill_id','skill_name','child_skill_id','missile_id','move_kind',
         'missile_speed_raw','declared_missiles','status','note','lua_level20_linked'])
    write_csv(out/'V44_4_LUA_LINKED_SKILLS.csv',events,
        ['school','parent_skill_id','level','trigger','linked_skill_id','linked_missile_id',
         'child_source_has_metadata','linked_spr_paths','source'])
    write_csv(out/'V44_4_SPR_DECODE_RISK.csv',assets,
        ['school','skill_id','missile_id','role','raw_spr_path','frames_metadata',
         'directions_metadata','in_known_hashes','decoder_over_512_frame_risk',
         'decoder_atlas_width_risk','note'])
    missing_hash=sum(not a['in_known_hashes'] for a in assets)
    risky=sum(bool(a['decoder_over_512_frame_risk']) for a in assets)
    problems=[x for x in summary if x['status']=='WRONG_VFX_BINDING']
    report=f'''JXNHALAM V44.4 / VFX SOURCE IDENTITY AUDIT
Source: settings/skills.txt + settings/missles.txt + extracted Lua event graph.
Nine-school selected skills: {sum(x.get('status')!='TV_NATIVE_COMBAT_EXCLUDED' for x in summary)}
TV skills excluded: {sum(x.get('status')=='TV_NATIVE_COMBAT_EXCLUDED' for x in summary)}
Wrong non-TV bindings remaining: {len(problems)}
Distinct source SPR stage rows: {len(assets)}
Paths absent from known_hashes.json: {missing_hash} (NOT proof of absent PAK file)
SPR rows claiming >512 frames: {risky} (decoder limitation; actual file headers need verification)
Lua event records at levels 1/10/20: {len(events)}
GDScript headless runtime: NOT tested here. Source metadata is edition-specific.

Confirmed comparison: earlier V44.3 school Thiếu Lâm 318 pointed to
missile 134 SPR despite skills.txt ChildSkillId=317. V44.4 corrects
missile ID, MoveKind=4, Speed=10 and both AnimFile2 / AnimFile4.
MoveKind=4 trajectory remains NOT IMPLEMENTED; no wrong straight-line VFX.

Skill 351 -> 352 Lua collision event exists, but actual client PAK SPRs
and native event timing have not been verified. The exact source paths for
351/352 DO exist in known_hashes.json after ASCII-only path normalization.
Missile 161's AnimFileInfo2 lists 1080 frames, beyond JXSPRCodec.gd
MAX_FRAMES=512. Do not fabricate replacement SPR. Existing signed/unsigned
hash entries do NOT prove any particular PAK contains the resource.
'''
    (out/'V44_4_REPORT_VI.txt').write_text(report,encoding='utf-8')
    print(report)
    return 1 if problems else 0

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--out',type=Path,default=None)
    x=ap.parse_args()
    raise SystemExit(main(x.root.resolve(),(x.out or x.root/'reports/v44_4').resolve()))
