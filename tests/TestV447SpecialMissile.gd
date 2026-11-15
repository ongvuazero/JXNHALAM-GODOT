extends SceneTree
const SPECIAL = preload("res://scripts/JXSpecialMissileMotion.gd")
const MOTION = preload("res://scripts/JXMissileMotion.gd")
func _initialize() -> void:
    var failures: Array[String] = []
    if MOTION.mode_for_kind(4) != "helix_preview": failures.append("4 must be helix")
    if MOTION.mode_for_kind(100) != "rollback_preview": failures.append("100 must be rollback")
    var timings: Array = []
    for i in range(5):
        timings.append(SPECIAL.release_tick(i, 5, 5, 2, 2))
    if timings != [6.0, 4.0, 2.0, 4.0, 6.0]: failures.append("native CENTEREXTENDLINE timing")
    var origin := Vector2(10.0, 20.0)
    var direction := Vector2.RIGHT
    var middle: Vector2 = SPECIAL.rollback_position(origin, direction, 16.0, 32.0, 360.0)
    var returned: Vector2 = SPECIAL.rollback_position(origin, direction, 32.0, 32.0, 360.0)
    if not is_equal_approx(middle.x, 330.0): failures.append("rollback midpoint")
    if returned.distance_to(origin) > 0.01: failures.append("rollback return")
    if SPECIAL.helix_position(origin, direction, 0.0, 10.0, 1, 0.55).distance_to(origin) > 0.01:
        failures.append("helix begins at origin")
    var h0: Vector2 = SPECIAL.spread_heading(direction, 0, 5, 1)
    var h4: Vector2 = SPECIAL.spread_heading(direction, 4, 5, 1)
    if absf(h0.angle() + h4.angle()) > 0.01: failures.append("spread symmetric angles")
    if failures.is_empty():
        print("V44.7 SPECIAL MOTION PASS: 7 source-informed assertions")
        quit(0)
    else:
        printerr("V44.7 SPECIAL MOTION FAIL: ", failures)
        quit(1)
