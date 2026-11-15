extends Node2D
## JXNHALAM M141 V10: timestamped renderer-trace replay and explicit end events.
## Optional trace: user://JX141_NATIVE_RENDER_TRACE.json (NEVER auto-generated).
## When no native trace is attached, V8 preview remains unchanged.
## NO damage, collision, mana, movement or input changes.
## Flight interpolation is visual-only; Form2 endpoints + map projection remain unverified.
## Verified: skill 325 -> child 408 -> missile 141 x3, trace dirs 3/11/19,
## state==1 main SPR rendering; native 320/32 fly and 6/1 hit atlases.
## NOT verified: exact screen XY projection, missile flight speed, contact timing,
## or the relationship of three allocations to three large yellow arcs in JX1.
## This is VISUAL ONLY: never modifies collision, actor, mana, HP, or Lua.
const FrameProbe = preload("res://scripts/JX141NativeFrameProbe.gd")
const NativeDirLUT = preload("res://scripts/JX141NativeDirectionLUT.gd") # V4 LUT
const NativeCoordinates = preload("res://scripts/JX141NativeCoordinates.gd") # EXE 0x570970
const FLY_TEXTURE = preload("res://assets/skill90/jx90_truyphong_sweep.png")
const HIT_TEXTURE = preload("res://assets/skill90/jx90_truyphong_impact.png")
const TRACE_FILE: String = "res://data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json"
const M141_TICK_SECONDS: float = 1.0 / 18.0 # inspection clock, not native-client clock
const FLY_TICKS: int = 4 # server V4 traced life 0,1,2,3
const IMPACT_SECONDS: float = 0.24 # DEMO V22 contact art, not a client measurement
const MAX_FLY: int = 36
const GROUP: String = "jx141_visual_v3"
const TRACE_REPLAY_PATH: String = "user://JX141_NATIVE_RENDER_TRACE.json"
const TRACE_REPLAY_SCHEMA: String = "jx141-client-render-v1"
# Only a resource-leak emergency guard if an external trace is truncated.
# NOT a native missile life or animation duration.
const NATIVE_STREAM_ORPHAN_GUARD_MS: int = 10000

var caster: Node2D
var locked_target: Vector2 = Vector2.ZERO
var face8: int = 0
var direction_center64: int = 0
# Verified from client trace: (delta_x_fixed, delta_y_fixed) = (x_factor, y_factor) * 30.
# For constant Z and camera, client renderer uses delta_screen = (delta_world_x, delta_world_y/2).
# The actor's Godot root is still an UNVERIFIED spawn anchor; no absolute camera parity is claimed.
const VERIFIED_M141_STEP_NATIVE: float = 30.0
const NATIVE_FACTOR_SCALE: float = 1024.0
var fly_states: Array[Dictionary] = []
var impact_states: Array[Dictionary] = []
var allocations: int = 0
var impact_events: int = 0
var trace_config: Dictionary = {}
var latest_label: String = "M141 / No cast"
var enabled: bool = true
var native_samples_applied: int = 0
var native_samples_rejected: int = 0
var native_samples_finished: int = 0
var native_snapshot_interpolations: int = 0
var replay_events: Array[Dictionary] = []
var replay_cursor: int = 0
var replay_elapsed_ms: float = 0.0
var replay_attached: bool = false
var replay_running: bool = false
var replay_preview_suppressed: int = 0
var replay_invalid_events: int = 0
var replay_consumed: int = 0
var replay_status: String = "NO TRACE: 18Hz PREVIEW"
# V14: one-to-one visual event linkage; never infer state from actor pose.
var bound_demo_cast_key: int = -1
var demo_allocation_keys: Dictionary = {}
var demo_contact_keys: Dictionary = {}
var native_state_samples_seen: int = 0

func _v14_event_key(cast_key: int, event_ordinal: int) -> String:
    return "%d:%d" % [cast_key, event_ordinal]

func bind_demo_cast(cast_key: int) -> void:
    # Main calls this immediately after CTC9XEffect.setup, which may already
    # have emitted tick-zero allocations. Bind those and future emissions.
    bound_demo_cast_key = cast_key
    for i in range(fly_states.size()):
        var item: Dictionary = fly_states[i]
        item["demo_cast_key"] = cast_key
        fly_states[i] = item
        demo_allocation_keys[_v14_event_key(cast_key, int(item.get("event_ordinal", -1)))] = true

