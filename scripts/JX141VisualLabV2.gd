# JX141 Visual Lab V2. This is an ISOLATED visual debugger; it NEVER modifies game combat.
# Uses original padded atlas PNGs and the 64-dir/32-Spr-dir frame selector from game.exe.
# 3 columns are SEPARATE INSPECTION SLOTS, NOT PROOF OF REAL-TIME THREE-ARC COMPOSITION.
extends Node2D
const FrameProbe = preload("res://scripts/JX141NativeFrameProbe.gd")
const StateModel = preload("res://scripts/JX141StateModel.gd")
const TRACE_PATH = "res://data/renderer_audit/M141_V2_NATIVE_EVIDENCE.json"
const FLY_TEXTURE = preload("res://assets/skill90/jx90_truyphong_sweep.png")
const HIT_TEXTURE = preload("res://assets/skill90/jx90_truyphong_impact.png")

var sample: Array = []
var sprites: Array[Sprite2D] = []
var slot_labels: Array[Label] = []
var title_label: Label
var detail_label: Label
var mode_label: Label
var error_label: Label
var stage: int = 1 # 1: native main fly (state=1), 3: explicitly inspect AnimFile4
var time_mode: int = 0 # 0 duration-mapped, 1 interval-based; actual client flag not yet verified
var tick_age: int = 0
var logical_age_max: int = 4
var interval: int = 1
var play: bool = false
var elapsed: float = 0.0
var direction_adjust: int = 0

func _ready() -> void:
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRACE_PATH))
    if typeof(raw) != TYPE_DICTIONARY:
        push_error("M141 V2 trace JSON is invalid")
        return
    sample = (raw as Dictionary).get("sample", [])
    if sample.size() != 3:
        push_error("M141 V2 expected 3 native server samples")
        return
    _build_background_and_sprites()
    _build_ui()
    _update_view()

func _build_background_and_sprites() -> void:
    for i in range(3):
        var sprite := Sprite2D.new()
        sprite.name = "Slot_%d" % (i + 1)
        sprite.texture = FLY_TEXTURE
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        sprite.centered = true
        sprite.region_enabled = true
        sprite.region_rect = Rect2(0, 0, 256, 256)
        sprite.position = Vector2(235 + i * 400, 385)
        add_child(sprite)
        sprites.append(sprite)
        var label := Label.new()
        label.position = Vector2(80 + i * 400, 545)
        label.size = Vector2(310, 95)
        label.add_theme_font_size_override("font_size", 16)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        add_child(label)
        slot_labels.append(label)

func _make_button(target: HBoxContainer, label: String, cb: Callable) -> void:
    var b := Button.new()
    b.text = label
    b.pressed.connect(cb)
    target.add_child(b)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.offset_left = 14
    panel.offset_top = 14
    panel.offset_right = 1264
    panel.offset_bottom = 168
    layer.add_child(panel)
    var top := VBoxContainer.new()
    top.add_theme_constant_override("separation", 5)
    panel.add_child(top)
    title_label = Label.new()
    title_label.add_theme_font_size_override("font_size", 21)
    title_label.text = "JXNHALAM — M141 NATIVE SPR DEBUG LAB V2 (KHÔNG PHẢI GAMEPLAY PATCH)"
    top.add_child(title_label)
    var row := HBoxContainer.new()
    top.add_child(row)
    _make_button(row, "FLY (state 1)", Callable(self, "_change_stage").bind(1))
    _make_button(row, "HIT SLOT 4 (test)", Callable(self, "_change_stage").bind(3))
    _make_button(row, "FRAME -", Callable(self, "_change_tick").bind(-1))
    _make_button(row, "FRAME +", Callable(self, "_change_tick").bind(1))
    _make_button(row, "DIR -", Callable(self, "_change_dir").bind(-1))
    _make_button(row, "DIR +", Callable(self, "_change_dir").bind(1))
    _make_button(row, "MODE SWITCH", Callable(self, "_toggle_time_mode"))
    _make_button(row, "PLAY/PAUSE", Callable(self, "_toggle_play"))
    _make_button(row, "RESET", Callable(self, "_reset_lab"))
    detail_label = Label.new()
    detail_label.add_theme_font_size_override("font_size", 16)
    top.add_child(detail_label)
    mode_label = Label.new()
    mode_label.add_theme_font_size_override("font_size", 14)
    top.add_child(mode_label)
    var bottom := PanelContainer.new()
    bottom.offset_left = 12
    bottom.offset_top = 650
    bottom.offset_right = 1268
    bottom.offset_bottom = 714
    layer.add_child(bottom)
    error_label = Label.new()
    error_label.text = "NGUỒN: V4 SERVER TRACE | 325 → 408 | 3 HƯỚNG: 3/11/19 (64 hệ) | KHÔNG SUY RA WORLD XY / DAMAGE"
    error_label.add_theme_font_size_override("font_size", 15)
    error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    bottom.add_child(error_label)

