extends Node2D
## V43.8 — Source-SPR stages for nine-sect QA.
## Reads actual precast/AnimFile1/AnimFile2/AnimFile3/AnimFile4 when present.
## Formation offsets and timings are QA approximations, NOT verified JX1 geometry.
## No hand-drawn placeholder VFX. Missing SPR parts remain visibly unimplemented.
const SOURCE_TICK_HZ: float = 18.0
const GEOMETRY = preload("res://scripts/JXCombatGeometry.gd")
const DIRECTION = preload("res://scripts/JXSPRDirection.gd")
const MOTION = preload("res://scripts/JXMissileMotion.gd")
const SPECIAL = preload("res://scripts/JXSpecialMissileMotion.gd")
const SPECIAL_IMPACT = preload("res://scripts/JXSpecialImpactVFX.gd")
const FORMATION = preload("res://scripts/JXMissileFormationV449.gd")
const LUA_EVENT_CODE = preload("res://scripts/JXLuaEventVFX.gd")

var caster: CharacterBody2D
var dummy: StaticBody2D
var aim: Vector2 = Vector2.ZERO
var skill: Dictionary = {}
var asset_resolver: RefCounted
var diagnostic_only: bool = false
var show_debug_overlay: bool = false
var school_id: String = ""
var face_dir: int = 0
var asset_notice: String = ""
var phase: String = ""
var elapsed: float = 0.0
var stage_duration: float = 0.2
var damage_done: bool = false
var source_count: int = 1
var displayed_count: int = 0
var source_stages: Dictionary = {}
var sprites: Dictionary = {}
var missing_paths: Array[String] = []
var stage_paths: Dictionary = {}
var flight_start: Vector2 = Vector2.ZERO
var flight_target: Vector2 = Vector2.ZERO
var formation_verified: bool = false
# V44.1: flight modes are not interchangeable. Only 0/1 are simulated here.
# Follow(5) is owned by JXHomingSkillPreview; other MoveKinds remain unverified.
var flight_mode: String = "unsupported"
var flight_heading: Vector2 = Vector2.DOWN
var flight_last_position: Vector2 = Vector2.ZERO
var impact_position: Vector2 = Vector2.ZERO
var visual_contact: bool = false
var contact_world_position: Vector2 = Vector2.ZERO
var strike_checked: bool = false
var unsupported_warned: bool = false
var lua_event_layer: Node2D
var lua_event_sent: Dictionary = {}
var special_spec: Dictionary = {}
var special_headings: Array[Vector2] = []
var special_previous: Array[Vector2] = []
var special_contacted: Dictionary = {}
var special_flight_age: float = 0.0
var special_initial_heading: Vector2 = Vector2.DOWN
var special_hit_visuals_created: int = 0
var special_hit_visuals_missing: int = 0
# V44.9 source-verified Line/Spread formations (QA world units, original source SPR).
var formation_enabled: bool = false
var formation_spec: Dictionary = {}
var formation_starts: Array[Vector2] = []
var formation_headings: Array[Vector2] = []
var formation_last_points: Array[Vector2] = []
var formation_contacted: Dictionary = {}
var formation_hits: int = 0

