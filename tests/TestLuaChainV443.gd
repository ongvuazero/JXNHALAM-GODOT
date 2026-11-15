extends SceneTree
## Headless source-graph smoke test, run with Godot 4.6.x:
## godot --headless --path PROJECT_DIR --script res://tests/TestLuaChainV443.gd
const LUA_LAYER = preload("res://scripts/JXLuaEventVFX.gd")
const LINK_VISUAL = preload("res://scripts/JXLuaLinkedVisual.gd")

func _initialize() -> void:
    call_deferred("_test")

func _check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("V44.3 CHECK FAILED: " + message)
    return ok

func _test() -> void:
    var graph: Dictionary = LUA_LAYER.load_graph_cached()
    var ok: bool = true
    ok = _check(graph.size() >= 39, "Lua graph absent/incomplete") and ok
    var gb: Dictionary = graph.get("357", {})
    var levels: Dictionary = gb.get("event_levels", {})
    var at20: Array = levels.get("20", [])
    var at1: Array = levels.get("1", [])
    ok = _check(at1.is_empty(), "357 collision layer must be gated at low level") and ok
    ok = _check(at20.size() == 1 and int(at20[0].get("skill_id", 0)) == 389,
        "357 must activate 389 at level 20") and ok
    ok = _check(LUA_LAYER.source_child_count_at_level(359) == 3,
        "359 Lua missile count at level 20 is 3") and ok
    var node := Node2D.new()
    node.set_script(LUA_LAYER)
    get_root().add_child(node)
    var player := CharacterBody2D.new()
    var target := StaticBody2D.new()
    get_root().add_child(player)
    get_root().add_child(target)
    node.call("setup", 357, player, target, null, 20)
    node.call("emit_parent", "collide", Vector2(25, 40), Vector2.RIGHT, 0)
    var result: Dictionary = node.call("get_diagnostic")
    ok = _check(int(result.get("linked_events_allocated", 0)) == 1,
        "one Lua event must allocate one child attempt") and ok
    ok = _check(int(result.get("missing_visual_links", 0)) == 1,
        "without mounted PAK the child should report missing SPR") and ok
    node.call("emit_parent", "collide", Vector2(25, 40), Vector2.RIGHT, 0)
    result = node.call("get_diagnostic")
    ok = _check(int(result.get("linked_events_allocated", 0)) == 1,
        "duplicate same-ordinal collide must be ignored") and ok
    node.call("emit_parent", "collide", Vector2(25, 40), Vector2.RIGHT, 1)
    result = node.call("get_diagnostic")
    ok = _check(int(result.get("linked_events_allocated", 0)) == 2,
        "different actual missile contacts must be separately correlated") and ok
    node.call("_emit_for_skill", 357, "collide", Vector2.ZERO, Vector2.RIGHT,
        [357, 389, 999], 2)
    result = node.call("get_diagnostic")
    ok = _check(int(result.get("linked_events_allocated", 0)) == 2,
        "max depth must block great-grandchild") and ok
    ok = _check(int(result.get("skipped_depth", 0)) > 0,
        "over-depth event must be recorded") and ok
    player.queue_free()
    target.queue_free()
    node.queue_free()
    if ok:
        print("V44.3 LUA LAYERS: PASS (graph, level gate, duplicate, ordinal, depth, missing SPR)")
    quit(0 if ok else 1)
