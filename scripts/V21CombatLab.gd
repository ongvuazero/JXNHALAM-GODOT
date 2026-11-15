extends Node2D
## Playable evidence lab for six 9x skills. Test geometry and test HP are deliberately
## separated from source-verified skill/child/missile counts and Lua level values.
## NOT a verified replica of JX server damage or original SPR frame timing.
const MISSILE = preload("res://scripts/V21LabMissile.gd")
const PROFILE_PATH: String = "res://data/v21/six_skills_v21.json"
const IDS: Array[int] = [322, 323, 325, 318, 319, 321]
const PLAYER_POS: Vector2 = Vector2(335, 424)
const TARGET_POS: Vector2 = Vector2(867, 424)
const TARGET_CENTER: Vector2 = Vector2(867, 375)
const STEP_PREVIEW_SECONDS: float = 0.19 # DEMO wall-clock, not measured JX tick.
const PRACTICE_DAMAGE_PER_CONTACT: int = 10 # DEMO constant; never Lua physicsenhance_p.
const PRACTICE_HP: int = 900

var database: Dictionary = {}
var selected_index: int = 0
var level: int = 1
var command_step: int = 0
var cast_number: int = 0
var child_attempts: int = 0
var allocations: int = 0
var contact_candidates: int = 0
var commits: int = 0
var dummy_hp: int = PRACTICE_HP
var scheduled: Array[Dictionary] = []
var projectiles: Array[Area2D] = []
var auto_play: bool = true
var demo_damage: bool = false
var spread_px: float = 68.0
var accumulator: float = 0.0
var event_lines: Array[String] = []
var selected_label: Label
var counters_label: Label
var source_label: Label
var controls_label: Label
var event_label: RichTextLabel
var damage_button: Button
var autoplay_button: Button
var level_label: Label
var ground_load_status: String = "NOT_LOADED"
var actor_sprite: Sprite2D
var actor_idle_texture: Texture2D
var actor_attack_texture: Texture2D
var actor_idle_frame_count: int = 11
var actor_attack_frame_count: int = 16
var actor_anim_elapsed: float = 0.0
var actor_attack_remaining: float = 0.0
var dummy_body: StaticBody2D
var dummy_collision: CollisionShape2D
var dummy_sprite: Sprite2D
var active_buttons: Array[Button] = []

func _ready() -> void:
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
    if not raw is Dictionary:
        push_error("V21: cannot parse source-based skill profiles")
        return
    database = raw.get("entries", {})
    _make_world()
    _make_ui()
    _select_skill(0)
    _append_event("V21.3 READY | Area2D + swept dummy geometry | test collision only")
    _append_event("BACKGROUND: " + ground_load_status)
    queue_redraw()

# Godot 4.6 may not have an imported Texture2D cache immediately after ZIP extraction.
# Decode the existing source PNG directly for the editor; imported textures remain
# a fallback for exported projects where the raw PNG is not packed.
func _load_training_background_texture() -> Texture2D:
    var path: String = "res://assets/background/training_ground.png"
    if FileAccess.file_exists(path):
        var image := Image.new()
        var err: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
        if err == OK and not image.is_empty():
            ground_load_status = "SOURCE_PNG %dx%d" % [image.get_width(), image.get_height()]
            return ImageTexture.create_from_image(image)
    if ResourceLoader.exists(path, "Texture2D"):
        var candidate: Resource = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
        if candidate is Texture2D:
            ground_load_status = "IMPORTED_TEXTURE"
            return candidate as Texture2D
    ground_load_status = "PNG_NOT_AVAILABLE / FALLBACK"
    push_warning("V21.2: training_ground.png unavailable; using the visible ground fallback")
    return null