func on_visual_contact_instance(cast_key: int, event_ordinal: int, contact_position: Vector2) -> bool:
    # One DEMO contact maps to one CTC schedule allocation. Neither native
    # collision nor damage is inferred from this preview signal.
    if replay_attached or cast_key < 0 or event_ordinal < 0:
        return false
    var event_key: String = _v14_event_key(cast_key, event_ordinal)
    if not demo_allocation_keys.has(event_key):
        return false
    if demo_contact_keys.has(event_key):
        return true # same collision callback was already handled
    demo_contact_keys[event_key] = true
    for i in range(fly_states.size()):
        var item: Dictionary = fly_states[i]
        if int(item.get("demo_cast_key", -1)) != cast_key or int(item.get("event_ordinal", -1)) != event_ordinal:
            continue
        item["state"] = 2 # DEMO contact stop, not a native state observation
        fly_states[i] = item
        _update_fly(item)
        break
    # Asset A / AnimFile4 is selected for M141 with MultiShow=0.
    # Duration, contact time and target position below remain DEMO.
    on_visual_contact(contact_position)
    return true

func _ready() -> void:
    add_to_group(GROUP)
    # Do not change imported PNG/SPR alpha or scale; additive M141 overlays
    # in the V42.2.4 prototype were never verified in the native client.
    if FileAccess.file_exists(TRACE_FILE):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRACE_FILE))
        if parsed is Dictionary:
            trace_config = parsed

func configure(actor: Node2D, destination: Vector2, facing8: int) -> void:
    caster = actor
    locked_target = destination
    face8 = posmod(facing8, 8)
    if is_instance_valid(caster):
        var aim: Vector2 = locked_target - caster.global_position
        if aim.length_squared() > 0.01:
            # The Godot demo target is already expressed in 2D *screen* coordinates.
            # JX1 renderer compresses world Y by 1/2 for equal-height positions.
            # Undo that compression before choosing the 64-dir heading.
            # The target's exact native-world position/caster-Z is still unknown.
            var native_flat_aim: Vector2 = Vector2(aim.x, aim.y * 2.0)
            var native_aim: Dictionary = NativeDirLUT.normalize_delta_1024(native_flat_aim)
            if bool(native_aim.get("ok", false)):
                direction_center64 = NativeDirLUT.direction_from_factors(
                    int(native_aim["x_factor"]), int(native_aim["y_factor"]))
        else:
            direction_center64 = posmod(face8 * 8, 64)
    _try_load_native_trace_replay()

func _try_load_native_trace_replay() -> void:
    # The game runs unchanged with no file. A fixture is not proof of JX1
    # provenance: collect it from the original client before claiming parity.
    if not FileAccess.file_exists(TRACE_REPLAY_PATH):
        return
    var f: FileAccess = FileAccess.open(TRACE_REPLAY_PATH, FileAccess.READ)
    if f == null:
        replay_status = "TRACE READ FAILED"
        return
    var payload: Variant = JSON.parse_string(f.get_as_text())
    if not (payload is Dictionary):
        replay_status = "INVALID TRACE JSON"
        push_warning("M141 V10 trace file is not a JSON object")
        return
    var result: Dictionary = attach_native_trace(payload)
    if not bool(result.get("ok", false)):
        push_warning("M141 V10 trace rejected: %s" % str(result.get("reason", "unknown")))

