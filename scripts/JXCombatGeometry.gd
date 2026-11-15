extends RefCounted
## V44.0: geometry calibration for nine-sect QA only.
## JX AttackRadius is NOT inherently Godot pixels. 0.55 preserves the old
## 400 raw -> 220 px baseline; its physical accuracy remains UNVERIFIED.
## TV 322/323/325 intentionally bypasses this adapter.
const SETTINGS_PATH: String = "res://data/combat/jx_geometry_qa.json"

static func _config() -> Dictionary:
    if FileAccess.file_exists(SETTINGS_PATH):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
        if parsed is Dictionary:
            return parsed
    return {}

static func attack_range_pixels(skill: Dictionary) -> float:
    var old_value: float = maxf(48.0, float(skill.get("attack_radius", 96.0)))
    if str(skill.get("preview_sect", "")).is_empty():
        return old_value # TV original, never recalibrate
    var raw: float = float(skill.get("attack_radius_raw", 0.0))
    if raw <= 0.0:
        return old_value
    var conf: Dictionary = _config()
    var ratios: Dictionary = conf.get("attack_radius_px_per_jx_unit_by_skill", {})
    var id: String = str(skill.get("legacy_skill_id", 0))
    var ratio: float = float(ratios.get(id, conf.get("attack_radius_px_per_jx_unit", 0.55)))
    return clampf(raw * clampf(ratio, 0.05, 3.0), 48.0, 600.0)

static func visible_sprite_limit(skill: Dictionary) -> int:
    # Do NOT turn ChildSkillNum into simultaneous visual instances.
    var conf: Dictionary = _config()
    var explicit_limits: Dictionary = conf.get("visible_sprite_limit_by_skill", {})
    return clampi(int(explicit_limits.get(str(skill.get("legacy_skill_id", 0)), 1)), 1, 3)

static func sprite_scale(skill: Dictionary, stage: String) -> float:
    # SPR source frame offsets have ALREADY been baked into JXSPRCodec's atlas.
    # Never translate frame_offsets again. Explicit QA overrides only.
    var conf: Dictionary = _config()
    var overrides: Dictionary = conf.get("sprite_scale_by_skill", {})
    var entry: Dictionary = overrides.get(str(skill.get("legacy_skill_id", 0)), {})
    return clampf(float(entry.get(stage, conf.get("sprite_scale_default", 1.0))), 0.25, 2.5)

static func native_projectile_limit_is_verified(_skill: Dictionary) -> bool:
    return false

# V44.1: QA-only visual speed, no assumption that JX Missile Speed == pixels/s.
# No per-skill value means retain the last project's fallback cast duration.
static func flight_speed_pixels(skill: Dictionary) -> float:
    var conf: Dictionary = _config()
    var values: Dictionary = conf.get("flight_speed_px_s_by_skill", {})
    return clampf(float(values.get(str(skill.get("legacy_skill_id", 0)), 0.0)), 0.0, 3500.0)

static func hit_radius_pixels(skill: Dictionary) -> float:
    var conf: Dictionary = _config()
    var values: Dictionary = conf.get("hit_radius_px_by_skill", {})
    return clampf(float(values.get(str(skill.get("legacy_skill_id", 0)), skill.get("hit_radius", 60.0))), 1.0, 240.0)
