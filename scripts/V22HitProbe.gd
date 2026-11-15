extends Area2D
## V22 main-scene non-rendered geometry probe. NOT the native JX collision engine.
## CollisionLayer 0 / Mask 1 tests Dummy StaticBody2D. A swept rectangle
## fallback prevents tunneling when the missile traverses a frame at high speed.
signal contacted(probe: Area2D)
signal vanished(probe: Area2D)

const RADIUS: float = 14.0
var direction: Vector2 = Vector2.RIGHT
var speed_px: float = 570.0 # Godot collision DEMO. NOT server missile speed.
var lifetime: float = 0.42
var settled: bool = false
var target_body: StaticBody2D
var target_shape: CollisionShape2D
var missile_id: int = 0
var skill_id: int = 0
var event_ordinal: int = -1
var cast_key: int = -1 # Visual correlation only, not native collision authority.
var contact_method: String = ""

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    monitoring = true
    monitorable = true
    var hit := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = RADIUS
    hit.shape = circle
    add_child(hit)
    body_entered.connect(_on_body_entered)
    # NO _draw(): main scene keeps its original VFX SPR, not demo circles.

func _physics_process(delta: float) -> void:
    if settled:
        return
    var start_pos: Vector2 = global_position
    global_position += direction * speed_px * delta
    var end_pos: Vector2 = global_position
    if _swept_overlaps_target(start_pos, end_pos):
        _contact("SWEPT_RECT")
        return
    lifetime -= delta
    if lifetime <= 0.0:
        settled = true
        vanished.emit(self)
        queue_free()

func _swept_overlaps_target(start_pos: Vector2, end_pos: Vector2) -> bool:
    if not is_instance_valid(target_body) or not is_instance_valid(target_shape):
        return false
    if target_body.has_method("is_alive") and not bool(target_body.call("is_alive")):
        return false
    var s: Shape2D = target_shape.shape
    if s is RectangleShape2D:
        # Convert world segment to the hurtbox-local coordinate system. The
        # rectangle is centered on the CollisionShape2D origin, not on NPC feet.
        var from_local: Vector2 = target_shape.to_local(start_pos)
        var to_local: Vector2 = target_shape.to_local(end_pos)
        var segment: Vector2 = to_local - from_local
        var extents: Vector2 = (s as RectangleShape2D).size * 0.5
        var region: Rect2 = Rect2(-extents, extents * 2.0).grow(RADIUS)
        var tmin: float = 0.0
        var tmax: float = 1.0
        for axis in range(2):
            var origin_axis: float = from_local.x if axis == 0 else from_local.y
            var delta_axis: float = segment.x if axis == 0 else segment.y
            var lo: float = region.position.x if axis == 0 else region.position.y
            var hi: float = region.end.x if axis == 0 else region.end.y
            if absf(delta_axis) < 0.00001:
                if origin_axis < lo or origin_axis > hi:
                    return false
            else:
                var a: float = (lo - origin_axis) / delta_axis
                var b: float = (hi - origin_axis) / delta_axis
                tmin = maxf(tmin, minf(a, b))
                tmax = minf(tmax, maxf(a, b))
                if tmin > tmax:
                    return false
        return true
    if s is CircleShape2D:
        var center: Vector2 = target_shape.global_position
        var scale_factor: float = maxf(absf(target_shape.global_scale.x), absf(target_shape.global_scale.y))
        var radius: float = (s as CircleShape2D).radius * scale_factor + RADIUS
        var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, start_pos, end_pos)
        return closest.distance_squared_to(center) <= radius * radius
    return false

func _on_body_entered(body: Node2D) -> void:
    if settled or body != target_body:
        return
    if body.has_method("is_alive") and not bool(body.call("is_alive")):
        return
    _contact("AREA_BODY_ENTERED")

func _contact(method: String) -> void:
    if settled:
        return
    settled = true
    contact_method = method
    contacted.emit(self)
    queue_free()
