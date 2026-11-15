extends Node2D

## V6.7 Thiên Vương 9x: server-verified DoManyAttack and 3/5/3 missile ALLOCATIONS.
## Visual offsets, 18Hz preview animation and practice-dummy damage are DEMO.
## V37: blade 322 missile-138 hit AnimFile4 is rendered on V22 CONTACT, not allocation.
## No claim of exact JX projectile physics or real HP damage.
const TIMELINE = preload("res://scripts/CTC9XTimeline.gd")
const BLADE_PRESENTATION = preload("res://scripts/Blade322Afterimages.gd")
# JXNHALAM TVC325: 3 independent M141 FLY sprites; no fixed near-target sweep.
const M141_RUNTIME = preload("res://scripts/JX141MissileVisualV3.gd")
const M139_RUNTIME_PATH: String = "res://scripts/JX139SpearFlight.gd"
const SPRITE_FALLBACK_MANIFEST: String = "res://assets/vfx/manifest.json"
const LIVE_SPR_LIMIT: int = 28

var caster: CharacterBody2D
var dummy: StaticBody2D
var target: Vector2
var skill: Dictionary = {}
var direction: int = 0
var asset_resolver: RefCounted
var diagnostic_only: bool = false
var show_debug_overlay: bool = false
var timeline: Dictionary = {}
var clock_tick: int = -1
var accumulator: float = 0.0
var event_cursor: int = 0
var spawned_total: int = 0
var finished_total: int = 0
var registered_damage: bool = false
# V22: collision and HP owned by main-scene V22MainCombat, not timeline distance guess.
var external_collision_authority: bool = false
var rendered_total: int = 0
var particles: Array[Dictionary] = []
var atlas_cache: Dictionary = {}
var fallback_manifest: Dictionary = {}
var last_sprite_source: String = ""
var last_stage: String = "WAIT"
var last_tick: int = 0
var visual_calibration: Dictionary = {"offset_x": 0.0, "offset_y": 0.0, "scale": 1.0}
var blade322_echo_enabled: bool = false
var blade_presentation: Node2D
var native141_v3: Node2D # Main binds one cast_key to the three visual allocations.
var native139_preview: Node2D # 323 has five independent sequential M139 allocations.

func set_calibration(data: Dictionary) -> void:
    visual_calibration = {
        "offset_x": clampf(float(data.get("offset_x", 0.0)), -160.0, 160.0),
        "offset_y": clampf(float(data.get("offset_y", 0.0)), -160.0, 160.0),
        "scale": clampf(float(data.get("scale", 1.0)), 0.15, 3.0)
    }
    for item in particles:
        var existing: Sprite2D = item.get("sprite") as Sprite2D
        if is_instance_valid(existing):
            var base_position: Vector2 = item.get("base_position", Vector2.ZERO)
            existing.position = base_position + Vector2(float(visual_calibration["offset_x"]), float(visual_calibration["offset_y"]))
            existing.scale = Vector2.ONE * float(visual_calibration["scale"])

func _ready() -> void:
    z_index = 5
    if FileAccess.file_exists(SPRITE_FALLBACK_MANIFEST):
        var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPRITE_FALLBACK_MANIFEST))
        if decoded is Dictionary:
            fallback_manifest = decoded

