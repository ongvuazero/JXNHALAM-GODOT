extends Node2D

## V36: K is a STATIC source-frame inspector, not a shadow generator.
## V25 created four spatially shifted copies even with G=OFF. That was a
## misleading preview artifact; keep just ONE unshifted source pose now.
const FRAME_SIZE: int = 192
const ATTACK_ATLAS: String = "res://assets/character/blade_attack.png"
const HOLD_FRAME_DEFAULT: int = 8
var actor: CharacterBody2D
var original_sprite: Sprite2D
var active: bool = false
var hold_frame: int = HOLD_FRAME_DEFAULT
var pose_sprite: Sprite2D
var hud_label: Label

func configure(source: CharacterBody2D) -> void:
    actor = source
    original_sprite = source.get_node_or_null("OriginalSPRAlignedVisual") as Sprite2D
    top_level = true
    z_as_relative = false
    z_index = 6
    visible = false
    var texture: Texture2D = load(ATTACK_ATLAS) as Texture2D
    if texture == null:
        push_error("V36 pose inspector: no original atlas")
        return
    pose_sprite = Sprite2D.new()
    pose_sprite.name = "V36_OneSourcePose_NoEcho"
    pose_sprite.region_enabled = true
    pose_sprite.texture = texture
    pose_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    pose_sprite.centered = true
    add_child(pose_sprite)
    hud_label = Label.new()
    hud_label.text = "K • GIỮ 1 KHUNG / N • FRAME"
    hud_label.position = Vector2(-115.0, -142.0)
    hud_label.add_theme_font_size_override("font_size", 13)
    hud_label.modulate = Color(0.96, 0.92, 0.71, 0.95)
    add_child(hud_label)

func set_active(value: bool) -> void:
    if value == active:
        return
    active = value
    if is_instance_valid(original_sprite):
        original_sprite.visible = not active
    visible = active
    if active:
        _redraw_frame()

func step_forward() -> void:
    hold_frame = posmod(hold_frame + 1, 16)
    _redraw_frame()

func _exit_tree() -> void:
    if is_instance_valid(original_sprite):
        original_sprite.visible = true

func _process(_delta: float) -> void:
    if not is_instance_valid(actor):
        if active:
            set_active(false)
        return
    var weapon: Dictionary = actor.call("get_weapon")
    if active and str(weapon.get("visual_id", "")) != "blade":
        set_active(false)
    if active:
        if is_instance_valid(original_sprite):
            global_transform = original_sprite.global_transform
        _redraw_frame()

func _redraw_frame() -> void:
    if not active or not is_instance_valid(pose_sprite) or not is_instance_valid(actor):
        return
    var dir_id: int = posmod(int(actor.get("facing_dir")), 8)
    pose_sprite.region_rect = Rect2(float(hold_frame * FRAME_SIZE),
        float(dir_id * FRAME_SIZE), float(FRAME_SIZE), float(FRAME_SIZE))
    pose_sprite.position = Vector2.ZERO
    pose_sprite.modulate = Color.WHITE
    if hud_label != null:
        hud_label.text = "KHUNG 322: %02d/15 • KHÔNG TẠO BÓNG" % hold_frame