func _make_world() -> void:
    var background_texture: Texture2D = _load_training_background_texture()
    if background_texture != null:
        var background := Sprite2D.new()
        background.name = "TrainingGround"
        background.texture = background_texture
        background.centered = false
        background.scale = Vector2(1280.0 / float(background_texture.get_width()), 720.0 / float(background_texture.get_height()))
        background.modulate = Color(0.51, 0.64, 0.72)
        background.z_index = -20
        add_child(background)
    else:
        var fallback := ColorRect.new()
        fallback.name = "GroundFallback"
        fallback.color = Color(0.13, 0.23, 0.24)
        fallback.size = Vector2(1280, 720)
        fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
        fallback.z_index = -20
        add_child(fallback)
    var shade := ColorRect.new()
    shade.color = Color(0.025, 0.07, 0.12, 0.34)
    shade.size = Vector2(1280, 720)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shade.z_index = -10
    add_child(shade)

    actor_sprite = Sprite2D.new()
    actor_sprite.name = "ReferenceCharacter"
    actor_sprite.region_enabled = true
    actor_sprite.region_rect = Rect2(0, 6 * 192, 192, 192)
    actor_sprite.position = PLAYER_POS + Vector2(0, -83)
    actor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    actor_sprite.scale = Vector2(0.95, 0.95)
    add_child(actor_sprite)

    dummy_body = StaticBody2D.new()
    dummy_body.name = "V21TargetDummy"
    dummy_body.position = TARGET_POS
    dummy_body.collision_layer = 1
    dummy_body.collision_mask = 0
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 37.0
    shape.shape = circle
    shape.position = Vector2(0, -49)
    shape.name = "DummyHurtboxDemo"
    dummy_body.add_child(shape)
    dummy_collision = shape
    add_child(dummy_body)
    dummy_sprite = Sprite2D.new()
    dummy_sprite.texture = load("res://assets/npc/training_dummy.png") as Texture2D
    dummy_sprite.scale = Vector2(0.54, 0.54)
    dummy_sprite.position = Vector2(0, -59)
    dummy_body.add_child(dummy_sprite)

func _label(parent: Node, content: String, pos: Vector2, size: Vector2, font_size: int = 16) -> Label:
    var item := Label.new()
    item.text = content
    item.position = pos
    item.size = size
    item.add_theme_font_size_override("font_size", font_size)
    item.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(item)
    return item

func _button(parent: Node, content: String, pos: Vector2, size: Vector2, callback: Callable) -> Button:
    var btn := Button.new()
    btn.text = content
    btn.position = pos
    btn.size = size
    btn.add_theme_font_size_override("font_size", 14)
    parent.add_child(btn)
    btn.pressed.connect(callback)
    return btn

func _make_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "V21Controls"
    add_child(layer)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(root)
    var top := ColorRect.new()
    top.color = Color(0.025, 0.07, 0.12, 0.94)
    top.size = Vector2(1280, 204)
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(top)
    _label(root, "V21 • 10 PHÁI 9X — KIỂM CHỨNG 6 SKILL", Vector2(18, 5), Vector2(850, 38), 22)
    _button(root, "B: Về game gốc", Vector2(1040, 8), Vector2(220, 31), _return_to_game)
    var names: Array[String] = ["1  ĐAO 322", "2  THƯƠNG 323", "3  CHÙY 325", "4  THIẾU LÂM 318", "5  THIẾU LÂM 319", "6  THIẾU LÂM 321"]
    for i in range(IDS.size()):
        var b := _button(root, names[i], Vector2(18 + i * 208, 47), Vector2(201, 38), _select_skill.bind(i))
        active_buttons.append(b)
    selected_label = _label(root, "", Vector2(18, 88), Vector2(770, 31), 17)
    _button(root, "− CẤP", Vector2(810, 91), Vector2(95, 29), _change_level.bind(-1))
    level_label = _label(root, "Cấp 1", Vector2(916, 92), Vector2(86, 30), 16)
    _button(root, "+ CẤP", Vector2(1008, 91), Vector2(90, 29), _change_level.bind(1))
    _button(root, "Cấp 20", Vector2(1109, 91), Vector2(141, 29), _set_level_20)
    source_label = _label(root, "", Vector2(18, 126), Vector2(1236, 27), 14)
    counters_label = _label(root, "", Vector2(18, 153), Vector2(1235, 25), 14)
    controls_label = _label(root, "", Vector2(18, 179), Vector2(1235, 23), 13)
    _button(root, "SPACE • TUNG SKILL", Vector2(19, 501), Vector2(238, 45), _cast)
    autoplay_button = _button(root, "P • AUTO: ON", Vector2(271, 501), Vector2(187, 45), _toggle_auto)
    _button(root, "ENTER • BƯỚC", Vector2(470, 501), Vector2(181, 45), _advance_step)
    damage_button = _button(root, "H • HP DEMO: OFF", Vector2(663, 501), Vector2(208, 45), _toggle_damage)
    _button(root, "R • RESET", Vector2(882, 501), Vector2(183, 45), _reset_battle)
    _button(root, "[  /  ]  SPREAD", Vector2(1075, 501), Vector2(182, 45), _cycle_spread)
    var bottom := ColorRect.new()
    bottom.color = Color(0.025, 0.065, 0.11, 0.94)
    bottom.size = Vector2(1280, 165)
    bottom.position = Vector2(0, 555)
    bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(bottom)
    event_label = RichTextLabel.new()
    event_label.bbcode_enabled = false
    event_label.scroll_following = true
    event_label.position = Vector2(20, 562)
    event_label.size = Vector2(1234, 148)
    event_label.add_theme_font_size_override("normal_font_size", 15)
    event_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(event_label)

