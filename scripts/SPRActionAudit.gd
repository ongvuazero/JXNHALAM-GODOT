extends Control
## JXNHALAM V26: source-driven inspection tool for JX1 character action sprites.
## Does not cast skills, change damage, or manufacture missing SPR pixel data.
const DB_PATH: String = "res://data/renderer_audit/blade_004_action_profiles.json"
const CANVAS_SCRIPT = preload("res://scripts/SPRMetadataCanvas.gd")
const SPR_CODEC = preload("res://scripts/JXSPRCodec.gd")
const AT03_EXTRACTOR = preload("res://scripts/V27AT03Extractor.gd")
const LOOSE_SPR_DIR: String = "res://data/spr/npcres/man/"
const COLOR_BG: Color = Color("#0c1921")
const COLOR_HEAD: Color = Color("#14252d")
const COLOR_ACCENT: Color = Color("#dfb962")
const INSPECT_INTERVAL: float = 0.15 # demonstration only; NOT original JX1 timing

var profiles: Array = []
var selected_action: int = 0
var direction_index: int = 6
var frame_index: int = 0
var is_playing: bool = false
var elapsed: float = 0.0
var preview: TextureRect
var missing_notice: Label
var metadata_view: Control
var info: Label
var source_list: Label
var status: Label
var action_selector: OptionButton
var play_button: Button
var frame_label: Label
var layer_selector: OptionButton
var atlas_cache: Dictionary = {}
var decoded_layer_cache: Dictionary = {}
var client_picker: FileDialog
var extraction_report: AcceptDialog
var scan_note: String = ""

func _ready() -> void:
    size = Vector2(1280, 720)
    var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(DB_PATH))
    if source is not Dictionary:
        push_error("V26 audit: cannot parse data " + DB_PATH)
        return
    profiles = source.get("actions", [])
    if profiles.is_empty():
        push_error("V26 audit: missing action profiles")
        return
    _build_layout()
    _refresh()

func _make_label(txt: String, p: Vector2, s: Vector2, font_px: int = 15, tint: Color = Color.WHITE) -> Label:
    var label := Label.new()
    label.text = txt
    label.position = p
    label.size = s
    label.add_theme_font_size_override("font_size", font_px)
    label.add_theme_color_override("font_color", tint)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(label)
    return label

func _panel(p: Vector2, s: Vector2, tint: Color = COLOR_HEAD) -> void:
    var panel := ColorRect.new()
    panel.position = p
    panel.size = s
    panel.color = tint
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(panel)

func _button(txt: String, p: Vector2, s: Vector2, method: Callable) -> Button:
    var button := Button.new()
    button.text = txt
    button.position = p
    button.size = s
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(method)
    add_child(button)
    return button

