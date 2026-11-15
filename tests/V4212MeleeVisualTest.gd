extends SceneTree
## V42.2.1 foot-anchored near-contact M141 VFX; Godot 4.6.x --headless.
const FX = preload("res://scripts/CTC9XCombatEffect.gd")
const GEO = preload("res://scripts/JXMissileGeometry.gd")
var failures: int = 0

func _initialize() -> void:
    var actor := CharacterBody2D.new()
    actor.position = Vector2(520.0, 710.0)
    root.add_child(actor)
    var renderer := Node2D.new()
    renderer.set_script(FX)
    root.add_child(renderer)
    renderer.set("caster", actor)
    renderer.set("registered_damage", true)
    renderer.set("timeline", {"events": [], "practice_damage_tick": 9999})
    renderer.set("clock_tick", -1)
    var center: int = GEO.aim_from_face(6)
    var sprites: Array[Sprite2D] = []
    var entries: Array[Dictionary] = []
    for j in range(3):
        var sprite := Sprite2D.new()
        renderer.add_child(sprite)
        sprites.append(sprite)
        entries.append({"sprite": sprite, "born": 0, "frames": 20,
            "interval": 1, "tile": 256, "direction": 0,
            "base_position": Vector2.ZERO, "attached_to_caster": true,
            "visual_dir64": GEO.missile_direction(325, center, j, 3)})
    renderer.set("particles", entries)
    renderer.call("_tick")
    var anchor: Vector2 = actor.global_position
    for j in range(3):
        var dir64: int = GEO.missile_direction(325, center, j, 3)
        _close(sprites[j].global_position, anchor + GEO.screen_vector(dir64) * 30.0,
            "initial short sweep %d" % j)
    for i in range(6):
        renderer.call("_tick")
    for j in range(3):
        var dir64: int = GEO.missile_direction(325, center, j, 3)
        _close(sprites[j].global_position, anchor + GEO.screen_vector(dir64) * 66.0,
            "bloomed short sweep %d" % j)
    # This test exercises foot anchoring and scale; the actual 1 visible
    # M141 sprite per cast policy is enforced in _emit_missile().
    actor.position += Vector2(155.0, -35.0)
    renderer.call("_tick")
    anchor = actor.global_position
    for j in range(3):
        var dir64: int = GEO.missile_direction(325, center, j, 3)
        _close(sprites[j].global_position, anchor + GEO.screen_vector(dir64) * 66.0,
            "caster-attached after movement %d" % j)
        _close(sprites[j].scale, Vector2.ONE, "raw SPR remains 1x")
    if failures == 0:
        print("PASS V42.2.1: foot anchor, short sweep positions at 1x scale")
    quit(0 if failures == 0 else 1)

func _close(actual: Vector2, expected: Vector2, label: String) -> void:
    if actual.distance_to(expected) > 0.01:
        failures += 1
        push_error("%s: %s != %s" % [label, actual, expected])
