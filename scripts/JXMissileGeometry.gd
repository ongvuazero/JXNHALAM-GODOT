extends RefCounted
## V42.1 — Relative missile directions seen in JX1 V4 runtime logs.
## Confirmed: 322/M138 = 3 same-direction instances; 323/M139 = 5
## sequential instances; 325/M141 = 3 directions at increments of 8/64.
## UNKNOWN: native world-axis phase, initial missile XY, speed conversion,
## hit geometry, and exact Godot animation/VFX synchronization.
## Screen-space convention matches Player.face(): SOUTH=0, WEST=16,
## NORTH=32, EAST=48. This is a PREVIEW COORDINATE MAPPING ONLY.
const DIR_COUNT: int = 64
const DIR_STEP_RADIANS: float = TAU / 64.0
const SOUTH_OFFSET: int = 48
const MACE_STEP: int = 8
# V42 baseline muzzle anchor, shared by V22 contact probes and 325 fly VFX.
# The value is STILL a Godot preview estimate, not JX1 native spawn XY.
const PREVIEW_MUZZLE_Y: float = -47.0
const PREVIEW_SPEED_PX: float = 570.0
const PREVIEW_LIFETIME_SEC: float = 0.42

static func cast_origin(source: Node2D) -> Vector2:
    return source.global_position + Vector2(0.0, PREVIEW_MUZZLE_Y)

static func aim_from_face(dir8: int) -> int:
    # Match the actor's already-chosen native 8-direction pose. Do not
    # calculate a separate VFX heading by aiming at another NPC pivot.
    return posmod(dir8, 8) * 8

static func aim_from_points(origin: Vector2, target: Vector2, fallback_dir8: int = 6) -> int:
    var delta: Vector2 = target - origin
    if delta.length_squared() <= 0.001:
        return posmod(fallback_dir8 * 8, DIR_COUNT)
    return posmod(roundi(delta.angle() / DIR_STEP_RADIANS) + SOUTH_OFFSET, DIR_COUNT)

static func screen_vector(dir64: int) -> Vector2:
    var angle: float = float(posmod(dir64 - SOUTH_OFFSET, DIR_COUNT)) * DIR_STEP_RADIANS
    return Vector2(cos(angle), sin(angle))

static func missile_direction(skill_id: int, center_dir64: int, sub_index: int, sub_count: int) -> int:
    var center: int = posmod(center_dir64, DIR_COUNT)
    if skill_id == 325 and sub_count == 3:
        # V4: base, base+8, base+16. Center = base+8.
        return posmod(center + (sub_index - 1) * MACE_STEP, DIR_COUNT)
    # 322 three parallel directions. 323 one missile per child attempt.
    return center

static func atlas_row(dir64: int, directions: int) -> int:
    if directions <= 1:
        return 0
    # Atlas has e.g. 32 directional rows => one row per 2 dir64 units.
    return posmod(roundi(float(posmod(dir64, DIR_COUNT)) * float(directions) / float(DIR_COUNT)), directions)

static func locked_target_center(body: Node2D, fallback: Vector2) -> Vector2:
    if not is_instance_valid(body):
        return fallback
    for item in body.get_children():
        if item is CollisionShape2D:
            return (item as CollisionShape2D).global_position
    return body.global_position