func setup(source: CharacterBody2D, target_node: StaticBody2D, destination: Vector2,
        skill_data: Dictionary, face_direction: int, resolver: RefCounted = null,
        preview_only: bool = false) -> void:
    caster = source
    dummy = target_node
    aim = destination
    skill = LUA_EVENT_CODE.authoritative_skill_visual(skill_data)
    asset_resolver = resolver
    diagnostic_only = preview_only
    school_id = str(skill.get("preview_sect", ""))
    face_dir = posmod(face_direction, 8)
    elapsed = 0.0
    damage_done = false
    source_count = maxi(1, int(skill.get("source_child_skill_num", 1)))
    source_count = LUA_EVENT_CODE.source_child_count_at_level(int(skill.get("legacy_skill_id", 0)), source_count)
    # V44.3: an unverified formation MUST NOT clone the same SPR many times
    # at one point. Actual Lua missile count remains in source_count for QA.
    displayed_count = 1
    flight_start = caster.global_position + Vector2(0.0, -55.0)
    flight_target = aim
    flight_last_position = flight_start
    impact_position = aim
    visual_contact = false
    strike_checked = false
    var move_kind: int = int(skill.get("missile_move_kind", -1))
    flight_mode = MOTION.mode_for_kind(move_kind)
    flight_heading = MOTION.heading(flight_start, flight_target)
    special_initial_heading = flight_heading
    special_spec = SPECIAL.spec(int(skill.get("legacy_skill_id", 0)))
    special_headings.clear()
    special_previous.clear()
    special_contacted.clear()
    special_hit_visuals_created = 0
    special_hit_visuals_missing = 0
    formation_enabled = false
    formation_spec = FORMATION.profile(int(skill.get("legacy_skill_id", 0)))
    formation_starts.clear()
    formation_headings.clear()
    formation_last_points.clear()
    formation_contacted.clear()
    formation_hits = 0
    if flight_mode == "rollback_preview" and int(skill.get("source_missles_form", -1)) == 2 and not special_spec.is_empty():
        # The native Spread form is verified for this skill; do not extend it to
        # unrelated ChildSkillNum values, which may mean logic rather than art.
        displayed_count = clampi(int(special_spec.get("child_skill_num", 1)), 1, 8)
        formation_verified = true
        for idx in range(displayed_count):
            special_headings.append(SPECIAL.spread_heading(flight_heading, idx, displayed_count,
                int(special_spec.get("skill_param1", 0))))
            special_previous.append(flight_start)
    elif flight_mode == "helix_preview" and not special_spec.is_empty():
        # Verified in Unity JX enum: form 12 is Melee_ManyAttack, not
        # a conventional projectile formation. Preserve only the single
        # HELIX QA trace until native melee event sequencing is proven.
        displayed_count = 1
        special_previous.append(flight_start)
        if int(skill.get("source_missles_form", -1)) == 12:
            print("V44.8 MELEE MANYATTACK SOURCE | skill=", int(skill.get("legacy_skill_id", 0)),
                " | move_kind=4 | child_count_is_not_simultaneous_vfx=true")
    if flight_mode == "straight" and FORMATION.matches(skill, formation_spec, source_count):
        # Only four explicit JX source rows enter this path. Never reuse the
        # formula for homing, melee, missing source or arbitrary skill IDs.
        formation_enabled = true
        formation_verified = true
        displayed_count = source_count
        for idx in range(displayed_count):
            var start: Vector2 = FORMATION.start_position(flight_start, flight_heading, idx, formation_spec)
            formation_starts.append(start)
            formation_headings.append(FORMATION.heading(flight_heading, idx, formation_spec))
            formation_last_points.append(start)
    if flight_mode == "follow_external":
        push_warning("V44.1: MoveKind=5 must use JXHomingSkillPreview; no fake straight-line motion for skill %d" % int(skill.get("legacy_skill_id", 0)))
    elif flight_mode == "unsupported":
        push_warning("V44.1: unsupported MoveKind=%d / skill %d; visual stays at cast source, not fake flight" % [move_kind, int(skill.get("legacy_skill_id", 0))])
    var paths: Array = skill.get("original_missile_spr", [])
    var precast_path: String = str(skill.get("original_precast_spr", ""))
    var anim1_path: String = str(paths[0]) if paths.size() > 0 else ""
    var anim2_path: String = str(paths[1]) if paths.size() > 1 else ""
    var anim3_path: String = str(paths[2]) if paths.size() > 2 else ""
    var anim4_path: String = str(paths[3]) if paths.size() > 3 else ""
    stage_paths = {
        "precast": precast_path if not precast_path.is_empty() else anim1_path,
        "fly": anim2_path,
        "travel_end": anim3_path,
        "hit": anim4_path
    }
    for role in ["precast", "fly", "travel_end", "hit"]:
        var virtual_path: String = str(stage_paths.get(role, ""))
        if virtual_path.is_empty():
            continue
        if asset_resolver != null:
            var loaded: Dictionary = asset_resolver.call("load_spr", virtual_path)
            if loaded.get("texture", null) is Texture2D:
                source_stages[role] = loaded
                continue
        missing_paths.append(role + ": " + virtual_path)
    for role in source_stages.keys():
        var pieces: Array[Sprite2D] = []
        var draw_count: int = displayed_count if str(role) == "fly" and formation_verified and (flight_mode == "rollback_preview" or formation_enabled) else 1
        for i in range(draw_count):
            var source_data: Dictionary = source_stages[role]
            var layer := Sprite2D.new()
            layer.name = "%s_SourceSPR_%02d" % [str(role), i]
            layer.texture = source_data.get("texture") as Texture2D
            layer.region_enabled = true
            layer.centered = true
            layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
            layer.scale = Vector2.ONE * GEOMETRY.sprite_scale(skill, str(role))
            layer.visible = false
            add_child(layer)
            pieces.append(layer)
        sprites[role] = pieces
    if source_stages.has("fly") and source_stages.has("hit"):
        asset_notice = "SOURCE_SPR_LOADED"
    elif not source_stages.has("fly") and not source_stages.has("hit"):
        asset_notice = "MISSING_SOURCE_SPR"
    elif not source_stages.has("fly"):
        asset_notice = "MISSING_FLY_SPR"
    else:
        asset_notice = "MISSING_HIT_SPR"
    if flight_mode == "unsupported" or flight_mode == "follow_external":
        # Correct source sprite is not proof of correct flight trajectory.
        asset_notice = "UNVERIFIED_MISSILE_MOVE_KIND_%d" % move_kind
    if not missing_paths.is_empty():
        print("V43.8 SPR PARTIAL | ", school_id, " | ", int(skill.get("legacy_skill_id", 0)),
            " | loaded=", source_stages.keys(), " | missing=", missing_paths.size())
    z_as_relative = false
    z_index = 5
    # Lua event stages are siblings of this FX so linked impacts may outlive
    # the parent missile sprite. This DOES NOT touch TV or demo damage.
    lua_event_sent.clear()
    var events_node := Node2D.new()
    events_node.set_script(LUA_EVENT_CODE)
    events_node.name = "LuaLinkedEvents_%d" % int(skill.get("legacy_skill_id", 0))
    get_parent().add_child(events_node)
    lua_event_layer = events_node
    lua_event_layer.call("setup", int(skill.get("legacy_skill_id", 0)), caster, dummy, asset_resolver)
    _emit_lua_once("start", caster.global_position + Vector2(0.0, -55.0))
    if source_stages.has("precast"):
        _enter_phase("precast")
    else:
        _enter_phase("fly")

