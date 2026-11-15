extends SceneTree
## Headless source-formula smoke test. Use Windows BAT in project root.
const F = preload("res://scripts/JXMissileFormationV449.gd")

func _initialize() -> void:
    var errors: int = 0
    var counts: Dictionary = {321: 2, 336: 5, 355: 2, 368: 3}
    for sid in counts.keys():
        var p: Dictionary = F.profile(sid)
        if p.is_empty() or int(p.get("count", 0)) != int(counts[sid]):
            push_error("V449 bad source profile %d" % sid)
            errors += 1
    var a: Dictionary = F.profile(321)
    if F.release_tick(0, a) != 5 or F.release_tick(1, a) != 14:
        push_error("V449 line timing failed")
        errors += 1
    var b: Dictionary = F.profile(336)
    var center: Vector2 = F.heading(Vector2.RIGHT, 2, b)
    if not center.is_equal_approx(Vector2.RIGHT):
        push_error("V449 spread center failed")
        errors += 1
    if not is_equal_approx(F.start_position(Vector2.ZERO, Vector2.RIGHT, 2, b).x, 13.2):
        push_error("V449 spread first offset failed")
        errors += 1
    if not F.profile(318).is_empty() or not F.profile(342).is_empty():
        push_error("V449 isolation failed")
        errors += 1
    if errors == 0:
        print("V44.9 SOURCE FORMATION SMOKE PASS (not an F5 visual test)")
    quit(0 if errors == 0 else 1)
