extends Control
## V28 SOURCE-PIXEL AT03 six-layer visual compositor.
## Six original SPR files must already exist under data/spr/npcres/man/.
## Z-order is EDITABLE QA only: numerical source ordering codes not decoded.
## No modification of combat, HP, client EXE or raw extracted files.
const CODEC = preload("res://scripts/V28SPRFrameDecoder.gd")
const V31_GUIDES = preload("res://scripts/V31AT03AnchorGuides.gd")
const INPUT_DIR: String = "res://data/spr/npcres/man/"
const DB_PATH: String = "res://data/renderer_audit/blade_004_action_profiles.json"
const ORDER_PATH: String = "res://data/renderer_audit/at03_male_raw_draworder.json"
const FRAME_COUNT: int = 14
const NDIR: int = 8
const PREVIEW_SECONDS: float = 0.14 # only for studying, NOT measured JX1 cadence
const LAYER_LABELS: Array[String] = ["BD · THÂN", "LH · TAY TRÁI", "RH · TAY PHẢI", "HD · ĐẦU", "LW · VŨ KHÍ TRÁI", "RW · VŨ KHÍ PHẢI"]
var reader = CODEC.new()
var layers: Array[Dictionary] = []
var visible_layers: Array[bool] = [true,true,true,true,true,true]
var order: Array[int] = [0,1,2,3,4,5] # UI-only initial order; NOT inferred native JX order
var selected_index: int = 0
var frame: int = 0
var facing: int = 6
var auto_play: bool = false
var accumulator: float = 0.0
var frame_cache: Dictionary = {}
var frame_cache_order: Array[String] = []
var stage: Node2D
var stats_label: Label
var order_label: Label
var msg_label: Label
var chosen_label: Label
var play_btn: Button
var reference_label: Label
var ready_count: int = 0
var source_lines: Dictionary = {}
var body_frame_offsets: Array = []
var show_anchor_guides: bool = true
var lock_body_bbox_bottom: bool = true
var selected_raw_row: int = 1 # 15 SOURCE rows; NEVER assume row=facing/frame
var source_row_button: OptionButton
var anchors_button: Button
var floor_button: Button
var anchors: Node2D
var anchor_floor_y: float = 448.0 # QA viewport position only
var last_report_path: String = ""

func _ready() -> void:
    size = Vector2(1280,720)
    _load_profiles_and_sources()
    _build_ui()
    _refresh_all()

func _panel(p: Vector2, s: Vector2, c: Color) -> void:
    var bg := ColorRect.new()
    bg.position = p
    bg.size = s
    bg.color = c
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

func _label(content: String, p: Vector2, s: Vector2, fontsize: int = 15, color: Color = Color.WHITE) -> Label:
    var node := Label.new()
    node.text = content
    node.position = p
    node.size = s
    node.add_theme_font_size_override("font_size", fontsize)
    node.add_theme_color_override("font_color", color)
    node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(node)
    return node

func _button(content: String, p: Vector2, s: Vector2, callback: Callable) -> Button:
    var b := Button.new()
    b.position = p
    b.size = s
    b.text = content
    b.focus_mode = Control.FOCUS_NONE
    b.pressed.connect(callback)
    add_child(b)
    return b

func _load_profiles_and_sources() -> void:
    var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(DB_PATH))
    if payload is Dictionary:
        for entry in payload.get("actions", []):
            if str(entry.get("id", "")) == "AT03":
                var raws: Array = entry.get("layers", [])
                for item in raws:
                    if str(item.get("layer", "")) == "BD_001":
                        body_frame_offsets = item.get("frame_offsets_xywh", []).duplicate()
                    var name: String = str(item.get("source_spr", ""))
                    var src: Dictionary = reader.open_source(INPUT_DIR + name, 112)
                    if not src.has("error"):
                        ready_count += 1
                    layers.append({"name":name, "source":src, "sprite":null})
                break
    var order_payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORDER_PATH))
    if order_payload is Dictionary:
        source_lines = order_payload.get("lines", {})

