"""Generate a new, EMPTY sect config. Run from anywhere: python tools/new_sect_template.py duong_mon
Does not create copyrighted art, sprites or pretend a sect is playable.
After adding sprite atlases, update visual_manifest and registry.json.
"""
import json
import re
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2 or not re.fullmatch(r'[a-z][a-z0-9_]*', sys.argv[1]):
    raise SystemExit('Usage: python tools/new_sect_template.py <ascii_sect_id>')
name = sys.argv[1]
target = root/'data'/'sects'/f'{name}.json'
if target.exists():
    raise SystemExit(f'Refuse to overwrite existing file: {target}')
obj = {'id':name,'name':name,'status':'asset_pending','visual_manifest':f'res://assets/sects/{name}/manifest.json', 'weapons':[]}
target.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Created:',target)