func attach_native_trace(payload: Dictionary) -> Dictionary:
    # Accepted JSON schema is intentionally strict. Never fabricate values.
    # {"schema":"jx141-client-render-v1","events":[
    #   {"t_ms":0,"kind":"allocate","event":{...}},
    #   {"t_ms":55,"kind":"sample","sample":{...}},
    #   {"t_ms":180,"kind":"end","native_instance_id":123}]}
    if str(payload.get("schema", "")) != TRACE_REPLAY_SCHEMA:
        replay_status = "TRACE SCHEMA MISMATCH"
        return {"ok": false, "reason": "schema mismatch"}
    if not (payload.get("events", null) is Array):
        replay_status = "TRACE EVENTS MISSING"
        return {"ok": false, "reason": "events not an Array"}
    var events: Array = payload["events"]
    if events.is_empty() or events.size() > 25000:
        replay_status = "TRACE EVENT COUNT INVALID"
        return {"ok": false, "reason": "empty or oversized events"}
    var pending: Array[Dictionary] = []
    var last_time: int = -1
    var allocation_ids: Dictionary = {}
    for raw in events:
        if not (raw is Dictionary):
            return {"ok": false, "reason": "event not a Dictionary"}
        var e: Dictionary = raw
        if not e.has("t_ms"):
            return {"ok": false, "reason": "missing t_ms"}
        var t_ms: int = int(e["t_ms"])
        if t_ms < 0 or t_ms < last_time:
            return {"ok": false, "reason": "unsorted or negative trace timestamp"}
        last_time = t_ms
        var kind: String = str(e.get("kind", ""))
        if kind == "allocate":
            if not (e.get("event", null) is Dictionary):
                return {"ok": false, "reason": "allocation missing event"}
            var alloc: Dictionary = e["event"]
            if int(alloc.get("missile_id", -1)) != 141 or not alloc.has("native_instance_id"):
                return {"ok": false, "reason": "expected M141 allocation with native_instance_id"}
            var alloc_id: int = int(alloc["native_instance_id"])
            if allocation_ids.has(alloc_id):
                return {"ok": false, "reason": "duplicate allocation id"}
            allocation_ids[alloc_id] = true
        elif kind == "sample":
            if not (e.get("sample", null) is Dictionary):
                return {"ok": false, "reason": "sample missing payload"}
            var sample: Dictionary = e["sample"]
            if not sample.has("native_instance_id"):
                return {"ok": false, "reason": "sample missing native_instance_id"}
            if not allocation_ids.has(int(sample["native_instance_id"])):
                return {"ok": false, "reason": "sample before allocation"}
        elif kind == "end":
            if not e.has("native_instance_id") or not allocation_ids.has(int(e["native_instance_id"])):
                return {"ok": false, "reason": "end without allocation"}
        else:
            return {"ok": false, "reason": "unsupported event kind: " + kind}
        pending.append(e.duplicate(true))
    replay_events = pending
    replay_cursor = 0
    replay_elapsed_ms = 0.0
    replay_attached = true
    replay_running = true
    replay_status = "TRACE INPUT CONNECTED - CLIENT PROVENANCE UNVERIFIED"
    return {"ok": true, "events": replay_events.size()}

func _consume_native_replay(delta: float) -> void:
    if not replay_running:
        return
    replay_elapsed_ms += maxf(0.0, delta) * 1000.0
    # Same timestamp is valid for 3 simultaneous allocations and snapshots.
    while replay_cursor < replay_events.size():
        var e: Dictionary = replay_events[replay_cursor]
        if float(int(e["t_ms"])) > replay_elapsed_ms:
            break
        var kind: String = str(e["kind"])
        if kind == "allocate":
            var alloc: Dictionary = (e["event"] as Dictionary).duplicate(true)
            alloc["native_replay_allocation"] = true
            emit_allocation(alloc)
        elif kind == "sample":
            var sample: Dictionary = (e["sample"] as Dictionary).duplicate(true)
            if not sample.has("native_sample_time_ms"):
                sample["native_sample_time_ms"] = int(e["t_ms"])
            if not apply_native_sample(sample):
                replay_invalid_events += 1
        elif kind == "end":
            var end_event: Dictionary = {"native_instance_id": int(e["native_instance_id"]),
                "native_sample_time_ms": int(e["t_ms"]), "native_done": true}
            if not apply_native_sample(end_event):
                replay_invalid_events += 1
        replay_cursor += 1
        replay_consumed += 1
    if replay_cursor >= replay_events.size():
        replay_running = false
        replay_status = "TRACE REPLAY COMPLETE - WAITING EXPLICIT MISSILE END"

static func trace_or_logic_dir64(mid_dir64: int, sub_index: int, sub_count: int, explicit_dir64: int = -1) -> int:
    if explicit_dir64 >= 0:
        return posmod(explicit_dir64, 64)
    # All 46 captured Chuy 325 casts: center-8, center, center+8 (64-dir).
    # Only x3 is supported here; no attempt to generalize native formation 2.
    if sub_count != 3:
        return posmod(mid_dir64, 64)
    return posmod(mid_dir64 + (sub_index - 1) * 8, 64)

static func traced_unit_vector(dir64: int) -> Vector2:
    # Static JX1 PE table for angle-only fallback, not exact for every native allocation.
    return NativeDirLUT.resolve(dir64, {}).get("unit", Vector2.ZERO)

