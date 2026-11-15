extends SceneTree
# Godot 4.6.x headless optional. Only checks geometric invariants and scales;
# the actual in-game visual still needs a user screenshot at 1.0x camera zoom.
const GEO = preload("res://scripts/JXMissileGeometry.gd")
var failed: int = 0

func _initialize() -> void:
    var actor := Node2D.new()
    root.add_child(actor)
    actor.position = Vector2(590.0, 725.0)
    _vector(GEO.cast_origin(actor), Vector2(590.0, 678.0), "V42 common muzzle")
    for facing in range(8):
        var center: int = GEO.aim_from_face(facing)
        _eq(center, facing * 8, "facing %d" % facing)
        var rows: Array[int] = []
        for i in range(3):
            var direction: int = GEO.missile_direction(325, center, i, 3)
            _eq(direction, posmod(center + (i - 1) * 8, 64), "dir%d/%d" % [facing, i])
            rows.append(GEO.atlas_row(direction, 32))
            _vector(GEO.cast_origin(actor), Vector2(590.0, 678.0), "shared origin")
            var travel: Vector2 = GEO.screen_vector(direction)
            if absf(travel.length() - 1.0) > 0.0001:
                _fail("unit vector")
        _eq(posmod(rows[1] - rows[0], 32), 4, "left row delta")
        _eq(posmod(rows[2] - rows[1], 32), 4, "right row delta")
    _eq(GEO.aim_from_face(6), 48, "east matches native pose")
    _eq(GEO.aim_from_face(0), 0, "south matches native pose")
    if absf(GEO.PREVIEW_SPEED_PX - 570.0) > 0.0001:
        _fail("speed demo baseline changed")
    if absf(GEO.PREVIEW_LIFETIME_SEC - 0.42) > 0.0001:
        _fail("lifetime demo baseline changed")
    print("V42.1.1 PASS: common origin, 8 headings, three 325 routes, 32-row atlas, preview speed") if failed == 0 else push_error("V42.1.1 FAILED %d checks" % failed)
    quit(0 if failed == 0 else 1)

func _eq(actual: int, expected: int, label: String) -> void:
    if actual != expected:
        _fail("%s: %d != %d" % [label, actual, expected])

func _vector(actual: Vector2, expected: Vector2, label: String) -> void:
    if actual.distance_to(expected) > 0.0001:
        _fail("%s: %s != %s" % [label, actual, expected])

func _fail(reason: String) -> void:
    failed += 1
    push_error(reason)
