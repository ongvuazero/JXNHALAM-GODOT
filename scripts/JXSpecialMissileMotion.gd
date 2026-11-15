extends RefCounted
## V44.7 — JX source-informed motion for the two previously unsupported routes.
## Unit scale and timing are Godot QA parameters; do NOT claim native pixel parity.
## Evidence: vltkunity-main, settings/skill/missile.fly.cs and skill.cast.spread.cs.
const HZ: float = 18.0
const DIRECTIONS: float = 64.0
const CONFIG_PATH: String = "res://data/combat/jx_special_motion_v447.json"
static var _cache: Dictionary = {}

static func spec(skill_id: int) -> Dictionary:
    if _cache.is_empty() and FileAccess.file_exists(CONFIG_PATH):
        var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
        if decoded is Dictionary:
            _cache = decoded
    var result: Variant = _cache.get(str(skill_id), {})
    return result if result is Dictionary else {}

static func spread_heading(base_heading: Vector2, index: int, count: int, raw_param1: int) -> Vector2:
    var original: Vector2 = base_heading.normalized() if base_heading.length_squared() > 0.0001 else Vector2.RIGHT
    var ncur_radius: int = int(count / 2) - index
    # CastSpread: nCurSubDir = nDir - Value1 * nCurMSRadius; 64 directions.
    return original.rotated(-TAU * float(raw_param1 * ncur_radius) / DIRECTIONS)

static func release_tick(index: int, count: int, style: int, wait_ticks: int, step_ticks: int) -> float:
    var delay: int = maxi(0, wait_ticks)
    match style:
        1: delay += maxi(0, step_ticks) # SAMETIME
        2: delay += index * maxi(0, step_ticks) # ORDER
        5: delay += abs(index - int(count / 2)) * maxi(0, step_ticks) # CENTEREXTENDLINE
    return float(delay)  # Other modes: no arbitrary randomness.

static func rollback_position(start: Vector2, direction: Vector2, age_ticks: float,
        life_ticks: float, speed_pixels_per_second: float) -> Vector2:
    var span: float = maxf(0.01, life_ticks)
    var t: float = clampf(age_ticks, 0.0, span)
    var half: float = span * 0.5
    var out_ticks: float = t if t <= half else span - t
    var unit_dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
    return start + unit_dir * maxf(0.0, speed_pixels_per_second) * out_ticks / HZ

static func helix_position(start: Vector2, heading: Vector2, age_ticks: float,
        speed_raw: float, raw_param1: int, qa_unit_scale: float) -> Vector2:
    # Native Helix uses g_DirCos/Sin differences, angle steps of one in 64,
    # and increasing radius (Speed + currentLife + 50). This continuous
    # expression approximates the corresponding discrete displacement.
    var ticks: float = maxf(0.0, age_ticks)
    var first_angle: float = heading.angle() if heading.length_squared() > 0.0001 else 0.0
    var turn_sign: float = 1.0 if raw_param1 != 0 else -1.0
    var angle: float = first_angle + turn_sign * TAU * ticks / DIRECTIONS
    var initial_radius: float = maxf(0.0, speed_raw) + 50.0
    var radius: float = initial_radius + ticks
    return start + qa_unit_scale * (Vector2.RIGHT.rotated(angle) * radius -
        Vector2.RIGHT.rotated(first_angle) * initial_radius)