func emit_allocation(event: Dictionary) -> void:
    # V18: native capture replay exists only as a read-only QA overlay.
    # Suppress extra DEMO render sprites while observing the original capture,
    # but do NOT modify skill cast, damage, collision, cooldown or animation.
    if get_tree().get_nodes_in_group("jx141_native_evidence_mode").size() > 0:
        return
    # Disable duplicate preview allocation if an explicit trace is replaying.
    if replay_attached and not bool(event.get("native_replay_allocation", false)):
        replay_preview_suppressed += 1
        return
    if not enabled or not is_instance_valid(caster):
        return
    if int(event.get("missile_id", 0)) != 141:
        return
    if fly_states.size() >= MAX_FLY:
        return
    var sub_count: int = int(event.get("sub_count", 1))
    var sub_index: int = int(event.get("sub_index", 0))
    var dir64: int = trace_or_logic_dir64(direction_center64, sub_index,
        sub_count, int(event.get("native_dir64", -1)))
    var native_info: Dictionary = {}
    if (event.has("native_dir64") and not event.has("native_x_factor")
            and not event.has("x_factor")
            and not (event.has("native_cast_center_x_factor")
                     and event.has("native_cast_center_y_factor"))):
        # An explicit client direction must not be silently rotated once more
        # by preview Form2 geometry when per-instance factors are unavailable.
        native_info = NativeDirLUT.resolve(dir64, event)
    else:
        # The preview geometry helper expects native flat-world deltas, not screen deltas.
        # Explicit x_factor/y_factor provided by runtime remain authoritative inside it.
        var demo_screen_delta: Vector2 = locked_target - caster.global_position
        var preview_native_target: Vector2 = caster.global_position + Vector2(
            demo_screen_delta.x, demo_screen_delta.y * 2.0)
        native_info = NativeDirLUT.resolve_from_geometry(dir64, event,
            caster.global_position, preview_native_target)
    if not bool(native_info.get("ok", false)):
        push_warning("M141 invalid native factor: %s" % str(native_info))
        return
    # Derive exact 64-dir sector from supplied native factor pair when no
    # explicit runtime dir64 is provided. Do NOT derive this from demo aim.
    if int(event.get("native_dir64", -1)) < 0 and str(native_info["source"]) != "client_exe_64dir_lut":
        dir64 = int(native_info["factor_dir64"])
    var sprite := Sprite2D.new()
    sprite.name = "M141_FLY_%d_dir%d" % [allocations + 1, dir64]
    sprite.texture = FLY_TEXTURE
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 0, 256, 256)
    sprite.centered = true
    sprite.scale = Vector2.ONE
    sprite.z_index = 0
    add_child(sprite)
    var position_info: Dictionary = NativeCoordinates.resolve_projected_world(event)
    # The skill event stream currently has NO region or camera offsets. Do not
    # pretend a missile native map/grid coordinate is a Godot screen coordinate.
    var has_native_position: bool = bool(position_info.get("ok", false))
    var origin: Vector2 = caster.global_position
    if has_native_position:
        origin = position_info["position"] as Vector2
    var runtime_id: int = int(event.get("native_instance_id", allocations + 1))
    var lifetime_ticks: int = maxi(1, int(event.get("native_total_lifetime", FLY_TICKS)))
    var item: Dictionary = {"sprite": sprite, "origin": origin,
        "native_instance_id": runtime_id, "life_ticks": lifetime_ticks,
        "position_source": str(position_info.get("source", "caster_foot_preview")) if has_native_position else "caster_foot_preview",
        "native_projected": has_native_position, "native_position": origin,
        "native_sample": replay_attached, "native_visual_slot": 2,
        "native_done": false, "native_last_arrival_ms": Time.get_ticks_msec() if replay_attached else -1,
        "native_last_trace_time_ms": -1,
        "native_lerp_start_ms": -1, "native_lerp_duration_ms": 0,
        "native_lerp_from": origin, "native_lerp_to": origin,
        "native_frame": -1, "native_elapsed": -1,
        "native_duration": -1, "native_interval": 1, "native_interval_mode": false,
        "dir64": dir64, "sub_index": sub_index,
        "age_seconds": 0.0, "state": 1,
        "unit": native_info["unit"],
        "x_factor": int(native_info["x_factor"]),
        "y_factor": int(native_info["y_factor"]),
        "vector_source": str(native_info["source"])}
    # CTC9XTimeline ordinal is shared by VFX and V22 collision adapter.
    item["event_ordinal"] = int(event.get("ordinal", allocations))
    item["demo_cast_key"] = bound_demo_cast_key
    if bound_demo_cast_key >= 0:
        demo_allocation_keys[_v14_event_key(bound_demo_cast_key, int(item["event_ordinal"]))] = true
    fly_states.append(item)
    allocations += 1
    latest_label = "M141 FLY: %d instances, dir64=%d" % [fly_states.size(), dir64]
    _update_fly(item)

