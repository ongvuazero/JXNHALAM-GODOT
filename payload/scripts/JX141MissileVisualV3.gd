extends Node2D
## JXNHALAM M141 V3: 3 runtime visual instances, attached to missile allocations.
## Verified: skill 325 -> child 408 -> missile 141 x3, trace dirs 3/11/19,
## state==1 main SPR rendering; native 320/32 fly and 6/1 hit atlases.
## NOT verified: exact screen XY projection, missile flight speed, contact timing,
## or the relationship of three allocations to three large yellow arcs in JX1.
## This is VISUAL ONLY: never modifies collision, actor, mana, HP, or Lua.
const FrameProbe = preload("res://scripts/JX141NativeFrameProbe.gd")
const FLY_TEXTURE = preload("res://assets/skill90/jx90_truyphong_sweep.png")
const HIT_TEXTURE = preload("res://assets/skill90/jx90_truyphong_impact.png")
const TRACE_FILE: String = "res://data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json"
const M141_TICK_SECONDS: float = 1.0 / 18.0 # inspection clock, not native-client clock
const FLY_TICKS: int = 4 # server V4 traced life 0,1,2,3
const IMPACT_SECONDS: float = 0.24 # DEMO V22 contact art, not a client measurement
const MAX_FLY: int = 36
const GROUP: String = "jx141_visual_v3"

var caster: Node2D
var locked_target: Vector2 = Vector2.ZERO
var face8: int = 0
var direction_center64: int = 0
var pixel_per_tick_preview: float = 24.0 # NOT a JX1 world-to-screen conversion
var fly_states: Array[Dictionary] = []
var impact_states: Array[Dictionary] = []
var allocations: int = 0
var impact_events: int = 0
var trace_config: Dictionary = {}
var latest_label: String = "M141 / No cast"
var enabled: bool = true

func _ready() -> void:
    add_to_group(GROUP)
    # Do not change imported PNG/SPR alpha or scale; additive M141 overlays
    # in the V42.2.4 prototype were never verified in the native client.
    if FileAccess.file_exists(TRACE_FILE):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRACE_FILE))
        if parsed is Dictionary:
            trace_config = parsed

func configure(actor: Node2D, destination: Vector2, facing8: int) -> void:
    caster = actor
    locked_target = destination
    face8 = posmod(facing8, 8)
    if is_instance_valid(caster):
        var aim: Vector2 = locked_target - caster.global_position
        if aim.length_squared() > 0.01:
            # Native directions: 0 SOUTH; 16 WEST; 32 NORTH; 48 EAST.
            # Convert screen XY to 64-dir logic; sample log headings 3/11/19
            # when the aim center is 11. Pixel projection is still unverified.
            direction_center64 = posmod(roundi(atan2(-aim.x, aim.y) * 64.0 / TAU), 64)
        else:
            direction_center64 = posmod(face8 * 8, 64)

static func trace_or_logic_dir64(mid_dir64: int, sub_index: int, sub_count: int, explicit_dir64: int = -1) -> int:
    if explicit_dir64 >= 0:
        return posmod(explicit_dir64, 64)
    # x3 server trace: center-8, center, center+8 (3,11,19).
    # Only x3 is supported here; no attempt to generalize native formation 2.
    if sub_count != 3:
        return posmod(mid_dir64, 64)
    return posmod(mid_dir64 + (sub_index - 1) * 8, 64)

static func traced_unit_vector(dir64: int) -> Vector2:
    # Grounded factors for ONE logged cast (native units, not Godot pixels).
    var sample_dirs: PackedInt32Array = PackedInt32Array([3, 11, 19])
    var xs: PackedInt32Array = PackedInt32Array([-327, -923, -979])
    var ys: PackedInt32Array = PackedInt32Array([978, 461, -327])
    for i in range(sample_dirs.size()):
        if posmod(dir64, 64) == sample_dirs[i]:
            return Vector2(float(xs[i]), float(ys[i])).normalized()
    var angle: float = float(posmod(dir64, 64)) * TAU / 64.0
    return Vector2(-sin(angle), cos(angle))

func emit_allocation(event: Dictionary) -> void:
    if not enabled or not is_instance_valid(caster):
        return
    if int(event.get("missile_id", 0)) != 141:
        return
    if fly_states.size() >= MAX_FLY:
        return
    var sub_count: int = int(event.get("sub_count", 1))
    var sub_index: int = int(event.get("sub_index", 0))
    var dir64: int = trace_or_logic_dir64(direction_center64, sub_index,
        sub_count, int(event.get("native_dir64", -1)))
    var sprite := Sprite2D.new()
    sprite.name = "M141_FLY_%d_dir%d" % [allocations + 1, dir64]
    sprite.texture = FLY_TEXTURE
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 0, 256, 256)
    sprite.centered = true
    sprite.scale = Vector2.ONE
    sprite.z_index = 0
    add_child(sprite)
    var origin: Vector2 = caster.global_position
    var item: Dictionary = {"sprite": sprite, "origin": origin,
        "dir64": dir64, "sub_index": sub_index,
        "age_seconds": 0.0, "state": 1,
        "unit": traced_unit_vector(dir64)}
    fly_states.append(item)
    allocations += 1
    latest_label = "M141 FLY: %d instances, dir64=%d" % [fly_states.size(), dir64]
    _update_fly(item)

