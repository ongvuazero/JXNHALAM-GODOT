extends Node2D
## Thien Vuong 323 => 327 => M139, 5 distinct missile allocations.
## Authored M139 AnimFile2: 64 frames / 16 dirs / 1 nominal tick.
## Runtime trajectory, velocity and contact timing are demonstrative, NOT EXE-verified.
const GROUP: String = "jx139_visual_preview"
const MAX_ITEMS: int = 20
const DEMO_SPEED: float = 610.0
const TTL: float = 0.75

var caster: Node2D
var destination: Vector2 = Vector2.ZERO
var face8: int = 0
var resolver: RefCounted
var atlas: Dictionary = {}
var samples: Array[Dictionary] = []
var cast_key: int = -1
var allocated: int = 0
var contacted: int = 0
var missing_spr: bool = false
var tick_elapsed: float = 0.0
var sprite_source_path: String = ""
var allow_geometry_debug: bool = false

func configure(actor: Node2D, target_point: Vector2, direction8: int, asset_resolver: RefCounted, virtual_path: String) -> void:
    caster = actor
    destination = target_point
    face8 = posmod(direction8, 8)
    resolver = asset_resolver
    sprite_source_path = virtual_path
    if resolver != null and not virtual_path.is_empty() and resolver.has_method("load_spr"):
        atlas = resolver.call("load_spr", virtual_path)
    missing_spr = atlas.is_empty() or atlas.get("texture", null) == null
    add_to_group(GROUP)
    z_as_relative = false
    z_index = 5

func bind_demo_cast(key: int) -> void:
    cast_key = key
    for i in range(samples.size()):
        var entry: Dictionary = samples[i]
        entry["cast_key"] = key
        samples[i] = entry

func emit_allocation(event: Dictionary) -> void:
    allocated += 1
    if not is_instance_valid(caster) or samples.size() >= MAX_ITEMS:
        return
    var aim: Vector2 = destination - caster.global_position
    if aim.length_squared() < 1.0:
        aim = Vector2.RIGHT
    var direction: Vector2 = aim.normalized()
    # M139 allocations are sequential. No fabricated left/middle/right spread.
    var origin: Vector2 = caster.global_position + direction * 22.0 + Vector2(0, -47)
    var end_point: Vector2 = destination
    var sprite: Sprite2D
    if not missing_spr:
        sprite = Sprite2D.new()
        sprite.texture = atlas.get("texture") as Texture2D
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        sprite.region_enabled = true
        sprite.centered = true
        sprite.z_as_relative = false
        sprite.z_index = 5
        add_child(sprite)
    samples.append({"ordinal": int(event.get("ordinal", -1)), "cast_key": cast_key,
        "pos": origin, "start": origin, "end": end_point, "age": 0.0,
        "direction": direction, "sprite": sprite, "finished": false})
    queue_redraw()

func on_visual_contact_instance(key: int, ordinal: int, _impact: Vector2) -> bool:
    if key < 0 or ordinal < 0 or key != cast_key:
        return false
    for i in range(samples.size()):
        var item: Dictionary = samples[i]
        if int(item.get("ordinal", -1)) != ordinal or bool(item.get("finished", false)):
            continue
        item["finished"] = true
        var sprite: Sprite2D = item.get("sprite") as Sprite2D
        if is_instance_valid(sprite):
            sprite.queue_free()
        samples[i] = item
        contacted += 1
        queue_redraw()
        return true
    return false

func _process(delta: float) -> void:
    for i in range(samples.size() - 1, -1, -1):
        var sample: Dictionary = samples[i]
        if bool(sample.get("finished", false)):
            samples.remove_at(i)
            continue
        var age: float = float(sample.get("age", 0.0)) + maxf(0.0, delta)
        var start: Vector2 = sample.get("start", Vector2.ZERO)
        var end_point: Vector2 = sample.get("end", start)
        var dist: float = start.distance_to(end_point)
        var ratio: float = clampf(age * DEMO_SPEED / maxf(1.0, dist), 0.0, 1.0)
        var pos: Vector2 = start.lerp(end_point, ratio)
        sample["age"] = age
        sample["pos"] = pos
        var sprite: Sprite2D = sample.get("sprite") as Sprite2D
        if is_instance_valid(sprite):
            sprite.global_position = pos
            var dirs: int = maxi(1, int(atlas.get("directions", 16)))
            var count: int = maxi(1, int(atlas.get("frames_per_direction", 4)))
            var tile: int = maxi(1, int(atlas.get("tile_size", atlas.get("tile", 256))))
            var row: int = posmod(face8 * maxi(1, int(dirs / 8)), dirs)
            var column: int = mini(count - 1, int(age * 18.0) % count)
            sprite.region_rect = Rect2(column * tile, row * tile, tile, tile)
        if age >= TTL or ratio >= 1.0:
            if is_instance_valid(sprite): sprite.queue_free()
            samples.remove_at(i)
        else:
            samples[i] = sample
    queue_redraw()

func _draw() -> void:
    # Draw a test line ONLY when debug visualization is explicitly enabled;
    # in normal gameplay missing authentic M139 art is clearly diagnosed.
    if not missing_spr or not allow_geometry_debug:
        return
    for sample in samples:
        if bool(sample.get("finished", false)): continue
        var pos: Vector2 = to_local(sample.get("pos", Vector2.ZERO))
        var direction: Vector2 = sample.get("direction", Vector2.RIGHT)
        draw_line(pos - direction * 18.0, pos + direction * 9.0, Color(1.0, 0.75, 0.26, 0.90), 3.0, true)
        draw_circle(pos, 2.5, Color(1.0, 0.94, 0.64, 0.95))

func diagnostic() -> Dictionary:
    return {"missile_id": 139, "total_allocations": allocated, "contacts": contacted,
        "flying": samples.size(), "source_spr_available": not missing_spr,
        "flight_timing_verified": false, "visual_only": true,
        "source_path": sprite_source_path, "source_kind": str(atlas.get("source", {}).get("kind", "MISSING"))}
