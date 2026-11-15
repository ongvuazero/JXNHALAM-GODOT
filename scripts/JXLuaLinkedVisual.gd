extends Node2D
## V44.3 - source-only visual for a Lua-triggered child skill.
## All stage SPRs come from the JX skill/missile tables. No synthesized FX.
## This is a QA renderer: no HP, mana, native collision or damage authority.
## The child start/fly/collide/vanish graph is from Lua; actual timing and
## velocity are still approximations until a client trace is available.
signal source_event(skill_id, trigger, world_position, direction, ancestry)

const DIRECTION = preload("res://scripts/JXSPRDirection.gd")
const MOTION = preload("res://scripts/JXMissileMotion.gd")
const LOGIC_HZ: float = 18.0
const MAX_FLIGHT_TIME: float = 2.7
const MAX_TOTAL_TIME: float = 5.0
const DEFAULT_CONTACT_RADIUS: float = 26.0

var skill_data: Dictionary = {}
var resolver: RefCounted
var caster: CharacterBody2D
var target: StaticBody2D
var ancestry: Array = []
var heading: Vector2 = Vector2.RIGHT
var spawn_point: Vector2 = Vector2.ZERO
var locked_point: Vector2 = Vector2.ZERO
var stage: String = ""
var elapsed: float = 0.0
var stage_duration: float = 0.1
var total_elapsed: float = 0.0
var move_kind: int = -1
var sources: Dictionary = {}
var actors: Dictionary = {}
var stage_meta: Dictionary = {}
var active_sprite: Sprite2D
var contact_fired: bool = false
var collision_emitted: bool = false
var fly_event_sent: bool = false
var fly_delay_seconds: float = 0.0
var travel_speed_px: float = 420.0  # QA, not JX pixels/second.
var follow_turn_rate: float = 9.0  # QA, not native steering.
var contact_radius: float = DEFAULT_CONTACT_RADIUS
var finished: bool = false
var entry_trigger: String = "start"

func setup(data: Dictionary, source: CharacterBody2D, live_target: StaticBody2D,
        world_origin: Vector2, facing: Vector2, asset_reader: RefCounted,
        source_ancestry: Array, qa_speed: float = 420.0, qa_turn: float = 9.0,
        qa_level: int = 20, parent_trigger: String = "start") -> void:
    skill_data = data
    caster = source
    target = live_target
    resolver = asset_reader
    ancestry = source_ancestry.duplicate()
    entry_trigger = parent_trigger
    spawn_point = world_origin
    locked_point = _target_center() if _has_live_target() else world_origin
    global_position = world_origin
    heading = facing.normalized() if facing.length_squared() > 0.001 else Vector2.RIGHT
    if (locked_point - world_origin).length_squared() > 1.0:
        heading = (locked_point - world_origin).normalized()
    move_kind = int(data.get("move_kind", -1))
    var ticks_by_level: Dictionary = data.get("fly_event_ticks_levels", {})
    var raw_ticks: int = maxi(0, int(ticks_by_level.get(str(qa_level), data.get("fly_event_time_raw", 0))))
    fly_delay_seconds = float(raw_ticks) / LOGIC_HZ
    travel_speed_px = clampf(qa_speed, 50.0, 1800.0)
    follow_turn_rate = clampf(qa_turn, 1.0, 20.0)

    # Source mappings: precast = PreCastSpr or AnimFile1; fly = AnimFile2;
    # travel_end = AnimFile3; hit = AnimFile4. Missing stages remain absent.
    var paths: Array = data.get("anim_paths", [])
    var precast_path: String = str(data.get("precast_spr", ""))
    if precast_path.is_empty() and paths.size() > 0:
        precast_path = str(paths[0])
    _load_source("precast", precast_path, 0)
    _load_source("fly", str(paths[1]) if paths.size() > 1 else "", 1)
    _load_source("travel_end", str(paths[2]) if paths.size() > 2 else "", 2)
    _load_source("hit", str(paths[3]) if paths.size() > 3 else "", 3)
    z_as_relative = false
    z_index = 7

    # A child skill can have an event graph even when its visual asset is
    # missing: report that fact; do not manufacture a surrogate SPR.
    if sources.is_empty():
        print("V44.3 LUA LINK ALL SPR MISSING | skill=", int(data.get("skill_id", 0)),
            " | source=", data.get("lua_script", ""))
        _finish()
        return

    # Event start belongs to the child skill lifecycle, not a fake HIT.
    source_event.emit(int(data.get("skill_id", 0)), "start", spawn_point, heading, ancestry)
    if entry_trigger == "collide":
        # A collide-linked child should not replay an unrelated precast from
        # another skill table. Start at the contact point using the most local
        # stage available, and propagate a real collide event once.
        contact_fired = true
        _emit_collision_once()
        if sources.has("travel_end"):
            _enter_stage("travel_end")
        elif sources.has("hit"):
            _enter_stage("hit")
        elif sources.has("fly"):
            _enter_stage("fly")
        else:
            _finish()
    elif entry_trigger == "vanish":
        # Vanish-linked children are end-of-flight visuals; skip any borrowed
        # caster/precast art and show only terminal stages.
        if sources.has("travel_end"):
            _enter_stage("travel_end")
        elif sources.has("hit"):
            _enter_stage("hit")
        elif sources.has("fly"):
            _enter_stage("fly")
        else:
            _finish()
    elif sources.has("precast"):
        _enter_stage("precast")
    elif sources.has("fly"):
        _enter_stage("fly")
    elif move_kind == 0 and sources.has("travel_end"):
        _enter_stage("travel_end")
    elif sources.has("hit") and _valid_collision_at(world_origin):
        contact_fired = true
        _emit_collision_once()
        _enter_stage("hit")
    else:
        # A HIT-only skill must not pop over a target it never touched.
        _finish()

