extends Node2D

## V6.3 gameplay FX: source SPR preferred, old PNG atlas only when decoding
## fails. Cast, flight and impact are distinct phases. Damage remains DEMO.
const TILE: int = 256
var caster: CharacterBody2D
var dummy: StaticBody2D
var target: Vector2 = Vector2.ZERO
var launch_point: Vector2 = Vector2.ZERO
var skill: Dictionary = {}
var direction: int = 0
var stage: String = "cast"
var elapsed: float = 0.0
var travel_seconds: float = 0.1
var vfx_library: Dictionary = {}
var current_vfx: Dictionary = {}
var hit_registered: bool = false
var effect_sprite: Sprite2D
var asset_resolver: RefCounted
var diagnostic_only: bool = false
var show_debug_overlay: bool = false
var last_sprite_source: String = ""
var active_frame: int = 0
var active_row: int = 0
var melee_attached: bool = false
var melee_hit_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
    var manifest: String = "res://assets/vfx/manifest.json"
    if FileAccess.file_exists(manifest):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
        if parsed is Dictionary:
            vfx_library = parsed
    effect_sprite = Sprite2D.new()
    effect_sprite.name = "DataDrivenVFX"
    effect_sprite.region_enabled = true
    effect_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    add_child(effect_sprite)
    z_index = 5

func setup(source: CharacterBody2D, practice_dummy: StaticBody2D, destination: Vector2, skill_data: Dictionary, face_dir: int, resolver: RefCounted = null, preview_only: bool = false) -> void:
    caster = source
    dummy = practice_dummy
    asset_resolver = resolver
    skill = skill_data
    direction = posmod(face_dir, 8)
    target = destination
    diagnostic_only = preview_only
    melee_attached = str(skill.get("combat_delivery", "")) == "melee_attached"
    melee_hit_pos = _melee_target_position() if melee_attached else destination
    stage = "cast"
    elapsed = 0.0
    hit_registered = false
    global_position = _muzzle_position()
    launch_point = global_position
    _apply_stage_texture()

func _muzzle_position() -> Vector2:
    if not is_instance_valid(caster):
        return global_position
    # Configurable approximation of the actor's hand socket. The legacy
    # client has its own skeleton/pivot data, not reconstructed here.
    var aim: Vector2 = target - caster.global_position
    if aim.length_squared() < 0.001:
        aim = Vector2.DOWN
    else:
        aim = aim.normalized()
    var side: Vector2 = Vector2(-aim.y, aim.x)
    var forward: float = float(skill.get("socket_forward", 22.0))
    var sideways: float = float(skill.get("socket_x", 0.0))
    var vertical: float = float(skill.get("socket_y", -83.0))
    return caster.global_position + aim * forward + side * sideways + Vector2(0.0, vertical)

func _melee_target_position() -> Vector2:
    if not is_instance_valid(caster):
        return target
    var diff: Vector2 = target - caster.global_position
    var d: Vector2 = diff.normalized() if diff.length_squared() > 0.001 else Vector2.RIGHT
    var reach: float = maxf(35.0, float(skill.get("attack_radius", 72.0)) * 0.78)
    var within: float = minf(reach, diff.length())
    return caster.global_position + d * within + Vector2(0.0, -45.0)

