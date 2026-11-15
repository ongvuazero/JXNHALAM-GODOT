#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
fx=(root/'scripts/CTC9XCombatEffect.gd').read_text()
assert 'var source_ticks: int = 10' in fx
assert 'duration: float = float(source_ticks) / MACE_CLOCK_HZ' in fx
assert 'var effect_tick: int = floori(mace_visual_elapsed * MACE_CLOCK_HZ)' in fx
assert 'CanvasItemMaterial.BLEND_MODE_ADD' in fx
assert 'MACE_VISUAL_TICKS' not in fx
im=Image.open(root/'assets/skill90/jx90_truyphong_sweep.png')
assert im.size==(2560,8192) # 10 frames x 32 directions
print('PASS source 10 frames x 32 directions; effect independent of 4-tick actor')
