extends RefCounted
## V44.1 - isolated nine-sect flight geometry (QA, not native physics).
## 0/1/5 map to the original MoveKind names in the researched JX1 source.
## Follow(5) is handled by JXHomingSkillPreview; never route it here.
## All values supplied by caller are GODOT world pixels, not raw JX units.

static func mode_for_kind(move_kind: int) -> String:
    match move_kind:
        0: return "stationary"
        1: return "straight"
        5: return "follow_external"
        4: return "helix_preview"
        100: return "rollback_preview"
        _: return "unsupported"

static func heading(start: Vector2, destination: Vector2, fallback: Vector2 = Vector2.DOWN) -> Vector2:
    var delta: Vector2 = destination - start
    if delta.length_squared() < 0.0001:
        return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector2.DOWN
    return delta.normalized()

static func closest_point_on_segment(start: Vector2, finish: Vector2, point: Vector2) -> Vector2:
    var segment: Vector2 = finish - start
    var squared: float = segment.length_squared()
    if squared < 0.00001:
        return start
    var fraction: float = clampf((point - start).dot(segment) / squared, 0.0, 1.0)
    return start + segment * fraction

static func segment_hits_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> bool:
    if radius <= 0.0:
        return false
    var p: Vector2 = closest_point_on_segment(start, finish, center)
    return p.distance_squared_to(center) <= radius * radius

static func motion_point(mode: String, start: Vector2, destination: Vector2, ratio: float) -> Vector2:
    match mode:
        "straight": return start.lerp(destination, clampf(ratio, 0.0, 1.0))
        "stationary": return destination
        _: return start # Unsupported kinds must not borrow straight-line physics.

static func flight_duration_preview(distance_pixels: float, speed_pixels_per_second: float,
        fallback_seconds: float) -> float:
    if speed_pixels_per_second <= 0.001:
        return clampf(fallback_seconds, 0.06, 2.5)
    return clampf(maxf(distance_pixels, 0.0) / speed_pixels_per_second, 0.06, 2.5)