func _build_ui() -> void:
    _panel(Vector2.ZERO,Vector2(1280,720),Color("#0b1720"))
    _panel(Vector2.ZERO,Vector2(1280,66),Color("#13252e"))
    _label("V31 / AT03 — SOURCE ORDER & BODY ANCHOR QA",Vector2(17,10),Vector2(900,36),22)
    _label("15 RAW LINE ≠ 8 HƯỚNG; BBOX DƯỚI THÂN ≠ CHÂN THỰC / KHÔNG THAY COMBAT",Vector2(18,40),Vector2(1010,20),13,Color("#e6bf75"))
    _button("B · VỀ AUDIT",Vector2(1081,12),Vector2(180,38),Callable(self,"_back"))
    _panel(Vector2(16,77),Vector2(666,566),Color("#162730"))
    _panel(Vector2(697,77),Vector2(565,566),Color("#14252d"))
    _label("AT03 / MeleeWCut · 14 frame/hướng · 8 hướng · 320px",Vector2(28,87),Vector2(635,24),16)
    stage = Node2D.new()
    stage.name = "OriginalAT03LayerStage"
    stage.position = Vector2(340,385)
    stage.scale = Vector2(1.47,1.47)
    add_child(stage)
    for i in range(6):
        var sprite := Sprite2D.new()
        sprite.name = "SourceSPR_"+str(i)
        sprite.centered = true
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        sprite.z_as_relative = false
        sprite.z_index = 1+i
        stage.add_child(sprite)
        if i < layers.size():
            layers[i]["sprite"] = sprite
        else:
            sprite.visible = false
    anchors = Node2D.new()
    anchors.name = "V31BodyBBoxAnchorMarkers"
    anchors.set_script(V31_GUIDES)
    anchors.z_as_relative = false
    anchors.z_index = 20
    stage.add_child(anchors)
    _button("HƯỚNG −",Vector2(24,576),Vector2(108,35),Callable(self,"_shift_dir").bind(-1))
    _button("HƯỚNG +",Vector2(139,576),Vector2(108,35),Callable(self,"_shift_dir").bind(1))
    _button("FRAME −",Vector2(257,576),Vector2(102,35),Callable(self,"_shift_frame").bind(-1))
    _button("FRAME +",Vector2(365,576),Vector2(102,35),Callable(self,"_shift_frame").bind(1))
    play_btn = _button("PLAY 0,14s",Vector2(479,576),Vector2(181,35),Callable(self,"_toggle_play"))
    stats_label = _label("",Vector2(25,610),Vector2(645,26),14,Color("#efcf8f"))
    _label("SÁU LỚP SPR (chọn, tắt/bật, đổi thứ tự)",Vector2(711,88),Vector2(525,25),16)
    var y: int = 126
    for i in range(6):
        _button(str(i+1)+" · "+LAYER_LABELS[i],Vector2(713,y),Vector2(299,31),Callable(self,"_choose_layer").bind(i))
        _button("ẨN/HIỆN",Vector2(1020,y),Vector2(111,31),Callable(self,"_toggle_layer").bind(i))
        y+=38
    _button("LỚP LÊN",Vector2(714,356),Vector2(157,35),Callable(self,"_move_layer").bind(1))
    _button("LỚP XUỐNG",Vector2(878,356),Vector2(157,35),Callable(self,"_move_layer").bind(-1))
    _button("RESET ORDER",Vector2(1044,356),Vector2(200,35),Callable(self,"_reset_order"))
    chosen_label = _label("",Vector2(714,398),Vector2(530,28),13,Color("#e5ca82"))
    order_label = _label("",Vector2(714,426),Vector2(530,39),13)
    source_row_button = OptionButton.new()
    source_row_button.position = Vector2(714,465)
    source_row_button.size = Vector2(152,35)
    source_row_button.focus_mode = Control.FOCUS_NONE
    for j in range(1,16):
        source_row_button.add_item("SOURCE Line%d" % j, j)
    source_row_button.select(0)
    source_row_button.item_selected.connect(Callable(self, "_select_raw_row"))
    add_child(source_row_button)
    anchors_button = _button("A · BBOX ON",Vector2(873,465),Vector2(119,35),Callable(self,"_toggle_guides"))
    floor_button = _button("F · BÁM Y",Vector2(1000,465),Vector2(111,35),Callable(self,"_toggle_floor_lock"))
    _button("S · LƯU QA",Vector2(1118,465),Vector2(126,35),Callable(self,"_save_qa_report"))
    reference_label = _label("",Vector2(714,509),Vector2(530,127),13,Color("#b9d0d7"))
    _panel(Vector2(16,653),Vector2(1246,55),Color("#172832"))
    msg_label = _label("",Vector2(26,660),Vector2(1210,43),14,Color("#f2cd8b"))

