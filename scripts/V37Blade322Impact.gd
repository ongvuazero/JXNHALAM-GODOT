extends Node2D

## V43.4: restore the SINGLE native M138 hit atlas at unmodified proportions.
## V43.3 mirrored the sprite and magnified it 2.2-2.9x; that made a fake,
## oversized cross-slash. The atlas itself is unchanged (8x320 source cells).
## Client exact visual matching still requires comparing raw client PAK data.
const ATLAS: String = "res://assets/skill90/jx90_potian_impact.png"
const CELL: int = 320
const FRAME_COUNT: int = 8
const NOMINAL_HZ: float = 18.0
const VFX_Y_OFFSET: float = -5.0

var sprite: Sprite2D
var step_index: int = 0
var clock: float = 0.0
var cell: int = CELL
var frame_count: int = FRAME_COUNT

func start_at(world_position: Vector2, source_info: Dictionary = {}) -> void:
    global_position = world_position + Vector2(0.0, VFX_Y_OFFSET)
    # Prefer the actual client SPR if a matching PAK is mounted. Fall back to
    # the bundled original atlas; never upscale or mirror the source pixels.
    var texture: Texture2D = source_info.get("texture") as Texture2D
    if texture != null:
        cell = maxi(1, int(source_info.get("tile_size", CELL)))
        frame_count = mini(FRAME_COUNT, maxi(1, int(source_info.get("frames_per_direction", FRAME_COUNT))))
    else:
        texture = load(ATLAS) as Texture2D
    if texture == null:
        push_warning("M138 AnimFile4 atlas missing: " + ATLAS)
        queue_free()
        return
    sprite = Sprite2D.new()
    sprite.name = "NativeM138_AnimFile4"
    sprite.texture = texture
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0.0, 0.0, cell, cell)
    sprite.centered = true
    sprite.scale = Vector2.ONE
    sprite.rotation = 0.0
    add_child(sprite)
    z_as_relative = false
    z_index = 5

func _process(delta: float) -> void:
    if not is_instance_valid(sprite):
        queue_free()
        return
    clock += maxf(0.0, delta)
    var tick: float = 1.0 / NOMINAL_HZ
    while clock >= tick:
        clock -= tick
        step_index += 1
    if step_index >= frame_count:
        queue_free()
        return
    sprite.region_rect = Rect2(step_index * cell, 0.0, cell, cell)
