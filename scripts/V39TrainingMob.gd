extends AnimatableBody2D
## V39 playable ENEMY PROTOTYPE. Not a JX1 native monster AI/damage formula.
## Reuses the bundled blade atlas; no generated or external game assets.
signal defeated(mob: StaticBody2D)
signal struck_player(damage: int, world_position: Vector2)

const STAND = preload("res://assets/character/blade_stand.png")
const RUN = preload("res://assets/character/blade_run.png")
const CELL: int = 192
const RESPAWN_SEC: float = 4.0
const PLAYER_ATTACK_DAMAGE: int = 8 # DEMO enemy melee damage, NOT native JX1.

var display_name: String = "Cao thủ tập luyện"
var max_hp: int = 40
var hp: int = 40
var spawn_point: Vector2 = Vector2.ZERO
var controlled_player: CharacterBody2D
var sprite: Sprite2D
var collider: CollisionShape2D
var name_label: Label
var idle_clock: float = 0.0
var hit_flash: float = 0.0
var dead_elapsed: float = 0.0
var strike_clock: float = 0.5
var moving: bool = false
var frame_direction: int = 6
var kill_reported: bool = false

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2
    var body_shape := RectangleShape2D.new()
    body_shape.size = Vector2(28, 56)
    collider = CollisionShape2D.new()
    collider.name = "MobHurtbox"
    collider.shape = body_shape
    collider.position = Vector2(0, -31)
    add_child(collider)
    sprite = Sprite2D.new()
    sprite.texture = STAND
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.region_rect = Rect2(0, 6 * CELL, CELL, CELL)
    sprite.position = Vector2(0, -64)
    sprite.modulate = Color(0.92, 0.61, 0.56)
    add_child(sprite)
    name_label = Label.new()
    name_label.text = display_name
    name_label.position = Vector2(-65, -114)
    name_label.size = Vector2(130, 20)
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_label.add_theme_font_size_override("font_size", 13)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(name_label)
    queue_redraw()

func configure(player_ref: CharacterBody2D, title: String, total_health: int, origin: Vector2) -> void:
    controlled_player = player_ref
    display_name = title
    max_hp = maxi(10, total_health)
    hp = max_hp
    spawn_point = origin
    global_position = origin
    if is_instance_valid(name_label):
        name_label.text = display_name
    queue_redraw()

func is_alive() -> bool:
    return hp > 0

func take_damage(amount: int) -> bool:
    if hp <= 0 or amount <= 0:
        return false
    hp = maxi(0, hp - amount)
    hit_flash = 0.15
    if hp == 0:
        dead_elapsed = 0.0
        moving = false
        collision_layer = 0
        if is_instance_valid(collider):
            collider.set_deferred("disabled", true)
        if not kill_reported:
            kill_reported = true
            defeated.emit(self)
    queue_redraw()
    return true

func reset_training_hp() -> void:
    hp = max_hp
    dead_elapsed = 0.0
    kill_reported = false
    strike_clock = 0.5
    global_position = spawn_point
    collision_layer = 1
    if is_instance_valid(collider):
        collider.set_deferred("disabled", false)
    if is_instance_valid(sprite):
        sprite.visible = true
        sprite.modulate = Color(0.92, 0.61, 0.56)
    if is_instance_valid(name_label):
        name_label.visible = true
    queue_redraw()

func _physics_process(delta: float) -> void:
    if hp <= 0:
        dead_elapsed += maxf(0.0, delta)
        if is_instance_valid(sprite):
            sprite.modulate.a = maxf(0.0, 1.0 - dead_elapsed / 0.6)
        if is_instance_valid(name_label):
            name_label.visible = false
        if dead_elapsed >= RESPAWN_SEC:
            reset_training_hp()
        return
    if not is_instance_valid(controlled_player):
        return
    idle_clock += delta
    hit_flash = maxf(0.0, hit_flash - delta)
    strike_clock = maxf(0.0, strike_clock - delta)
    var to_player: Vector2 = controlled_player.global_position - global_position
    var distance: float = to_player.length()
    moving = false
    if distance < 320.0 and distance > 76.0:
        # Moving StaticBody2D's animatable subclass; no fabricated JX1 AI claim.
        var step: Vector2 = to_player.normalized() * 77.0 * delta
        global_position += step
        moving = true
        frame_direction = 6 if step.x >= 0.0 else 2
    if distance <= 85.0 and strike_clock <= 0.0:
        strike_clock = 1.45
        struck_player.emit(PLAYER_ATTACK_DAMAGE, global_position)
    if is_instance_valid(sprite):
        sprite.texture = RUN if moving else STAND
        var frame: int = int(idle_clock * (9.0 if moving else 4.0)) % 11
        sprite.region_rect = Rect2(frame * CELL, frame_direction * CELL, CELL, CELL)
        sprite.modulate = Color(1.0, 0.95, 0.85) if hit_flash > 0.0 else Color(0.92, 0.61, 0.56)
    queue_redraw()

func _draw() -> void:
    if hp <= 0:
        return
    draw_rect(Rect2(-26, -124, 52, 8), Color(0.08, 0.10, 0.12, 0.94))
    draw_rect(Rect2(-24, -122, 48.0 * float(hp) / float(max_hp), 4), Color(0.91, 0.31, 0.26))