func setup(source: CharacterBody2D, practice_dummy: StaticBody2D, destination: Vector2,
        skill_data: Dictionary, face_dir: int, resolver: RefCounted = null,
        preview_only: bool = false) -> void:
    caster = source
    dummy = practice_dummy
    target = destination
    skill = skill_data
    direction = posmod(face_dir, 8)
    asset_resolver = resolver
    diagnostic_only = preview_only
    var base_frames: int = int(source.get("ctc_attack_frame_baseline"))
    if base_frames < 1:
        base_frames = 18
    timeline = TIMELINE.build(skill, base_frames, int(source.get("ctc_attack_speed_percent")))
    clock_tick = -1
    accumulator = 0.0
    event_cursor = 0
    spawned_total = 0
    finished_total = 0
    registered_damage = false
    rendered_total = 0
    last_sprite_source = "WAIT"
    last_stage = "MANY_ATTACK (VERIFIED ROUTE)"
    if int(skill.get("legacy_skill_id", 0)) == 325:
        native141_v3 = Node2D.new()
        native141_v3.name = "M141_ThreeIndependentMissiles"
        native141_v3.set_script(M141_RUNTIME)
        add_child(native141_v3)
        native141_v3.call("configure", caster, target, direction)
    if int(skill.get("legacy_skill_id", 0)) == 323:
        # Resolve optional M139 renderer only when SPEAR is cast. A bad optional
        # renderer must not prevent CTC9XCombatEffect from parsing for 322/325.
        var runtime_resource: Resource = load(M139_RUNTIME_PATH)
        if runtime_resource is Script:
            native139_preview = Node2D.new()
            native139_preview.name = "M139_FiveSequentialMissiles"
            native139_preview.set_script(runtime_resource)
            add_child(native139_preview)
            var paths: Array = skill.get("original_missile_spr", [])
            var fly_spr: String = ""
            if paths.size() > 1:
                fly_spr = str(paths[1])
            native139_preview.call("configure", caster, target, direction, asset_resolver, fly_spr)
        else:
            push_warning("TVC323: M139 optional renderer failed; CTC timeline is still active")
    # Dispatch tick-zero visuals immediately; waiting until the first physics
    # update would add an artificial 55 ms to skills with zero delay.
    # Preview never moves the actor or subtracts mana / dummy HP.
    _tick()
    # V37: native seven-slot pose history via MaxShadowNum gate (EXE V12).
    # The Godot render callback cadence is an approximation; combat unchanged.
    if int(skill.get("legacy_skill_id", 0)) == 322:
        blade_presentation = Node2D.new()
        blade_presentation.name = "Blade322Afterimages"
        blade_presentation.set_script(BLADE_PRESENTATION)
        add_child(blade_presentation)
        # G toggles render-call history snapshots (7 slots; alpha 0x80; fade 0x10).
        # Snapshots keep world coordinates captured at that instant; no fake drift.
        var seconds: float = maxf(0.20, float(caster.get("blade322_combo_duration")))
        blade_presentation.call("configure", caster, target, direction, seconds)
        blade_presentation.call("set_enabled", blade322_echo_enabled)

func set_blade_echo_enabled(value: bool) -> void:
    blade322_echo_enabled = value
    if is_instance_valid(blade_presentation) and blade_presentation.has_method("set_enabled"):
        blade_presentation.call("set_enabled", value)

func _process(delta: float) -> void:
    if not is_instance_valid(caster):
        queue_free()
        return
    accumulator += maxf(0.0, delta)
    var dt: float = 1.0 / TIMELINE.TICK_HZ
    var catchup: int = 0
    while accumulator >= dt and catchup < 48:
        accumulator -= dt
        catchup += 1
        _tick()
    # Inspect child renderers separately. No typed casts or nested boolean
    # expressions on Variant-returning calls: this is Godot 4.6 parser-safe.
    if clock_tick > int(timeline.get("duration_ticks", 1)):
        var m139_active: bool = false
        if is_instance_valid(native139_preview):
            var m139_status: Variant = native139_preview.call("diagnostic")
            if m139_status is Dictionary:
                m139_active = int(m139_status.get("flying", 0)) > 0
        var m141_active: bool = false
        if is_instance_valid(native141_v3):
            var m141_status: Variant = native141_v3.call("diagnostic")
            if m141_status is Dictionary:
                m141_active = int(m141_status.get("active_fly", 0)) > 0 or int(m141_status.get("impact_sprites", 0)) > 0
        if particles.is_empty() and not is_instance_valid(blade_presentation) and not m139_active and not m141_active:
            queue_free()
    if show_debug_overlay:
        queue_redraw()

func _tick() -> void:
    clock_tick += 1
    last_tick = clock_tick
    if not registered_damage and clock_tick >= int(timeline.get("practice_damage_tick", 100000)):
        _apply_practice_damage_once()
    var events: Array = timeline.get("events", [])
    while event_cursor < events.size() and int(events[event_cursor].get("tick", -1)) <= clock_tick:
        _emit_missile(events[event_cursor])
        event_cursor += 1
    for i in range(particles.size() - 1, -1, -1):
        var particle: Dictionary = particles[i]
        var sprite: Sprite2D = particle.get("sprite") as Sprite2D
        if sprite == null or not is_instance_valid(sprite):
            particles.remove_at(i)
            continue
        var age: int = clock_tick - int(particle.get("born", clock_tick))
        var frames: int = int(particle.get("frames", 1))
        var interval: int = maxi(1, int(particle.get("interval", 1)))
        var frame: int = mini(frames - 1, floori(float(age) / float(interval)))
        var dir_row: int = int(particle.get("direction", 0))
        var tile: int = int(particle.get("tile", 256))
        sprite.region_rect = Rect2(frame * tile, dir_row * tile, tile, tile)
        sprite.modulate.a = 1.0
        if age >= frames * interval:
            sprite.queue_free()
            particles.remove_at(i)
            finished_total += 1

func _apply_practice_damage_once() -> void:
    registered_damage = true
    # Exactly ONE dummy-damage demonstration per cast, regardless of allocation
    # count. This is neither a server hit nor HP inferred from ProcessDamage.
    if external_collision_authority or diagnostic_only or not is_instance_valid(dummy):
        return
    var hit_point: Vector2 = dummy.global_position + Vector2(0, -45)
    if caster.global_position.distance_to(hit_point) <= float(skill.get("hit_radius", 92)) + 60.0:
        if dummy.has_method("take_damage"):
            dummy.call("take_damage", int(skill.get("damage", 0)))

