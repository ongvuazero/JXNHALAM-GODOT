# JXNHALAM — M141 frame selector forensic probe (NOT a runtime visual patch)
# Binary evidence: game.exe 0x5FEC67..0x5FED5D; 64 directions; vtable +0x48.
# This module does NOT decide stage, world->screen, direction offset, or cast damage.
extends RefCounted
# Local script loaded via preload(); deliberately no class_name (Godot 4.6 global registry safety).

static func inspect(total_frames: int, spr_dirs: int, dir64: int, elapsed: int, duration: int, interval: int = 1, interval_mode: bool = false) -> Dictionary:
	if spr_dirs <= 0 or total_frames <= 0 or spr_dirs > 64:
		return {"ok": false, "error": "invalid frame/dir count"}
	if (64 % spr_dirs) != 0 or (total_frames % spr_dirs) != 0:
		return {"ok": false, "error": "direction/frame count not divisible"}
	if elapsed < 0 or duration <= 0 or interval <= 0:
		return {"ok": false, "error": "invalid duration/interval"}
	# The native code divides 64 and 32 by direction count and rounds to nearest sector.
	var sector: int = int(64 / spr_dirs)
	var half_sector: int = int(32 / spr_dirs)
	var row: int = posmod(int((posmod(dir64, 64) + half_sector) / sector), spr_dirs)
	var per_dir: int = int(total_frames / spr_dirs)
	if elapsed > duration:
		return {"ok": false, "error": "expired"}
	var frame_in_dir: int = 0
	if interval_mode:
		# Native branch when the interval-based mode flag is active and loop overrides are off.
		frame_in_dir = posmod(int(elapsed / interval), per_dir)
	else:
		# Native duration-mapped branch at game.exe 0x5FED09..0x5FED13.
		frame_in_dir = int((per_dir * elapsed) / duration)
	if frame_in_dir >= per_dir:
		return {"ok": false, "error": "animation finished"}
	return {"ok": true, "spr_row": row, "local_frame": frame_in_dir,
		"absolute_frame": row * per_dir + frame_in_dir, "frames_per_direction": per_dir}
