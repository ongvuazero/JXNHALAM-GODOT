extends Node2D
## V44.8: standalone impact from ORIGINAL Sprite2D stages.
## Spawned only on actual projectile contact; one instance per missile.
## No synthesized VFX or authority over JX damage/cooldowns.
const GEOMETRY = preload("res://scripts/JXCombatGeometry.gd")
const DIRECTION = preload("res://scripts/JXSPRDirection.gd")
const LOGIC_HZ: float = 18.0

var sources: Dictionary = {}
var skill: Dictionary = {}
var resolver: RefCounted
var heading: Vector2 = Vector2.RIGHT
var stage: String = ""
var elapsed: float = 0.0
var stage_duration: float = 0.1
var sprite: Sprite2D

func setup(source_stages: Dictionary, skill_data: Dictionary, impact_world: Vector2,
        impact_heading: Vector2, asset_reader: RefCounted = null) -> void:
    sources = source_stages
    skill = skill_data
    resolver = asset_reader
    global_position = impact_world
    heading = impact_heading.normalized() if impact_heading.length_squared() > 0.001 else Vector2.RIGHT
    z_as_relative = false
    z_index = 8
    sprite = Sprite2D.new()
    sprite.name = "NativeImpactSPR"
    sprite.region_enabled = true
    sprite.centered = true
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(sprite)
    if sources.has("travel_end"):
        _enter_stage("travel_end")
    elif sources.has("hit"):
        _enter_stage("hit")
    else:
        queue_free()

func _meta(role: String) -> Dictionary:
    var infos: Dictionary = skill.get("original_anim_info", {})
    var parts: PackedStringArray = str(infos.get(role, "")).split(",", false)
    if parts.size() != 3:
        return {}
    for token in parts:
        if not token.strip_edges().is_valid_int():
            return {}
    var total: int = int(parts[0])
    var dirs: int = int(parts[1])
    var ticks: int = int(parts[2])
    if total <= 0 or dirs <= 0 or ticks <= 0 or total % dirs != 0:
        return {}
    return {"frames": int(total / dirs), "ticks": ticks}

func _enter_stage(role: String) -> void:
    stage = role
    elapsed = 0.0
    var data: Dictionary = sources.get(role, {})
    var tex: Texture2D = data.get("texture") as Texture2D
    if tex == null:
        queue_free()
        return
    sprite.texture = tex
    sprite.scale = Vector2.ONE * GEOMETRY.sprite_scale(skill, role)
    var meta: Dictionary = _meta(role)
    var frames: int = maxi(1, int(data.get("frames_per_direction", 1)))
    frames = mini(frames, maxi(1, int(meta.get("frames", frames))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    stage_duration = clampf(float(frames * ticks) / LOGIC_HZ, 0.055, 2.4)
    _update_frame()

func _process(delta: float) -> void:
    elapsed += maxf(0.0, delta)
    _update_frame()
    if elapsed >= stage_duration:
        if stage == "travel_end" and sources.has("hit"):
            _enter_stage("hit")
        else:
            queue_free()

func _update_frame() -> void:
    if not is_instance_valid(sprite) or stage.is_empty():
        return
    var data: Dictionary = sources.get(stage, {})
    var meta: Dictionary = _meta(stage)
    var frames: int = maxi(1, int(data.get("frames_per_direction", 1)))
    frames = mini(frames, maxi(1, int(meta.get("frames", frames))))
    var ticks: int = maxi(1, int(meta.get("ticks", 1)))
    var frame: int = mini(frames - 1, floori(elapsed * LOGIC_HZ / float(ticks)))
    var dirs: int = maxi(1, int(data.get("directions", 1)))
    var row: int = DIRECTION.row_from_vector(heading, dirs)
    var tile: int = maxi(1, int(data.get("tile_size", data.get("tile", 256))))
    if resolver == null or not bool(resolver.call("draw_source_frame", sprite, data, frame, row)):
        sprite.region_rect = Rect2(frame * tile, row * tile, tile, tile)
