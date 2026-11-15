extends SceneTree
## Run with Godot 4.6.1 headless:
## godot --headless --path <project> --script res://tests/TestJXMissileMotion.gd
const MOTION = preload("res://scripts/JXMissileMotion.gd")
const DIRECTION = preload("res://scripts/JXSPRDirection.gd")
var passed: int = 0
var failed: int = 0

func _verify(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS V44.1 | ", label)
    else:
        failed += 1
        push_error("FAIL V44.1 | " + label)

func _initialize() -> void:
    _verify(MOTION.mode_for_kind(0) == "stationary", "MoveKind0 stays in place")
    _verify(MOTION.mode_for_kind(1) == "straight", "MoveKind1 is straight")
    _verify(MOTION.mode_for_kind(5) == "follow_external", "MoveKind5 is routed to homing")
    _verify(MOTION.mode_for_kind(100) == "unsupported", "MoveKind100 is not invented")
    _verify(MOTION.motion_point("stationary", Vector2.ZERO, Vector2(50, 50), 0.1) == Vector2(50, 50), "stationary target anchor")
    _verify(MOTION.motion_point("straight", Vector2.ZERO, Vector2(100, 0), 0.5).distance_to(Vector2(50, 0)) < 0.001, "straight halfway")
    _verify(MOTION.motion_point("unsupported", Vector2(8, 9), Vector2(100, 0), 1.0) == Vector2(8, 9), "unknown kind cannot fly straight")
    _verify(MOTION.segment_hits_circle(Vector2.ZERO, Vector2(100, 0), Vector2(50, 5), 6), "swept hit at 10 FPS")
    _verify(not MOTION.segment_hits_circle(Vector2.ZERO, Vector2(100, 0), Vector2(50, 20), 6), "moving NPC outside path must miss")
    _verify(not MOTION.segment_hits_circle(Vector2.ZERO, Vector2(100, 0), Vector2(50, 0), 0), "invalid radius not a hit")
    _verify(MOTION.flight_duration_preview(200, 400, 0.8) == 0.5, "calibrated speed/duration")
    _verify(MOTION.flight_duration_preview(200, 0, 0.8) == 0.8, "fallback duration with no native speed")
    _verify(DIRECTION.row_from_vector(Vector2.UP, 16) == 8, "north facing 16 directions")
    _verify(DIRECTION.row_from_vector(Vector2.RIGHT, 16) == 12, "east facing 16 directions")
    _verify(DIRECTION.row_from_vector(Vector2.DOWN, 16) == 0, "south facing 16 directions")
    print("V44.1 motion unit test: PASS=", passed, " FAIL=", failed)
    quit(1 if failed > 0 else 0)