func _build_layout() -> void:
    _panel(Vector2.ZERO, Vector2(1280, 720), COLOR_BG)
    _panel(Vector2.ZERO, Vector2(1280, 69))
    _make_label("V26 / JX1 SPR RENDERER AUDIT — DAO 1 TAY", Vector2(18, 10), Vector2(820, 32), 23)
    _make_label("Client AT02/AT03 • raw SPR extraction without full PAK unpack", Vector2(18, 39), Vector2(830, 24), 13, COLOR_ACCENT)
    _button("T · TÌM AT03 TỪ PAK", Vector2(847, 15), Vector2(220, 37), Callable(self, "_choose_client_folder"))
    _button("B · VỀ GAME", Vector2(1080, 15), Vector2(177, 37), Callable(self, "_back_to_game"))
    _button("C · GHÉP 6 SPR", Vector2(1078, 535), Vector2(178, 33), Callable(self, "_open_six_layer_composer"))
    action_selector = OptionButton.new()
    action_selector.position = Vector2(18, 88)
    action_selector.size = Vector2(389, 36)
    action_selector.focus_mode = Control.FOCUS_NONE
    for item in profiles:
        var p: Dictionary = item
        var has_atlas: bool = bool(p.get("atlas_available", false))
        var label: String = "%s / %s / %s" % [str(p.get("id")), str(p.get("mapped_column")), "PNG" if has_atlas else "THIẾU PIXEL"]
        action_selector.add_item(label)
    action_selector.item_selected.connect(Callable(self, "_select_action"))
    add_child(action_selector)
    _button("HƯỚNG −", Vector2(430, 88), Vector2(104, 36), Callable(self, "_prev_dir"))
    _button("HƯỚNG +", Vector2(541, 88), Vector2(104, 36), Callable(self, "_next_dir"))
    _button("FRAME −", Vector2(653, 88), Vector2(103, 36), Callable(self, "_prev_frame"))
    _button("FRAME +", Vector2(763, 88), Vector2(103, 36), Callable(self, "_next_frame"))
    play_button = _button("PLAY thử", Vector2(877, 88), Vector2(131, 36), Callable(self, "_toggle_play"))
    frame_label = _make_label("", Vector2(1018, 94), Vector2(250, 28), 15, COLOR_ACCENT)

    _panel(Vector2(18, 142), Vector2(386, 423))
    _panel(Vector2(415, 142), Vector2(398, 423))
    _panel(Vector2(825, 142), Vector2(438, 423))
    _make_label("ATLAS GHÉP (192×192 mỗi frame)", Vector2(31, 155), Vector2(362, 22), 15)
    _make_label("BBOX SPR GỐC (tọa độ 320×320)", Vector2(429, 155), Vector2(372, 22), 15)
    _make_label("THÔNG TIN / ĐỘ TIN CẬY", Vector2(840, 155), Vector2(416, 23), 15)

    preview = TextureRect.new()
    preview.position = Vector2(43, 213)
    preview.size = Vector2(336, 312)
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(preview)
    missing_notice = _make_label("", Vector2(36, 255), Vector2(360, 235), 17, COLOR_ACCENT)
    missing_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    missing_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    metadata_view = Control.new()
    metadata_view.name = "OriginalSPRBBoxes"
    metadata_view.set_script(CANVAS_SCRIPT)
    metadata_view.position = Vector2(454, 195)
    metadata_view.size = Vector2(320, 320)
    add_child(metadata_view)
    _make_label("Khung giới hạn từng layer; KHÔNG phải ảnh SPR", Vector2(436, 531), Vector2(375, 24), 12, Color("#b9c7cb"))

    info = _make_label("", Vector2(839, 187), Vector2(414, 206), 14)
    layer_selector = OptionButton.new()
    layer_selector.position = Vector2(840, 394)
    layer_selector.size = Vector2(406, 31)
    layer_selector.focus_mode = Control.FOCUS_NONE
    layer_selector.item_selected.connect(Callable(self, "_select_layer"))
    add_child(layer_selector)
    source_list = _make_label("", Vector2(841, 435), Vector2(410, 94), 12)

    _panel(Vector2(18, 579), Vector2(1245, 124))
    status = _make_label("", Vector2(31, 592), Vector2(1217, 105), 15)
    # Windows directory picker; no CLI or Codex is required on the user's PC.
    client_picker = FileDialog.new()
    client_picker.title = "Chọn thư mục JX1 chứa package.ini + data\\*.pak"
    client_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    client_picker.access = FileDialog.ACCESS_FILESYSTEM
    client_picker.use_native_dialog = false
    client_picker.size = Vector2i(950, 570)
    client_picker.dir_selected.connect(Callable(self, "_on_client_folder_picked"))
    add_child(client_picker)
    extraction_report = AcceptDialog.new()
    extraction_report.title = "V27 — Kết quả trích AT03"
    extraction_report.size = Vector2i(980, 510)
    add_child(extraction_report)

func _load_png(path: String) -> Texture2D:
    if atlas_cache.has(path):
        return atlas_cache[path]
    var result: Texture2D = null
    if path.begins_with("res://") and FileAccess.file_exists(path):
        var image: Image = Image.new()
        var err: Error = image.load(path)
        if err == OK:
            result = ImageTexture.create_from_image(image)
    if result == null:
        result = load(path) as Texture2D
    atlas_cache[path] = result
    return result

