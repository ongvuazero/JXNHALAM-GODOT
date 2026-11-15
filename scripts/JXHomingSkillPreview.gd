extends Node2D
## JXNHALAM V43.9 - JX1 MoveKind=5 (MISSLE_MMK_Follow) preview.
## Each visible projectile owns its own position, heading, flight frame and hit.
## IMPORTANT: ChildSkillNum is source gameplay metadata, NOT a sprite count.
## Max concurrent VFX=3 for CB 357 and 359, including overlapping casts.
## Original SPR only; no generated replacement effects and no native damage claim.

const PROFILE_PATH: String = "res://data/vfx_routes/follow_preview.json"
const GEOMETRY = preload("res://scripts/JXCombatGeometry.gd")
const DIRECTION = preload("res://scripts/JXSPRDirection.gd")
const LUA_EVENT_CODE = preload("res://scripts/JXLuaEventVFX.gd")
const LOGIC_HZ: float = 18.0
const DEFAULT_MAX_VISIBLE: int = 1
const MAX_CAST_LIFETIME: float = 3.0
const TARGET_Y: float = -44.0
const ORIGIN_Y: float = -55.0
const GROUP_NAME: String = "jx_godot_homing_vfx"

var caster: CharacterBody2D
var locked_target: StaticBody2D
var target_last_position: Vector2 = Vector2.ZERO
var cast_point: Vector2 = Vector2.ZERO
var skill: Dictionary = {}
var skill_id: int = 0
var source_child_count: int = 0
var profile: Dictionary = {}
var resolver: RefCounted
var source_assets: Dictionary = {}
var source_missing: Array[String] = []
var missiles: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var cast_clock: float = 0.0
var release_time: float = 0.10
var emission_interval: float = 0.11
var spawned_visual_count: int = 0
var emission_attempt_clock: float = 0.0
var completed_visual_count: int = 0
var registered_demo_damage: bool = false
var diagnostic_only: bool = false
var show_debug_overlay: bool = false
var initial_facing: int = 0
var cast_vector: Vector2 = Vector2.RIGHT
var precast: Sprite2D
var precast_duration: float = 0.10
var initialized: bool = false
var asset_notice: String = "MISSING_SOURCE_SPR"
var lua_event_layer: Node2D
var lua_event_sent: Dictionary = {}

func setup(source: CharacterBody2D, target_node: StaticBody2D, destination: Vector2,
        skill_data: Dictionary, face_direction: int, asset_resolver: RefCounted = null,
        preview_only: bool = false) -> void:
    caster = source
    locked_target = target_node
    skill = LUA_EVENT_CODE.authoritative_skill_visual(skill_data)
    skill_id = int(skill.get("legacy_skill_id", 0))
    resolver = asset_resolver
    diagnostic_only = preview_only
    initial_facing = posmod(face_direction, 8)
    source_child_count = maxi(1, int(skill.get("source_child_skill_num", 1)))
    # Lua's level-adjusted missile count is NOT ChildSkillNum/visible count.
    # Uses cached manifest to avoid a large JSON parse on each held Space.
    source_child_count = LUA_EVENT_CODE.source_child_count_at_level(skill_id, source_child_count)
    cast_point = destination
    target_last_position = destination
    if _has_live_target():
        target_last_position = locked_target.global_position + Vector2(0.0, TARGET_Y)
    var from: Vector2 = caster.global_position + Vector2(0.0, ORIGIN_Y)
    cast_vector = (target_last_position - from).normalized()
    if cast_vector.length_squared() < 0.01:
        cast_vector = Vector2.DOWN

    profile = _load_profile(skill_id)
    # "5 ticks" from source is NOT necessarily exact Godot visual spacing;
    # using 18Hz here is an explicit QA preview assumption.
    emission_interval = clampf(float(profile.get("launch_spacing_seconds",
        float(skill.get("source_msls_generate", 2)) / LOGIC_HZ)), 0.07, 0.3)
    _load_original_sprites()
    if source_assets.has("fly") and source_assets.has("hit"):
        asset_notice = "SOURCE_SPR_LOADED"
    elif source_assets.has("fly"):
        asset_notice = "MISSING_HIT_SPR"
    elif source_assets.has("hit"):
        asset_notice = "MISSING_FLY_SPR"
    precast_duration = _stage_duration("precast", 0.10)
    release_time = minf(0.20, precast_duration) if source_assets.has("precast") else 0.0
    add_to_group(GROUP_NAME)
    global_position = Vector2.ZERO
    if source_assets.has("precast"):
        precast = _new_sprite("precast", "PrecastOriginalSPR")
        if is_instance_valid(precast):
            precast.position = to_local(from)
            _set_spr_frame(precast, "precast", 0.0, cast_vector, false)
    initialized = true
    lua_event_sent.clear()
    var lua_node := Node2D.new()
    lua_node.name = "LuaLinkedEvents_%d" % skill_id
    lua_node.set_script(LUA_EVENT_CODE)
    get_parent().add_child(lua_node)
    lua_event_layer = lua_node
    lua_event_layer.call("setup", skill_id, caster, locked_target, resolver)
    _emit_lua_once("start", caster.global_position + Vector2(0.0, ORIGIN_Y))
    print("JX FOLLOW PREVIEW: skill=", skill_id, " MoveKind=", int(skill.get("missile_move_kind", -1)),
        " source_children=", source_child_count, " max_visible=", _max_visible(),
        " loaded=", source_assets.keys(), " missing=", source_missing)