func _process(delta: float) -> void:
    if not is_instance_valid(caster) or effect_sprite == null:
        queue_free()
        return
    elapsed += maxf(delta, 0.0)
    match stage:
        "cast":
            global_position = _muzzle_position()
            var release_sec: float = maxf(0.0, float(skill.get("release_ms", skill.get("cast_ms", 425))) / 1000.0)
            if elapsed >= release_sec:
                launch_point = global_position
                if melee_attached:
                    melee_hit_pos = _melee_target_position()
                    # Only play locally attached slash/sweep if the original 9x
                    # source has one. Never translate it across world space.
                    if str(skill.get("vfx", {}).get("fly", "")).is_empty():
                        global_position = melee_hit_pos
                        _apply_impact()
                        _switch_stage("hit")
                    else:
                        _switch_stage("fly")
                else:
                    travel_seconds = maxf(0.075, launch_point.distance_to(target) / maxf(1.0, float(skill.get("fly_speed", 900))))
                    _switch_stage("fly")
        "fly":
            if melee_attached:
                global_position = _melee_target_position()
            else:
                global_position = launch_point.lerp(target, clampf(elapsed / travel_seconds, 0.0, 1.0))
            if elapsed >= (maxf(0.12, _animation_duration()) if melee_attached else travel_seconds):
                global_position = _melee_target_position() if melee_attached else target
                _apply_impact()
                _switch_stage("hit")
        "hit":
            # Impact plays once, not a constantly cycling sprite. Hold its
            # final frame until the test hit stage ends.
            if melee_attached:
                global_position = _melee_target_position()
            var requested: float = float(skill.get("hit_ms", 450)) / 1000.0
            if elapsed >= maxf(requested, _animation_duration()):
                _switch_stage("end")
        "end":
            var fade_seconds: float = maxf(0.001, float(skill.get("end_ms", 250)) / 1000.0)
            effect_sprite.modulate.a = 1.0 - clampf(elapsed / fade_seconds, 0.0, 1.0)
            if elapsed >= fade_seconds:
                queue_free()
    _render_frame()
    if show_debug_overlay:
        queue_redraw()

func _apply_impact() -> void:
    if hit_registered or not is_instance_valid(dummy):
        return
    hit_registered = true
    if diagnostic_only or bool(skill.get("target_self", false)):
        return
    var hit_point: Vector2 = dummy.global_position + Vector2(0, -45)
    var contact: Vector2 = global_position if melee_attached else target
    if contact.distance_to(hit_point) <= float(skill.get("hit_radius", 120)):
        if dummy.has_method("take_damage"):
            dummy.call("take_damage", int(skill.get("damage", 100)))

func _switch_stage(next_stage: String) -> void:
    stage = next_stage
    elapsed = 0.0
    if stage == "end":
        # Keep the final impact image visible while fading out. Do not reload
        # AnimFile4 and replay its first frame for a second impact.
        return
    _apply_stage_texture()

func _apply_stage_texture() -> void:
    var effects: Dictionary = skill.get("vfx", {})
    var fx_key: String = str(effects.get(stage, ""))
    current_vfx = vfx_library.get(fx_key, {})
    last_sprite_source = "FALLBACK_ATLAS" if not current_vfx.is_empty() else "NO_TEXTURE"
    var virtual_sprite: String = ""
    var missile_paths: Array = skill.get("original_missile_spr", [])
    if missile_paths.size() >= 4:
        if stage == "fly":
            virtual_sprite = str(missile_paths[1]) if not str(missile_paths[1]).is_empty() else str(missile_paths[0])
        elif stage == "hit":
            virtual_sprite = str(missile_paths[3]) if not str(missile_paths[3]).is_empty() else str(missile_paths[2])
    if stage == "cast":
        virtual_sprite = str(skill.get("original_precast_spr", ""))
    var decoded: Dictionary = {}
    if asset_resolver != null and not virtual_sprite.is_empty():
        decoded = asset_resolver.call("load_spr", virtual_sprite)
    if not decoded.is_empty():
        current_vfx = decoded
        effect_sprite.texture = decoded.get("texture") as Texture2D
        var loc: Dictionary = decoded.get("source", {})
        last_sprite_source = str(loc.get("pak", loc.get("file", "PAK_OR_LOOSE"))).get_file()
    else:
        var path: String = str(current_vfx.get("file", ""))
        if not path.is_empty():
            effect_sprite.texture = load(path) as Texture2D
        else:
            effect_sprite.texture = null
    effect_sprite.visible = effect_sprite.texture != null
    effect_sprite.modulate.a = 1.0
    _render_frame()