func _frame_result(layer_id: int) -> Dictionary:
    if layer_id >= layers.size():
        return {"error":"MISSING_LAYER"}
    var key: String = "%d:%d:%d" % [layer_id,facing,frame]
    if frame_cache.has(key):
        return frame_cache[key]
    var layer: Dictionary = layers[layer_id]
    var source: Dictionary = layer.get("source", {})
    var decoded: Dictionary = reader.frame_image(source, facing*FRAME_COUNT+frame)
    if frame_cache_order.size() >= 24:
        var oldest: String = frame_cache_order.pop_front()
        frame_cache.erase(oldest)
    frame_cache_order.append(key)
    frame_cache[key] = decoded
    return decoded

func _refresh_all() -> void:
    var loaded: int = 0
    var failed: Array[String] = []
    for i in range(6):
        if i >= layers.size():
            continue
        var layer: Dictionary = layers[i]
        var sprite: Sprite2D = layer["sprite"] as Sprite2D
        if not visible_layers[i]:
            sprite.visible = false
            continue
        var frame_result: Dictionary = _frame_result(i)
        if frame_result.has("texture"):
            sprite.texture = frame_result["texture"] as Texture2D
            sprite.visible = true
            loaded+=1
        else:
            sprite.visible = false
            failed.append(str(layer["name"])+" "+str(frame_result.get("error","?")))
        sprite.z_index = order.find(i)+1
    var bbox_bottom: float = NAN
    var bbox: Array = []
    var idx: int = facing * FRAME_COUNT + frame
    if idx >= 0 and idx < body_frame_offsets.size():
        bbox = body_frame_offsets[idx]
        if bbox.size() == 4:
            bbox_bottom = float(bbox[1]) + float(bbox[3])
    if anchors != null:
        anchors.call("update_bbox",bbox,show_anchor_guides)
    if lock_body_bbox_bottom and bbox.size() == 4:
        stage.position.y = anchor_floor_y - (bbox_bottom - 160.0) * stage.scale.y
    else:
        stage.position.y = 385.0
    stats_label.text = "HƯỚNG %d/7 | FRAME %02d/13 | SPR %d/6 | BD BBOX Y %.0f (KHÔNG PHẢI CHÂN)" % [facing,frame,loaded,bbox_bottom]
    chosen_label.text = "Đang chọn: %s (%s)" % [LAYER_LABELS[selected_index],"HIỆN" if visible_layers[selected_index] else "ẨN"]
    var names: PackedStringArray = PackedStringArray()
    for i in order:
        names.append(LAYER_LABELS[i].split(" · ")[0])
    order_label.text = "Lớp vẽ dưới → trên (THỬ NGHIỆM):\n"+" → ".join(names)
    var codes: Array = source_lines.get(str(selected_raw_row), [])
    reference_label.text = "SOURCE MeleeWCut/Line%d (13 mã):\n%s\nBBOX BD y=%.0f / canvas=320; neo màn Y=%.0f\nCHƯA MỞ MÃ: 15 dòng không tương ứng 8 hướng hay 6 layer.\nS: ghi trạng thái QA (order + frame + nguồn)" % [selected_raw_row, str(codes), bbox_bottom, anchor_floor_y]
    anchors_button.text = "A · BBOX ON" if show_anchor_guides else "A · BBOX OFF"
    floor_button.text = "F · BÁM Y" if lock_body_bbox_bottom else "F · KHÔNG BÁM"
    if layers.size() < 6 or ready_count < 6:
        msg_label.text = "CHƯA ĐỦ SPR: %d/6. Chạy V27 để trích AT03 trước. %s" % [ready_count, " / ".join(failed)]
    elif not failed.is_empty():
        msg_label.text = "GIẢI MÃ FRAME LỖI: " + " / ".join(failed)
    else:
        msg_label.text = "SÁU SPR AT03 ĐÃ GIẢI MÃ TRỰC TIẾP. Ghép là bản QA; thứ tự lớp và action của skill 322 vẫn cần đối chiếu EXE."
    if not last_report_path.is_empty():
        msg_label.text = "QA đã lưu: " + last_report_path
    play_btn.text = "DỪNG PLAY" if auto_play else "PLAY 0,14s"