func _refresh() -> void:
    if profiles.is_empty():
        return
    var p: Dictionary = profiles[selected_action]
    var count: int = int(p.get("frames_per_dir", 1))
    frame_index = clampi(frame_index, 0, count - 1)
    frame_label.text = "DIR %d/7  |  FRAME %02d/%02d" % [direction_index, frame_index, count - 1]
    play_button.text = "DỪNG" if is_playing else "PLAY thử"

    var atlas_path: String = str(p.get("composite_atlas", ""))
    var loose_spr: String = ""
    var current_layer_id: int = layer_selector.get_selected_id()
    var action_layers: Array = p.get("layers", [])
    if current_layer_id > 0 and current_layer_id <= action_layers.size():
        loose_spr = LOOSE_SPR_DIR + str(action_layers[current_layer_id - 1].get("source_spr", ""))
    preview.texture = null
    missing_notice.text = ""
    if loose_spr != "" and FileAccess.file_exists(loose_spr):
        var decoded: Dictionary = _load_one_loose_spr(loose_spr, count)
        var raw_texture: Texture2D = decoded.get("texture") as Texture2D
        if raw_texture != null:
            var crop_raw := AtlasTexture.new()
            crop_raw.atlas = raw_texture
            var raw_tile: int = int(decoded.get("tile_size", 320))
            crop_raw.region = Rect2(frame_index * raw_tile, direction_index * raw_tile, raw_tile, raw_tile)
            crop_raw.filter_clip = true
            preview.texture = crop_raw
            atlas_path = "" # preview now displays ONE ORIGINAL SPR LAYER, not a fake composite
            missing_notice.text = ""
    if preview.texture == null and atlas_path != "":
        var texture: Texture2D = _load_png(atlas_path)
        if texture != null:
            var crop := AtlasTexture.new()
            crop.atlas = texture
            var tile: int = int(p.get("tile_size", 192))
            crop.region = Rect2(frame_index * tile, direction_index * tile, tile, tile)
            crop.filter_clip = true
            preview.texture = crop
        else:
            missing_notice.text = "KHÔNG ĐỌC ĐƯỢC PNG\n" + atlas_path
    if preview.texture == null and atlas_path == "":
        missing_notice.text = "AT03 / MeleeWCut\n\nCHỈ CÓ OFFSET METADATA\nKHÔNG CÓ PIXEL SPR\n\nChép đúng SPR vào data/spr/npcres/man/"

    metadata_view.call("update_from_profile", p, direction_index, frame_index)
    var dirnames: Array = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
    info.text = "Action: %s (ID %d)\nNPCRes: %s\nHướng: %s  |  Frame: %d / %d\nBảng nguồn: 8 hướng × %d frame\nDữ liệu layer: 6 SPR riêng\nAtlas: %s\n\nLƯU Ý: AT02/AT03 là\n2 action KHÁC NHAU.\nChưa xác minh skill 322 lúc chạy\nchọn chính xác action nào." % [str(p.get("action")), int(p.get("action_id", -1)), str(p.get("mapped_column")), dirnames[direction_index], frame_index, count - 1, count, "PNG ghép sẵn" if atlas_path != "" else "SPR 1 layer" if preview.texture != null else "CHƯA CÓ HÌNH"]
    var current_select: int = layer_selector.get_selected_id()
    layer_selector.clear()
    layer_selector.add_item("HIỆN TẤT CẢ BBOX", 0)
    var layers: Array = p.get("layers", [])
    for i in range(layers.size()):
        layer_selector.add_item(str(layers[i].get("layer", "")), i + 1)
    var safe_select: int = clampi(current_select, 0, layers.size())
    layer_selector.select(safe_select)
    metadata_view.set("selected_layer_index", safe_select - 1)
    metadata_view.queue_redraw()
    var idx: int = direction_index * count + frame_index
    var names: PackedStringArray = PackedStringArray()
    for item in layers:
        var layer: Dictionary = item
        var src: Array = layer.get("frame_offsets_xywh", [])
        if idx < src.size():
            names.append("%s: %s  xywh=%s" % [str(layer.get("layer", "")), str(layer.get("source_spr", "")), str(src[idx])])
    source_list.text = "\n".join(names)
    var headline: String = "ĐÃ CÓ PNG GHÉP, KHÔNG CÓ CÁC LAYER PIXEL RIÊNG" if atlas_path != "" else "ĐANG XEM RAW SPR 1 LAYER — CHƯA GHÉP LAYER" if preview.texture != null else "THIẾU SPR AT03, KHÔNG THỂ RENDER ĐÚNG ATTACK1"
    status.text = "%s\nCHỨNG CỨ: Attack1=AT03 (Cut, 14f) / Attack2=AT02 (Puncture, 16f); bảng NPCRes nam / đao một tay.\nT chọn thư mục client để tự trích 6 SPR AT03 qua package.ini, không bung toàn bộ PAK. B/O về." % headline
    if not scan_note.is_empty():
        status.text = scan_note + "\n" + status.text

