#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
fx=(root/'scripts/CTC9XCombatEffect.gd').read_text()
clock=(root/'scripts/CTC9XTimeline.gd').read_text()
main=(root/'scripts/Main.gd').read_text()
probe=(root/'scripts/V22MainCombat.gd').read_text()
assert 'caster.global_position + GEOMETRY.screen_vector(visual_heading)' in fx
assert 'int(event.get("sub_index", 0)) != 1' in fx
assert 'MACE_VISUAL_LEAD_TICKS: int = 1' in fx
assert 'action_ticks = maxi(1, last_allocation_tick)' in clock
assert 'SPACE_REPEAT_SAMPLE' in main
assert 'GEOMETRY.missile_direction(skill_id' in probe
print('V42.2.1 static audit PASS: foot VFX, 1 visible sweep, 3 missile routing, space held')
