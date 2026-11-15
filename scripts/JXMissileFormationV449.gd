extends RefCounted
## JXNHALAM V44.9 - source-scoped Line/Spread missile formation geometry.
## Trust values only from settings/skills.txt + settings/missles.txt profiles.
## Unit-to-pixel factors are QA; native JX scale remains unverified.
const PROFILE_PATH: String = "res://data/combat/jx_formations_v449.json"
const HZ: float = 18.0
static var _cache: Dictionary = {}

static func profile(skill_id: int) -> Dictionary:
    if _cache.is_empty() and FileAccess.file_exists(PROFILE_PATH):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
        if parsed is Dictionary:
            _cache = parsed
    var value: Variant = _cache.get(str(skill_id), {})
    return value if value is Dictionary else {}

static func matches(skill: Dictionary, spec: Dictionary, actual_count: int) -> bool:
    if spec.is_empty():
        return false
    return (
        int(skill.get("legacy_skill_id", 0)) == int(spec.get("skill_id", -1))
        and int(skill.get("source_missles_form", -1)) == int(spec.get("form", -1))
        and int(skill.get("missile_move_kind", -1)) == 1
        and int(skill.get("source_child_skill_id", 0)) == int(spec.get("missile_id", -1))
        and actual_count == int(spec.get("count", -1))
        and actual_count > 1 and actual_count <= 8
    )

static func heading(base: Vector2, index: int, spec: Dictionary) -> Vector2:
    var direction: Vector2 = base.normalized() if base.length_squared() > 0.0001 else Vector2.RIGHT
    if int(spec.get("form", -1)) != 2:
        return direction
    var count: int = maxi(1, int(spec.get("count", 1)))
    # Unity CastSpread: nCurMSRadius = ChildSkillNum/2 - i, nCurSubDir = dir - Param1*radius.
    # Each JX directional step is 2*PI/64. The + sign converts game's angle orientation
    # to Godot world-space; calibrate direction in 8-way visual QA before declaring parity.
    var radius: int = int(count / 2) - index
    return direction.rotated(-TAU * float(int(spec.get("param1", 0)) * radius) / 64.0)

static func start_position(origin: Vector2, base: Vector2, index: int, spec: Dictionary) -> Vector2:
    var units: float = float(spec.get("qa_start_offset_px_per_raw_unit", 0.55))
    var amount_raw: int = 0
    if int(spec.get("form", -1)) == 1:
        amount_raw = int(spec.get("param1", 0)) * (index + 1)
        return origin + heading(base, index, spec) * float(amount_raw) * units
    if int(spec.get("form", -1)) == 2:
        amount_raw = int(spec.get("param2", 0))
        return origin + heading(base, index, spec) * float(amount_raw) * units
    return origin

static func release_tick(index: int, spec: Dictionary) -> int:
    var style: int = int(spec.get("generate_style", 0))
    var count: int = maxi(1, int(spec.get("count", 1)))
    var wait: int = maxi(0, int(spec.get("wait_ticks", 0)))
    var data: int = maxi(0, int(spec.get("generate_step_ticks", 0)))
    match style:
        0: return wait # SKILL_MGS_NULL
        1: return wait + data # SKILL_MGS_SAMETIME
        2: return wait + index * data # SKILL_MGS_ORDER
        5: return wait + absi(index - int(count / 2)) * data # CENTEREXTENDLINE
        _: return wait # random types intentionally not faked

static func duration_seconds(spec: Dictionary) -> float:
    var count: int = maxi(1, int(spec.get("count", 1)))
    var max_tick: int = 0
    for i in range(count):
        max_tick = maxi(max_tick, release_tick(i, spec))
    return float(max_tick + maxi(1, int(spec.get("life_ticks", 1)))) / HZ

static func point_at(start: Vector2, direction: Vector2, age_ticks: float, spec: Dictionary) -> Vector2:
    var speed: float = float(spec.get("speed_raw", 0)) * float(spec.get("qa_speed_px_per_raw_speed_unit", 10.0))
    return start + direction.normalized() * maxf(0.0, age_ticks) / HZ * maxf(0.0, speed)