func _load_source(role: String, path: String, info_index: int) -> void:
    if path.is_empty() or resolver == null:
        return
    var decoded: Dictionary = resolver.call("load_spr", path)
    var texture: Texture2D = decoded.get("texture") as Texture2D
    if texture == null:
        print("V44.3 LUA LINK SPR NOT FOUND | skill=", int(skill_data.get("skill_id", 0)),
            " | role=", role, " | path=", path)
        return
    var spr := Sprite2D.new()
    spr.name = "Lua_%s_%d" % [role, int(skill_data.get("skill_id", 0))]
    spr.texture = texture
    spr.region_enabled = true
    spr.centered = true
    spr.visible = false
    spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(spr)
    actors[role] = spr
    sources[role] = decoded
    var infos: Array = skill_data.get("anim_infos", [])
    var info: String = str(infos[info_index]) if infos.size() > info_index else ""
    var numbers: PackedStringArray = info.split(",", false)
    var frames: int = maxi(1, int(decoded.get("frames_per_direction", 1)))
    var ticks: int = 1
    if numbers.size() == 3 and numbers[0].strip_edges().is_valid_int() and numbers[1].strip_edges().is_valid_int() and numbers[2].strip_edges().is_valid_int():
        var total: int = int(numbers[0])
        var raw_dirs: int = int(numbers[1])
        if raw_dirs > 0 and total > 0 and total % raw_dirs == 0:
            frames = mini(frames, maxi(1, int(total / raw_dirs)))
        ticks = maxi(1, int(numbers[2]))
    stage_meta[role] = {"frames": frames, "ticks": ticks,
        "directions": maxi(1, int(decoded.get("directions", 1))),
        "tile": maxi(1, int(decoded.get("tile_size", decoded.get("tile", 256))))}

func _has_live_target() -> bool:
    if not is_instance_valid(target):
        return false
    if target.has_method("is_alive"):
        return bool(target.call("is_alive"))
    return true

func _target_center() -> Vector2:
    if _has_live_target():
        return target.global_position + Vector2(0.0, -45.0)
    return locked_point

func _valid_collision_at(world_pos: Vector2) -> bool:
    return _has_live_target() and world_pos.distance_to(_target_center()) <= contact_radius

func _enter_stage(next_stage: String) -> void:
    stage = next_stage
    elapsed = 0.0
    for role in actors.keys():
        var sprite: Sprite2D = actors[role] as Sprite2D
        if is_instance_valid(sprite):
            sprite.visible = str(role) == stage
    active_sprite = actors.get(stage) as Sprite2D
    var m: Dictionary = stage_meta.get(stage, {})
    stage_duration = clampf(float(maxi(1, int(m.get("frames", 1))) * maxi(1, int(m.get("ticks", 1)))) / LOGIC_HZ, 0.06, 2.4)
    if next_stage == "fly":
        if move_kind == 1 or move_kind == 5:
            # A projectile can take longer than one sprite animation cycle to
            # reach a target. Its frames repeat but contact still controls HIT.
            var min_travel: float = spawn_point.distance_to(locked_point) / maxf(1.0, travel_speed_px)
            stage_duration = clampf(maxf(stage_duration, min_travel), 0.15, MAX_FLIGHT_TIME)
        elif move_kind != 0:
            # Unknown motion: don't assign a fabricated straight trajectory.
            stage_duration = 0.12
        if fly_delay_seconds <= 0.0:
            _emit_fly_once()
    _update_frame()