func _emit_missile(event: Dictionary) -> void:
    spawned_total += 1
    last_stage = "ALLOCATED M%d" % int(event.get("missile_id", 0))
    if int(skill.get("legacy_skill_id", 0)) == 325 and int(event.get("missile_id", 0)) == 141:
        # One CTC timeline event -> exactly one independent missile 141.
        # The child has its own dir64, flight clock, position, sprite frame and HIT.
        # Never also draw the old three stationary near-target SWEEP sprites.
        if is_instance_valid(native141_v3):
            native141_v3.call("emit_allocation", event)
        else:
            push_error("TVC325: M141 visual bridge not initialized")
        return
    if int(skill.get("legacy_skill_id", 0)) == 323 and int(event.get("missile_id", 0)) == 139:
        if is_instance_valid(native139_preview):
            native139_preview.call("emit_allocation", event)
        else:
            push_error("TVC323: M139 visual bridge not initialized")
        return
    # V12 native: missile 138 stage-3 AnimFile4 is generated at CONTACT,
    # not when three missiles are allocated. Main receives V22 contact signal.
    # F7 pure-preview keeps the former sprite view for asset inspection.
    if int(skill.get("legacy_skill_id", 0)) == 322 and not diagnostic_only:
        last_stage = "M138 ALLOCATED; AnimFile4 VFX ON CONTACT (V37)"
        return
    # 323/M139 and 325/M141 use AnimFile4 as hit-stage *table assets*.
    # Their event/anchor in this Godot demo remains unverified. Do not display
    # a target impact at allocation time before a V22 CONTACT occurred.
    var active_id: int = int(skill.get("legacy_skill_id", 0))
    if active_id == 323 and not diagnostic_only:
        last_stage = "M139 ALLOCATED; HIT VISUAL ON DEMO CONTACT (V40)"
        return
    # Chùy 325/M141 still plays its AnimFile2 sweep on allocation (VISUAL
    # PREVIEW). Its separate AnimFile4 impact plays only after demo contact.
    if particles.size() >= LIVE_SPR_LIMIT:
        return
    var use_sweep: bool = int(skill.get("legacy_skill_id", 0)) == 325
    var visual: Dictionary = _get_visual("fly" if use_sweep else "hit")
    if visual.is_empty():
        return
    var texture: Texture2D = visual.get("texture") as Texture2D
    if texture == null:
        return
    var dirs: int = maxi(1, int(visual.get("directions", 1)))
    var available_frames: int = maxi(1, int(visual.get("frames_per_direction", 1)))
    var info: Dictionary = _parse_anim_file_info("fly" if use_sweep else "hit")
    var declared_frames: int = int(info.get("frames", available_frames))
    var frames: int = mini(available_frames, maxi(1, declared_frames))
    var interval_ticks: int = maxi(1, int(info.get("ticks", 1)))
    var sub_index: int = int(event.get("sub_index", 0))
    var sub_count: int = int(event.get("sub_count", 1))
    var formation: int = int(event.get("formation", -1))
    var atlas_row: int = 0
    if dirs == 32:
        atlas_row = posmod(direction * 4, dirs)
        if formation == 2:
            atlas_row = posmod(atlas_row + sub_index - floori(float(sub_count - 1) / 2.0), dirs)
    elif dirs == 16:
        atlas_row = posmod(direction * 2, dirs)
    elif dirs > 1:
        atlas_row = posmod(direction, dirs)
    var sprite := Sprite2D.new()
    sprite.region_enabled = true
    sprite.texture = texture
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    var tile: int = int(visual.get("tile_size", visual.get("tile", 256)))
    sprite.region_rect = Rect2(0, atlas_row * tile, tile, tile)
    var display_index: int = int(event.get("display_index", sub_index))
    var display_count: int = int(event.get("display_count", sub_count))
    var base_position: Vector2 = _local_missile_offset(formation, display_index, display_count)
    sprite.position = base_position + Vector2(float(visual_calibration["offset_x"]), float(visual_calibration["offset_y"]))
    sprite.scale = Vector2.ONE * float(visual_calibration["scale"])
    add_child(sprite)
    rendered_total += 1
    particles.append({"sprite": sprite, "born": clock_tick, "frames": frames,
        "interval": interval_ticks, "tile": tile, "direction": atlas_row, "base_position": base_position})

