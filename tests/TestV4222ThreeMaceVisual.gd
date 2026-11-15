extends SceneTree
## Run from project root: godot --headless --path . --script res://tests/TestV4222ThreeMaceVisual.gd
const FX = preload("res://scripts/CTC9XCombatEffect.gd")
var errors: int = 0

func _initialize() -> void:
    var actor := CharacterBody2D.new()
    actor.global_position = Vector2(500.0, 350.0)
    root.add_child(actor)
    var effect := Node2D.new()
    effect.set_script(FX)
    root.add_child(effect)
    effect.set("caster", actor)
    effect.set("cast_aim_dir64", 48)
    effect.set("clock_tick", 0)
    effect.set("registered_damage", true)
    effect.set("skill", {"legacy_skill_id": 325,
        "original_missile_spr": [], "vfx": {"fly": "jx90_truyphong_sweep"}})
    effect.set("timeline", {"events": [], "practice_damage_tick": 9999,
        "duration_ticks": 99})
    for sub in range(3):
        effect.call("_emit_missile", {"missile_id": 141,
            "sub_index": sub, "sub_count": 3})
    var particles: Array = effect.get("particles")
    _assert_eq(particles.size(), 3, "three visible sprite particles")
    _assert_eq(int(effect.get("spawned_total")), 3, "three server-model allocations")
    _assert_eq(int(effect.get("rendered_total")), 3, "three rendered SPRs")
    if particles.size() == 3:
        var dirs := {}
        var rows := {}
        for p in particles:
            var sprite: Sprite2D = p.get("sprite")
            if not is_instance_valid(sprite):
                errors += 1
                continue
            dirs[int(p.get("visual_dir64"))] = true
            rows[int(p.get("direction"))] = true
            _assert_eq(sprite.scale, Vector2.ONE, "raw sprite scale remains 1x")
        _assert_eq(dirs.size(), 3, "three directional trajectories")
        _assert_eq(rows.size(), 3, "three different native atlas rows")
        for t in range(7):
            effect.call("_tick")
        _assert_eq(int(effect.get("rendered_total")), 3, "repeated tick does not duplicate emission")
    if errors == 0:
        print("PASS V42.2.2: 3 native M141 SPRs visible, independent 32-dir rows")
    quit(0 if errors == 0 else 1)

func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
    if actual != expected:
        errors += 1
        push_error("%s: actual=%s expected=%s" % [label, actual, expected])
