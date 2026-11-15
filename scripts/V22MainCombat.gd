extends Node2D
## V22: playable main-scene combat adapter.
## Verified from server: parent -> child -> missile allocation counts 3 / 5 / 3.
## NOT verified: wall-clock timing, hitbox, missile trajectory, final HP formula.
## VFX belongs to existing CTC9XCombatEffect; this module is collision only.
signal status_changed
# V37: visual notification only; native missile-138 hit AnimFile4 is on impact.
signal impact_contacted(skill_id: int, missile_id: int, world_position: Vector2)
# Visual contact metadata matches the CTC allocation within its own cast.
# This is a DEMO contact event, not native JX1 damage or hit timing.
signal impact_contacted_visual(skill_id: int, missile_id: int, cast_key: int,
    event_ordinal: int, world_position: Vector2)
# V38: cosmetic feedback for existing DEMO HP commit, not a native damage formula.
signal demo_hp_committed(skill_id: int, amount: int, target_world_position: Vector2)

const TIMELINE = preload("res://scripts/CTC9XTimeline.gd")
const ROUTES = preload("res://scripts/JX9XVerifiedRoute.gd")
const PROBE = preload("res://scripts/V22HitProbe.gd")
const TEST_DAMAGE: int = 10 # DEMO collision test, not JX1 final damage.
const TICK_SECONDS: float = 1.0 / 18.0 # PREVIEW cadence only.

var practice_dummy: StaticBody2D
var dummy_hurtbox: CollisionShape2D
var casts: Array[Dictionary] = []
var probes: Array[Area2D] = []
var hp_demo_enabled: bool = true
var cast_count: int = 0
var child_attempts: int = 0
var missile_allocations: int = 0
var contact_candidates: int = 0
var hp_commits: int = 0
var last_event: String = "SẴN SÀNG: 1/2/3 chọn vũ khí · Space tung chiêu"
var last_skill_id: int = 0

func setup(dummy_node: StaticBody2D) -> void:
    practice_dummy = dummy_node
    dummy_hurtbox = null
    for item in practice_dummy.get_children():
        if item is CollisionShape2D:
            dummy_hurtbox = item as CollisionShape2D
            break
    if dummy_hurtbox == null:
        push_error("V22: missing main scene Dummy CollisionShape2D")
    status_changed.emit()

func begin_cast(skill: Dictionary, source: CharacterBody2D, locked_target: StaticBody2D, cast_key: int = -1) -> void:
    var id: int = int(skill.get("legacy_skill_id", 0))
    var proof: Dictionary = ROUTES.find(id)
    if proof.is_empty() or not is_instance_valid(source):
        return
    var sequence: Dictionary = TIMELINE.build(skill, int(source.get("ctc_attack_frame_baseline")), int(source.get("ctc_attack_speed_percent")))
    var events: Array = sequence.get("events", [])
    if events.is_empty():
        return
    cast_count += 1
    last_skill_id = id
    casts.append({"id": id, "source": source, "target": locked_target, "cast_key": cast_key, "events": events,
        "cursor": 0, "tick": -1, "acc": 0.0,
        "last_tick": int(sequence.get("last_allocation_tick", 0)),
        "last_child": -1})
    last_event = "SKILL %d: ĐÃ TUNG · %d missile cấu hình" % [id, int(proof.get("total_allocations", 0))]
    status_changed.emit()

func _physics_process(delta: float) -> void:
    for i in range(casts.size() - 1, -1, -1):
        var run: Dictionary = casts[i]
        run["acc"] = float(run["acc"]) + delta
        var guard: int = 0
        while float(run["acc"]) >= TICK_SECONDS and guard < 16:
            run["acc"] = float(run["acc"]) - TICK_SECONDS
            guard += 1
            run["tick"] = int(run["tick"]) + 1
            var events: Array = run["events"]
            while int(run["cursor"]) < events.size() and int(events[int(run["cursor"])].get("tick", 0)) <= int(run["tick"]):
                var event: Dictionary = events[int(run["cursor"])]
                var parent_index: int = int(event.get("cast_index", -1))
                if parent_index != int(run["last_child"]):
                    child_attempts += 1
                    run["last_child"] = parent_index
                _spawn_probe(run["source"] as CharacterBody2D, int(run["id"]), event,
                    run.get("target") as StaticBody2D, int(run.get("cast_key", -1)))
                run["cursor"] = int(run["cursor"]) + 1
            if int(run["cursor"]) >= events.size() and int(run["tick"]) > int(run["last_tick"]) + 1:
                break
        if int(run["cursor"]) >= (run["events"] as Array).size() and int(run["tick"]) > int(run["last_tick"]) + 1:
            casts.remove_at(i)

