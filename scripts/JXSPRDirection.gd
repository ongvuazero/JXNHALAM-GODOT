extends RefCounted
## Unified 64-way JX direction -> SPR row. No class_name/global registration.
## Convention (screen coords): South=0, West=16, North=32, East=48.
## SPR row order for 8-dir: S SW W NW N NE E SE.
static func direction64_from_vector(heading: Vector2) -> int:
    if heading.length_squared() < 0.0001:
        return 0
    return posmod(roundi(heading.angle() * 64.0 / TAU) + 48, 64)

static func row_from_direction64(dir64: int, sprite_dirs: int) -> int:
    if sprite_dirs <= 1:
        return 0
    return posmod(roundi(float(posmod(dir64, 64)) * float(sprite_dirs) / 64.0), sprite_dirs)

static func row_from_vector(heading: Vector2, sprite_dirs: int) -> int:
    return row_from_direction64(direction64_from_vector(heading), sprite_dirs)

static func row_from_character_dir8(character_dir8: int, sprite_dirs: int) -> int:
    return row_from_direction64(posmod(character_dir8, 8) * 8, sprite_dirs)