func clear_demo_preview_visuals() -> void:
    # V18 activates captured FLY: remove previous DEMO sprites from the arena.
    # Existing gameplay and all previous visual sessions remain untouched.
    for item in fly_states:
        var sprite: Sprite2D = item.get("sprite", null) as Sprite2D
        if is_instance_valid(sprite):
            sprite.queue_free()
    fly_states.clear()
    for item in impact_states:
        var sprite: Sprite2D = item.get("sprite", null) as Sprite2D
        if is_instance_valid(sprite):
            sprite.queue_free()
    impact_states.clear()
    demo_allocation_keys.clear()
    demo_contact_keys.clear()

func _process(delta: float) -> void:
    _consume_native_replay(delta)
    for i in range(fly_states.size() - 1, -1, -1):
        var item: Dictionary = fly_states[i]
        item["age_seconds"] = float(item["age_seconds"]) + maxf(0.0, delta)
        var max_ticks: int = int(item.get("life_ticks", FLY_TICKS))
        var expired: bool = false
        if bool(item.get("native_sample", false)):
            # Native end events determine the actual observed termination.
            # 10-second orphan guard protects resources from a truncated trace;
            # it must NEVER be described as a JX1 timing formula.
            var last_arrival_ms: int = int(item.get("native_last_arrival_ms", -1))
            expired = bool(item.get("native_done", false))
            if last_arrival_ms >= 0 and Time.get_ticks_msec() - last_arrival_ms > NATIVE_STREAM_ORPHAN_GUARD_MS:
                expired = true
                push_warning("M141 V10: orphan native trace expired by safety guard (NOT client lifetime)")
        else:
            expired = int(floori(float(item["age_seconds"]) / M141_TICK_SECONDS)) >= max_ticks
        if expired:
            var old_sprite: Sprite2D = item["sprite"] as Sprite2D
            if is_instance_valid(old_sprite):
                old_sprite.queue_free()
            fly_states.remove_at(i)
            continue
        fly_states[i] = item
        _update_fly(item)
    for i in range(impact_states.size() - 1, -1, -1):
        var impact: Dictionary = impact_states[i]
        impact["age_seconds"] = float(impact["age_seconds"]) + maxf(0.0, delta)
        if float(impact["age_seconds"]) >= IMPACT_SECONDS:
            var old_hit: Sprite2D = impact["sprite"] as Sprite2D
            if is_instance_valid(old_hit):
                old_hit.queue_free()
            impact_states.remove_at(i)
            continue
        impact_states[i] = impact
        _update_hit(impact)