func _profile() -> Dictionary:
    return database.get(str(IDS[selected_index]), {})

func _field_scalar(field_name: String) -> Variant:
    var level_data: Dictionary = _profile().get("level_triplets", {})
    if not level_data.has(field_name):
        return null
    var series: Array = level_data[field_name]
    if level < 1 or level > series.size():
        return null
    var triple: Array = series[level - 1]
    return triple[0] if triple.size() > 0 else null

func _select_skill(index: int) -> void:
    if index < 0 or index >= IDS.size():
        return
    selected_index = index
    _reset_battle()
    var source: String = "blade_stand.png"
    if IDS[index] == 323:
        source = "spear_stand.png"
    elif IDS[index] == 325:
        source = "hammer_stand.png"
    var weapon: String = source.trim_suffix("_stand.png")
    actor_idle_texture = load("res://assets/character/" + source) as Texture2D
    actor_attack_texture = load("res://assets/character/" + weapon + "_attack.png") as Texture2D
    var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/manifest.json"))
    var actor_data: Dictionary = manifest.get(weapon, {})
    actor_idle_frame_count = int(actor_data.get("stand", {}).get("frames_per_direction", 11))
    actor_attack_frame_count = int(actor_data.get("attack", {}).get("frames_per_direction", 16))
    actor_sprite.texture = actor_idle_texture
    actor_sprite.region_rect = Rect2(0, 6 * 192, 192, 192)
    actor_anim_elapsed = 0.0
    actor_attack_remaining = 0.0
    actor_sprite.modulate = Color(0.70, 0.95, 1.00) if IDS[index] in [318, 319, 321] else Color.WHITE
    _append_event("SELECT %d | %s | %s" % [IDS[index], str(_profile().get("name", "")), str(_profile().get("family", "?"))])
    if IDS[index] in [318, 319, 321]:
        _append_event("ART: Thiếu Lâm chỉ dùng nhân vật Đao tạm để QUAN SÁT — chưa có SPR Thiếu Lâm đã duyệt")
    _refresh_ui()

func _change_level(delta: int) -> void:
    level = clampi(level + delta, 1, 20)
    _reset_battle()
    _append_event("LUA LEVEL changed -> %d (not player XP level)" % level)

func _set_level_20() -> void:
    level = 20
    _reset_battle()
    _append_event("LUA LEVEL -> 20")

func _cast() -> void:
    if not scheduled.is_empty() or not projectiles.is_empty():
        _append_event("WAIT: Finish current trial or R to reset")
        return
    var profile: Dictionary = _profile()
    if profile.is_empty():
        return
    command_step = 0
    cast_number += 1
    actor_attack_remaining = 0.82 # Visual inspection only, NOT JX pose duration.
    actor_anim_elapsed = 0.0
    var family: String = str(profile.get("family", ""))
    var count: int = int(profile.get("child_attempts", 0))
    var interval: Variant = profile.get("interval_calls", null)
    for i in range(count):
        var at_step: int = (i + 1) * int(interval) if family == "STYLE1_FORM12" else i + 1
        scheduled.append({"step": at_step, "index": i + 1})
    _append_event("PARENT #%d skill=%d | child %d x%d | schedule %s" % [cast_number, int(profile["id"]), int(profile["child_skill_id"]), count, "ASM counter" if family == "STYLE1_FORM12" else "UNVERIFIED preview"])
    _refresh_ui()

func _advance_step() -> void:
    if scheduled.is_empty():
        return
    command_step += 1
    while not scheduled.is_empty() and int(scheduled[0]["step"]) <= command_step:
        var e: Dictionary = scheduled.pop_front()
        child_attempts += 1
        _emit_child(int(e["index"]))
    _refresh_ui()

func _emit_child(child_index: int) -> void:
    var profile: Dictionary = _profile()
    var per_child: int = int(profile.get("missiles_per_child", 1))
    _append_event("STEP %d -> child attempt %d: Skill %d / %d missile configuration(s)" % [command_step, child_index, int(profile["child_skill_id"]), per_child])
    for j in range(per_child):
        allocations += 1
        _spawn_projectile(j, per_child)