func _local_missile_offset(formation: int, index: int, count: int) -> Vector2:
    # Godot local space is the same world coordinates as parent Main.
    # Distinct sprite previews keep allocation count observable.
    # These INSPECTION-SCALE OFFSETS are NOT JX collision/hit geometry.
    var raw: Vector2 = target - caster.global_position
    var aim: Vector2 = raw.normalized() if raw.length_squared() > 0.1 else Vector2.RIGHT
    var side: Vector2 = Vector2(-aim.y, aim.x)
    var centered: float = float(index) - float(count - 1) * 0.5
    var near: Vector2 = caster.global_position + aim * minf(60.0, raw.length())
    if is_instance_valid(dummy) and target.distance_to(dummy.global_position) < 180:
        near = dummy.global_position + Vector2(0, -45)
    match formation:
        0: return near + side * centered * 22.0 # KSkill::CastWall
        1: return near + aim * float(index + 1) * 7.0 # KSkill::CastLine
        2: return near + side * centered * 26.0 + aim * absf(centered) * 7.0 # KSkill::CastSpread
        _: return near

func _parse_anim_file_info(stage: String) -> Dictionary:
    var info: Dictionary = skill.get("original_anim_info", {})
    var s: String = str(info.get(stage, ""))
    var raw: PackedStringArray = s.split(",", false)
    if raw.size() != 3:
        return {}
    for val in raw:
        if not val.strip_edges().is_valid_int():
            return {}
    var total: int = int(raw[0].strip_edges())
    var dirs: int = maxi(1, int(raw[1].strip_edges()))
    var tick_interval: int = maxi(1, int(raw[2].strip_edges()))
    if total < 1 or total % dirs != 0:
        return {}
    return {"frames": floori(float(total) / float(dirs)), "directions": dirs, "ticks": tick_interval}

func _get_visual(stage: String) -> Dictionary:
    if atlas_cache.has(stage):
        return atlas_cache[stage]
    var paths: Array = skill.get("original_missile_spr", [])
    var virtual_path: String = ""
    if paths.size() >= 4:
        if stage == "fly":
            virtual_path = str(paths[1]) if not str(paths[1]).is_empty() else str(paths[0])
        elif stage == "hit":
            virtual_path = str(paths[3]) if not str(paths[3]).is_empty() else str(paths[2])
    var data: Dictionary = {}
    if asset_resolver != null and not virtual_path.is_empty():
        data = asset_resolver.call("load_spr", virtual_path)
    if not data.is_empty():
        last_sprite_source = str(data.get("source", {}).get("kind", "SPR"))
        atlas_cache[stage] = data
        return data
    var vfx: Dictionary = skill.get("vfx", {})
    var key: String = str(vfx.get("fly" if stage == "fly" else "hit", ""))
    var fallback: Dictionary = fallback_manifest.get(key, {})
    if not fallback.is_empty():
        var path: String = str(fallback.get("file", ""))
        if not path.is_empty():
            var texture: Texture2D = load(path) as Texture2D
            if texture != null:
                data = fallback.duplicate(true)
                data["texture"] = texture
                last_sprite_source = "SOURCE_SPR_ATLAS" if str(fallback.get("original_spr_sha256", "")) != "" else "PNG_FALLBACK"
    atlas_cache[stage] = data
    return data

func get_diagnostic() -> Dictionary:
    var m141_visual: Dictionary = {}
    if is_instance_valid(native141_v3):
        var m141_status: Variant = native141_v3.call("diagnostic")
        if m141_status is Dictionary:
            m141_visual = m141_status
    var m139_visual: Dictionary = {}
    if is_instance_valid(native139_preview):
        var m139_status: Variant = native139_preview.call("diagnostic")
        if m139_status is Dictionary:
            m139_visual = m139_status
    return {"m141_native_v3": m141_visual, "m139_preview": m139_visual, "skill": str(skill.get("legacy_skill_id", "")),
        "stage": last_stage, "frame": spawned_total, "frames": int(timeline.get("total_missiles", 0)),
        "ctc_frame_ms": int(round(1000.0 / TIMELINE.TICK_HZ)),
        "direction": direction, "directions": 8,
        "sprite_source": last_sprite_source, "event_tick": last_tick,
        "active_missiles": particles.size(), "preview_only": diagnostic_only,
        "qa_calibration": visual_calibration,
        "rendered_total": rendered_total, "combat_route": timeline.get("combat_route", "?"),
        "blade_presentation": blade_presentation.call("diagnostic") if is_instance_valid(blade_presentation) else {},
        "tick_verified": false, "damage_verified": false}

func _draw() -> void:
    if not show_debug_overlay:
        return
    if not is_instance_valid(caster):
        return
    var from: Vector2 = to_local(caster.global_position + Vector2(0, -70))
    var at: Vector2 = to_local(target)
    draw_line(from, at, Color(0.5, 1.0, 0.9, 0.4), 1.0)
    draw_arc(at, 9.0, 0.0, TAU, 20, Color(0.8, 0.8, 0.25, 0.7))