func _update_fly(item: Dictionary) -> void:
    var sprite: Sprite2D = item["sprite"] as Sprite2D
    if not is_instance_valid(sprite):
        return
    # Original client main FLY render only runs in missile state 1.
    # An explicit independently observed slot-4 sample may still render HIT;
    # never translate state=2 into HIT automatically.
    if int(item.get("state", 1)) != 1 and int(item.get("native_visual_slot", 2)) == 2:
        sprite.visible = false
        return
    var slot: int = int(item.get("native_visual_slot", 2))
    if slot != 2 and slot != 4:
        sprite.visible = false
        return
    var total_frames: int = 320 if slot == 2 else 6
    var dirs: int = 32 if slot == 2 else 1
    var row: int = 0
    var frame: int = -1
    if int(item.get("native_frame", -1)) >= 0:
        # Authoritative renderer frame (not a synthetic age-to-frame guess).
        var absolute_frame: int = int(item["native_frame"])
        if absolute_frame >= total_frames:
            sprite.visible = false
            return
        row = int(absolute_frame / int(total_frames / dirs))
        frame = posmod(absolute_frame, int(total_frames / dirs))
    else:
        if bool(item.get("native_sample", false)) and (int(item.get("native_elapsed", -1)) < 0 or int(item.get("native_duration", -1)) <= 0):
            # Real position does not prove a real frame: wait for renderer frame
            # or elapsed/duration. No disguised 18Hz preview in native mode.
            sprite.visible = false
            return
        var age_tick: int = clampi(floori(float(item["age_seconds"]) / M141_TICK_SECONDS), 0, int(item.get("life_ticks", FLY_TICKS)) - 1)
        var elapsed: int = int(item.get("native_elapsed", -1))
        var duration: int = int(item.get("native_duration", -1))
        var native_timing: bool = bool(item.get("native_sample", false)) and elapsed >= 0 and duration > 0
        if not native_timing:
            elapsed = age_tick
            duration = int(item.get("life_ticks", FLY_TICKS))
        var source: Dictionary = FrameProbe.inspect(total_frames, dirs, int(item["dir64"]),
            elapsed, duration, maxi(1, int(item.get("native_interval", 1))),
            bool(item.get("native_interval_mode", false)) if native_timing else false)
        if not bool(source.get("ok", false)):
            sprite.visible = false
            return
        row = int(source["spr_row"])
        frame = int(source["local_frame"])
    sprite.texture = FLY_TEXTURE if slot == 2 else HIT_TEXTURE
    sprite.visible = true
    sprite.region_rect = Rect2(float(frame * 256), float(row * 256), 256.0, 256.0)
    # IMPORTANT: not weapon-anchored; 3 separate in-flight locations.
    # Observed FIXED-POINT world movement is 30 native units per tick.
    # The original client screen projection reduces Y by half for constant-Z motion.
    # Only the relative per-tick DELTA is verified: the spawn origin and demo tick
    # interpolation below still have to be reconciled with the native client.
    if bool(item.get("native_projected", false)):
        # Two *observed* projected positions; never extrapolate after the
        # latest sample. The one-sample case intentionally holds position.
        var start_ms: int = int(item.get("native_lerp_start_ms", -1))
        var duration_ms: int = int(item.get("native_lerp_duration_ms", 0))
        if start_ms >= 0 and duration_ms > 0:
            var alpha: float = clampf(float(Time.get_ticks_msec() - start_ms) / float(duration_ms), 0.0, 1.0)
            sprite.global_position = (item["native_lerp_from"] as Vector2).lerp(
                item["native_lerp_to"] as Vector2, alpha)
        else:
            sprite.global_position = item["native_position"] as Vector2
        return
    var motion_ticks: float = clampf(float(item["age_seconds"]) / M141_TICK_SECONDS,
        0.0, float(int(item.get("life_ticks", FLY_TICKS)) - 1))
    # Same-Z/camera delta from represent2/represent3: (dX, dY/2).
    # Continuous inter-tick motion is a DISPLAY interpolation, not byte-exact
    # JX1 render sampling, and native world origin at the cast is not known.
    var step_screen: Vector2 = Vector2(
        float(item["x_factor"]) * VERIFIED_M141_STEP_NATIVE / NATIVE_FACTOR_SCALE,
        float(item["y_factor"]) * VERIFIED_M141_STEP_NATIVE / (2.0 * NATIVE_FACTOR_SCALE))
    sprite.global_position = (item["origin"] as Vector2) + step_screen * motion_ticks

