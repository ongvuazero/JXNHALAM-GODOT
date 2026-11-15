extends StaticBody2D

const MAX_HP = 900
var hp: int = MAX_HP
var reset_timer: float = 0.0
var sprite: Sprite2D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	var box := RectangleShape2D.new()
	box.size = Vector2(24, 55)
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = Vector2(0, -29)
	add_child(shape)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/npc/training_dummy.png") as Texture2D
	sprite.scale = Vector2(0.34, 0.34)
	sprite.position = Vector2(0, -36) # bottom of visible pixels near foot anchor
	add_child(sprite)
	queue_redraw()

func take_damage(amount: int) -> bool:
	if hp <= 0:
		return false
	hp = maxi(0, hp - maxi(0, amount))
	if hp == 0:
		reset_timer = 2.0
		sprite.visible = false
	queue_redraw()
	return true

func _process(delta: float) -> void:
	if hp == 0:
		reset_timer -= delta
		if reset_timer <= 0.0:
			hp = MAX_HP
			sprite.visible = true
			queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-24, -88, 48, 10), Color(0.09, 0.15, 0.18))
	draw_rect(Rect2(-22, -86, 44.0 * float(hp) / float(MAX_HP), 6), Color(0.84, 0.27, 0.21))


# V22 training reset from game HUD; keeps original dummy scene and texture.
func reset_training_hp() -> void:
	hp = MAX_HP
	reset_timer = 0.0
	if is_instance_valid(sprite):
		sprite.visible = true
	queue_redraw()