func _process(delta: float) -> void:
    for i in range(fly_states.size() - 1, -1, -1):
        var item: Dictionary = fly_states[i]
        item["age_seconds"] = float(item["age_seconds"]) + maxf(0.0, delta)
        if int(floori(float(item["age_seconds"]) / M141_TICK_SECONDS)) >= FLY_TICKS:
            var old_sprite: Sprite2D = item["sprite"] as Sprite2D
            if is_instance_valid(old_sprite):
                old_sprite.queue_free()
            fly_states.remove_at(i)
            continue
        fly_states[i] = item
        _update_fly(item)
    for i in range(impact_states.size() - 1, -1, -1):
        var impact: Dictionary = impact_states[i]
        impact["age_seconds"] = float(impact["age_seconds"]) + maxf(0.0, delta)
        if float(impact["age_seconds"]) >= IMPACT_SECONDS:
            var old_hit: Sprite2D = impact["sprite"] as Sprite2D
            if is_instance_valid(old_hit):
                old_hit.queue_free()
            impact_states.remove_at(i)
            continue
        impact_states[i] = impact
        _update_hit(impact)

func _update_fly(item: Dictionary) -> void:
    var sprite: Sprite2D = item["sprite"] as Sprite2D
    if not is_instance_valid(sprite):
        return
    var age_tick: int = clampi(floori(float(item["age_seconds"]) / M141_TICK_SECONDS), 0, FLY_TICKS - 1)
    var source: Dictionary = FrameProbe.inspect(320, 32, int(item["dir64"]), age_tick, FLY_TICKS, 1, false)
    if not bool(source.get("ok", false)):
        sprite.visible = false
        return
    sprite.region_rect = Rect2(float(int(source["local_frame"]) * 256),
        float(int(source["spr_row"]) * 256), 256.0, 256.0)
    # IMPORTANT: not weapon-anchored; 3 separate in-flight locations.
    # The 24px/tick projection is only a visible inspection scale, because
    # server x_factor/y_factor are fixed-point values, not screen pixels.
    var units: Vector2 = item["unit"] as Vector2
    var pos: Vector2 = (item["origin"] as Vector2) + units * (float(age_tick) * pixel_per_tick_preview)
    sprite.global_position = pos

func on_visual_contact(world_position: Vector2) -> void:
    # V22's impact_contacted signal is DEMO collision and does not identify a
    # specific missile slot. We show one separate impact sprite at contact,
    # without pretending which M141 FLY object it belonged to.
    var sprite := Sprite2D.new()
    sprite.name = "M141_HIT_PREVIEW_%d" % (impact_events + 1)
    sprite.texture = HIT_TEXTURE
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 0, 256, 256)
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.centered = true
    sprite.scale = Vector2.ONE
    add_child(sprite)
    var new_impact: Dictionary = {"sprite": sprite,
        "age_seconds": 0.0, "position": world_position}
    impact_states.append(new_impact)
    impact_events += 1
    latest_label = "M141 DEMO CONTACT AnimFile4 ×%d" % impact_events
    _update_hit(new_impact)

func _update_hit(item: Dictionary) -> void:
    var sprite: Sprite2D = item["sprite"] as Sprite2D
    if not is_instance_valid(sprite):
        return
    var age: float = float(item["age_seconds"])
    var frame: int = clampi(floori(age / IMPACT_SECONDS * 6.0), 0, 5)
    var frame_info: Dictionary = FrameProbe.inspect(6, 1, 0, frame, 6, 1, true)
    if bool(frame_info.get("ok", false)):
        sprite.region_rect = Rect2(float(int(frame_info["local_frame"]) * 256), 0.0, 256.0, 256.0)
    sprite.global_position = item["position"] as Vector2

func diagnostic() -> Dictionary:
    var active_dirs: Array[int] = []
    for item in fly_states:
        active_dirs.append(int(item["dir64"]))
    return {"active_fly": fly_states.size(), "impact_sprites": impact_states.size(),
        "fly_total": allocations, "contact_preview_total": impact_events,
        "dir64_active": active_dirs, "pixel_per_tick_preview": pixel_per_tick_preview,
        "stage": latest_label, "position_verified": false, "damage_modified": false}
