# -*- coding: utf-8 -*-
"""V30 source assertions, no Godot runtime. Python 3 standard library only."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
preview=(ROOT/'scripts/V29AT03LivePreview.gd').read_text(encoding='utf-8')
assert 'use_at03_in_main = bool(at03_live_renderer.call("set_enabled", true))' in main
assert 'visual_decode_failed' in main and 'signal visual_decode_failed(reason: String)' in preview
assert 'V30 CAST 322 visual action = ' in main
assert 'fx.set("blade322_echo_enabled", blade322_echo_enabled and not use_at03_in_main)' in main
assert main.count('fx.set("blade322_echo_enabled", blade322_echo_enabled and not use_at03_in_main)')==2
assert 'KEY_Y: _toggle_at03_live_preview()' in main
assert 'func _v30_at03_runtime_fallback(reason: String)' in main
assert 'blade_pose_button.disabled = use_at03_in_main' in main
assert 'blade_shadow_button.disabled = use_at03_in_main' in main
assert 'AT02 FALLBACK' in main
assert 'var ready: bool' not in preview
assert 'var at03_sources_loaded: bool = false' in preview
assert 'EXPECTED_FRAMES: int = 14' in preview and 'EXPECTED_DIRS: int = 8' in preview
assert 'SOURCE_DIR: String = "res://data/spr/npcres/man/"' in preview
for n in ['V22MainCombat.gd','V22HitProbe.gd','Player.gd','CTC9XTimeline.gd']:
 assert (ROOT/'scripts'/n).is_file()
print('V30 STATIC OK: AT03 default-if-ready, fallback, Y QA, no false AT02 afterimages, runtime warning signal; Godot runtime NOT TESTED.')
