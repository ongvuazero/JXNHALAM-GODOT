extends Node2D
## V40 Spear 323 / Mace 325 impact VISUAL adapter.
## Table-grounded: 323 -> child 327 -> missile 139 (AnimFile4 4,1,1)
##                 325 -> child 408 -> missile 141 (AnimFile4 6,1,1).
## The collision event and target anchoring here are V22 DEMO; native EXE
## stage-3 creation/anchor/blend have not yet been traced for missile 139/141.
## Source SPR-derived atlas pixels are not recolored/replaced.
const TICK_HZ: float = 18.0 # Visual preview, NOT confirmed missile-139/141 runtime cadence.
const PROFILES: Dictionary = {
    323: {"missile": 139, "atlas": "res://assets/skill90/jx90_truytinh_impact.png", "frames": 4, "tile": 256},
    325: {"missile": 141, "atlas": "res://assets/skill90/jx90_truyphong_impact.png", "frames": 6, "tile": 256},
}

var sprite: Sprite2D
var frame_index: int = 0
var elapsed: float = 0.0
var frame_count: int = 0
var cell: int = 256

func start_at(skill_id: int, missile_id: int, world_position: Vector2,
        resolver: RefCounted = null, source_path: String = "") -> void:
    var info: Dictionary = PROFILES.get(skill_id, {})
    if info.is_empty() or int(info.get("missile", 0)) != missile_id:
        queue_free()
        return
    var atlas: Texture2D = null
    if skill_id == 323:
        # Original server table points M139 slot-4 to a shared hit SPR.
        # The bundled generic flare was visually rejected by the user; do not
        # label it as the authentic spear effect. Use actual client's SPR only.
        if resolver != null and not source_path.is_empty() and resolver.has_method("load_spr"):
            var decoded: Dictionary = resolver.call("load_spr", source_path)
            var source: Dictionary = decoded.get("source", {})
            if str(source.get("kind", "")) in ["pak", "loose"]:
                atlas = decoded.get("texture") as Texture2D
                frame_count = mini(int(info.get("frames", 4)), int(decoded.get("frames_per_direction", 4)))
                cell = int(decoded.get("tile_size", decoded.get("tile", 256)))
        if atlas == null:
            push_warning("TV SPEAR 323: M139 AnimFile4 not verified in client PAK; misleading shared flare disabled")
            queue_free()
            return
    else:
        # Legacy profile is retained for compatibility, while M141 runs its
        # independent bundled-fly/impact renderer outside this script.
        atlas = load(str(info.get("atlas", ""))) as Texture2D
        frame_count = int(info.get("frames", 1))
        cell = int(info.get("tile", 256))
    if atlas == null or frame_count < 1 or cell < 1:
        queue_free()
        return
    if atlas.get_width() < cell * frame_count or atlas.get_height() < cell:
        push_warning("V40: atlas hit size mismatch %d" % skill_id)
        queue_free()
        return
    global_position = world_position # Demonstration target origin; native anchor NOT verified.
    sprite = Sprite2D.new()
    sprite.name = "M%d_AnimFile4_Impact" % missile_id
    sprite.texture = atlas
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 0, cell, cell)
    add_child(sprite)
    z_as_relative = false
    z_index = 5

func _process(delta: float) -> void:
    if not is_instance_valid(sprite):
        queue_free()
        return
    elapsed += maxf(0.0, delta)
    frame_index = int(elapsed * TICK_HZ)
    if frame_index >= frame_count:
        queue_free()
        return
    sprite.region_rect = Rect2(frame_index * cell, 0, cell, cell)
