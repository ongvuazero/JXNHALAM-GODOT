extends CanvasLayer
## V6.7.1 visual QA panel. User reference images are independent of server trace.
## Calibration affects only VFX rendering offsets/scale; not collision, HP or missile counts.
signal calibration_changed(skill_id: int, config: Dictionary)

const CONFIG_PATH: String = "user://JXNHALAM_9X_VISUAL_QA.json"
const REFERENCES: Dictionary = {
    "322": "res://qa_reference/client_9x_322.jpg",
    "323": "res://qa_reference/client_9x_323.jpg"
}
const WARNINGS: Dictionary = {
    "322": "Đao: vệt vàng có trước marker. Không suy ra hit frame.",
    "323": "Thương: xanh = buff 1427; có ảnh damage, chưa rõ SPR 9x.",
    "325": "Chùy: ảnh gốc bị bảng trang bị che; CHƯA CÓ tham chiếu sạch."
}

var enabled: bool = false
var current_skill_id: int = 322
var values: Dictionary = {}
var background: ColorRect
var reference: TextureRect
var header: Label
var detail: Label
var warning: Label
var saved: Label

func _ready() -> void:
    layer = 12
    _load_values()
    _build_panel()
    visible = false

func _default_calibration() -> Dictionary:
    return {"offset_x": 0.0, "offset_y": 0.0, "scale": 1.0}

func _load_values() -> void:
    values = {"322": _default_calibration(), "323": _default_calibration(), "325": _default_calibration()}
    if not FileAccess.file_exists(CONFIG_PATH):
        return
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
    if not decoded is Dictionary:
        return
    var recorded: Variant = decoded.get("skills", {})
    if not recorded is Dictionary:
        return
    for skill_id in values.keys():
        var row: Variant = recorded.get(skill_id, {})
        if row is Dictionary:
            values[skill_id] = _validated(row)

func _validated(row: Dictionary) -> Dictionary:
    return {
        "offset_x": clampf(float(row.get("offset_x", 0.0)), -160.0, 160.0),
        "offset_y": clampf(float(row.get("offset_y", 0.0)), -160.0, 160.0),
        "scale": clampf(float(row.get("scale", 1.0)), 0.15, 3.0)
    }

func _build_panel() -> void:
    background = ColorRect.new()
    background.position = Vector2(759, 66)
    background.size = Vector2(508, 534)
    background.color = Color(0.04, 0.07, 0.11, 0.96)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    header = Label.new()
    header.position = Vector2(775, 76)
    header.add_theme_font_size_override("font_size", 19)
    header.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(header)
    reference = TextureRect.new()
    reference.position = Vector2(775, 109)
    reference.size = Vector2(475, 337)
    reference.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    reference.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    reference.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    reference.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(reference)
    detail = Label.new()
    detail.position = Vector2(778, 457)
    detail.size = Vector2(474, 47)
    detail.add_theme_font_size_override("font_size", 14)
    detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(detail)
    warning = Label.new()
    warning.position = Vector2(778, 508)
    warning.size = Vector2(474, 48)
    warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    warning.add_theme_font_size_override("font_size", 13)
    warning.add_theme_color_override("font_color", Color(1.0, 0.81, 0.49))
    warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(warning)
    saved = Label.new()
    saved.position = Vector2(778, 565)
    saved.size = Vector2(474, 25)
    saved.add_theme_font_size_override("font_size", 12)
    saved.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(saved)
    _refresh()

func set_active_skill(skill_id: int) -> void:
    if skill_id == current_skill_id:
        return
    current_skill_id = skill_id
    _refresh()

func get_for_skill(skill_id: int) -> Dictionary:
    return (values.get(str(skill_id), _default_calibration()) as Dictionary).duplicate(true)

func toggle_panel() -> void:
    enabled = not enabled
    visible = enabled
    _refresh()

func adjust_scale(delta: float) -> void:
    var row: Dictionary = get_for_skill(current_skill_id)
    row["scale"] = clampf(snappedf(float(row["scale"]) + delta, 0.05), 0.15, 3.0)
    _change(row)

func adjust_position(dx: float, dy: float) -> void:
    var row: Dictionary = get_for_skill(current_skill_id)
    row["offset_x"] = clampf(float(row["offset_x"]) + dx, -160.0, 160.0)
    row["offset_y"] = clampf(float(row["offset_y"]) + dy, -160.0, 160.0)
    _change(row)

func reset_skill() -> void:
    _change(_default_calibration())

func _change(row: Dictionary) -> void:
    values[str(current_skill_id)] = _validated(row)
    if saved != null:
        saved.text = "CHƯA LƯU — J để ghi JSON"
    _refresh()
    calibration_changed.emit(current_skill_id, get_for_skill(current_skill_id))

func save_values() -> void:
    var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
    if file == null:
        saved.text = "LỖI GHI: " + str(FileAccess.get_open_error())
        return
    file.store_string(JSON.stringify({"version": 1, "unit": "Godot world px; scale visual only", "skills": values}, "  "))
    file.close()
    saved.text = "ĐÃ LƯU: " + ProjectSettings.globalize_path(CONFIG_PATH)
    print("VFX QA JSON: ", ProjectSettings.globalize_path(CONFIG_PATH))

func capture_screenshot() -> void:
    var path: String = "user://JXNHALAM_VFX_QA_%d.png" % current_skill_id
    var image: Image = get_viewport().get_texture().get_image()
    var status: Error = image.save_png(path)
    saved.text = "ẢNH: " + ProjectSettings.globalize_path(path) if status == OK else "LỖI XUẤT ẢNH"
    print("VFX QA screenshot: ", ProjectSettings.globalize_path(path))

func _refresh() -> void:
    if header == null:
        return
    header.text = "F9 VFX QA — 9x Skill %d" % current_skill_id
    var path: String = str(REFERENCES.get(str(current_skill_id), ""))
    if path.is_empty():
        reference.texture = null
    else:
        reference.texture = load(path) as Texture2D
    var row: Dictionary = get_for_skill(current_skill_id)
    detail.text = "Alt+←↑↓→: ±4px | [ ]: scale ±5%% | R: reset\nX:%+5.0f Y:%+5.0f Scale: %.2f | J: lưu JSON | K: ảnh" % [
        float(row["offset_x"]), float(row["offset_y"]), float(row["scale"])]
    warning.text = str(WARNINGS.get(str(current_skill_id), "Chưa có ảnh tham chiếu."))
