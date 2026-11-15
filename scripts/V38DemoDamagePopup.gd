extends Node2D
## V38 video-visible training feedback, not native JX1 damage math/animation.
## Corrected original clip ~00:39.95 shows a red hit number at the practice post.
## The only number shown here is the existing V22 -10 DEMO HP commit.
## Spawning this label has no collision, missile, skill or HP side effects.
const DISPLAY_SECONDS: float = 0.56
const LIFT_PIXELS: float = 26.0

var elapsed_seconds: float = 0.0
var value_label: Label
var demo_label: Label

func start_at(target_foot: Vector2, amount: int) -> void:
    if amount <= 0:
        queue_free()
        return
    top_level = true
    z_as_relative = false
    z_index = 8
    global_position = target_foot + Vector2(19.0, -70.0)
    value_label = Label.new()
    value_label.name = "V38DemoHitNumber"
    value_label.text = str(amount)
    value_label.position = Vector2(-38.0, -6.0)
    value_label.size = Vector2(76.0, 32.0)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    value_label.add_theme_font_size_override("font_size", 26)
    value_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.22))
    value_label.add_theme_color_override("font_outline_color", Color(0.11, 0.04, 0.03, 1.0))
    value_label.add_theme_constant_override("outline_size", 4)
    add_child(value_label)
    demo_label = Label.new()
    demo_label.name = "V38ClearlyMarkedDemo"
    demo_label.text = "DEMO"
    demo_label.position = Vector2(-31.0, 22.0)
    demo_label.size = Vector2(62.0, 14.0)
    demo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    demo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    demo_label.add_theme_font_size_override("font_size", 9)
    demo_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.63))
    add_child(demo_label)

func _process(delta: float) -> void:
    elapsed_seconds += maxf(0.0, delta)
    var progress: float = clampf(elapsed_seconds / DISPLAY_SECONDS, 0.0, 1.0)
    position.y -= LIFT_PIXELS * maxf(0.0, delta) / DISPLAY_SECONDS
    # Ease-in fade, reduced jumpiness at video-equivalent 60 FPS.
    var alpha: float = 1.0 if progress < 0.34 else 1.0 - (progress - 0.34) / 0.66
    modulate.a = clampf(alpha, 0.0, 1.0)
    if elapsed_seconds >= DISPLAY_SECONDS:
        queue_free()
