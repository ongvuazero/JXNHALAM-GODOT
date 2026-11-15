extends SceneTree
## Run with Godot 4.x --headless --path PROJECT --script res://tests/V421MissileGeometryTest.gd
const G = preload("res://scripts/JXMissileGeometry.gd")
var fails: int = 0

func _initialize() -> void:
    _eq(G.aim_from_points(Vector2.ZERO, Vector2.RIGHT), 48, "east")
    _eq(G.aim_from_points(Vector2.ZERO, Vector2.DOWN), 0, "south")
    _eq(G.aim_from_points(Vector2.ZERO, Vector2.LEFT), 16, "west")
    _eq(G.aim_from_points(Vector2.ZERO, Vector2.UP), 32, "north")
    _eq(G.aim_from_points(Vector2.ZERO, Vector2.ZERO, 6), 48, "fallback")
    for i in range(3):
        _eq(G.missile_direction(325, 11, i, 3), 3 + i * 8, "325 relative V4")
        _eq(G.missile_direction(322, 11, i, 3), 11, "322 parallel")
    _eq(G.missile_direction(323, 16, 0, 1), 16, "323 repeated child")
    _eq(G.missile_direction(325, 1, 0, 3), 57, "64 wrap lower")
    _eq(G.missile_direction(325, 1, 2, 3), 9, "64 wrap upper")
    _eq(G.atlas_row(3, 32), 2, "atlas32 edge")
    _eq(G.atlas_row(11, 32) - G.atlas_row(3, 32), 4, "32 atlas +4")
    _eq(G.atlas_row(19, 32) - G.atlas_row(11, 32), 4, "32 atlas +4 second")
    _eq(G.atlas_row(11, 1), 0, "non directional atlas")
    _eq(G.atlas_row(64, 32), 0, "atlas wrap")
    var v: Vector2 = G.screen_vector(48)
    if v.distance_to(Vector2.RIGHT) > 0.00001:
        _bad("screen east vector")
    if fails == 0:
        print("V42.1 PASS — 20 checks; relative directions are V4 grounded. Runtime JX parity not claimed.")
    quit(0 if fails == 0 else 1)

func _eq(actual: int, expected: int, label: String) -> void:
    if actual != expected:
        _bad("%s: actual %d != %d" % [label, actual, expected])

func _bad(s: String) -> void:
    fails += 1
    push_error("V42.1 FAIL " + s)
