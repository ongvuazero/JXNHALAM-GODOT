extends Area2D
## V21.3 training projectile. Area2D signals + swept geometry fallback verify demo contact.
## Speed, spread, collider radius and damage are TEST parameters, NOT JX1 rules.
signal contacted(projectile: Area2D)
signal vanished(projectile: Area2D)

var direction: Vector2 = Vector2.RIGHT
var speed_px: float = 540.0
var life_seconds: float = 2.0
var stationary: bool = false
var projectile_color: Color = Color(0.98, 0.7, 0.22)
var settled: bool = false
var missile_id: int = 0
var ordinal: int = 0
var target_body: StaticBody2D
var target_shape: CollisionShape2D
var contact_mode: String = ""
const HIT_RADIUS: float = 16.0 # Test geometry only.

func _ready() -> void:
    monitoring = true
    monitorable = true
    collision_layer = 0
    collision_mask = 1
    var circle := CircleShape2D.new()
    circle.radius = HIT_RADIUS
    var hit_shape := CollisionShape2D.new()
    hit_shape.shape = circle
    add_child(hit_shape)
    body_entered.connect(_on_body_entered)
    z_index = 10
    queue_redraw()

func _physics_process(delta: float) -> void:
    if settled:
        return
    # Area2D can miss fast-moving overlap transitions between fixed physics steps.
    # This segment-vs-circle check is a DEMO safeguard, not JX missile collision code.
    var start_pos: Vector2 = global_position
    if not stationary:
        position += direction * speed_px * delta
    var end_pos: Vector2 = global_position
    if _segment_touches_dummy(start_pos, end_pos):
        _resolve_contact("SWEPT_GEOMETRY")
        return
    life_seconds -= delta
    if life_seconds <= 0.0:
        settled = true
        vanished.emit(self)
        queue_free()
        return
    rotation += 2.2 * delta
    queue_redraw()

func _segment_touches_dummy(start_pos: Vector2, end_pos: Vector2) -> bool:
    if not is_instance_valid(target_body) or not is_instance_valid(target_shape):
        return false
    var target_collision: Shape2D = target_shape.shape
    if not target_collision is CircleShape2D:
        return false
    var center: Vector2 = target_shape.global_position
    var scale_factor: float = maxf(absf(target_shape.global_scale.x), absf(target_shape.global_scale.y))
    var sum_radius: float = (target_collision as CircleShape2D).radius * scale_factor + HIT_RADIUS
    var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, start_pos, end_pos)
    return closest.distance_squared_to(center) <= sum_radius * sum_radius

func _resolve_contact(method: String) -> void:
    if settled:
        return
    settled = true
    contact_mode = method
    contacted.emit(self)
    queue_free()

func _on_body_entered(body: Node2D) -> void:
    if settled or body != target_body:
        return
    _resolve_contact("AREA_BODY_ENTERED")

func _draw() -> void:
    var outer: Color = projectile_color
    outer.a = 0.3
    draw_circle(Vector2.ZERO, 24.0, outer)
    draw_circle(Vector2.ZERO, 13.0, projectile_color)
    draw_arc(Vector2.ZERO, 20.0, 0.4, 5.9, 18, Color(1, 1, 1, 0.75), 2.5, true)