func _emit_fly_once() -> void:
    if fly_event_sent:
        return
    fly_event_sent = true
    source_event.emit(int(skill_data.get("skill_id", 0)), "fly", global_position, heading, ancestry)

func _emit_collision_once() -> void:
    if not contact_fired or collision_emitted:
        return
    collision_emitted = true
    source_event.emit(int(skill_data.get("skill_id", 0)), "collide", global_position, heading, ancestry)

func _on_contact(world_pos: Vector2) -> void:
    if contact_fired:
        return
    contact_fired = true
    global_position = world_pos
    _emit_collision_once()
    if sources.has("travel_end"):
        _enter_stage("travel_end")
    elif sources.has("hit"):
        _enter_stage("hit")
    else:
        _finish()

func _finish() -> void:
    if finished:
        return
    finished = true
    source_event.emit(int(skill_data.get("skill_id", 0)), "vanish", global_position, heading, ancestry)
    queue_free()

func _process(delta: float) -> void:
    if finished:
        return
    if not is_instance_valid(caster):
        _finish()
        return
    var dt: float = maxf(0.0, delta)
    elapsed += dt
    total_elapsed += dt
    if total_elapsed >= MAX_TOTAL_TIME:
        _finish()
        return
    match stage:
        "precast":
            global_position = caster.global_position + Vector2(0.0, -55.0)
            if elapsed >= stage_duration:
                if sources.has("fly"):
                    # A child missile launches at the position and heading of
                    # the actual caster at the end of precast.
                    spawn_point = global_position
                    _enter_stage("fly")
                elif move_kind == 0 and sources.has("travel_end"):
                    _enter_stage("travel_end")
                elif sources.has("hit") and _valid_collision_at(global_position):
                    _on_contact(_target_center())
                else:
                    _finish()
                return
        "fly":
            if not fly_event_sent and elapsed >= fly_delay_seconds:
                _emit_fly_once()
            var old_pos: Vector2 = global_position
            if move_kind == 1 or move_kind == 5:
                if move_kind == 5 and not _has_live_target():
                    _finish()  # Follow loses its target; never jumps to a new one.
                    return
                var desired: Vector2 = _target_center() if move_kind == 5 else locked_point
                if move_kind == 5 and (desired - old_pos).length_squared() > 1.0:
                    var target_dir: Vector2 = (desired - old_pos).normalized()
                    heading = Vector2.RIGHT.rotated(lerp_angle(heading.angle(), target_dir.angle(), clampf(dt * follow_turn_rate, 0.0, 1.0)))
                global_position = old_pos + heading * travel_speed_px * dt
                if _has_live_target() and MOTION.segment_hits_circle(old_pos, global_position, _target_center(), contact_radius):
                    _on_contact(_target_center())
                    return
            elif move_kind == 0:
                # Stationary child graphics stay at the Lua event position.
                if _valid_collision_at(global_position):
                    _on_contact(_target_center())
                    return
            if elapsed >= stage_duration:
                _finish()  # No contact -> no fabricated HIT image.
                return
        "travel_end":
            if elapsed >= stage_duration:
                if contact_fired and sources.has("hit"):
                    _enter_stage("hit")
                else:
                    _finish()
                return
        "hit":
            if elapsed >= stage_duration:
                _finish()
                return
        _:
            _finish()
            return
    _update_frame()

func _update_frame() -> void:
    if not is_instance_valid(active_sprite):
        return
    var m: Dictionary = stage_meta.get(stage, {})
    var frames: int = maxi(1, int(m.get("frames", 1)))
    var ticks: int = maxi(1, int(m.get("ticks", 1)))
    var dirs: int = maxi(1, int(m.get("directions", 1)))
    var cell: int = maxi(1, int(m.get("tile", 256)))
    var frame: int = int(elapsed * LOGIC_HZ / float(ticks))
    if stage == "fly" and move_kind in [1, 5]:
        frame = posmod(frame, frames)
    else:
        frame = mini(frames - 1, frame)
    var row: int = DIRECTION.row_from_vector(heading, dirs)
    if resolver == null or not bool(resolver.call("draw_source_frame", active_sprite, sources.get(stage, {}), frame, row)):
        active_sprite.region_rect = Rect2(frame * cell, row * cell, cell, cell)

func visual_available() -> bool:
    return not sources.is_empty()