func _spawn_projectile(index: int, count: int) -> void:
    var profile: Dictionary = _profile()
    var missile: Area2D = MISSILE.new()
    missile.set("missile_id", int(profile.get("missile_id", 0)))
    missile.set("ordinal", allocations)
    missile.set("target_body", dummy_body)
    missile.set("target_shape", dummy_collision)
    missile.set("projectile_color", Color(1.0, 0.65, 0.20) if selected_index < 3 else Color(0.26, 0.83, 1.0))
    var center: float = float(index) - float(count - 1) * 0.5
    var offset: float = center * spread_px
    missile.set("stationary", int(profile.get("missile_move_kind", 1)) == 0)
    if bool(missile.get("stationary")):
        missile.position = TARGET_CENTER + Vector2(0, offset)
    else:
        missile.position = PLAYER_POS + Vector2(26, -50 + offset)
        missile.set("direction", (TARGET_CENTER + Vector2(0, offset) - missile.position).normalized())
        missile.set("speed_px", 560.0) # DEMO speed, NOT source.
    missile.set("life_seconds", 1.75)
    missile.connect("contacted", _on_missile_contact)
    missile.connect("vanished", _on_missile_expired)
    add_child(missile)
    projectiles.append(missile)
    _refresh_ui()

func _on_missile_contact(missile: Area2D) -> void:
    contact_candidates += 1
    _forget_missile(missile)
    _append_event("CONTACT %s: M%d #%d -> dummy | demo collider only" % [str(missile.get("contact_mode")), int(missile.get("missile_id")), int(missile.get("ordinal"))])
    if demo_damage:
        if dummy_hp > 0:
            dummy_hp = maxi(0, dummy_hp - PRACTICE_DAMAGE_PER_CONTACT)
            commits += 1
            _append_event("HP DEMO: -%d -> %d/%d [TEST CONSTANT, NOT JX DAMAGE]" % [PRACTICE_DAMAGE_PER_CONTACT, dummy_hp, PRACTICE_HP])
    queue_redraw()
    _refresh_ui()

func _on_missile_expired(missile: Area2D) -> void:
    _forget_missile(missile)
    _append_event("MISS / EXPIRE: M%d #%d -> no collision candidate" % [int(missile.get("missile_id")), int(missile.get("ordinal"))])
    _refresh_ui()

func _forget_missile(missile: Area2D) -> void:
    projectiles.erase(missile)

func _process(delta: float) -> void:
    actor_anim_elapsed += delta
    if actor_attack_remaining > 0.0:
        actor_attack_remaining = maxf(0.0, actor_attack_remaining - delta)
    if actor_sprite != null:
        var attacking: bool = actor_attack_remaining > 0.0
        var count: int = actor_attack_frame_count if attacking else actor_idle_frame_count
        var speed: float = 0.82 / float(maxi(1, count)) if attacking else 0.10
        var frame: int = mini(maxi(0, count - 1), int(actor_anim_elapsed / speed)) if attacking else posmod(int(actor_anim_elapsed / speed), maxi(1, count))
        actor_sprite.texture = actor_attack_texture if attacking else actor_idle_texture
        actor_sprite.region_rect = Rect2(float(frame * 192), float(6 * 192), 192.0, 192.0)
    if auto_play and not scheduled.is_empty():
        accumulator += delta
        var max_steps: int = 0
        while accumulator >= STEP_PREVIEW_SECONDS and max_steps < 5:
            accumulator -= STEP_PREVIEW_SECONDS
            max_steps += 1
            _advance_step()
    queue_redraw()

func _toggle_auto() -> void:
    auto_play = not auto_play
    accumulator = 0.0
    _refresh_ui()

func _toggle_damage() -> void:
    demo_damage = not demo_damage
    _append_event("HP TEST constant 10 per candidate is now %s" % ("ON" if demo_damage else "OFF"))
    _refresh_ui()

func _cycle_spread() -> void:
    var values: Array[float] = [0.0, 32.0, 68.0, 96.0]
    var idx: int = values.find(spread_px)
    spread_px = values[(idx + 1) % values.size()]
    _append_event("DEMO SPREAD = %d px | Affects collider path, not source missile count" % int(spread_px))
    _refresh_ui()

