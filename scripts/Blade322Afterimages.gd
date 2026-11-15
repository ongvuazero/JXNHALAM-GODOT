extends Node2D

## V37: client EXE V12 actor pose-history reproduction.
## FUN_0057D030 MaxShadowNum != 0 enables history; FUN_005C6100: 7 slots,
## capture/fade every 3 FUN_005C6300 render invocations; alpha=0x80, -=0x10.
## The snapshots preserve historical GLOBAL transforms, native six-layer order
## and source frames. If caster stands still, ghosts overlap at the same spot.
## This uses Godot _process as a REPRESENTATIVE RENDER CALLBACK. Exact timing
## and native DrawSpriteAlpha's alpha-to-opacity mapping remain unverified.
## No physics, HP, animation selection, cast timing or missile effects here.
const RING_SLOTS: int = 7
const MAX_PART_RECORDS: int = 20 # native capacity; actor currently has 6 layers
const HISTORY_INTERVAL: int = 3
const INITIAL_ALPHA: int = 0x80
const FADE_DECREMENT: int = 0x10

var caster: CharacterBody2D
var source_sprite: Sprite2D
var native_renderer: Node2D
var duration: float = 0.28
var elapsed: float = 0.0
var enabled: bool = false
var render_invocations: int = 0
var history_counter: int = 0
var ring_index: int = 0
var slots: Array[Dictionary] = []
var captured_total: int = 0
var fade_steps: int = 0
var sampled_ticks: Array[int] = []

func _ready() -> void:
    # Renderer updates before the snapshot is taken; Player/AT03 have default 0.
    process_priority = 100

func configure(source: CharacterBody2D, _aim: Vector2,
        _face_dir: int, duration_seconds: float) -> void:
    caster = source
    source_sprite = source.get_node_or_null("OriginalSPRAlignedVisual") as Sprite2D
    native_renderer = source.get_node_or_null("V33NativeAction9Renderer") as Node2D
    duration = clampf(duration_seconds, 0.1, 1.5)
    slots.clear()
    for _i in range(RING_SLOTS):
        slots.append({})

func set_enabled(value: bool) -> void:
    enabled = value
    if not enabled:
        _clear_echoes()
        history_counter = 0

func _process(delta: float) -> void:
    if not is_instance_valid(caster):
        _clear_echoes()
        queue_free()
        return
    elapsed += maxf(0.0, delta)
    if enabled:
        _render_history_invocation()
    if elapsed > duration and not _has_visible_echoes():
        queue_free()

func _render_history_invocation() -> void:
    # Called once per Godot visual update, NOT once per fixed 18-Hz logic tick.
    # Native V12 increments history counter inside FUN_005C6300's render path.
    render_invocations += 1
    history_counter += 1
    if history_counter < HISTORY_INTERVAL:
        return
    history_counter = 0
    _fade_all_slots()
    var valid_capture: bool = (
        elapsed <= duration
        and str(caster.get("state")) == "attack"
        and bool(caster.get("blade322_native_visual_active"))
    )
    if not valid_capture:
        return
    var snapshot: Node2D = null
    var has_native: bool = (
        is_instance_valid(native_renderer)
        and bool(native_renderer.get("enabled"))
        and bool(native_renderer.get("at03_sources_loaded"))
    )
    if has_native:
        snapshot = _snapshot_native_six_layers()
    if snapshot == null:
        snapshot = _snapshot_at02_atlas()
    if snapshot == null:
        return
    var prior: Dictionary = slots[ring_index]
    var previous_node: Node2D = prior.get("node") as Node2D
    if is_instance_valid(previous_node):
        previous_node.queue_free()
    slots[ring_index] = {"node": snapshot, "alpha_byte": INITIAL_ALPHA,
        "source_tick": int(caster.get("blade322_native_tick")),
        "world_position": snapshot.global_position}
    _set_native_alpha(snapshot, INITIAL_ALPHA)
    ring_index = (ring_index + 1) % RING_SLOTS
    captured_total += 1
    sampled_ticks.append(int(caster.get("blade322_native_tick")))

func _fade_all_slots() -> void:
    fade_steps += 1
    for i in range(slots.size()):
        var entry: Dictionary = slots[i]
        var node: Node2D = entry.get("node") as Node2D
        if not is_instance_valid(node):
            slots[i] = {}
            continue
        var current: int = int(entry.get("alpha_byte", 0))
        var faded: int = current - FADE_DECREMENT
        if faded <= 0:
            node.queue_free()
            slots[i] = {}
        else:
            entry["alpha_byte"] = faded
            slots[i] = entry
            _set_native_alpha(node, faded)