func _choose_layer(index: int) -> void:
    selected_index = index
    _refresh_all()

func _toggle_layer(index: int) -> void:
    visible_layers[index] = not visible_layers[index]
    _refresh_all()

func _move_layer(direction: int) -> void:
    var position: int = order.find(selected_index)
    var dest: int = clampi(position+direction,0,5)
    if position != dest:
        order.remove_at(position)
        order.insert(dest,selected_index)
    _refresh_all()

func _reset_order() -> void:
    order = [0,1,2,3,4,5]
    visible_layers = [true,true,true,true,true,true]
    _refresh_all()

func _shift_frame(step: int) -> void:
    frame = posmod(frame+step,FRAME_COUNT)
    _refresh_all()

func _shift_dir(step: int) -> void:
    facing = posmod(facing+step,NDIR)
    _refresh_all()

func _toggle_play() -> void:
    auto_play = not auto_play
    accumulator = 0.0
    _refresh_all()

func _process(delta: float) -> void:
    if not auto_play:
        return
    accumulator += delta
    if accumulator >= PREVIEW_SECONDS:
        accumulator = fmod(accumulator,PREVIEW_SECONDS)
        _shift_frame(1)

func _select_raw_row(index: int) -> void:
    selected_raw_row = clampi(index + 1,1,15)
    _refresh_all()

func _toggle_guides() -> void:
    show_anchor_guides = not show_anchor_guides
    _refresh_all()

func _toggle_floor_lock() -> void:
    lock_body_bbox_bottom = not lock_body_bbox_bottom
    _refresh_all()

func _save_qa_report() -> void:
    var candidates: Array[String] = ["res://data/renderer_audit/V31_QA_REPORT.txt", "user://V31_QA_REPORT.txt"]
    var report: PackedStringArray = PackedStringArray()
    report.append("V31 JX1 AT03 RENDER AUDIT; NOT VERIFIED NATIVE ORDER")
    report.append("Action=MeleeWCut/AT03 | direction=%d | frame=%d" % [facing,frame])
    report.append("Layer order (BOTTOM TO TOP, MANUAL)=" + str(order))
    report.append("Layer visibility=" + str(visible_layers))
    report.append("Source row selected=Line%d: %s" % [selected_raw_row,str(source_lines.get(str(selected_raw_row),[]))])
    report.append("Raw 15 Line values do NOT map directly to 6 sprite layers/8 dirs")
    report.append("BBOX guide=%s | body-bottom lock=%s" % [str(show_anchor_guides),str(lock_body_bbox_bottom)])
    var row_index: int = facing * FRAME_COUNT + frame
    if row_index < body_frame_offsets.size():
        var xywh: Array = body_frame_offsets[row_index]
        report.append("BODY_BBOX_xywh=" + str(xywh))
        if xywh.size() == 4:
            report.append("BODY_BBOX_BOTTOM_Y=%.0f (not anatomically verified foot)" % (float(xywh[1]) + float(xywh[3])))
    for i in range(layers.size()):
        var layer: Dictionary = layers[i]
        report.append("Layer%d=%s | visible=%s | order_rank=%d" % [i,str(layer.get("name","?")),str(visible_layers[i]),order.find(i)])
    report.append("Combat remains V30: no changes to cast/missiles/contact/HP")
    for path in candidates:
        var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
        if file != null:
            file.store_string("\n".join(report) + "\n")
            file.close()
            last_report_path = ProjectSettings.globalize_path(path)
            print("V31 QA SAVED: ",last_report_path)
            _refresh_all()
            return
    last_report_path = "SAVE_FAILED (read-only project and user storage)"
    push_warning(last_report_path)
    _refresh_all()

func _back() -> void:
    get_tree().change_scene_to_file("res://scenes/spr_renderer_audit.tscn")

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_B, KEY_ESCAPE: _back()
        KEY_LEFT: _shift_frame(-1)
        KEY_RIGHT: _shift_frame(1)
        KEY_UP: _shift_dir(1)
        KEY_DOWN: _shift_dir(-1)
        KEY_SPACE: _toggle_play()
        KEY_A: _toggle_guides()
        KEY_F: _toggle_floor_lock()
        KEY_S: _save_qa_report()
        _: return
    get_viewport().set_input_as_handled()