# Server CTC KMissleRes::Draw / KMissle::CreateSpecialEffect use
# AnimFileInfoN = total_frames,directions,interval_legacy_ticks.
# Server baseline Common.AttackFrame=18, so 1 tick ~= 55.56ms.
# Do not use raw SPR frame count when the missile setting specifies fewer.
func _source_stage_meta() -> Dictionary:
    var info: Dictionary = skill.get("original_anim_info", {})
    var key: String = "hit" if stage == "end" else stage
    var value: String = str(info.get(key, ""))
    var fields: PackedStringArray = value.split(",", false)
    if fields.size() != 3:
        return {}
    for field in fields:
        if not field.strip_edges().is_valid_int():
            return {}
    var total: int = int(fields[0].strip_edges())
    var dirs: int = int(fields[1].strip_edges())
    var ticks: int = int(fields[2].strip_edges())
    if total < 1 or dirs < 1 or total % dirs != 0 or ticks < 1:
        return {}
    return {"frames": total / dirs, "dirs": dirs, "ticks": ticks, "total": total}

func _stage_frame_count() -> int:
    var source_frames: int = maxi(1, int(current_vfx.get("frames_per_direction", 1)))
    var metadata: Dictionary = _source_stage_meta()
    if metadata.is_empty():
        return source_frames
    return mini(source_frames, maxi(1, int(metadata.get("frames", 1))))

func _stage_frame_interval_ms() -> float:
    var metadata: Dictionary = _source_stage_meta()
    if not metadata.is_empty():
        return 1000.0 * float(metadata.get("ticks", 1)) / 18.0
    return maxf(20.0, float(current_vfx.get("anim_ms", 65)))

func _animation_duration() -> float:
    if current_vfx.is_empty():
        return 0.0
    return float(_stage_frame_count()) * _stage_frame_interval_ms() / 1000.0

func _render_frame() -> void:
    if effect_sprite == null or effect_sprite.texture == null or current_vfx.is_empty():
        return
    var count: int = _stage_frame_count()
    var directions: int = maxi(1, int(current_vfx.get("directions", 1)))
    var interval: float = _stage_frame_interval_ms()
    var index: int = int(elapsed * 1000.0 / interval)
    if stage == "hit" or stage == "end":
        active_frame = mini(index, count - 1) if stage == "hit" else count - 1
    else:
        active_frame = posmod(index, count)
    active_row = 0
    if directions == 32:
        active_row = posmod(direction * 4, directions)
    elif directions == 16:
        active_row = posmod(direction * 2, directions)
    elif directions > 1:
        active_row = posmod(direction, directions)
    var tile: int = int(current_vfx.get("tile_size", current_vfx.get("tile", TILE)))
    effect_sprite.region_rect = Rect2(active_frame * tile, active_row * tile, tile, tile)

func get_diagnostic() -> Dictionary:
    return {"skill": str(skill.get("id", "")), "stage": stage, "delivery": "MELEE_9X" if melee_attached else "PROJECTILE",
        "frame": active_frame + 1,
        "frames": _stage_frame_count(),
        "ctc_frame_ms": int(round(_stage_frame_interval_ms())),
        "source_frames": maxi(1, int(current_vfx.get("frames_per_direction", 1))),
        "direction": active_row,
        "directions": maxi(1, int(current_vfx.get("directions", 1))),
        "sprite_source": last_sprite_source,
        "preview_only": diagnostic_only}

func _draw() -> void:
    if not show_debug_overlay:
        return
    var end_local: Vector2 = to_local(target)
    draw_line(Vector2.ZERO, end_local, Color(0.2, 0.95, 0.95, 0.5), 1.5)
    draw_arc(Vector2.ZERO, 12, 0.0, TAU, 24, Color(1.0, 0.7, 0.2, 0.8), 1.5)
    draw_arc(end_local, 10, 0.0, TAU, 24, Color(0.2, 1.0, 0.6, 0.8), 1.5)
