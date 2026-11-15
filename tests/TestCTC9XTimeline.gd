extends SceneTree
## Godot 4 headless test for VERIFIED COUNTS / unverified inspection ticks.
const BRIDGE = preload("res://scripts/BaselineDataBridge.gd")
const CLOCK = preload("res://scripts/CTC9XTimeline.gd")
const ROUTES = preload("res://scripts/JX9XVerifiedRoute.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var errors: Array[String] = []
    var bridge = BRIDGE.new()
    if not bridge.load_client_data():
        errors.append("Missing CTC baseline")
    var sect: Dictionary = bridge.inject_client_skills(JSON.parse_string(
        FileAccess.get_file_as_string("res://data/sects/thien_vuong.json")))
    var weapons: Array = sect.get("weapons", [])
    var expected_ids: Array[int] = [322, 323, 325]
    var expected_missiles: Array[int] = [138, 139, 141]
    var expected_child_casts: Array[int] = [1, 5, 1]
    var expected_alloc: Array[int] = [3, 5, 3]
    var expected_offset: Array[int] = [10, 6, 4] # metadata-derived preview only
    if weapons.size() != 3:
        errors.append("Expected 3 weapon entries")
    for i in range(mini(weapons.size(), 3)):
        var skill: Dictionary = weapons[i]["skills"][0]
        var model: Dictionary = CLOCK.build(skill, 18, 0)
        var id: int = int(skill.get("legacy_skill_id", 0))
        var events: Array = model.get("events", [])
        if id != expected_ids[i]:
            errors.append("Unexpected skill id for weapon %d" % i)
        if not bool(skill.get("ctc_9x_many_attack", false)):
            errors.append("ManyAttack flag missing %d" % id)
        if bool(skill.get("ctc_9x_run_attack", true)):
            errors.append("Obsolete RunAttack flag still set %d" % id)
        if str(model.get("combat_route", "")) != ROUTES.ROUTE:
            errors.append("Wrong dispatch for %d" % id)
        if int(model.get("verified_missile_id", 0)) != expected_missiles[i]:
            errors.append("Wrong missile for %d" % id)
        if int(model.get("child_casts", 0)) != expected_child_casts[i]:
            errors.append("Wrong child cast count %d" % id)
        if int(model.get("total_missiles", 0)) != expected_alloc[i] or events.size() != expected_alloc[i]:
            errors.append("Wrong allocation count %d" % id)
        if not bool(model.get("metadata_graph_matches", false)):
            errors.append("2024 trace counts / CTC graph mismatch %d" % id)
        if int(model.get("last_allocation_tick", -1)) != expected_offset[i]:
            errors.append("Unexpected preview offset for %d" % id)
        if bool(model.get("timing_verified", true)) or bool(model.get("damage_verified", true)):
            errors.append("Preview falsely claims precision for %d" % id)
        for j in range(events.size()):
            if int(events[j].get("missile_id", 0)) != expected_missiles[i]:
                errors.append("Event missile mismatch for %d" % id)
            if j > 0 and int(events[j].get("tick", 0)) < int(events[j - 1].get("tick", 0)):
                errors.append("Unordered events for %d" % id)
        print("V6.7 %d -> M%d: casts=%d allocations=%d preview_last_tick=%d (NOT runtime timing)" % [
            id, expected_missiles[i], expected_child_casts[i], events.size(),
            int(model.get("last_allocation_tick", -1))])
    if ROUTES.DISTINCT_BUFF_SKILL_ID != 1427:
        errors.append("Buff 1427 must stay separate")
    if errors.is_empty():
        print("V6.7 ROUTE/COUNTS PASS (preview timing UNVERIFIED)")
        quit(0)
    else:
        for msg in errors:
            push_error(msg)
        quit(1)