func _reset_battle() -> void:
    for projectile in projectiles:
        if is_instance_valid(projectile):
            projectile.queue_free()
    projectiles.clear()
    scheduled.clear()
    command_step = 0
    accumulator = 0.0
    child_attempts = 0
    allocations = 0
    contact_candidates = 0
    commits = 0
    dummy_hp = PRACTICE_HP
    actor_attack_remaining = 0.0
    actor_anim_elapsed = 0.0
    event_lines.clear()
    _refresh_ui()
    queue_redraw()

func _return_to_game() -> void:
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _append_event(line: String) -> void:
    event_lines.append(line)
    if event_lines.size() > 7:
        event_lines.pop_front()
    if event_label != null:
        event_label.text = "\n".join(PackedStringArray(event_lines))

func _refresh_ui() -> void:
    if selected_label == null:
        return
    var p: Dictionary = _profile()
    if p.is_empty():
        return
    for i in range(active_buttons.size()):
        active_buttons[i].disabled = i == selected_index
    level_label.text = "Cấp %02d" % level
    selected_label.text = "%s — Skill %d | Con %d × %d → Missile %d × %d" % [str(p.get("name", "")), int(p["id"]), int(p["child_skill_id"]), int(p["child_attempts"]), int(p["missile_id"]), int(p["missiles_per_child"])]
    var physical: Variant = _field_scalar("physicsenhance_p")
    var cost: Variant = _field_scalar("skill_cost_v")
    var radius: Variant = _field_scalar("skill_attackradius")
    source_label.text = "LUA GỐC [tham số, KHÔNG phải HP]: physicsenhance_p=%s | skill_cost_v=%s | skill_attackradius=%s | group=%s" % [str(physical), str(cost), str(radius), str(p["family"])]
    counters_label.text = "BƯỚC %d | Cast thử %d | Child attempts %d | Missile đã sinh %d | CONTACT %d | HP COMMIT DEMO %d | Dummy %d/%d" % [command_step, cast_number, child_attempts, allocations, contact_candidates, commits, dummy_hp, PRACTICE_HP]
    controls_label.text = "AUTO %s | HP DEMO %s | SPREAD %dpx | [ ] điều chỉnh spread | ENTER bước riêng | H bật HP | P auto | R reset | B về game" % ["ON" if auto_play else "OFF", "ON" if demo_damage else "OFF", int(spread_px)]
    if damage_button != null:
        damage_button.text = "H • HP DEMO: " + ("ON" if demo_damage else "OFF")
    if autoplay_button != null:
        autoplay_button.text = "P • AUTO: " + ("ON" if auto_play else "OFF")

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
            _select_skill(int(event.keycode) - KEY_1)
        KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
            _change_level(1)
        KEY_MINUS, KEY_KP_SUBTRACT:
            _change_level(-1)
        KEY_SPACE:
            _cast()
        KEY_ENTER, KEY_KP_ENTER:
            _advance_step()
        KEY_P:
            _toggle_auto()
        KEY_H:
            _toggle_damage()
        KEY_R:
            _reset_battle()
        KEY_BRACKETLEFT:
            spread_px = maxf(0.0, spread_px - 16.0)
            _refresh_ui()
        KEY_BRACKETRIGHT:
            spread_px = minf(128.0, spread_px + 16.0)
            _refresh_ui()
        KEY_B, KEY_F2, KEY_ESCAPE:
            _return_to_game()
    queue_redraw()

func _draw() -> void:
    var white := Color(0.91, 0.97, 1.0, 0.62)
    draw_line(Vector2(352, 373), TARGET_CENTER, Color(0.5, 0.81, 0.98, 0.35), 2.0, true)
    draw_arc(TARGET_CENTER, 54.0, 0, TAU, 48, Color(1.0, 0.82, 0.2, 0.30), 2.0, true)
    draw_rect(Rect2(813, 264, 108, 11), Color(0.06, 0.12, 0.15, 0.91))
    draw_rect(Rect2(815, 266, 104.0 * float(dummy_hp) / float(PRACTICE_HP), 7), Color(0.89, 0.23, 0.17))
    draw_string(ThemeDB.fallback_font, Vector2(804, 248), "TARGET DUMMY   %d / %d" % [dummy_hp, PRACTICE_HP], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, white)
    draw_string(ThemeDB.fallback_font, Vector2(255, 265), "PLAYER POSE • SPR bundle", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, white)
    draw_string(ThemeDB.fallback_font, Vector2(405, 475), "V21.3 swept + Area2D DEMO collision; NOT original JX1 geometry", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.72))
