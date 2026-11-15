extends RefCounted
## V6.7: allocation-count model for server-observed DoManyAttack route.
## Direct evidence: V3.5 (285 allocs in 85 casts) and V3.6 (95 dispatches,
## all MisslesForm=12 -> DoManyAttack for 322/323/325).
## Relative animation timing BELOW is an INSPECTION APPROXIMATION from
## settings/skills.txt MslsGenerate / WaitTime metadata, not a runtime timing
## trace. 18 Hz is a UI PREVIEW clock, not a confirmed game/server clock.
const ROUTES = preload("res://scripts/JX9XVerifiedRoute.gd")
const TICK_HZ: float = 18.0
const TICK_PROVEN: bool = false

static func generate_time(style: int, wait_ticks: int, data_ticks: int,
        number: int, child_count: int) -> int:
    match style:
        0: return wait_ticks # null
        1: return wait_ticks + data_ticks # same-time
        2: return wait_ticks + number * data_ticks # order
        5: # center-extend line
            if child_count <= 1:
                return wait_ticks
            return wait_ticks + absi(number - int(child_count / 2)) * data_ticks
        _:
            # Modes 3/4 involve randomness; deterministic fallback is NOT
            # an engine implementation. No current 9x skills use these modes.
            return wait_ticks

static func preview_actor_frames(attack_frame: int, attack_speed_percent: int) -> int:
    # Unverified action/cooldown simulation, independent of missile allocations.
    var frames: int = int(float(maxi(1, attack_frame) * 100) / float(maxi(1, 100 + attack_speed_percent)))
    return maxi(1, frames)

static func build(skill: Dictionary, attack_frame: int = 18,
        attack_speed_percent: int = 0) -> Dictionary:
    var id: int = int(skill.get("legacy_skill_id", 0))
    var proof: Dictionary = ROUTES.find(id)
    if proof.is_empty():
        return {"events": [], "total_missiles": 0, "duration_ticks": 1,
            "combat_route": "UNVERIFIED", "timing_verified": false}
    var graph: Dictionary = skill.get("source_nested_cast", {})
    var root_casts: int = int(proof.get("child_casts", 0))
    var alloc_per_child: int = int(proof.get("missiles_per_child", 0))
    var parent_style: int = int(graph.get("parent_generate_style", 1))
    var parent_wait: int = int(graph.get("parent_wait_ticks", 0))
    var parent_step: int = int(graph.get("parent_generate_data_ticks", 0))
    var child_style: int = int(graph.get("secondary_generate_style", 0))
    var child_wait: int = int(graph.get("secondary_wait_ticks", 0))
    var child_step: int = int(graph.get("secondary_generate_data_ticks", 0))
    var formation: int = int(graph.get("secondary_missles_form", -1))
    var events: Array[Dictionary] = []
    var ordinal: int = 0
    for cast_index in range(root_casts):
        # V22: server OnManyAttack calls WaitForFrame for EACH child attempt.
        # Parent SkillStyle=1 / MisslesForm=12 with generate mode 1 therefore
        # has a CUMULATIVE schedule (322:5, 323:3/6/9/12/15, 325:4).
        # The old V6.7 preview incorrectly placed all spear child casts at
        # the same tick. Timing unit -> 18 Hz remains PREVIEW ONLY.
        var cast_tick: int = maxi(0, generate_time(parent_style, parent_wait,
            parent_step, cast_index, root_casts))
        if int(graph.get("parent_melee_form", -1)) == 12 and parent_style == 1:
            cast_tick = (cast_index + 1) * maxi(1, parent_wait + parent_step)
        for sub_index in range(alloc_per_child):
            # 322/323/325: V3.5 linked missile allocations to a child CastMissles
            # call; don't append another independent WaitTime from the child
            # skill to these timestamps. Missile launch physics still unverified.
            var missile_tick: int = 0
            events.append({"tick": cast_tick + missile_tick,
                "phase": "allocation", "cast_index": cast_index,
                "cast_count": root_casts, "sub_index": sub_index,
                "sub_count": alloc_per_child,
                "display_index": cast_index * alloc_per_child + sub_index,
                "display_count": root_casts * alloc_per_child,
                "formation": formation, "missile_id": int(proof["missile_id"]),
                "ordinal": ordinal})
            ordinal += 1
    events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a["tick"]) == int(b["tick"]):
            return int(a["ordinal"]) < int(b["ordinal"])
        return int(a["tick"]) < int(b["tick"])
    )
    var last_allocation_tick: int = 0
    for event in events:
        last_allocation_tick = maxi(last_allocation_tick, int(event["tick"]))
    var action_ticks: int = preview_actor_frames(attack_frame, attack_speed_percent)
    var allocated: int = root_casts * alloc_per_child
    return {"events": events, "total_missiles": allocated,
        "child_casts": root_casts, "missiles_per_child_cast": alloc_per_child,
        "verified_missile_id": int(proof["missile_id"]),
        "combat_route": ROUTES.ROUTE,
        "formation": formation, "last_allocation_tick": last_allocation_tick,
        "action_lock_ticks": action_ticks,
        "practice_damage_tick": last_allocation_tick,
        "duration_ticks": maxi(last_allocation_tick + 14, action_ticks + 6),
        "clock_hz": TICK_HZ, "timing_verified": false,
        "position_verified": false, "damage_verified": false,
        "metadata_graph_matches": (
            int(graph.get("parent_child_id", -1)) == int(proof["child_id"])
            and int(graph.get("parent_child_num", -1)) == root_casts
            and int(graph.get("secondary_child_num", -1)) == alloc_per_child
            and int(graph.get("missile_id", -1)) == int(proof["missile_id"])
            and int(graph.get("parent_melee_form", -1)) == 12),
        "note": "Counts and dispatch verified. Ticks, geometry, hit/HP unverified (Godot inspection preview)."}