func _emit_lua_once(event_name: String, point: Vector2) -> void:
    if lua_event_sent.has(event_name) or not is_instance_valid(lua_event_layer):
        return
    lua_event_sent[event_name] = true
    var heading: Vector2 = flight_heading
    if heading.length_squared() < 0.001:
        heading = Vector2.RIGHT
    lua_event_layer.call("emit_parent", event_name, point, heading)

func set_calibration(_settings: Dictionary) -> void:
    pass

func _anim_meta(role: String) -> Dictionary:
    var info: Dictionary = skill.get("original_anim_info", {})
    var key: String = "cast" if role == "precast" else role
    var fields: PackedStringArray = str(info.get(key, "")).split(",", false)
    if fields.size() != 3:
        return {}
    for token in fields:
        if not token.strip_edges().is_valid_int():
            return {}
    var total: int = int(fields[0])
    var dirs: int = int(fields[1])
    var ticks: int = int(fields[2])
    if total < 1 or dirs < 1 or ticks < 1 or total % dirs != 0:
        return {}
    return {"frames": total / dirs, "dirs": dirs, "ticks": ticks}

func _source_duration(role: String) -> float:
    if not source_stages.has(role):
        return 0.0
    var data: Dictionary = source_stages[role]
    var meta: Dictionary = _anim_meta(role)
    var actual_frames: int = maxi(1, int(data.get("frames_per_direction", 1)))
    var frames: int = mini(actual_frames, maxi(1, int(meta.get("frames", actual_frames))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    var duration: float = float(frames * ticks) / SOURCE_TICK_HZ
    if meta.is_empty():
        duration = float(frames * maxi(20, int(data.get("anim_ms", 70)))) / 1000.0
    return clampf(duration, 0.08, 3.0)

func _enter_phase(next: String) -> void:
    phase = next
    elapsed = 0.0
    for role in sprites.keys():
        var layers: Array = sprites[role]
        for layer in layers:
            if is_instance_valid(layer):
                layer.visible = str(role) == phase and (flight_mode in ["stationary", "straight", "helix_preview", "rollback_preview"] or str(role) == "precast")
    match phase:
        "precast":
            stage_duration = _source_duration("precast")
            global_position = caster.global_position + Vector2(0.0, -55.0)
        "fly":
            # Lua FlyEventTime is honored as a provisional 18Hz delay.
            if is_instance_valid(lua_event_layer) and float(lua_event_layer.call("parent_fly_delay_seconds")) <= 0.0:
                _emit_lua_once("fly", flight_start)
            flight_last_position = flight_start
            var fallback_seconds: float = clampf(float(skill.get("character_cast_ms", 700)) / 1000.0, 0.25, 1.5)
            if formation_enabled:
                stage_duration = FORMATION.duration_seconds(formation_spec)
            elif flight_mode == "straight":
                # Speed is an explicit Godot QA calibration. Do NOT interpret
                # original missile Speed as pixels/second without conversion.
                var calibrated_speed: float = GEOMETRY.flight_speed_pixels(skill)
                stage_duration = MOTION.flight_duration_preview(
                    flight_start.distance_to(flight_target), calibrated_speed, fallback_seconds)
            elif flight_mode == "stationary":
                stage_duration = maxf(0.12, _source_duration("fly")) if source_stages.has("fly") else 0.06
            elif flight_mode == "rollback_preview" and formation_verified:
                var lifetime: float = float(special_spec.get("missile_lifetime_ticks", 32))
                var maximum_delay: float = 0.0
                for idx in range(displayed_count):
                    maximum_delay = maxf(maximum_delay, SPECIAL.release_tick(idx, displayed_count,
                        int(special_spec.get("generate_style", 0)),
                        int(special_spec.get("wait_ticks", 0)),
                        int(special_spec.get("generate_step_ticks", 0))))
                stage_duration = (lifetime + maximum_delay) / SOURCE_TICK_HZ
            elif flight_mode == "helix_preview":
                stage_duration = maxf(0.4, float(special_spec.get("qa_helix_seconds", 1.5)))
            else:
                stage_duration = 0.06
            if not source_stages.has("fly") and source_stages.has("hit") and flight_mode not in ["helix_preview", "rollback_preview"]:
                stage_duration = 0.04
            global_position = flight_start if flight_mode == "rollback_preview" else MOTION.motion_point(flight_mode, flight_start, flight_target, 0.0)
        "travel_end":
            stage_duration = maxf(0.06, _source_duration("travel_end"))
            global_position = impact_position
        "hit":
            if visual_contact:
                _emit_lua_once("collide", impact_position)
            stage_duration = maxf(0.06, _source_duration("hit")) if source_stages.has("hit") else 0.12
            global_position = impact_position
            if not damage_done:
                damage_done = true
                _apply_demo_damage()
        "end":
            _emit_lua_once("vanish", global_position)
            if is_instance_valid(lua_event_layer):
                lua_event_layer.call("mark_parent_finished")
            stage_duration = 0.12
        _:
            stage_duration = 0.1
    _update_stage_sprites()

func _next_phase() -> void:
    match phase:
        "precast": _enter_phase("fly")
        "fly":
            # V44.8: Spread/RollBack children already resolve their own HIT at
            # contact. Never replay one big explosion after all five return.
            if (flight_mode == "rollback_preview" and formation_verified) or formation_enabled:
                _enter_phase("end")
            elif visual_contact and source_stages.has("travel_end"):
                _enter_phase("travel_end")
            elif visual_contact:
                _enter_phase("hit")
            else:
                _enter_phase("end")
        "travel_end":
            if visual_contact:
                _enter_phase("hit")
            else:
                _enter_phase("end")
        "hit": _enter_phase("end")
        _:
            if is_instance_valid(lua_event_layer):
                lua_event_layer.call("mark_parent_finished")
            queue_free()

func _process(delta: float) -> void:
    if not is_instance_valid(caster):
        queue_free()
        return
    elapsed += maxf(delta, 0.0)
    if phase == "precast":
        global_position = caster.global_position + Vector2(0.0, -55.0)
    elif phase == "fly":
        if is_instance_valid(lua_event_layer) and not lua_event_sent.has("fly"):
            var required_delay: float = float(lua_event_layer.call("parent_fly_delay_seconds"))
            if elapsed >= required_delay:
                _emit_lua_once("fly", global_position)
        var ratio: float = clampf(elapsed / maxf(stage_duration, 0.001), 0.0, 1.0)
        var visual_world: Vector2 = MOTION.motion_point(flight_mode, flight_start, flight_target, ratio)
        if formation_enabled:
            visual_world = flight_start
            _tick_native_formation()
        elif flight_mode == "helix_preview":
            visual_world = SPECIAL.helix_position(flight_start, special_initial_heading, elapsed * SOURCE_TICK_HZ,
                float(special_spec.get("missile_speed_raw", 10)),
                int(special_spec.get("missile_param1", 1)),
                float(special_spec.get("qa_unit_scale", 0.55)))
            var delta_motion: Vector2 = visual_world - flight_last_position
            if delta_motion.length_squared() > 0.0001:
                flight_heading = delta_motion.normalized()
            if not strike_checked and _has_live_target() and MOTION.segment_hits_circle(
                flight_last_position, visual_world, _live_target_center(), GEOMETRY.hit_radius_pixels(skill)):
                strike_checked = true
                visual_contact = true
                impact_position = _live_target_center()
                contact_world_position = impact_position
                elapsed = stage_duration
        elif flight_mode == "rollback_preview" and formation_verified:
            visual_world = flight_start # Each missile has its own Sprite2D offset.
            var speed: float = GEOMETRY.flight_speed_pixels(skill)
            if speed <= 0.01:
                speed = 315.0 # QA conversion: original Speed=32 is not px/s.
            for idx in range(displayed_count):
                var release_ticks: float = SPECIAL.release_tick(idx, displayed_count,
                    int(special_spec.get("generate_style", 0)), int(special_spec.get("wait_ticks", 0)),
                    int(special_spec.get("generate_step_ticks", 0)))
                var age_ticks: float = elapsed * SOURCE_TICK_HZ - release_ticks
                if age_ticks < 0.0 or age_ticks >= float(special_spec.get("missile_lifetime_ticks", 32)):
                    continue
                var new_point: Vector2 = SPECIAL.rollback_position(flight_start, special_headings[idx], age_ticks,
                    float(special_spec.get("missile_lifetime_ticks", 32)), speed)
                if not special_contacted.has(idx) and _has_live_target() and MOTION.segment_hits_circle(
                    special_previous[idx], new_point, _live_target_center(), GEOMETRY.hit_radius_pixels(skill)):
                    special_contacted[idx] = true
                    visual_contact = true
                    impact_position = _live_target_center()
                    contact_world_position = impact_position
                    # Each live contact has its own Lua collision event and
                    # an independent original-SPR impact visual. The missile
                    # ordinal prevents the chain from merging five contacts.
                    var impact_heading: Vector2 = special_headings[idx]
                    if age_ticks >= float(special_spec.get("missile_lifetime_ticks", 32)) * 0.5:
                        impact_heading = -impact_heading
                    _create_special_impact(impact_position, impact_heading, idx)
                    if is_instance_valid(lua_event_layer):
                        lua_event_layer.call("emit_parent", "collide", impact_position, impact_heading, idx)
                    if not damage_done:
                        damage_done = true
                        _apply_demo_damage() # One DEMO hit per cast, unchanged damage cap.
                special_previous[idx] = new_point
        global_position = visual_world
        # A straight missile checks its traveled SEGMENT against the live NPC.
        # A moving target does not cause the projectile to magically turn.
        if flight_mode == "straight" and not formation_enabled and not strike_checked and _has_live_target():
            var center: Vector2 = _live_target_center()
            var hit_radius: float = maxf(1.0, GEOMETRY.hit_radius_pixels(skill))
            if MOTION.segment_hits_circle(flight_last_position, visual_world, center, hit_radius):
                strike_checked = true
                visual_contact = true
                impact_position = center
                contact_world_position = center
                elapsed = stage_duration
        flight_last_position = visual_world
    elif phase == "travel_end" or phase == "hit":
        global_position = impact_position
    _update_stage_sprites()
    if elapsed >= stage_duration:
        if phase == "fly" and not strike_checked and not formation_enabled:
            _evaluate_stationary_contact()
        _next_phase()
    if show_debug_overlay:
        queue_redraw()

func _update_stage_sprites() -> void:
    var layers: Array = sprites.get(phase, [])
    if layers.is_empty():
        return
    var data: Dictionary = source_stages.get(phase, {})
    if data.is_empty():
        return
    if phase == "fly" and formation_enabled:
        _update_native_formation_sprites(layers, data)
        return
    if phase == "fly" and flight_mode == "rollback_preview" and formation_verified:
        _update_rollback_sprites(layers, data)
        return
    var dirs: int = maxi(1, int(data.get("directions", 1)))
    var frames: int = maxi(1, int(data.get("frames_per_direction", 1)))
    var meta: Dictionary = _anim_meta(phase)
    frames = mini(frames, maxi(1, int(meta.get("frames", frames))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    var frame: int = mini(frames - 1, floori(elapsed * SOURCE_TICK_HZ / float(ticks)))
    var row: int = DIRECTION.row_from_character_dir8(face_dir, dirs)
    if (phase == "fly" or phase == "travel_end" or phase == "hit") and flight_mode in ["straight", "helix_preview"]:
        row = DIRECTION.row_from_vector(flight_heading, dirs)
    var tile: int = maxi(1, int(data.get("tile_size", data.get("tile", 256))))
    var rect: Rect2 = Rect2(frame * tile, row * tile, tile, tile)
    for i in range(layers.size()):
        var layer: Sprite2D = layers[i] as Sprite2D
        if not is_instance_valid(layer):
            continue
        if asset_resolver == null or not bool(asset_resolver.call("draw_source_frame", layer, data, frame, row)):
            layer.region_rect = rect
        # Codec bakes frame ox/oy into the atlas. Do not add new per-frame offsets.
        layer.position = Vector2.ZERO
        if phase == "end":
            layer.modulate.a = maxf(0.0, 1.0 - elapsed / maxf(stage_duration, 0.001))

func _tick_native_formation() -> void:
    var life: float = float(formation_spec.get("life_ticks", 1))
    var radius: float = GEOMETRY.hit_radius_pixels(skill)
    var target_available: bool = _has_live_target()
    for idx in range(formation_starts.size()):
        if formation_contacted.has(idx):
            continue
        var delay: float = float(FORMATION.release_tick(idx, formation_spec))
        var age: float = elapsed * SOURCE_TICK_HZ - delay
        if age < 0.0 or age >= life:
            continue
        var world_pos: Vector2 = FORMATION.point_at(formation_starts[idx], formation_headings[idx], age, formation_spec)
        if target_available and MOTION.segment_hits_circle(formation_last_points[idx], world_pos, _live_target_center(), radius):
            formation_contacted[idx] = true
            formation_hits += 1
            visual_contact = true
            impact_position = _live_target_center()
            contact_world_position = impact_position
            _create_special_impact(impact_position, formation_headings[idx], idx)
            if is_instance_valid(lua_event_layer):
                lua_event_layer.call("emit_parent", "collide", impact_position, formation_headings[idx], idx)
            if not damage_done:
                damage_done = true
                _apply_demo_damage()  # One QA hit per cast; TV damage unchanged.
        formation_last_points[idx] = world_pos

func _update_native_formation_sprites(layers: Array, source_data: Dictionary) -> void:
    var dirs: int = maxi(1, int(source_data.get("directions", 1)))
    var frames: int = maxi(1, int(source_data.get("frames_per_direction", 1)))
    var meta: Dictionary = _anim_meta("fly")
    frames = mini(frames, maxi(1, int(meta.get("frames", frames))))
    var ticks_per_frame: int = maxi(1, int(meta.get("ticks", 1)))
    var tile: int = maxi(1, int(source_data.get("tile_size", source_data.get("tile", 256))))
    var life: float = float(formation_spec.get("life_ticks", 1))
    for idx in range(layers.size()):
        var sprite: Sprite2D = layers[idx] as Sprite2D
        if not is_instance_valid(sprite):
            continue
        var delay: float = float(FORMATION.release_tick(idx, formation_spec))
        var age: float = elapsed * SOURCE_TICK_HZ - delay
        sprite.visible = age >= 0.0 and age < life and not formation_contacted.has(idx)
        if not sprite.visible:
            continue
        var frame: int = posmod(int(age / float(ticks_per_frame)), frames)
        var row: int = DIRECTION.row_from_vector(formation_headings[idx], dirs)
        if asset_resolver == null or not bool(asset_resolver.call("draw_source_frame", sprite, source_data, frame, row)):
            sprite.region_rect = Rect2(frame * tile, row * tile, tile, tile)
        sprite.position = to_local(FORMATION.point_at(formation_starts[idx], formation_headings[idx], age, formation_spec))

func _create_special_impact(point: Vector2, direction: Vector2, ordinal: int) -> void:
    if not source_stages.has("hit") and not source_stages.has("travel_end"):
        special_hit_visuals_missing += 1
        print("V44.8 IMPACT SPR MISSING | skill=", int(skill.get("legacy_skill_id", 0)), " | missile=", ordinal)
        return
    var impact := Node2D.new()
    impact.name = "OriginalHit_%d_Missile_%d" % [int(skill.get("legacy_skill_id", 0)), ordinal]
    impact.set_script(SPECIAL_IMPACT)
    # The impact is a sibling, so it survives the parent missile's vanish.
    get_parent().add_child(impact)
    impact.call("setup", source_stages, skill, point, direction, asset_resolver)
    special_hit_visuals_created += 1
    print("V44.8 MISSILE CONTACT | skill=", int(skill.get("legacy_skill_id", 0)),
        " | missile=", ordinal, " | vfx=original_spr", " | pos=", point)

func _update_rollback_sprites(layers: Array, source_data: Dictionary) -> void:
    var dirs: int = maxi(1, int(source_data.get("directions", 1)))
    var frames: int = maxi(1, int(source_data.get("frames_per_direction", 1)))
    var meta: Dictionary = _anim_meta("fly")
    frames = mini(frames, maxi(1, int(meta.get("frames", frames))))
    var ticks_per_frame: int = maxi(1, int(meta.get("ticks", 1)))
    var tile: int = maxi(1, int(source_data.get("tile_size", source_data.get("tile", 256))))
    var speed: float = GEOMETRY.flight_speed_pixels(skill)
    if speed <= 0.01:
        speed = 315.0 # Adjustable QA speed, NOT literal JX unit conversion.
    var lifetime: float = float(special_spec.get("missile_lifetime_ticks", 32))
    for idx in range(layers.size()):
        var sprite: Sprite2D = layers[idx] as Sprite2D
        if not is_instance_valid(sprite):
            continue
        var start_ticks: float = SPECIAL.release_tick(idx, displayed_count,
            int(special_spec.get("generate_style", 0)), int(special_spec.get("wait_ticks", 0)),
            int(special_spec.get("generate_step_ticks", 0)))
        var age_ticks: float = elapsed * SOURCE_TICK_HZ - start_ticks
        sprite.visible = age_ticks >= 0.0 and age_ticks < lifetime
        if not sprite.visible:
            continue
        var age_frame: int = mini(frames - 1, int(age_ticks / float(ticks_per_frame)))
        age_frame = posmod(age_frame, frames)
        var outbound: bool = age_ticks < lifetime * 0.5
        var render_heading: Vector2 = special_headings[idx] if outbound else -special_headings[idx]
        var row: int = DIRECTION.row_from_vector(render_heading, dirs)
        if asset_resolver == null or not bool(asset_resolver.call("draw_source_frame", sprite, source_data, age_frame, row)):
            sprite.region_rect = Rect2(age_frame * tile, row * tile, tile, tile)
        var world_pos: Vector2 = SPECIAL.rollback_position(flight_start, special_headings[idx],
            age_ticks, lifetime, speed)
        sprite.position = to_local(world_pos)

func _has_live_target() -> bool:
    if not is_instance_valid(dummy):
        return false
    if dummy.has_method("is_alive"):
        return bool(dummy.call("is_alive"))
    return true

func _live_target_center() -> Vector2:
    if not is_instance_valid(dummy):
        return flight_target
    return dummy.global_position + Vector2(0.0, -45.0)

func _evaluate_stationary_contact() -> void:
    # This is QA-only impact geometry. Unsupported MoveKinds never fabricate
    # a registered target contact or target damage.
    strike_checked = true
    if flight_mode != "stationary" and flight_mode != "straight":
        return
    if not _has_live_target():
        return
    var center: Vector2 = _live_target_center()
    var radius: float = maxf(1.0, GEOMETRY.hit_radius_pixels(skill))
    var reference: Vector2 = flight_target
    if flight_mode == "straight":
        reference = global_position
    if center.distance_to(reference) <= radius:
        visual_contact = true
        impact_position = center
        contact_world_position = center

func _apply_demo_damage() -> void:
    if diagnostic_only or not visual_contact or not _has_live_target():
        return
    if not bool(skill.get("target_enemy", true)):
        return
    if dummy.has_method("take_damage"):
        dummy.call("take_damage", 10) # Exactly one DEMO hit; not native JX damage.

func _draw() -> void:
    if not show_debug_overlay:
        return
    var color: Color = Color(1.0, 0.5, 0.2, 0.7) if asset_notice != "SOURCE_SPR_LOADED" else Color(0.4, 1.0, 0.65, 0.7)
    draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, color, 2.0)

func get_diagnostic() -> Dictionary:
    return {"school": school_id, "skill_id": int(skill.get("legacy_skill_id", 0)),
        "source_spr_available": not source_stages.is_empty(),
        "source_fly_loaded": source_stages.has("fly"),
        "source_hit_loaded": source_stages.has("hit"),
        "source_precast_loaded": source_stages.has("precast"),
        "source_travel_end_loaded": source_stages.has("travel_end"),
        "asset_notice": asset_notice, "stage": phase,
        "loaded_roles": source_stages.keys(), "missing_paths": missing_paths,
        "declared_children": source_count, "displayed_children": displayed_count,
        "formation_missing": source_count > displayed_count,
        "formation_verified": formation_verified, "damage_verified": false, "preview": true,
        "motion_mode": flight_mode, "special_motion_from_source": not special_spec.is_empty(),
        "special_contact_count": special_contacted.size(),
        "special_hit_visuals_created": special_hit_visuals_created,
        "special_hit_visuals_missing": special_hit_visuals_missing,
        "source_style_melee_manyattack": int(skill.get("source_missles_form", -1)) == 12,
        "v449_formation_enabled": formation_enabled,
        "v449_formation_form": int(formation_spec.get("form", -1)),
        "v449_formation_hit_count": formation_hits,
        "visual_contact": visual_contact,
        "impact_position": impact_position, "native_trajectory_verified": false}