# Optional read-only runtime sample bridge for future JX1 log/client trace.
# No fake stage mapping: only an EXPLICIT AnimFile slot 2/4 selects the atlas.
# Existing V6 casts keep working as preview even if no native samples arrive.
func apply_native_sample(sample: Dictionary) -> bool:
    # A full trace sample must identify a missile allocated by emit_allocation.
    # This bridge does not generate native observations or a camera calibration.
    if not sample.has("native_instance_id"):
        native_samples_rejected += 1
        return false
    var slot_id: int = int(sample["native_instance_id"])
    for i in range(fly_states.size()):
        var item: Dictionary = fly_states[i]
        if int(item.get("native_instance_id", -1)) != slot_id:
            continue
        # Validate EVERY optional field before mutating the state. A malformed
        # sample must not partially switch texture, frame or world position.
        var next_slot: int = int(sample.get("native_visual_slot", item.get("native_visual_slot", 2)))
        if next_slot != 2 and next_slot != 4:
            native_samples_rejected += 1
            return false
        var total_frames: int = 320 if next_slot == 2 else 6
        if sample.has("native_render_frame"):
            var absolute_frame: int = int(sample["native_render_frame"])
            if absolute_frame < 0 or absolute_frame >= total_frames:
                native_samples_rejected += 1
                return false
        if sample.has("native_missile_state") and not [1, 2].has(int(sample["native_missile_state"])):
            native_samples_rejected += 1
            return false
        if sample.has("native_dir64"):
            var incoming_dir: int = int(sample["native_dir64"])
            if incoming_dir < 0 or incoming_dir >= 64:
                native_samples_rejected += 1
                return false
        if sample.has("native_total_lifetime") and int(sample["native_total_lifetime"]) <= 0:
            native_samples_rejected += 1
            return false
        var has_timing: bool = sample.has("native_elapsed_ticks") or sample.has("native_duration_ticks")
        if has_timing and (not sample.has("native_elapsed_ticks") or not sample.has("native_duration_ticks")
                or int(sample["native_elapsed_ticks"]) < 0 or int(sample["native_duration_ticks"]) <= 0):
            native_samples_rejected += 1
            return false
        var has_x_factor: bool = sample.has("native_x_factor")
        var has_y_factor: bool = sample.has("native_y_factor")
        if has_x_factor != has_y_factor:
            native_samples_rejected += 1
            return false
        if has_x_factor and int(sample["native_x_factor"]) == 0 and int(sample["native_y_factor"]) == 0:
            native_samples_rejected += 1
            return false
        var position_info: Dictionary = NativeCoordinates.resolve_projected_world(sample)
        var has_position: bool = bool(position_info.get("ok", false))
        # Camera / region fields must be complete. Reject an incomplete
        # projection instead of quietly accepting a wrong screen position.
        if NativeCoordinates.has_any_native_position_field(sample) and not has_position:
            native_samples_rejected += 1
            return false
        var now_ms: int = Time.get_ticks_msec()
        var last_arrival_ms: int = int(item.get("native_last_arrival_ms", -1))
        var last_trace_ms: int = int(item.get("native_last_trace_time_ms", -1))
        var sample_trace_ms: int = int(sample.get("native_sample_time_ms", -1))
        if sample.has("native_sample_time_ms") and sample_trace_ms < 0:
            native_samples_rejected += 1
            return false
        if sample_trace_ms >= 0 and last_trace_ms >= 0 and sample_trace_ms < last_trace_ms:
            # Reject out-of-order trace timestamps: don't rewind a missile.
            native_samples_rejected += 1
            return false
        if has_position:
            var next_position: Vector2 = position_info["position"] as Vector2
            var previous_position: Vector2 = item["native_position"] as Vector2
            # Continue from current displayed point if an earlier interpolation
            # hasn't reached its final observed endpoint yet.
            var previous_displayed: Vector2 = (item["sprite"] as Sprite2D).global_position
            var had_projected_position: bool = bool(item.get("native_projected", false))
            item["native_projected"] = true
            item["native_position"] = next_position
            item["position_source"] = str(position_info["source"])
            if had_projected_position and next_position != previous_position:
                # Smoothly replay previous -> current OBSERVED sample for one
                # interval. No forward prediction / no fictitious positions.
                var dt_ms: int = 0
                if sample_trace_ms >= 0 and last_trace_ms >= 0:
                    dt_ms = sample_trace_ms - last_trace_ms
                elif last_arrival_ms >= 0:
                    dt_ms = now_ms - last_arrival_ms
                if dt_ms > 0 and dt_ms <= 500:
                    item["native_lerp_from"] = previous_displayed
                    item["native_lerp_to"] = next_position
                    item["native_lerp_start_ms"] = now_ms
                    item["native_lerp_duration_ms"] = dt_ms
                    native_snapshot_interpolations += 1
                else:
                    item["native_lerp_duration_ms"] = 0
            else:
                item["native_lerp_duration_ms"] = 0
        if sample.has("native_visual_slot"):
            item["native_visual_slot"] = next_slot
            # Stage changes do not implicitly carry an old frame index.
            if not sample.has("native_render_frame") and not has_timing:
                item["native_frame"] = -1
                item["native_elapsed"] = -1
                item["native_duration"] = -1
        if sample.has("native_render_frame"):
            item["native_frame"] = int(sample["native_render_frame"])
            item["native_elapsed"] = -1
            item["native_duration"] = -1
        elif has_timing:
            item["native_frame"] = -1
            item["native_elapsed"] = int(sample["native_elapsed_ticks"])
            item["native_duration"] = int(sample["native_duration_ticks"])
            item["native_interval"] = maxi(1, int(sample.get("native_interval_ticks", 1)))
            item["native_interval_mode"] = bool(sample.get("native_interval_mode", false))
        if sample.has("native_dir64"):
            item["dir64"] = int(sample["native_dir64"])
        if sample.has("native_missile_state"):
            item["state"] = int(sample["native_missile_state"])
            native_state_samples_seen += 1
        if has_x_factor:
            item["x_factor"] = int(sample["native_x_factor"])
            item["y_factor"] = int(sample["native_y_factor"])
            item["unit"] = Vector2(float(item["x_factor"]), float(item["y_factor"])).normalized()
            item["vector_source"] = "observed_per_instance_factors"
        if sample.has("native_total_lifetime"):
            item["life_ticks"] = int(sample["native_total_lifetime"])
        item["native_sample"] = true
        item["native_last_arrival_ms"] = now_ms
        if sample_trace_ms >= 0:
            item["native_last_trace_time_ms"] = sample_trace_ms
        if bool(sample.get("native_done", false)):
            item["native_done"] = true
            native_samples_finished += 1
        fly_states[i] = item
        native_samples_applied += 1
        _update_fly(item)
        return true
    native_samples_rejected += 1
    return false