func _load_one_loose_spr(path: String, expected_frames: int) -> Dictionary:
    if decoded_layer_cache.has(path):
        return decoded_layer_cache[path]
    var result: Dictionary = SPR_CODEC.new().decode_atlas(FileAccess.get_file_as_bytes(path), 320)
    if int(result.get("frames_per_direction", -1)) != expected_frames or int(result.get("directions", -1)) != 8:
        push_warning("V26: raw SPR does not match 8 dirs and expected frame count: " + path)
        result = {}
    decoded_layer_cache.clear() # keep max one decoded 320x320 layer atlas in memory
    decoded_layer_cache[path] = result
    return result

func _choose_client_folder() -> void:
    if client_picker == null:
        return
    client_picker.popup_centered(Vector2i(980, 580))

func _on_client_folder_picked(folder: String) -> void:
    # FileDialog supplies an absolute directory. Scan only the supplied
    # client data folder and standard project VFS fallbacks; never run EXE.
    scan_note = "V27: ĐANG ĐỌC PAK INDEX / 6 SPR AT03..."
    if status != null:
        status.text = scan_note
    call_deferred("_extract_client_at03", folder)

func _extract_client_at03(folder: String) -> void:
    var reader = AT03_EXTRACTOR.new()
    var result: Dictionary = reader.extract(folder)
    var details: PackedStringArray = PackedStringArray()
    details.append(str(result.get("result", "KHÔNG THỂ QUÉT: " + folder)))
    details.append("Khong sua PAK / EXE goc. Chi luu 6 SPR hop le vao project audit.")
    details.append("Bao cao: data/renderer_audit/V27_AT03_EXTRACTION_REPORT.txt")
    details.append("---")
    for line in result.get("details", []):
        details.append(str(line))
    for warning in result.get("pak_warnings", []):
        details.append("PAK_WARNING: " + str(warning))
    for error in result.get("errors", []):
        details.append("ERROR: " + str(error))
    scan_note = str(result.get("result", "CHƯA TRÍCH ĐƯỢC SPR"))
    if extraction_report != null:
        extraction_report.dialog_text = "\n".join(details)
        extraction_report.popup_centered(Vector2i(1040, 570))
    # Show real AT03 BODY layer after successful extraction, not a fabricated
    # composite. User can choose the other five layers from the right dropdown.
    if int(result.get("written", 0)) + int(result.get("existing", 0)) > 0:
        selected_action = 1
        action_selector.select(1)
        frame_index = 0
        layer_selector.select(1)
    _refresh()

func _select_action(index: int) -> void:
    selected_action = index
    frame_index = 0
    is_playing = false
    elapsed = 0.0
    _refresh()

func _select_layer(index: int) -> void:
    metadata_view.set("selected_layer_index", index - 1)
    metadata_view.queue_redraw()
    _refresh()

func _prev_dir() -> void:
    direction_index = posmod(direction_index - 1, 8)
    _refresh()

func _next_dir() -> void:
    direction_index = posmod(direction_index + 1, 8)
    _refresh()

func _prev_frame() -> void:
    var count: int = int(profiles[selected_action].get("frames_per_dir", 1))
    frame_index = posmod(frame_index - 1, count)
    _refresh()

func _next_frame() -> void:
    var count: int = int(profiles[selected_action].get("frames_per_dir", 1))
    frame_index = posmod(frame_index + 1, count)
    _refresh()

func _toggle_play() -> void:
    is_playing = not is_playing
    elapsed = 0.0
    _refresh()

func _process(delta: float) -> void:
    if not is_playing or profiles.is_empty():
        return
    elapsed += delta
    if elapsed >= INSPECT_INTERVAL:
        elapsed = fmod(elapsed, INSPECT_INTERVAL)
        _next_frame()

func _open_six_layer_composer() -> void:
    get_tree().change_scene_to_file("res://scenes/v28_at03_layer_composer.tscn")

func _back_to_game() -> void:
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode not in [KEY_B, KEY_O, KEY_T, KEY_C, KEY_ESCAPE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE]:
            return
        get_viewport().set_input_as_handled()
        match event.keycode:
            KEY_B, KEY_O, KEY_ESCAPE: _back_to_game()
            KEY_LEFT: _prev_frame()
            KEY_RIGHT: _next_frame()
            KEY_UP: _next_dir()
            KEY_DOWN: _prev_dir()
            KEY_SPACE: _toggle_play()
            KEY_T: _choose_client_folder()
            KEY_C: _open_six_layer_composer()
            _: return