func _spawn_probe(source: CharacterBody2D, skill_id: int, event: Dictionary,
        locked_target: StaticBody2D, cast_key: int) -> void:
    if not is_instance_valid(source):
        return
    missile_allocations += 1
    # A cast locks its target; a later click must not retarget in-flight probes.
    if not is_instance_valid(locked_target):
        return
    if locked_target.has_method("is_alive") and not bool(locked_target.call("is_alive")):
        return
    var locked_shape: CollisionShape2D
    for item in locked_target.get_children():
        if item is CollisionShape2D:
            locked_shape = item as CollisionShape2D
            break
    if locked_shape == null:
        return
    var origin: Vector2 = source.global_position + Vector2(0.0, -47.0)
    var target_center: Vector2 = locked_shape.global_position
    var advance: Vector2 = target_center - origin
    var forward: Vector2 = advance.normalized() if advance.length_squared() > 0.001 else Vector2.RIGHT
    var sideways: Vector2 = Vector2(-forward.y, forward.x)
    var count: int = maxi(1, int(event.get("sub_count", 1)))
    var index: int = int(event.get("sub_index", 0))
    # JX1 formation collision geometry has not been decoded. The spread below
    # is explicitly DEMO, not a claim that all 3 blade missiles strike 1 target.
    # V43 preview geometry: 323 is five *sequential* M139 allocations, not a 5-way fan.
    # 322 has three M138 melee allocations; do not borrow Chuy 325 sweep positions.
    # 325 spread geometry remains only a provisional collision model.
    var spread: float = 52.0 if skill_id == 325 and count > 1 else (18.0 if skill_id == 322 and count > 1 else 0.0)
    var origin_offset: Vector2 = sideways * (float(index) - float(count - 1) * 0.5) * spread
    var probe := Area2D.new()
    probe.set_script(PROBE)
    probe.set("missile_id", int(event.get("missile_id", 0)))
    probe.set("skill_id", skill_id)
    # Global missile_allocations is a HUD counter, NOT an event ID.
    # Use the CTC timeline's per-cast ordinal 0..2 for Chuy 325.
    probe.set("event_ordinal", int(event.get("ordinal", -1)))
    probe.set("cast_key", cast_key)
    probe.set("target_body", locked_target)
    probe.set("target_shape", locked_shape)
    probe.set("direction", forward)
    # M139: five sequential missiles aim at the same NPC, not at five fake lanes.
    # M138: the 3 allocations stay near the melee slash; collision is DEMO only.
    if skill_id == 322:
        probe.set("speed_px", 720.0)
        probe.set("lifetime", 0.28)
    elif skill_id == 323:
        probe.set("speed_px", 610.0)
        probe.set("lifetime", 0.72)
    probe.position = origin + origin_offset
    probe.connect("contacted", Callable(self, "_on_probe_contact"))
    probe.connect("vanished", Callable(self, "_on_probe_vanished"))
    add_child(probe)
    probes.append(probe)
    last_event = "SKILL %d: PHÁT MISSILE %d (HÌNH VFX GỐC TÁCH RIÊNG)" % [skill_id, int(event.get("missile_id", 0))]
    status_changed.emit()

func _on_probe_contact(probe: Area2D) -> void:
    probes.erase(probe)
    contact_candidates += 1
    last_event = "CONTACT: skill %d / missile %d / %s" % [int(probe.get("skill_id")), int(probe.get("missile_id")), str(probe.get("contact_method"))]
    var target: StaticBody2D = probe.get("target_body") as StaticBody2D
    if hp_demo_enabled and is_instance_valid(target) and target.has_method("take_damage"):
        if bool(target.call("take_damage", TEST_DAMAGE)):
            hp_commits += 1
            last_event += " · -10 HP DEMO"
            demo_hp_committed.emit(int(probe.get("skill_id")), TEST_DAMAGE, target.global_position)
    # NPC world origin, not demo hurtbox center. No additional collision/damage.
    var body: Node2D = target as Node2D
    var impact_world: Vector2 = body.global_position if is_instance_valid(body) else probe.global_position
    impact_contacted.emit(int(probe.get("skill_id")), int(probe.get("missile_id")), impact_world)
    impact_contacted_visual.emit(int(probe.get("skill_id")),
        int(probe.get("missile_id")), int(probe.get("cast_key")),
        int(probe.get("event_ordinal")), impact_world)
    status_changed.emit()

func _on_probe_vanished(probe: Area2D) -> void:
    probes.erase(probe)

func toggle_hp_demo() -> void:
    hp_demo_enabled = not hp_demo_enabled
    last_event = "HP DEMO: ON (-10 mỗi va chạm)" if hp_demo_enabled else "HP DEMO: OFF (chỉ đếm va chạm)"
    status_changed.emit()

func reset_dummy() -> void:
    for probe in probes:
        if is_instance_valid(probe):
            probe.queue_free()
    probes.clear()
    casts.clear()
    cast_count = 0
    child_attempts = 0
    missile_allocations = 0
    contact_candidates = 0
    hp_commits = 0
    if is_instance_valid(practice_dummy):
        practice_dummy.call("reset_training_hp")
    last_event = "RESET: HP người gỗ và bộ đếm về mặc định"
    status_changed.emit()

func summary() -> String:
    return "V22 | CAST %d · MISSILE %d · CONTACT %d · HP DEMO %d | %s" % [cast_count, missile_allocations, contact_candidates, hp_commits, "ON" if hp_demo_enabled else "OFF"]

func diagnostics() -> String:
    var text: String = "CHỈ DEMO VA CHẠM/HP — KHÔNG PHẢI SÁT THƯƠNG JX1\n"
    text += "Cast mẹ: %d | Skill con: %d | Missile: %d | Contact: %d | HP commits: %d\n" % [cast_count, child_attempts, missile_allocations, contact_candidates, hp_commits]
    text += "Cơ chế: Style1/Form12 · source allocations 3/5/3 · PREVIEW 18Hz\n"
    return text + last_event