# Multiple samples can be injected by an external native trace adapter; no
# auto-connection to client process or server network is claimed.
func apply_native_samples(samples: Array) -> Dictionary:
    var accepted: int = 0
    var rejected: int = 0
    for sample in samples:
        if sample is Dictionary and apply_native_sample(sample):
            accepted += 1
        else:
            rejected += 1
    return {"accepted": accepted, "rejected": rejected}

func on_visual_contact(world_position: Vector2) -> void:
    # V22's impact_contacted signal is DEMO collision and does not identify a
    # specific missile slot. We show one separate impact sprite at contact,
    # without pretending which M141 FLY object it belonged to.
    var sprite := Sprite2D.new()
    sprite.name = "M141_HIT_PREVIEW_%d" % (impact_events + 1)
    sprite.texture = HIT_TEXTURE
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 0, 256, 256)
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.centered = true
    sprite.scale = Vector2.ONE
    add_child(sprite)
    var new_impact: Dictionary = {"sprite": sprite,
        "age_seconds": 0.0, "position": world_position}
    impact_states.append(new_impact)
    impact_events += 1
    latest_label = "M141 DEMO CONTACT AnimFile4 ×%d" % impact_events
    _update_hit(new_impact)

func _update_hit(item: Dictionary) -> void:
    var sprite: Sprite2D = item["sprite"] as Sprite2D
    if not is_instance_valid(sprite):
        return
    var age: float = float(item["age_seconds"])
    var frame: int = clampi(floori(age / IMPACT_SECONDS * 6.0), 0, 5)
    var frame_info: Dictionary = FrameProbe.inspect(6, 1, 0, frame, 6, 1, true)
    if bool(frame_info.get("ok", false)):
        sprite.region_rect = Rect2(float(int(frame_info["local_frame"]) * 256), 0.0, 256.0, 256.0)
    sprite.global_position = item["position"] as Vector2

func diagnostic() -> Dictionary:
    var active_dirs: Array[int] = []
    var active_vectors: Array[Dictionary] = []
    for item in fly_states:
        active_dirs.append(int(item["dir64"]))
        active_vectors.append({"dir64": int(item["dir64"]),
            "x_factor": int(item["x_factor"]), "y_factor": int(item["y_factor"]),
            "source": str(item["vector_source"])})
    return {"active_fly": fly_states.size(), "impact_sprites": impact_states.size(),
        "replay_status": replay_status, "replay_attached": replay_attached,
        "replay_events_total": replay_events.size(), "replay_events_consumed": replay_consumed,
        "replay_invalid_events": replay_invalid_events,
        "preview_allocations_suppressed": replay_preview_suppressed,
        "fly_total": allocations, "contact_preview_total": impact_events,
        "dir64_active": active_dirs, "vector_sources": active_vectors,
        "pixel_per_tick_preview": -1.0,
        "native_world_step_per_tick_observed": VERIFIED_M141_STEP_NATIVE,
        "relative_screen_y_divisor": 2.0,
        "native_samples_applied": native_samples_applied,
        "native_samples_finished": native_samples_finished,
        "native_snapshot_interpolations": native_snapshot_interpolations,
        "native_samples_stream_adapter_connected": replay_attached,
        "form2_46_casts_spacing_verified": true,
        "form2_approx_side_fixed1024_max_error": 1,
        "m141_server_lifetime_ticks": FLY_TICKS,
        "m141_server_tick_interval_ms_observed": "mostly 53-57",
        "client_render_tick_clock_verified": false,
        "native_samples_rejected": native_samples_rejected,
        "v14_native_state_samples": native_state_samples_seen,
        "v14_demo_contact_ids": demo_contact_keys.size(),
        "v14_demo_cast_key": bound_demo_cast_key,
        "v14_origin": "actor world root (native NPC anchor not yet verified)",
        "client_region_projection": "requires region metadata and calibrated native-to-Godot transform",
        "native_coordinate_projection_verified": false,
        "native_camera_affine_supported_when_supplied": true,
        "native_trace_position_interpolation": "observed previous-to-current; no extrapolation",
        "native_trace_file": TRACE_REPLAY_PATH,
        "native_trace_source_provenance_verified": false,
        "form2_per_instance_generation_verified": false,
        "stage": latest_label, "position_verified": false, "damage_modified": false}