func _emit_lua_once(event_name: String, world_point: Vector2) -> void:
    if lua_event_sent.has(event_name) or not is_instance_valid(lua_event_layer):
        return
    lua_event_sent[event_name] = true
    lua_event_layer.call("emit_parent", event_name, world_point, cast_vector)

func set_calibration(_settings: Dictionary) -> void:
    pass

func _load_profile(id: int) -> Dictionary:
    var defaults: Dictionary = {
        "max_visible_projectiles": DEFAULT_MAX_VISIBLE,
        "speed_px_per_s": 400.0,
        "homing_turn_rate": 9.0,
        "hit_range_px": 20.0,
        "max_flight_seconds": 1.2
    }
    if not FileAccess.file_exists(PROFILE_PATH):
        return defaults
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
    if decoded is Dictionary:
        var item: Variant = decoded.get(str(id), {})
        if item is Dictionary:
            defaults.merge(item, true)
    return defaults

func _load_original_sprites() -> void:
    source_assets.clear()
    source_missing.clear()
    var paths: Array = skill.get("original_missile_spr", [])
    var stage_paths: Dictionary = {
        "precast": str(skill.get("original_precast_spr", "")),
        "fly": str(paths[1]) if paths.size() > 1 else "",
        "travel_end": str(paths[2]) if paths.size() > 2 else "",
        "hit": str(paths[3]) if paths.size() > 3 else ""
    }
    for stage in stage_paths.keys():
        var path: String = str(stage_paths[stage])
        if path.is_empty():
            continue
        if resolver == null:
            source_missing.append(stage)
            continue
        var loaded: Dictionary = resolver.call("load_spr", path)
        if loaded.get("texture", null) is Texture2D:
            source_assets[stage] = loaded
        else:
            source_missing.append(stage)

func _has_live_target() -> bool:
    if not is_instance_valid(locked_target):
        return false
    if locked_target.has_method("is_alive"):
        return bool(locked_target.call("is_alive"))
    return true

func _current_target() -> Vector2:
    if _has_live_target():
        target_last_position = locked_target.global_position + Vector2(0.0, TARGET_Y)
    return target_last_position

func _max_visible() -> int:
    return clampi(int(profile.get("max_visible_projectiles", 1)), 1, 3)

func homing_active_count(caster_id: int) -> int:
    if not initialized or not is_instance_valid(caster) or caster.get_instance_id() != caster_id:
        return 0
    return missiles.size()

func _caster_active_missiles() -> int:
    if not is_instance_valid(caster):
        return 0
    var caster_id: int = caster.get_instance_id()
    var active: int = 0
    for other in get_tree().get_nodes_in_group(GROUP_NAME):
        if is_instance_valid(other) and other.has_method("homing_active_count"):
            active += int(other.call("homing_active_count", caster_id))
    return active

func _new_sprite(stage: String, node_name: String) -> Sprite2D:
    var data: Dictionary = source_assets.get(stage, {})
    var texture: Texture2D = data.get("texture") as Texture2D
    if texture == null:
        return null
    var sprite := Sprite2D.new()
    sprite.name = node_name
    sprite.texture = texture
    sprite.region_enabled = true
    sprite.centered = true
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.scale = Vector2.ONE * GEOMETRY.sprite_scale(skill, stage)
    sprite.z_as_relative = false
    sprite.z_index = 5
    add_child(sprite)
    return sprite

func _stage_meta(stage: String) -> Dictionary:
    var raw: Dictionary = skill.get("original_anim_info", {})
    var key: String = "cast" if stage == "precast" else stage
    var fields: PackedStringArray = str(raw.get(key, "")).split(",", false)
    if fields.size() != 3:
        return {}
    for value in fields:
        if not value.strip_edges().is_valid_int():
            return {}
    var total: int = int(fields[0])
    var dirs: int = int(fields[1])
    var ticks: int = int(fields[2])
    if total < 1 or dirs < 1 or ticks < 1 or total % dirs != 0:
        return {}
    return {"frames": int(total / dirs), "ticks": ticks}