func _change_stage(value: int) -> void:
    stage = value
    _update_view()

func _change_tick(amount: int) -> void:
    tick_age = clampi(tick_age + amount, 0, logical_age_max - 1)
    _update_view()

func _change_dir(amount: int) -> void:
    direction_adjust += amount
    _update_view()

func _toggle_time_mode() -> void:
    time_mode = 1 - time_mode
    _update_view()

func _toggle_play() -> void:
    play = not play
    _update_view()

func _reset_lab() -> void:
    stage = 1
    tick_age = 0
    direction_adjust = 0
    time_mode = 0
    play = false
    _update_view()

func _process(delta: float) -> void:
    if not play:
        return
    elapsed += delta
    if elapsed >= 0.5:
        elapsed = 0.0
        tick_age = posmod(tick_age + 1, logical_age_max)
        _update_view()

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    var key_event: InputEventKey = event as InputEventKey
    if not key_event.pressed or key_event.echo:
        return
    match key_event.keycode:
        KEY_LEFT:
            direction_adjust -= 1
        KEY_RIGHT:
            direction_adjust += 1
        KEY_UP:
            tick_age = mini(logical_age_max - 1, tick_age + 1)
        KEY_DOWN:
            tick_age = maxi(0, tick_age - 1)
        KEY_SPACE:
            play = not play
        KEY_R:
            tick_age=0; direction_adjust=0
        _:
            return
    _update_view()

func _update_view() -> void:
    if sample.size() != 3 or sprites.size() != 3:
        return
    var is_fly: bool = stage == 1
    var count: int = 320 if is_fly else 6
    var dirs: int = 32 if is_fly else 1
    var tex: Texture2D = FLY_TEXTURE if is_fly else HIT_TEXTURE
    for i in range(3):
        var point: Dictionary = sample[i]
        var d: int = posmod(int(point.get("dir64", 0)) + direction_adjust, 64)
        var effective_duration: int = logical_age_max
        # These are TEST time modes. M141 runtime mode flag/duration still unmeasured.
        var result: Dictionary = FrameProbe.inspect(count, dirs, d, tick_age, effective_duration, interval, time_mode == 1)
        var spr: Sprite2D = sprites[i]
        spr.texture = tex
        spr.visible = bool(result.get("ok", false))
        if spr.visible:
            var f: int = int(result.get("absolute_frame", 0))
            var row: int = int(result.get("spr_row", 0))
            var local: int = int(result.get("local_frame", 0))
            spr.region_rect = Rect2(local * 256, row * 256, 256, 256)
            slot_labels[i].text = "Slot %d | d64=%d | SPR row=%d\nframe=%d | source trace seq=%d" % [int(point.get("missile_slot",0)), d, row, f, int(point.get("source_seq",0))]
        else:
            slot_labels[i].text = "INVALID frame selector state: %s" % str(result.get("error","?"))
    detail_label.text = "SPR: %s | sample age: %d / 4 | input dir64 offset: %+d" % ["AnimFile2 / 320 frames / 32 dirs" if is_fly else "AnimFile4 / 6 frames / 1 dir",tick_age,direction_adjust]
    mode_label.text = "PREVIEW TIMING: %s | button HIT SLOT 4 is a MANUAL preview, not automatic collision logic" % ("interval branch (parameter=%d)" % interval if time_mode==1 else "duration-mapped branch (duration=4 TEST units)")
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color(0.055, 0.085, 0.107))
    for i in range(0, 1281, 40):
        draw_line(Vector2(i,175),Vector2(i,650),Color(0.16,0.23,0.25,0.4),1.0)
    for i in range(175,650,40):
        draw_line(Vector2(0,i),Vector2(1280,i),Color(0.16,0.23,0.25,0.4),1.0)
    if sample.size() != 3:
        return
    for i in range(3):
        var point: Dictionary = sample[i]
        var center := Vector2(235+i*400,385)
        draw_circle(center,2.5,Color(0.45,0.8,0.9))
        # An arrow points along NATIVE SERVER X/Y FACTOR, drawn in a fixed
        # purely illustrative scale. This arrow is NOT a world position trace.
        var direction := Vector2(float(point.get("x_factor",0)),float(point.get("y_factor",0))).normalized()
        var vec := direction * 116.0
        draw_line(center,center+vec,Color(0.25,0.75,0.9,0.65),2.0)
        draw_line(center+vec, center+vec-direction.rotated(0.5)*14.0, Color(0.25,0.75,0.9,0.65),2.0)
        draw_line(center+vec, center+vec-direction.rotated(-0.5)*14.0,Color(0.25,0.75,0.9,0.65),2.0)