func _set_native_alpha(snapshot: Node2D, byte_value: int) -> void:
    # Represent2 receives byte >> 3 (0x80=16, 0x70=14,...), whereas
    # Godot requires normalized opacity. Byte/255 is a visual approximation.
    snapshot.modulate = Color(1.0, 1.0, 1.0, float(byte_value) / 255.0)

func _has_visible_echoes() -> bool:
    for entry in slots:
        if is_instance_valid(entry.get("node") as Node2D):
            return true
    return false

func _make_snapshot_root(source_transform: Transform2D) -> Node2D:
    var root := Node2D.new()
    root.name = "V37_PoseHistorySlot"
    root.top_level = true
    root.z_as_relative = false
    root.z_index = 3 # current actor uses z=4; never obscure the live pose
    add_child(root)
    root.global_transform = source_transform
    return root

func _snapshot_native_six_layers() -> Node2D:
    # The V35 renderer has already resolved native order for this source frame.
    # Copy its children in scene-tree order; do NOT recalculate z-order.
    var ordered_layers: Array[Sprite2D] = []
    for child in native_renderer.get_children():
        var source_layer: Sprite2D = child as Sprite2D
        if source_layer != null and source_layer.name.begins_with("AT03Layer") \
                and source_layer.visible and source_layer.texture != null:
            ordered_layers.append(source_layer)
    if ordered_layers.size() != 6:
        return null
    var snapshot: Node2D = _make_snapshot_root(native_renderer.global_transform)
    for source_layer in ordered_layers:
        var image_layer := Sprite2D.new()
        image_layer.texture = source_layer.texture
        image_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        image_layer.centered = source_layer.centered
        image_layer.offset = source_layer.offset
        image_layer.transform = source_layer.transform
        image_layer.flip_h = source_layer.flip_h
        image_layer.flip_v = source_layer.flip_v
        image_layer.region_enabled = source_layer.region_enabled
        if source_layer.region_enabled:
            image_layer.region_rect = source_layer.region_rect
        # All ghost layers have equal z; sibling order is V35's painter order.
        image_layer.z_as_relative = true
        image_layer.z_index = 0
        snapshot.add_child(image_layer)
    return snapshot

func _snapshot_at02_atlas() -> Node2D:
    if not is_instance_valid(source_sprite) or source_sprite.texture == null \
            or not source_sprite.region_enabled:
        return null
    var region: Rect2 = source_sprite.region_rect
    if region.size.x < 1.0 or region.size.y < 1.0:
        return null
    var snapshot: Node2D = _make_snapshot_root(source_sprite.global_transform)
    var image_layer := Sprite2D.new()
    image_layer.texture = source_sprite.texture
    image_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    image_layer.region_enabled = true
    image_layer.region_rect = region
    image_layer.centered = source_sprite.centered
    image_layer.offset = source_sprite.offset
    image_layer.flip_h = source_sprite.flip_h
    image_layer.flip_v = source_sprite.flip_v
    snapshot.add_child(image_layer)
    return snapshot

func _clear_echoes() -> void:
    for entry in slots:
        var ghost: Node2D = entry.get("node") as Node2D
        if is_instance_valid(ghost):
            ghost.queue_free()
    slots.clear()
    for _i in range(RING_SLOTS):
        slots.append({})

func diagnostic() -> Dictionary:
    var live_count: int = 0
    for entry in slots:
        if is_instance_valid(entry.get("node") as Node2D):
            live_count += 1
    return {"style": "V37_NATIVE_POSE_HISTORY_RENDERCALL_APPROX",
        "sample_count": captured_total, "source_ticks": sampled_ticks.duplicate(),
        "live_echoes": live_count, "slots": RING_SLOTS,
        "render_invocations": render_invocations, "fade_steps": fade_steps,
        "alpha_initial": INITIAL_ALPHA, "alpha_step": FADE_DECREMENT,
        "capture_every_render_calls": HISTORY_INTERVAL, "enabled": enabled,
        "position_policy": "HISTORICAL_WORLD_POSITION",
        "evidence": "game.exe FUN_005C6300, FUN_005C40F0, FUN_005C6140; represent2 alpha",
        "limits": "Godot _process is proxy for native render callback; opacity normalization approximated"}
