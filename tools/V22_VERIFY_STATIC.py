# -*- coding: utf-8 -*-
"""V22 read-only structural checker; not a substitute for running Godot 4."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
script = root/'scripts'
def file(name):
 p = script/name
 if not p.is_file(): raise AssertionError('Missing file: '+str(p))
 return p.read_text(encoding='utf-8')
main = file('Main.gd');combat=file('V22MainCombat.gd')
probe=file('V22HitProbe.gd');fx=file('CTC9XCombatEffect.gd')
clock=file('CTC9XTimeline.gd');dummy=file('Dummy.gd')
assert 'V22_COMBAT_CODE' in main and 'main_combat.call("begin_cast", skill, player)' in main
assert 'external_collision_authority' in fx and 'fx.set("external_collision_authority", true)' in main
assert 'func reset_training_hp()' in dummy and 'func toggle_hp_demo()' in combat
assert 'func _swept_overlaps_target' in probe and 'RectangleShape2D' in probe
assert 'func _on_body_entered' in probe and 'monitoring = true' in probe
assert 'cast_index + 1' in clock and 'parent_melee_form' in clock
assert 'func _open_v21_lab()' in main and (root/'scenes/v21_lab.tscn').is_file()
assert 'func _toggle_v22_hp_demo()' in main and 'func _toggle_v22_debug()' in main
assert 'test_player_level' in file('Player.gd')
reg = json.loads((root/'data/sects/registry.json').read_text(encoding='utf-8'))
assert reg.get('default_sect') == 'thien_vuong'
profiles = json.loads((root/'data/v21/six_skills_v21.json').read_text(encoding='utf-8'))['entries']
reference = {322:(326,1,138,3,5), 323:(327,5,139,1,3), 325:(408,1,141,3,4)}
for id,(child,n,missile,per_child,step) in reference.items():
 p=profiles[str(id)]
 assert (p['child_skill_id'],p['child_attempts'],p['missile_id'],p['missiles_per_child'],p['interval_calls']) == (child,n,missile,per_child,step),id
 expected=[step*(i+1) for i in range(n) for _ in range(per_child)]
 assert len(expected)==n*per_child
 print('%d: child %d x%d, missile %d x%d, schedule %s (counter steps)'%(id,child,n,missile,per_child,expected))
for f in ['blade_attack.png','spear_attack.png','hammer_attack.png']:
 assert (root/'assets/character'/f).is_file(),f
for f in ['jx90_potian_impact.png','jx90_truytinh_impact.png','jx90_truyphong_sweep.png']:
 assert (root/'assets/skill90'/f).is_file(),f
# Main/world starting point is unchanged from V6.7.6. VFX source assets untouched.
assert 'player.position = Vector2(590, 725)' in main
assert 'dummy.position = Vector2(1030, 790)' in main
print('V22 STATIC CHECK PASS: route data, scenes, signals, collision hooks and assets exist.')
print('NOT TESTED: GDScript parser and Godot runtime (requires Godot 4.4+).')