func _stage_duration(stage: String, fallback: float) -> float:
    var data: Dictionary = source_assets.get(stage, {})
    if data.is_empty():
        return fallback
    var meta: Dictionary = _stage_meta(stage)
    var frames: int = mini(maxi(1, int(data.get("frames_per_direction", 1))),
        maxi(1, int(meta.get("frames", 9999))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    return clampf(float(frames * ticks) / LOGIC_HZ, 0.05, 0.8)

func _row_from_heading(heading: Vector2, dirs: int) -> int:
    if dirs <= 1:
        return 0
    return DIRECTION.row_from_vector(heading, dirs)

func _set_spr_frame(sprite: Sprite2D, stage: String, age: float,
        direction: Vector2, loop_animation: bool) -> void:
    var data: Dictionary = source_assets.get(stage, {})
    if data.is_empty() or not is_instance_valid(sprite):
        return
    var meta: Dictionary = _stage_meta(stage)
    var dirs: int = maxi(1, int(data.get("directions", 1)))
    var original_frames: int = maxi(1, int(data.get("frames_per_direction", 1)))
    var frames: int = mini(original_frames, maxi(1, int(meta.get("frames", original_frames))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    var raw_index: int = maxi(0, floori(age * LOGIC_HZ / float(ticks)))
    var frame: int = (raw_index % frames) if loop_animation else mini(frames - 1, raw_index)
    var row: int = _row_from_heading(direction, dirs)
    var tile: int = maxi(1, int(data.get("tile_size", data.get("tile", 256))))
    if resolver == null or not bool(resolver.call("draw_source_frame", sprite, data, frame, row)):
        sprite.region_rect = Rect2(frame * tile, row * tile, tile, tile)

func _process(delta: float) -> void:
    if not initialized or not is_instance_valid(caster):
        queue_free()
        return
    var dt: float = clampf(delta, 0.0, 0.08)
    cast_clock += dt
    _current_target()
    if is_instance_valid(precast):
        precast.position = to_local(caster.global_position + Vector2(0.0, ORIGIN_Y))
        _set_spr_frame(precast, "precast", cast_clock, cast_vector, false)
        if cast_clock >= release_time:
            precast.queue_free()
            precast = null

    if cast_clock >= release_time and cast_clock <= 1.25 and source_assets.has("fly"):
        # Source ChildSkillNum=16 does not imply 16 simultaneous visible clubs.
        # Three in-flight sprites maximum across overlapping casts for this caster.
        emission_attempt_clock += dt
        var target_max: int = mini(_max_visible(), source_child_count)
        while spawned_visual_count < target_max and emission_attempt_clock >= emission_interval:
            if _caster_active_missiles() >= _max_visible():
                break
            emission_attempt_clock -= emission_interval
            var before_spawn: int = spawned_visual_count
            _spawn_missile(before_spawn)
            if spawned_visual_count == before_spawn:
                break
    _step_missiles(dt)
    _step_hits(dt)
    if cast_clock >= MAX_CAST_LIFETIME or (cast_clock > 1.25 and missiles.is_empty() and hits.is_empty()):
        _emit_lua_once("vanish", global_position)
        if is_instance_valid(lua_event_layer):
            lua_event_layer.call("mark_parent_finished")
        queue_free()
    if show_debug_overlay:
        queue_redraw()

func _spawn_missile(index: int) -> void:
    var sprite: Sprite2D = _new_sprite("fly", "OriginalJX_Follow_%02d" % index)
    if not is_instance_valid(sprite):
        return
    var origin: Vector2 = caster.global_position + Vector2(0.0, ORIGIN_Y)
    var side: Vector2 = Vector2(-cast_vector.y, cast_vector.x)
    var centered: float = float(index) - float(_max_visible() - 1) * 0.5
    origin += side * centered * 12.0
    var heading: Vector2 = cast_vector.rotated(centered * 0.14).normalized()
    sprite.position = to_local(origin)
    _set_spr_frame(sprite, "fly", 0.0, heading, true)
    missiles.append({"sprite": sprite, "position": origin, "heading": heading, "age": 0.0, "id": index})
    spawned_visual_count += 1
    _emit_lua_once("fly", origin)

func _step_missiles(dt: float) -> void:
    for index in range(missiles.size() - 1, -1, -1):
        var state: Dictionary = missiles[index]
        var sprite: Sprite2D = state.get("sprite") as Sprite2D
        if not is_instance_valid(sprite):
            missiles.remove_at(index)
            continue
        var age: float = float(state.get("age", 0.0)) + dt
        var pos: Vector2 = state.get("position", Vector2.ZERO)
        var heading: Vector2 = state.get("heading", cast_vector)
        var toward: Vector2 = _current_target() - pos
        var distance: float = toward.length()
        # JX1 MISSLE_MMK_Follow initially travels along cast heading; then
        # retargets to the target's CURRENT position.  Turn-rate is QA only.
        if age > 5.0 / LOGIC_HZ and _has_live_target() and distance > 0.01:
            var desired: float = toward.angle()
            heading = Vector2.RIGHT.rotated(lerp_angle(heading.angle(), desired,
                clampf(dt * float(profile.get("homing_turn_rate", 9.0)), 0.0, 1.0)))
        var speed: float = float(profile.get("speed_px_per_s", 500.0))
        var prev_pos: Vector2 = pos
        pos += heading * speed * dt
        state["age"] = age
        state["position"] = pos
        state["heading"] = heading
        missiles[index] = state
        sprite.position = to_local(pos)
        _set_spr_frame(sprite, "fly", age, heading, true)
        var hit_range: float = float(profile.get("hit_range_px", 20.0))
        var destination: Vector2 = _current_target()
        var delta_step: Vector2 = pos - prev_pos
        var fraction: float = clampf((destination - prev_pos).dot(delta_step) / maxf(delta_step.length_squared(), 0.0001), 0.0, 1.0)
        var closest: Vector2 = prev_pos + delta_step * fraction
        var touched: bool = closest.distance_to(destination) <= hit_range
        if age > 0.12 and _has_live_target() and touched:
            _spawn_hit(destination, true, heading)
            sprite.queue_free()
            missiles.remove_at(index)
            completed_visual_count += 1
        elif age >= float(profile.get("max_flight_seconds", 1.3)):
            # Missing/dead target: vanish, do not retarget a different NPC.
            sprite.queue_free()
            missiles.remove_at(index)
            completed_visual_count += 1

func _spawn_hit(world_position: Vector2, actual_contact: bool, impact_heading: Vector2) -> void:
    if actual_contact and is_instance_valid(lua_event_layer):
        # Actual missile contacts can each invoke the source Lua CollideEvent.
        # This is NOT a request to create ChildSkillNum cloned sprites.
        lua_event_layer.call("emit_parent", "collide", world_position,
            impact_heading, completed_visual_count)
    var sprite: Sprite2D = _new_sprite("hit", "OriginalJX_Impact")
    if is_instance_valid(sprite):
        sprite.position = to_local(world_position)
        _set_spr_frame(sprite, "hit", 0.0, impact_heading, false)
        hits.append({"sprite": sprite, "position": world_position, "age": 0.0, "heading": impact_heading})
    if not diagnostic_only and actual_contact and not registered_demo_damage and _has_live_target():
        registered_demo_damage = true
        if locked_target.has_method("take_damage"):
            locked_target.call("take_damage", 10) # QA ONLY: not JX combat damage.

func _step_hits(dt: float) -> void:
    for i in range(hits.size() - 1, -1, -1):
        var hit_state: Dictionary = hits[i]
        var sprite: Sprite2D = hit_state.get("sprite") as Sprite2D
        if not is_instance_valid(sprite):
            hits.remove_at(i)
            continue
        var age: float = float(hit_state.get("age", 0.0)) + dt
        hit_state["age"] = age
        hits[i] = hit_state
        _set_spr_frame(sprite, "hit", age, hit_state.get("heading", cast_vector), false)
        if age >= _stage_duration("hit", 0.2):
            sprite.queue_free()
            hits.remove_at(i)

func _draw() -> void:
    if not show_debug_overlay:
        return
    var center: Vector2 = to_local(_current_target())
    draw_circle(center, 4.0, Color(1.0, 0.8, 0.2, 0.85))
    draw_arc(center, float(profile.get("hit_range_px", 20.0)), 0.0, TAU, 28,
        Color(0.9, 0.9, 0.4, 0.45), 1.0)

func get_diagnostic() -> Dictionary:
    return {"skill_id": skill_id, "asset_notice": asset_notice, "move_kind": int(skill.get("missile_move_kind", -1)),
        "source_children": source_child_count, "max_visible": _max_visible(),
        "visual_spawned_total": spawned_visual_count,
        "active_fly": missiles.size(), "completed_fly": completed_visual_count,
        "active_hit": hits.size(), "has_live_target": _has_live_target(),
        "tracked_target": _current_target(), "original_spr_roles": source_assets.keys(),
        "missing_spr_roles": source_missing, "native_damage_verified": false}
