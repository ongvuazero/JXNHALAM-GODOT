extends SceneTree
## Headless regression for source-traced frame sampling. Does NOT execute EXE.
## godot --headless --path Godot_Project --script res://tests/TestV34NativeClock.gd
const CLOCK = preload("res://scripts/V34JX322NativeClock.gd")

func _initialize() -> void:
    var at03: Array[int] = [0, 2, 5, 8, 11]
    var at02: Array[int] = [0, 3, 6, 9, 12]
    for t in range(5):
        if CLOCK.frame_in_direction(14, t) != at03[t]:
            push_error("V34 AT03 frame wrong at tick %d" % t)
            quit(1)
            return
        if CLOCK.frame_in_direction(16, t) != at02[t]:
            push_error("V34 AT02 frame wrong at tick %d" % t)
            quit(1)
            return
    for t in range(5):
        var elapsed: float = (float(t) + 0.25) / CLOCK.HZ
        if CLOCK.tick_at_elapsed(elapsed) != t:
            push_error("V34 nominal tick wrong at %f" % elapsed)
            quit(1)
            return
    if CLOCK.tick_at_elapsed(500.0) != 4 or CLOCK.tick_at_elapsed(-1.0) != 0:
        push_error("V34 tick clamp wrong")
        quit(1)
        return
    if absf(CLOCK.nominal_seconds() - 5.0 / 18.0) > 0.000001:
        push_error("V34 nominal seconds wrong")
        quit(1)
        return
    print("V34 PASS: AT03=[0,2,5,8,11] AT02=[0,3,6,9,12], nominal 18Hz/5 ticks")
    quit(0)
