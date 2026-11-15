extends Node2D

## Vertical slice with one playable sect (Thiên Vương); the same code loads
## additional sect JSON files whenever a new asset pack becomes available.
const PLAYER_CODE = preload("res://scripts/Player.gd")
const BLADE_POSE_INSPECTOR = preload("res://scripts/Blade322PoseInspector.gd")
const AT03_LIVE_PREVIEW = preload("res://scripts/V29AT03LivePreview.gd")
const V41_NATIVE_COMPOSER = preload("res://scripts/V41NativeSpearMaceRenderer.gd")
const V41_NATIVE_EXTRACTOR = preload("res://scripts/V41SpearMaceExtractor.gd")
const V33_ACTION_SELECTOR = preload("res://scripts/V33JX322ActionSelector.gd")
const DUMMY_CODE = preload("res://scripts/Dummy.gd")
const SKILL_CODE = preload("res://scripts/SkillEffect.gd")
const CTC_9X_EFFECT = preload("res://scripts/CTC9XCombatEffect.gd")
const CTC_9X_TIMELINE = preload("res://scripts/CTC9XTimeline.gd")
const V21_M141_DIR_LUT = preload("res://scripts/JX141NativeDirectionLUT.gd")
const V18_CAPTURE_VIEWER = preload("res://scripts/JX141NativeGameplayEvidence.gd")
const V22_COMBAT_CODE = preload("res://scripts/V22MainCombat.gd")
const SECT_PREVIEW_CODE = preload("res://scripts/JXSectSkillPreview.gd")
const FOLLOW_PREVIEW_CODE = preload("res://scripts/JXHomingSkillPreview.gd")
const JX_GEOMETRY = preload("res://scripts/JXCombatGeometry.gd")
const V436_SPR_AUDIT = preload("res://scripts/JXSectVFXAudit.gd")
const V37_NATIVE_IMPACT = preload("res://scripts/V37Blade322Impact.gd")
const V38_DEMO_NUMBER = preload("res://scripts/V38DemoDamagePopup.gd")
const V39_MOB = preload("res://scripts/V39TrainingMob.gd")
const V40_SPEAR_MACE_HIT = preload("res://scripts/V40SpearMaceHit.gd")
const V40_VERIFIED_ROUTES = preload("res://scripts/JX9XVerifiedRoute.gd")
const VIS_QA_CODE = preload("res://scripts/JX9XVisualQA.gd")
const CLIENT_DATA_CODE = preload("res://scripts/BaselineDataBridge.gd")
var client_data = CLIENT_DATA_CODE.new()
var data_status: String = ""
const INSPECTOR_CODE = preload("res://scripts/BaselineInspector.gd")
const RESOURCE_RESOLVER_CODE = preload("res://scripts/ClientAssetResolver.gd")
const ASSET_AUDIT_CODE = preload("res://scripts/AssetAudit.gd")
var resource_resolver = RESOURCE_RESOLVER_CODE.new()
var show_pak_debug: bool = false
var asset_audit_message: String = ""
# V43.5: true source SPR availability per active skill; never substitute invented effects.
var sect_spr_status: Dictionary = {}
var baseline_inspector: CanvasLayer
var weapon_buttons: Array[Button] = []
var selected_weapon_ui: int = -1
var show_vfx_diagnostics: bool = false
var show_timeline_details: bool = false
var blade322_echo_enabled: bool = true # V37 traced seven-slot pose history; G toggles
var blade322_slow_inspect: bool = false # optional U slow visual-only inspection
var vfx_probe: Label
var vfx_debug_button: Button
var blade_shadow_button: Button
var lab_open_button: Button
var hp_demo_button: Button
var main_combat: Node2D
var main_combat_status: Label
var main_combat_details: PanelContainer
var main_combat_debug: Label
var show_main_combat_debug: bool = false
var visual_qa: CanvasLayer
# V6.7.2 display-only: verify source image bytes independent of .godot import cache.
var ground_texture: Texture2D
var ground_status: String = "UNINITIALIZED"
var qa_zoom_index: int = 0
const QA_ZOOM_LEVELS = [1.0, 1.5, 2.0]

var blade_pose_inspector: Node2D
var blade_pose_button: Button
var spr_audit_button: Button
var v41_native_renderer: Node2D
var v41_import_dialog: FileDialog
var v41_import_summary: String = ""
var at03_live_renderer: Node2D
var at03_live_button: Button
var use_at03_in_main: bool = false # V33: true only when this cast selected action 9 and AT03 decoded
var v33_qa_mode: int = 0 # 0=native path, 1=force action 9, 2=force action 10 (next cast only)
var v33_last_selected_action: int = 0 # JX1 action requested, even if AT03 source falls back
var v33_last_rng: int = -1
var v33_cast_counter: int = 0
var visual_mode_status: Label # Read-only display of selected action vs actual renderer
var player: CharacterBody2D
var dummy: StaticBody2D
# Playable training arena; damage and enemy AI are DEMO until verified in Lua.
var v39_mobs: Array[StaticBody2D] = []
var v39_target: StaticBody2D
var v39_kills: int = 0
var v39_player_hp: int = 160
var v39_respawn: float = 0.0
# V23 visual-only training default. This does NOT alter damage dealt to mobs,
# V22 projectile contacts, or JX1 data. Press I to opt into incoming DEMO damage.
var v23_no_incoming_demo_damage: bool = true
const V39_PLAYER_MAX_HP: int = 160
var hud: Label
var info: Label
var school: Dictionary = {}
var registry: Dictionary = {}
var show_debug: bool = false
# V6 training controls: key-down starts repeat, key-up stops it.  The actual
# cooldown/action lock in Player.cast_at() remains authoritative.
const SPACE_HOLD_RECHECK_MS: int = 45
var space_hold_active: bool = false
var space_hold_next_try_msec: int = 0
# V14: stable per-cast key shared by VFX and the existing V22 DEMO probes.
var v14_visual_cast_sequence: int = 0
# V15: VFX-only test mode. No collision/HP and no AI/monster behavior while ON.
# Native M141 frame/position still require client trace; this mode isolates PREVIEW.
var v15_vfx_only: bool = false
var v15_hidden_actors: Array[Dictionary] = []
var v15_combat_was_processing: bool = true
var v15_aim_direction: Vector2 = Vector2.RIGHT
var v15_vfx_casts: int = 0
# Read-only observed JX1 FLY frames directly in the existing gameplay arena.
var v18_capture_viewer: Node2D
var v18_capture_segment: int = 0
# V20: temporarily hand the 325/141 Form12 allocation tick to the actor
# clock. The existing CTC V3/V14 effect script remains completely untouched.
var v20_m141_clock_sessions: Array[Dictionary] = []

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Missing file: " + path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if parsed is Dictionary:
        return parsed
    push_error("Invalid JSON: " + path)
    return {}

func _get_enabled_school(sect_id: String) -> Dictionary:
    var entries: Variant = registry.get("sects", [])
    if entries is Array:
        for item in entries:
            if item is Dictionary and str(item.get("id", "")) == sect_id and str(item.get("status", "")) == "playable_prototype":
                return _load_json(str(item.get("config", "")))
    push_error("Sect not enabled: " + sect_id)
    return {}

func _cycle_enabled_school() -> void:
    var entries: Variant = registry.get("sects", [])
    if not entries is Array:
        return
    var enabled: Array[String] = []
    for item in entries:
        if item is Dictionary and str(item.get("status", "")) == "playable_prototype":
            enabled.append(str(item.get("id", "")))
    if enabled.size() < 2:
        return
    var old_index: int = enabled.find(str(school.get("id", "")))
    var next_id: String = enabled[posmod(old_index + 1, enabled.size())]
    var config: Dictionary = _get_enabled_school(next_id)
    if config.is_empty():
        return
    school = client_data.inject_client_skills(config)
    player.call("load_sect", school)
    sect_spr_status.clear()
    if str(school.get("id", "")) != "thien_vuong":
        print("NINE SECTS PREVIEW: ", school.get("name", "?"),
            " | temporary TV character art, native school SPR required, test damage only")
    var old_ui: Node = get_node_or_null("CombatHUD")
    if old_ui != null:
        remove_child(old_ui)
        old_ui.queue_free()
    _make_hud()
    if hud != null:
        hud.text = "%s | 9-PHAI QA: THIEU SPR/ANIMATION RIENG" % str(school.get("name", "?"))

# Draw ground as the root CanvasItem, before world-space children (actor, dummy and VFX).
# This avoids relying on an import-only Sprite2D path which left a blank #4D4D4D
# default viewport in the user's Godot 4.6.1 test.
func _draw() -> void:
    if ground_texture != null:
        draw_texture(ground_texture, Vector2.ZERO)
    else:
        # Diagnostic fallback: never mistake the Godot gray clear-color for a level.
        draw_rect(Rect2(0.0, 0.0, 2300.0, 1700.0), Color(0.20, 0.28, 0.26))
        for x in range(0, 2301, 128):
            draw_line(Vector2(x, 0), Vector2(x, 1700), Color(0.29, 0.38, 0.35, 0.23), 1.0)
        for y in range(0, 1701, 128):
            draw_line(Vector2(0, y), Vector2(2300, y), Color(0.29, 0.38, 0.35, 0.23), 1.0)

func _load_training_ground() -> void:
    var path: String = "res://assets/background/training_ground.png"
    ground_texture = null
    # In an editable Godot project, the original PNG can be decoded without a
    # stale .godot/import cache. First validate the bytes, not ResourceLoader.exists.
    if FileAccess.file_exists(path):
        var source_image := Image.new()
        var error: Error = source_image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
        if error == OK and not source_image.is_empty():
            ground_texture = ImageTexture.create_from_image(source_image)
            ground_status = "SOURCE_PNG %dx%d" % [source_image.get_width(), source_image.get_height()]
        else:
            ground_status = "PNG_READ_ERROR_%d" % int(error)
    if ground_texture == null:
        # Imported textures still work in exported packs where source PNG is remapped.
        var candidate: Resource = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
        if candidate is Texture2D:
            ground_texture = candidate as Texture2D
            ground_status = "IMPORTED_TEXTURE %dx%d" % [ground_texture.get_width(), ground_texture.get_height()]
    if ground_texture == null:
        ground_status = "MISSING_BACKGROUND / GRID_FALLBACK"
        push_warning("JXNHALAM visual QA: could not load " + path + ". Using visible grid fallback.")
    print("JXNHALAM V6.7.6 GROUND: ", ground_status)
    queue_redraw()

func _cycle_qa_zoom() -> void:
    if player == null:
        return
    var camera: Camera2D = player.get_node_or_null("CameraFollowFootAnchor") as Camera2D
    if camera == null:
        return
    qa_zoom_index = (qa_zoom_index + 1) % QA_ZOOM_LEVELS.size()
    var factor: float = QA_ZOOM_LEVELS[qa_zoom_index]
    camera.zoom = Vector2(factor, factor)
    print("JXNHALAM V6.7.6 VISUAL QA ZOOM: %.1fx (Z cycles 1.0/1.5/2.0)" % factor)

func _ready() -> void:
    y_sort_enabled = true
    resource_resolver = RESOURCE_RESOLVER_CODE.new()
    var external_root: String = ""
    # User override survives project updates; P selects the real client.
    for config_path in ["user://client_root_override.txt", "res://client_root.txt", OS.get_executable_path().get_base_dir().path_join("client_root.txt")]:
        if FileAccess.file_exists(config_path):
            external_root = FileAccess.get_file_as_string(config_path).strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
            break
    resource_resolver.setup(external_root)
    registry = _load_json("res://data/sects/registry.json")
    school = _get_enabled_school(str(registry.get("default_sect", "thien_vuong")))
    if client_data.load_client_data():
        school = client_data.inject_client_skills(school)
        data_status = "SERVER BASELINE: " + client_data.get_counts()
    else:
        data_status = "SERVER BASELINE MISSING — V3 VISUAL FALLBACK"
        push_warning(client_data.load_warning)
    # V6.7.2: root-level draw, source PNG first, explicit visible fallback.
    _load_training_ground()
    player = CharacterBody2D.new()
    player.name = "Actor"
    player.set_script(PLAYER_CODE)
    player.position = Vector2(590, 725)
    add_child(player)
    player.call("load_sect", school)
    player.set("blade322_combo_enabled", blade322_echo_enabled)
    if not client_data.actor_defaults.is_empty():
        player.call("set_actor_defaults", client_data.actor_defaults)
    player.connect("skill_started", Callable(self, "_on_skill_started"))
    blade_pose_inspector = Node2D.new()
    blade_pose_inspector.name = "V25Blade322PoseInspector"
    blade_pose_inspector.set_script(BLADE_POSE_INSPECTOR)
    add_child(blade_pose_inspector)
    blade_pose_inspector.call("configure", player)
    # V33: The traced client cast path writes NPC action 9 or 10 after
    # g_Random(2). Keep the renderer OFF until a successful skill-322 cast
    # selects an action. AT03 sources still load here for readiness/fallback.
    # No cast, mana, missile, collision or HP code is changed.
    at03_live_renderer = Node2D.new()
    at03_live_renderer.name = "V33NativeAction9Renderer"
    at03_live_renderer.set_script(AT03_LIVE_PREVIEW)
    player.add_child(at03_live_renderer)
    at03_live_renderer.call("configure", player)
    at03_live_renderer.connect("visual_decode_failed", Callable(self, "_v30_at03_runtime_fallback"))
    at03_live_renderer.call("set_enabled", false)
    use_at03_in_main = false
    # V41: per-frame decoded native SPR for Spear/Mace. Separate from Blade 322.
    v41_native_renderer = Node2D.new()
    v41_native_renderer.name = "V41OriginalSpearMaceSPR"
    v41_native_renderer.set_script(V41_NATIVE_COMPOSER)
    player.add_child(v41_native_renderer)
    v41_native_renderer.call("configure", player)
    v41_import_dialog = FileDialog.new()
    v41_import_dialog.title = "V43.6 — Chọn thư mục CLIENT JX1 có data/*.pak"
    v41_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    v41_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
    v41_import_dialog.dir_selected.connect(Callable(self, "_v41_import_sources"))
    add_child(v41_import_dialog)
    # Reuse the explicit source hint from the previous V27 extraction if present.
    # Only scan PAK when V41 raw SPR are missing. Do not alter source client.
    var v41_known_root: String = external_root
    if v41_known_root.is_empty():
        var previous_report: String = "res://data/renderer_audit/V27_AT03_EXTRACTION_REPORT.txt"
        if FileAccess.file_exists(previous_report):
            for item in FileAccess.get_file_as_string(previous_report).split("\n"):
                if item.begins_with("client_root="):
                    v41_known_root = item.trim_prefix("client_root=").strip_edges()
                    break
    var missing_before_import: Array = v41_native_renderer.call("missing_files")
    if not v41_known_root.is_empty() and DirAccess.dir_exists_absolute(v41_known_root) and not missing_before_import.is_empty():
        _v41_import_sources(v41_known_root)
    if bool(at03_live_renderer.get("at03_sources_loaded")):
        print("V33 STARTUP: AT03 READY; waiting for first successful 322 cast to select action 9/10")
    else:
        push_warning("V33 STARTUP: AT03 source unavailable; action 9 will use AT02 visual fallback: " + str(at03_live_renderer.call("status")))


    dummy = StaticBody2D.new()
    dummy.name = "PracticeDummy"
    dummy.set_script(DUMMY_CODE)
    dummy.position = Vector2(1030, 790)
    add_child(dummy)
    # V22: main-scene collision adapter, invisible hit probes; VFX stays SPR-based.
    main_combat = Node2D.new()
    main_combat.name = "V22LiveCombat"
    main_combat.set_script(V22_COMBAT_CODE)
    add_child(main_combat)
    main_combat.call("setup", dummy)
    main_combat.connect("status_changed", Callable(self, "_refresh_v22_status"))
    main_combat.connect("impact_contacted", Callable(self, "_v37_on_impact_contact"))
    main_combat.connect("impact_contacted_visual", Callable(self, "_v14_on_m141_visual_contact"))
    main_combat.connect("demo_hp_committed", Callable(self, "_v38_on_demo_hp_committed"))
    _v39_spawn_mobs()
    _make_hud()
    visual_qa = VIS_QA_CODE.new()
    visual_qa.name = "JX9XVisualQA"
    add_child(visual_qa)
    visual_qa.connect("calibration_changed", Callable(self, "_on_visual_qa_changed"))
    baseline_inspector = CanvasLayer.new()
    baseline_inspector.name = "ServerBaselineInspector"
    baseline_inspector.set_script(INSPECTOR_CODE)
    add_child(baseline_inspector)
    baseline_inspector.call("initialize", client_data)

func _make_hud() -> void:
    var ui := CanvasLayer.new()
    ui.name = "CombatHUD"
    add_child(ui)
    var top := ColorRect.new()
    top.color = Color(0.052, 0.081, 0.094, 0.92)
    top.position = Vector2.ZERO
    top.size = Vector2(1280, 60)
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(top)
    var bottom := ColorRect.new()
    bottom.color = Color(0.052, 0.081, 0.094, 0.93)
    bottom.position = Vector2(0, 625)
    bottom.size = Vector2(1280, 95)
    bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(bottom)
    var heading := Label.new()
    heading.position = Vector2(22, 8)
    # V38: avoid a long heading overlapping developer/debug controls.
    heading.text = "JXNHALAM / V44 · TẦM ĐÁNH / HƯỚNG SPR QA"
    heading.add_theme_font_size_override("font_size", 24)
    heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(heading)
    info = Label.new()
    info.position = Vector2(22, 37)
    info.text = "TRÁI: DI CHUYỂN | PHẢI: CHỌN ĐỊCH/ĐÁNH | GIỮ SPACE: ĐÁNH LIÊN TỤC | R: RESET | D: DEBUG"
    info.add_theme_font_size_override("font_size", 14)
    info.size = Vector2(1230, 18)
    info.clip_text = true
    info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(info)
    # V6.3.1: Godot Editor reserves F8 for STOP. Use V and a clickable button.
    vfx_debug_button = Button.new()
    vfx_debug_button.name = "VFXDebugToggle"
    vfx_debug_button.position = Vector2(1085, 5)
    vfx_debug_button.size = Vector2(173, 32)
    vfx_debug_button.focus_mode = Control.FOCUS_NONE
    vfx_debug_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    vfx_debug_button.tooltip_text = "V: bật/tắt HUD kiểm tra VFX (không dùng F8 trong Godot Editor)"
    vfx_debug_button.text = "VFX DEBUG: ON" if show_vfx_diagnostics else "VFX DEBUG: OFF"
    vfx_debug_button.pressed.connect(Callable(self, "_toggle_vfx_diagnostics"))
    ui.add_child(vfx_debug_button)
    # V23: player-facing toggle for pose history. G is intentionally not F8.
    # The effect is only a presentation overlay; the proven child/missile route
    # and HP probe are not changed by this toggle.
    blade_shadow_button = Button.new()
    blade_shadow_button.name = "V23BladeShadowToggle"
    blade_shadow_button.position = Vector2(684, 5)
    blade_shadow_button.size = Vector2(142, 32)
    blade_shadow_button.add_theme_font_size_override("font_size", 13)
    blade_shadow_button.focus_mode = Control.FOCUS_NONE
    blade_shadow_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    blade_shadow_button.tooltip_text = "G: lịch sử tư thế 7 ô; lưu vị trí thực khi chụp; alpha 0x80 giảm 0x10 mỗi 3 lần vẽ (V12 EXE)"
    blade_shadow_button.text = "G · SHADOW: ON" if blade322_echo_enabled else "G · SHADOW: OFF"
    blade_shadow_button.pressed.connect(Callable(self, "_toggle_blade322_echo"))
    ui.add_child(blade_shadow_button)
    # V21.1: visible lab launcher. F8 is Godot Editor STOP, never bind F8 here.
    lab_open_button = Button.new()
    lab_open_button.name = "OpenV21SixSkillLab"
    lab_open_button.position = Vector2(833, 5)
    lab_open_button.size = Vector2(105, 32)
    lab_open_button.text = "L • LAB"
    lab_open_button.add_theme_font_size_override("font_size", 14)
    lab_open_button.focus_mode = Control.FOCUS_NONE
    lab_open_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    lab_open_button.tooltip_text = "Bấm để mở phòng thử 6 skill 9x (hoặc nhấn L). Không dùng F8."
    lab_open_button.pressed.connect(Callable(self, "_open_v21_lab"))
    ui.add_child(lab_open_button)
    hp_demo_button = Button.new()
    hp_demo_button.name = "V22HPDemoToggle"
    hp_demo_button.position = Vector2(945, 5)
    hp_demo_button.size = Vector2(133, 32)
    hp_demo_button.focus_mode = Control.FOCUS_NONE
    hp_demo_button.tooltip_text = "H: chỉ kiểm tra trừ 10 HP mỗi va chạm DEMO, không phải damage JX1"
    hp_demo_button.pressed.connect(Callable(self, "_toggle_v22_hp_demo"))
    ui.add_child(hp_demo_button)
    # A visible entry: top-bar key help is clipped on 1280x720.
    blade_pose_button = Button.new()
    blade_pose_button.name = "V25PoseHoldButton"
    blade_pose_button.position = Vector2(1080, 574)
    blade_pose_button.size = Vector2(180, 38)
    blade_pose_button.text = "K · GIỮ POSE 322"
    blade_pose_button.focus_mode = Control.FOCUS_NONE
    blade_pose_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    blade_pose_button.tooltip_text = "K: giữ frame gốc của Đao 322 để xem. N: xem frame tiếp. Không đổi sát thương."
    blade_pose_button.pressed.connect(Callable(self, "_toggle_blade322_pose_inspector"))
    ui.add_child(blade_pose_button)
    # V26 renderer audit is independent of combat; no new hit/timer logic.
    spr_audit_button = Button.new()
    spr_audit_button.name = "OpenJX1SPRRendererAudit"
    spr_audit_button.position = Vector2(890, 574)
    spr_audit_button.size = Vector2(180, 38)
    spr_audit_button.text = "O · SPR AUDIT"
    spr_audit_button.focus_mode = Control.FOCUS_NONE
    spr_audit_button.tooltip_text = "O: kiểm tra action 9/10, frame 8 hướng, layer source SPR. Không sửa combat."
    spr_audit_button.pressed.connect(Callable(self, "_open_spr_renderer_audit"))
    ui.add_child(spr_audit_button)
    at03_live_button = Button.new()
    at03_live_button.name = "V33NativeActionQA"
    at03_live_button.position = Vector2(704, 574)
    at03_live_button.size = Vector2(178, 38)
    at03_live_button.text = "Y · QA: AUTO"
    at03_live_button.focus_mode = Control.FOCUS_NONE
    at03_live_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    at03_live_button.tooltip_text = "Y: AUTO → ép action 9 → ép action 10 → AUTO; chỉ tác động cast 322 kế tiếp. Mặc định: random 0→10, 1→9 theo trace EXE."
    at03_live_button.pressed.connect(Callable(self, "_toggle_at03_live_preview"))
    ui.add_child(at03_live_button)
    visual_mode_status = Label.new()
    visual_mode_status.name = "V30ActualSourceStatus"
    visual_mode_status.position = Vector2(20, 543)
    visual_mode_status.size = Vector2(1220, 26)
    visual_mode_status.add_theme_font_size_override("font_size", 15)
    visual_mode_status.add_theme_color_override("font_color", Color(0.98, 0.83, 0.48))
    visual_mode_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(visual_mode_status)
    _v30_refresh_visual_state()

    # V6.2: The source CTC skill IDs supply the icons; every slot is an actual
    # clickable control with an explicit ACTIVE border (unlike V6.1's three
    # equally styled icons). Keyboard 1/2/3 still works.
    weapon_buttons.clear()
    selected_weapon_ui = -1
    var weapons: Array = player.call("get_weapons")
    var four_branches: bool = weapons.size() >= 4
    var button_step: int = 194 if four_branches else 216
    var button_width: int = 188 if four_branches else 209
    for i in range(weapons.size()):
        var w: Dictionary = weapons[i]
        var slot := Button.new()
        slot.name = "WeaponSlot%d" % i
        slot.text = ""
        slot.position = Vector2(18 + i * button_step, 636)
        slot.size = Vector2(button_width, 72)
        slot.focus_mode = Control.FOCUS_NONE
        slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        slot.pressed.connect(Callable(self, "_select_weapon").bind(i))
        var icon := TextureRect.new()
        icon.name = "WeaponIcon"
        icon.position = Vector2(6, 9)
        icon.size = Vector2(42, 54) if four_branches else Vector2(54, 54)
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        var icon_path: String = str(w.get("icon", ""))
        if not icon_path.is_empty():
            icon.texture = load(icon_path) as Texture2D
        slot.add_child(icon)
        var key := Label.new()
        key.name = "WeaponLabel"
        key.position = Vector2(52 if four_branches else 66, 5)
        key.size = Vector2(128 if four_branches else 140, 43)
        key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var slot_skills: Array = w.get("skills", [])
        var slot_name: String = str(slot_skills[0].get("name", "?")) if not slot_skills.is_empty() else str(w.get("label", "?"))
        key.text = "%d. %s" % [i + 1, slot_name.to_upper()]
        key.add_theme_font_size_override("font_size", 12 if four_branches else 13)
        key.mouse_filter = Control.MOUSE_FILTER_IGNORE
        slot.add_child(key)
        var state_label := Label.new()
        state_label.name = "ActiveState"
        state_label.position = Vector2(52 if four_branches else 66, 53)
        state_label.text = ""
        state_label.add_theme_font_size_override("font_size", 11)
        state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        slot.add_child(state_label)
        var skills: Array = w.get("skills", [])
        if not skills.is_empty():
            slot.tooltip_text = "%s · %s" % [str(w.get("label", "?")), str(skills[0].get("name", ""))]
        ui.add_child(slot)
        weapon_buttons.append(slot)
    _refresh_weapon_selection()
    hud = Label.new()
    hud.position = Vector2(810 if four_branches else 690, 639)
    hud.add_theme_font_size_override("font_size", 13 if four_branches else 16)
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(hud)
    vfx_probe = Label.new()
    vfx_probe.name = "VFXProbe"
    vfx_probe.position = Vector2(20, 574)
    vfx_probe.add_theme_font_size_override("font_size", 13)
    vfx_probe.add_theme_color_override("font_color", Color(0.92, 0.91, 0.56))
    vfx_probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vfx_probe.visible = show_vfx_diagnostics
    ui.add_child(vfx_probe)
    main_combat_status = Label.new()
    main_combat_status.name = "V22CombatStatus"
    main_combat_status.position = Vector2(20, 596)
    main_combat_status.size = Vector2(1245, 22)
    main_combat_status.add_theme_font_size_override("font_size", 14)
    main_combat_status.add_theme_color_override("font_color", Color(0.95, 0.86, 0.60))
    main_combat_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(main_combat_status)
    main_combat_details = PanelContainer.new()
    main_combat_details.name = "V22DebugPanel"
    main_combat_details.position = Vector2(20, 80)
    main_combat_details.custom_minimum_size = Vector2(580, 105)
    main_combat_details.visible = false
    main_combat_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var debug_style := StyleBoxFlat.new()
    debug_style.bg_color = Color(0.03, 0.06, 0.085, 0.86)
    debug_style.content_margin_left = 12
    debug_style.content_margin_right = 10
    debug_style.content_margin_top = 7
    debug_style.content_margin_bottom = 7
    main_combat_details.add_theme_stylebox_override("panel", debug_style)
    main_combat_debug = Label.new()
    main_combat_debug.add_theme_font_size_override("font_size", 15)
    main_combat_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
    main_combat_details.add_child(main_combat_debug)
    ui.add_child(main_combat_details)
    _refresh_v22_status()

func _select_weapon(index: int) -> void:
    if player == null:
        return
    player.call("set_weapon", index)
    # AT03 is a blade-only live renderer. Releasing an old selected action
    # prevents stale blade fragments from masking spear/hammer previews.
    use_at03_in_main = false
    if is_instance_valid(at03_live_renderer):
        at03_live_renderer.call("set_enabled", false)
    if is_instance_valid(blade_pose_inspector) and bool(blade_pose_inspector.get("active")):
        blade_pose_inspector.call("set_active", false)
    _refresh_weapon_selection()
    _v30_refresh_visual_state()

func _v41_open_import_dialog() -> void:
    if v41_import_dialog == null:
        return
    v41_import_dialog.popup_centered(Vector2i(900, 560))

func _v41_import_sources(root_folder: String) -> void:
    # V43.7.1: select client root without rewriting original TV weapon/actor pose sprites.
    var normalized_root: String = root_folder.replace("\\", "/").trim_suffix("/")
    if normalized_root.get_file().to_lower() == "data":
        normalized_root = normalized_root.get_base_dir()
    resource_resolver.setup(normalized_root)
    sect_spr_status.clear()
    var override: FileAccess = FileAccess.open("user://client_root_override.txt", FileAccess.WRITE)
    if override != null:
        override.store_string(normalized_root + "\n")
        override.close()
    print("V43.7.1 CLIENT PAK ROOT: ", normalized_root, " | ", resource_resolver.status())
    if resource_resolver.fs.archives.is_empty():
        push_warning("CLIENT PAK: none mounted; select a client root containing data/*.pak")
    # Do not call V41 importer here: it writes TV actor pose sources to the project.
    v41_import_summary = "SOURCE PAK SELECTED (read-only) | TV actor SPR unchanged"
    print(v41_import_summary)

func _v436_run_spr_audit() -> void:
    if resource_resolver == null:
        return
    var result: Dictionary = V436_SPR_AUDIT.run(resource_resolver)
    var line: String = str(result.get("summary", "AUDIT ERROR"))
    var path: String = str(result.get("report_path", ""))
    asset_audit_message = line + " | CSV: " + path
    print("V43.6 ", asset_audit_message)
    for sample in result.get("samples", []):
        print("V43.6 MISSING ", sample)
    if resource_resolver.fs != null:
        for warning in resource_resolver.fs.warnings:
            print("V43.6 PACK WARNING ", warning)

func _v41_choose_action(cast_id: int) -> void:
    # The same SkillStyle=1 / MisslesForm=12 dispatch branch traced for 322.
    # Action selection happens once after successful parent cast, never per missile.
    var random_sample: int = randi_range(0, 1)
    var selected_action: int = 10 if random_sample == 0 else 9
    player.set("v41_native_action", selected_action)
    var label: String = ("AT04" if selected_action == 9 else "AT05") if cast_id == 323 else ("AT06" if selected_action == 9 else "AT07")
    var action_clock: int = int(player.get("v42_native_cycle_ticks"))
    var child_cycles: int = int(player.get("v42_native_child_cycles"))
    print("V42 CAST %d | cycle 1/%d | action %d → %s | %d nominal tick/cycle @18Hz; sprite positions native; HP DEMO" % [
        cast_id, child_cycles, selected_action, label, action_clock])

func _slot_style(active: bool, hover: bool = false) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.16, 0.22, 0.26, 0.98) if active else Color(0.082, 0.126, 0.16, 0.94)
    if hover:
        style.bg_color = Color(0.22, 0.30, 0.33, 0.98) if active else Color(0.13, 0.19, 0.23, 0.98)
    style.border_color = Color(1.0, 0.78, 0.35) if active else Color(0.26, 0.37, 0.42)
    var line_width: int = 3 if active else 1
    style.border_width_left = line_width
    style.border_width_right = line_width
    style.border_width_top = line_width
    style.border_width_bottom = line_width
    style.corner_radius_top_left = 5
    style.corner_radius_top_right = 5
    style.corner_radius_bottom_left = 5
    style.corner_radius_bottom_right = 5
    return style

func _refresh_weapon_selection() -> void:
    if player == null:
        return
    var current: int = int(player.get("weapon_id"))
    if selected_weapon_ui == current:
        return
    selected_weapon_ui = current
    for i in range(weapon_buttons.size()):
        var slot: Button = weapon_buttons[i]
        var active: bool = i == current
        slot.add_theme_stylebox_override("normal", _slot_style(active))
        slot.add_theme_stylebox_override("hover", _slot_style(active, true))
        slot.add_theme_stylebox_override("pressed", _slot_style(active, true))
        slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        var txt: Label = slot.get_node("WeaponLabel") as Label
        txt.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58) if active else Color(0.84, 0.90, 0.91))
        var state_label: Label = slot.get_node("ActiveState") as Label
        state_label.text = "● ĐANG CHỌN" if active else "Bấm chọn"
        state_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35) if active else Color(0.55, 0.65, 0.68))
        var icon: TextureRect = slot.get_node("WeaponIcon") as TextureRect
        icon.modulate = Color.WHITE if active else Color(0.76, 0.79, 0.80, 0.84)

func _process(_delta: float) -> void:
    if player == null or dummy == null:
        return
    _v20_advance_m141_allocation_clock()
    if space_hold_active:
        # Alt-tab / missed key-up must not leave a permanent auto-chase.
        if not Input.is_key_pressed(KEY_SPACE) or not get_window().has_focus():
            if bool(player.get("pending_cast")):
                player.call("cancel_pending_skill_approach")
            space_hold_active = false
        else:
            if not v15_vfx_only and bool(player.get("pending_cast")):
                if _v39_target_alive(v39_target):
                    player.call("refresh_pending_skill_target", v39_target.global_position)
                else:
                    player.call("cancel_pending_skill_approach")
                    v39_target = null
            _space_hold_try_cast()
    if v39_respawn > 0.0 and not v15_vfx_only:
        v39_respawn = maxf(0.0, v39_respawn - _delta)
        if v39_respawn <= 0.0:
            v39_player_hp = V39_PLAYER_MAX_HP
            player.global_position = Vector2(590, 725)
            player.set("has_destination", false)
            player.set("pending_cast", false)
            player.set("action_remaining", 0.0)
    _refresh_weapon_selection()
    _update_vfx_probe()
    _refresh_v22_status()
    var selected: Dictionary = player.call("get_weapon")
    var skill: Dictionary = player.call("get_active_skill")
    if visual_qa != null:
        visual_qa.call("set_active_skill", int(skill.get("legacy_skill_id", 0)))
    var hp: int = int(dummy.get("hp"))
    var live_mobs: int = 0
    for mob in v39_mobs:
        if is_instance_valid(mob) and bool(mob.call("is_alive")):
            live_mobs += 1
    var route: Dictionary = V40_VERIFIED_ROUTES.find(int(skill.get("legacy_skill_id", 0)))
    var count_note: String = "M%d ×%d cấp phát" % [int(route.get("missile_id", 0)), int(route.get("total_allocations", 0))] if not route.is_empty() else "chưa rõ route"
    # Original Missles.txt ID 138 has no AnimFile2; Sword 322 shows the
    # actor AT03/AT02 while airborne M138 has no standalone FLY sprite.
    # Its 8-frame AnimFile4 is a CONTACT-only effect (not a launch effect).
    if int(skill.get("legacy_skill_id", 0)) == 322:
        count_note = "M138 ×3 • AT03/AT02 + HIT (KHÔNG SPR BAY)"
    if str(school.get("id", "")) != "thien_vuong":
        count_note = "JX1 %d | R%d→%.0fpx QA" % [int(skill.get("legacy_skill_id", 0)),
            int(skill.get("attack_radius_raw", 0)), JX_GEOMETRY.attack_range_pixels(skill)]
    var visual_key: String = str(selected.get("visual_id", ""))
    if v41_native_renderer != null and visual_key in ["spear", "hammer"]:
        count_note += " | SPR %s" % ("RAW VERIFIED" if bool(v41_native_renderer.call("selected_state_ready", visual_key)) else "ATLAS FALLBACK")
        if bool(player.get("v42_native_visual_active")):
            count_note += " | ACTION %d (%d/%d) · TICK %d/%d @18Hz" % [
                int(player.get("v41_native_action")), int(player.get("v42_native_cycle_index")) + 1,
                int(player.get("v42_native_child_cycles")), int(player.get("v42_native_local_tick")) + 1,
                int(player.get("v42_native_cycle_ticks"))]
    var incoming_damage_label: String = "BẤT TỬ TEST [I]" if v23_no_incoming_demo_damage else "DEMO HP [I]"
    hud.text = "HP %d/%d (%s) | QUÁI %d/3 | HẠ %d\n%s [%s] | %s | %s" % [v39_player_hp, V39_PLAYER_MAX_HP, incoming_damage_label, live_mobs, v39_kills, str(skill.get("name", "?")), str(selected.get("label", "?")), count_note, "HỒI SINH..." if v39_respawn > 0.0 else str(player.get("last_skill_error"))]
    if v15_vfx_only:
        if is_instance_valid(v18_capture_viewer):
            hud.text = "V18 JX1 LOG FLY · KHÔNG AI / HP / HITBOX\n%s" % str(v18_capture_viewer.call("status_line"))
        else:
            hud.text = "V15 VFX-ONLY · KHÔNG AI / HP / HITBOX · CAST %d\n%s [%s] | FLY PREVIEW | B: SOI LOG JX1 THẬT" % [
                v15_vfx_casts, str(skill.get("name", "?")), str(selected.get("label", "?"))]
    var current_visual: String = str(selected.get("visual_id", ""))
    var native_missing: bool = v41_native_renderer != null and current_visual in ["spear", "hammer"] and not bool(v41_native_renderer.call("is_weapon_ready", current_visual))
    if native_missing and str(school.get("id", "")) == "thien_vuong":
        info.text = "V41: THIẾU RAW SPR %s — NHẤN P CHỌN THƯ MỤC CLIENT JX1 (PAK) | ATLAS V40 CHỈ LÀ FALLBACK" % current_visual.to_upper()
    elif not v41_import_summary.is_empty():
        info.text = v41_import_summary
    elif not asset_audit_message.is_empty():
        info.text = asset_audit_message
    elif show_pak_debug and resource_resolver != null:
        info.text = resource_resolver.status()
    elif show_timeline_details and bool(skill.get("ctc_9x_many_attack", false)):
        var schedule: Dictionary = CTC_9X_TIMELINE.build(skill, int(player.get("ctc_attack_frame_baseline")), int(player.get("ctc_attack_speed_percent")))
        var graph: Dictionary = skill.get("source_nested_cast", {})
        info.text = "V3.6 DoManyAttack [ROUTE VERIFIED] | %d→%d→M%d | cast con:%d | alloc:%d (%d/cast con) | last:%d ticks* | *18Hz PREVIEW ONLY" % [
            int(graph.get("parent_id", 0)), int(graph.get("parent_child_id", 0)), int(graph.get("missile_id", 0)),
            int(schedule.get("child_casts", 0)), int(schedule.get("total_missiles", 0)),
            int(schedule.get("missiles_per_child_cast", 0)), int(schedule.get("last_allocation_tick", 0))]
    elif show_debug:
        info.text = "WORLD X:%d Y:%d | DIR:%d (0=S) | FPS:%d | RUN:%d | %s | BG:%s | ZOOM:%.1fx" % [int(player.global_position.x), int(player.global_position.y), int(player.get("facing_dir")), Engine.get_frames_per_second(), int(client_data.actor_defaults.get("RunSpeed", 10)), data_status, ground_status, QA_ZOOM_LEVELS[qa_zoom_index]]
    else:
        info.text = "TRÁI: DI CHUYỂN | PHẢI: CHỌN ĐỊCH/ĐÁNH | GIỮ SPACE: ĐÁNH LIÊN TỤC | R: RESET | D: DEBUG"
    if str(school.get("id", "")) != "thien_vuong":
        var spr_note: String = str(sect_spr_status.get(int(skill.get("legacy_skill_id", 0)), "CHUA THU CAST"))
        var vfs_note: String = resource_resolver.status() if resource_resolver != null else "NO PAK READER"
        info.text = "%s | Skill %d | SPR: %s | %s | TAB doi phai" % [
            str(school.get("name", "?")), int(skill.get("legacy_skill_id", 0)),
            spr_note, vfs_note]
    if v15_vfx_only:
        if is_instance_valid(v18_capture_viewer):
            info.text = "V18: B = TẮT LOG | M = ĐỔI ĐOẠN 1/2/3 | SPACE = DIỄN HOẠT NHÂN VẬT (KHÔNG TẠO THÊM FLY PREVIEW) | F7 THOÁT"
        else:
            info.text = "V15: GIỮ SPACE ĐÁNH LIÊN TỤC | B = PHÁT LẠI 789 MẪU CLIENT JX1 | C = SCENE AUDIT | F7 THOÁT"

# Space is a held combat control, not an edge-triggered menu shortcut.
# _input runs before GUI buttons can consume Space as an activate shortcut.
# Escape/editable fields/dialogs keep their own normal keyboard handling.
func _input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key: InputEventKey = event as InputEventKey
    if key.keycode != KEY_SPACE:
        return
    if not key.pressed:
        # Releasing held Space cancels only the pending Space approach.
        # An attack already committed is never interrupted.
        if space_hold_active and is_instance_valid(player) and bool(player.get("pending_cast")):
            player.call("cancel_pending_skill_approach")
            v39_target = null
        space_hold_active = false
        get_viewport().set_input_as_handled()
        return
    if key.echo:
        get_viewport().set_input_as_handled()
        return
    if _space_blocked_by_ui():
        return
    space_hold_active = true
    space_hold_next_try_msec = 0
    # Explicit new press clears a blocked target; just holding must not
    # restart a failed approach every 45ms against the same collision wall.
    if is_instance_valid(player) and str(player.get("last_skill_error")) == "TARGET BLOCKED (TEST)":
        player.set("last_skill_error", "")
    _space_hold_try_cast()
    get_viewport().set_input_as_handled()

func _space_blocked_by_ui() -> bool:
    if baseline_inspector != null and bool(baseline_inspector.call("is_open")):
        return true
    if v41_import_dialog != null and v41_import_dialog.visible:
        return true
    var focused: Control = get_viewport().gui_get_focus_owner()
    return focused is LineEdit or focused is TextEdit or focused is SpinBox

func _space_hold_try_cast() -> void:
    if not space_hold_active or not is_instance_valid(player):
        return
    if not get_window().has_focus() or _space_blocked_by_ui():
        return
    if v39_respawn > 0.0:
        return
    # One cast is in flight; don't change the locked target or queue another.
    if float(player.get("action_remaining")) > 0.0 or float(player.get("recovery_remaining")) > 0.0:
        return
    if bool(player.get("pending_cast")):
        return
    # If blocked outside even the DEMO attack radius, don't auto-chase the
    # same unreachable NPC endlessly. Release/repress Space to retry.
    if str(player.get("last_skill_error")) == "TARGET BLOCKED (TEST)":
        return
    var now: int = Time.get_ticks_msec()
    if now < space_hold_next_try_msec:
        return
    space_hold_next_try_msec = now + SPACE_HOLD_RECHECK_MS
    # request_skill/cast_at still enforce cooldown and validity; we do NOT
    # shorten native/preview action durations, spawn extra missiles or skip MP.
    if v15_vfx_only:
        _v15_cast_at_aim()
    else:
        _v39_cast_nearest()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if visual_qa != null and bool(visual_qa.get("enabled")):
            if event.alt_pressed:
                match event.keycode:
                    KEY_LEFT: visual_qa.call("adjust_position", -4.0, 0.0)
                    KEY_RIGHT: visual_qa.call("adjust_position", 4.0, 0.0)
                    KEY_UP: visual_qa.call("adjust_position", 0.0, -4.0)
                    KEY_DOWN: visual_qa.call("adjust_position", 0.0, 4.0)
                    _: pass
                if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
                    get_viewport().set_input_as_handled()
                    return
            if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_R, KEY_J, KEY_K]:
                match event.keycode:
                    KEY_BRACKETLEFT: visual_qa.call("adjust_scale", -0.05)
                    KEY_BRACKETRIGHT: visual_qa.call("adjust_scale", 0.05)
                    KEY_R: visual_qa.call("reset_skill")
                    KEY_J: visual_qa.call("save_values")
                    KEY_K: visual_qa.call("capture_screenshot")
                get_viewport().set_input_as_handled()
                return
        match event.keycode:
            KEY_1: _select_weapon(0)
            KEY_2: _select_weapon(1)
            KEY_3: _select_weapon(2)
            KEY_4: _select_weapon(3)
            KEY_F:
                if not v15_vfx_only and is_instance_valid(player):
                    if float(player.get("action_remaining")) <= 0.0 and float(player.get("recovery_remaining")) <= 0.0:
                        var basic_target: StaticBody2D = _v39_find_near(player.global_position, 680.0)
                        if _v39_target_alive(basic_target):
                            _v19_face_player_to_npc(basic_target)
                player.call("basic_attack")
            KEY_Q: player.call("cycle_skill", -1)
            KEY_E: player.call("cycle_skill", 1)
            KEY_TAB: _cycle_enabled_school()
            KEY_F3: show_debug = not show_debug
            KEY_F4: baseline_inspector.call("toggle")
            KEY_F5:
                show_pak_debug = not show_pak_debug
                asset_audit_message = ""
            KEY_F6: _audit_runtime_sprites()
            KEY_F7: _v15_toggle_vfx_only()
            KEY_B: _v18_toggle_capture_viewer()
            KEY_M: _v18_next_capture_segment()
            KEY_C: _v15_open_native_trace()
            KEY_L: _open_v21_lab()
            KEY_O: _open_spr_renderer_audit()
            KEY_P: _v41_open_import_dialog()
            KEY_F10: _v436_run_spr_audit()
            KEY_Y: _toggle_at03_live_preview()
            KEY_H: _toggle_v22_hp_demo()
            KEY_I: _v23_toggle_incoming_demo_damage()
            KEY_R: _v39_reset_arena()
            KEY_D: _toggle_v22_debug()
            KEY_F9:
                if visual_qa != null:
                    visual_qa.call("toggle_panel")
            KEY_V: _toggle_vfx_diagnostics()
            KEY_G: _toggle_blade322_echo()
            KEY_U: _toggle_blade322_visual_slow()
            KEY_K: _toggle_blade322_pose_inspector()
            KEY_N: _step_blade322_pose_inspector()
            KEY_Z: _cycle_qa_zoom()
            KEY_T: show_timeline_details = not show_timeline_details
            KEY_PAGEUP:
                if baseline_inspector.call("is_open"):
                    baseline_inspector.call("cycle_faction", -1)
            KEY_PAGEDOWN:
                if baseline_inspector.call("is_open"):
                    baseline_inspector.call("cycle_faction", 1)
            KEY_LEFT:
                if baseline_inspector.call("is_open"):
                    baseline_inspector.call("cycle_skill", -1)
            KEY_RIGHT:
                if baseline_inspector.call("is_open"):
                    baseline_inspector.call("cycle_skill", 1)
            KEY_ESCAPE: get_tree().quit()
        return
    if event is InputEventMouseButton and event.pressed:
        if baseline_inspector != null and baseline_inspector.call("is_open"):
            return
        var y: float = get_viewport().get_mouse_position().y
        if y < 60.0 or y > 625.0:
            return
        var pos: Vector2 = get_global_mouse_position()
        if v15_vfx_only and event.button_index == MOUSE_BUTTON_RIGHT:
            _v15_set_aim(pos)
        if event.button_index == MOUSE_BUTTON_LEFT:
            if v39_respawn <= 0.0:
                player.call("move_to", pos)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _cast_towards(pos)

func _refresh_v22_status() -> void:
    if main_combat == null or not is_instance_valid(main_combat):
        return
    if main_combat_status != null:
        main_combat_status.text = str(main_combat.call("summary")) + "  | D: ẨN/HIỆN"
        # Gameplay view: technical counters are hidden until the player presses D.
        main_combat_status.visible = show_main_combat_debug
    if hp_demo_button != null:
        hp_demo_button.text = "HP DEMO: ON" if bool(main_combat.get("hp_demo_enabled")) else "HP DEMO: OFF"
    if main_combat_details != null:
        main_combat_details.visible = show_main_combat_debug
    if vfx_debug_button != null:
        vfx_debug_button.visible = show_main_combat_debug or show_vfx_diagnostics
    if blade_shadow_button != null:
        blade_shadow_button.visible = show_main_combat_debug
    if lab_open_button != null:
        lab_open_button.visible = show_main_combat_debug
    if hp_demo_button != null:
        hp_demo_button.visible = show_main_combat_debug
    if blade_pose_button != null:
        blade_pose_button.visible = show_main_combat_debug
    if spr_audit_button != null:
        spr_audit_button.visible = show_main_combat_debug
    if at03_live_button != null:
        at03_live_button.visible = show_main_combat_debug
    if visual_mode_status != null:
        visual_mode_status.visible = show_main_combat_debug
    if main_combat_debug != null and show_main_combat_debug:
        main_combat_debug.text = str(main_combat.call("diagnostics"))

func _toggle_v22_hp_demo() -> void:
    if main_combat != null:
        main_combat.call("toggle_hp_demo")
    _refresh_v22_status()

func _reset_v22_dummy() -> void:
    if main_combat != null:
        main_combat.call("reset_dummy")
    _refresh_v22_status()

func _toggle_v22_debug() -> void:
    show_main_combat_debug = not show_main_combat_debug
    _refresh_v22_status()

func _v30_refresh_visual_state() -> void:
    var available: bool = at03_live_renderer != null and is_instance_valid(at03_live_renderer) and bool(at03_live_renderer.get("at03_sources_loaded"))
    var qa_text: String = "AUTO" if v33_qa_mode == 0 else ("ÉP ACTION 9" if v33_qa_mode == 1 else "ÉP ACTION 10")
    if at03_live_button != null:
        at03_live_button.text = "Y · QA: " + qa_text
        # QA action 10 must remain usable even if the six AT03 SPR are absent.
        at03_live_button.disabled = false
    if visual_mode_status != null:
        var cast_text: String = "322 | CHƯA CAST"
        if v33_last_selected_action == 9:
            cast_text = "322 | ACTION 9 → Attack1/MeleeWCut/AT03 (6 SPR)" if use_at03_in_main else "322 | ACTION 9 → AT02 FALLBACK (AT03 SPR THIẾU/LỖI)"
        elif v33_last_selected_action == 10:
            cast_text = "322 | ACTION 10 → Attack2/MeleeWPuncture/AT02"
        visual_mode_status.text = "V38 CAST #%d | %s | 18Hz / 5 TICK | SHADOW 7 SLOT | Y: %s%s" % [
            v33_cast_counter, cast_text, qa_text,
            "" if available else " | AT03 UNAVAILABLE"
        ]
    # K holds the legacy AT02 stills. Never display them over live AT03.
    if blade_pose_button != null:
        blade_pose_button.disabled = use_at03_in_main
        blade_pose_button.tooltip_text = "K chỉ dùng khi action 10/AT02 được hiển thị" if use_at03_in_main else "K: giữ pose AT02 để soi frame"
    if blade_shadow_button != null:
        blade_shadow_button.disabled = false
        blade_shadow_button.text = "G · SHADOW: ON" if blade322_echo_enabled else "G · SHADOW: OFF"

func _v30_update_live_effect_echoes() -> void:
    for child in get_children():
        if child.name.begins_with("SkillEffect_") and child.has_method("set_blade_echo_enabled"):
            var current: Variant = child.get("skill")
            if current is Dictionary and int(current.get("legacy_skill_id", 0)) == 322:
                child.call("set_blade_echo_enabled", blade322_echo_enabled)

func _v30_at03_runtime_fallback(reason: String) -> void:
    # Action remains 9; only the visual falls back when one SPR frame fails.
    # This is NOT a random action-10 selection.
    use_at03_in_main = false
    _v30_refresh_visual_state()
    _v30_update_live_effect_echoes()
    push_warning("V33 ACTION 9 / AT03 decode failed; AT02 VISUAL FALLBACK: " + reason)

func _toggle_at03_live_preview() -> void:
    if player != null and int((player.call("get_active_skill") as Dictionary).get("legacy_skill_id", 0)) != 322:
        print("V40: Y QA chỉ dành cho Đao 322. Thương/Chùy dùng pose atlas hiện có.")
        return
    # Y is a QA override for the NEXT successful skill-322 cast.
    # Never swap the middle of a cast or generate an extra random action.
    v33_qa_mode = (v33_qa_mode + 1) % 3
    _v30_refresh_visual_state()
    print("V33 QA NEXT CAST: ", "AUTO" if v33_qa_mode == 0 else ("FORCE ACTION 9" if v33_qa_mode == 1 else "FORCE ACTION 10"))


func _v33_choose_action_on_successful_cast() -> void:
    # Called exactly once by player.skill_started, only AFTER cast_at()
    # has passed cooldown/mana/range. No per-frame/per-missile RNG.
    # Ghidra trace: 0057B55B g_Random(2), 0057B56F NPC+F0 = 10 if 0 else 9.
    # Godot RNG distribution is a functional approximation, NOT the JX PRNG.
    var sample: int = randi_range(0, 1) if v33_qa_mode == 0 else -1
    var action_id: int = int(V33_ACTION_SELECTOR.resolve_action(sample, v33_qa_mode))
    v33_last_rng = sample
    v33_last_selected_action = action_id
    v33_cast_counter += 1
    use_at03_in_main = false
    if at03_live_renderer != null and is_instance_valid(at03_live_renderer):
        if action_id == 9 and not bool(at03_live_renderer.get("at03_sources_loaded")):
            # Header/decode already failed; no repeated enable attempts.
            at03_live_renderer.call("set_enabled", false)
        else:
            use_at03_in_main = bool(at03_live_renderer.call("set_enabled", action_id == 9))
    # K may have frozen a QA reference pose; it cannot mask the real cast.
    if blade_pose_inspector != null and bool(blade_pose_inspector.get("active")):
        blade_pose_inspector.call("set_active", false)
        if blade_pose_button != null:
            blade_pose_button.text = "K · GIỮ POSE 322"
    _v30_refresh_visual_state()
    _v30_update_live_effect_echoes()
    var source_text: String = "AT03 (6 SPR)" if use_at03_in_main else ("AT02 (ACTION 10)" if action_id == 10 else "AT02 FALLBACK (ACTION 9)")
    print("V38 CAST #", v33_cast_counter, " | skill=322 | action=", action_id,
        " | rng=", sample, " | qa_mode=", v33_qa_mode, " | visual=", source_text,
        " | NATIVE frame clock: 5 logic ticks @ 18Hz nominal; combat unchanged")

func _open_spr_renderer_audit() -> void:
    get_tree().change_scene_to_file("res://scenes/spr_renderer_audit.tscn")

func _open_v21_lab() -> void:
    # Defer scene replacement from both the HUD button and keyboard callbacks.
    # F8 is reserved by the editor for STOP, so this scene is opened with L/click.
    var target_path := "res://scenes/v21_lab.tscn"
    if not ResourceLoader.exists(target_path, "PackedScene"):
        push_error("JXNHALAM V21: scene missing: " + target_path)
        return
    get_tree().call_deferred("change_scene_to_file", target_path)

func _audit_runtime_sprites() -> void:
    var report: Dictionary = ASSET_AUDIT_CODE.run(resource_resolver, client_data)
    var output: String = ASSET_AUDIT_CODE.save(report)
    var results: Array = report.get("records", [])
    asset_audit_message = "F6 9X: %d/%d READY | client PAK SPR:%d loose SPR:%d bundled SPR:%d PNG:%d | optional unused:%d | %d PAK | CSV: %s" % [
        int(report.get("required_usable", 0)), int(report.get("required_total", 0)),
        int(report.get("pak_ok", 0)), int(report.get("loose_ok", 0)),
        int(report.get("bundled_ok", 0)), int(report.get("fallback_ok", 0)),
        int(report.get("unused_optional", 0)), int(report.get("archives", 0)), output]
    print(asset_audit_message)
    for item in results:
        print("%s %s => %s" % [str(item.get("skill_id", "")), str(item.get("part", "")), str(item.get("status", ""))])
    for warning in report.get("vfs_warnings", []):
        print("PAK WARNING: %s" % str(warning))

func _v14_on_m141_visual_contact(skill_id: int, missile_id: int, cast_key: int,
        event_ordinal: int, world_position: Vector2) -> void:
    if skill_id == 323 and missile_id == 139 and cast_key >= 0 and event_ordinal >= 0:
        for session in get_tree().get_nodes_in_group("jx139_visual_preview"):
            if is_instance_valid(session) and session.has_method("on_visual_contact_instance"):
                if bool(session.call("on_visual_contact_instance", cast_key, event_ordinal, world_position)):
                    return
        return
    if skill_id != 325 or missile_id != 141 or cast_key < 0 or event_ordinal < 0:
        return
    for session in get_tree().get_nodes_in_group("jx141_visual_v3"):
        if is_instance_valid(session) and session.has_method("on_visual_contact_instance"):
            if bool(session.call("on_visual_contact_instance", cast_key, event_ordinal, world_position)):
                return
    # No compatible visual allocation/session: don't manufacture a HIT sprite.

func _v37_on_impact_contact(skill_id: int, missile_id: int, world_position: Vector2) -> void:
    # M141 is handled separately with exact (cast_key, ordinal) correlation.
    # DO NOT broadcast its DEMO contact to the newest session. That could show
    # another cast's HIT and leave the actual missile FLY visible.
    # V12 EXE: child 326, missile 138, stage 3 AnimFile4 at hit NPC origin.
    # V22's contact is still DEMO geometry; only the VFX stage/asset/anchor
    # follow the traced client path. This does not modify damage or hit logic.
    if skill_id == 322 and missile_id == 138:
        # ONLY M138 has its exact native target x/y-5 / stage-3 path traced.
        var blade_effect := Node2D.new()
        blade_effect.name = "V37Missile138Hit"
        blade_effect.set_script(V37_NATIVE_IMPACT)
        add_child(blade_effect)
        # 9X table M138: use AnimFile4 from the selected JX1 client when
        # available. Preserve bundled 8-frame source as a read-only fallback.
        var m138_source: Dictionary = {}
        if resource_resolver != null and client_data != null:
            var missile_row: Dictionary = client_data.by_missile.get("138", {})
            var src_path: String = str(missile_row.get("AnimFile4", ""))
            if not src_path.is_empty():
                m138_source = resource_resolver.call("load_spr", src_path)
        blade_effect.call("start_at", world_position, m138_source)
    elif skill_id == 323 and missile_id == 139:
        # V7: M141 contact already creates its own HIT sprite above.
        # Do not spawn V40Missile141Hit a SECOND time for the same demo signal.
        # Server/skill table confirms these missile IDs and AnimFile4 atlases.
        # Contact timing and anchor remain V22 demonstration, NOT native JX1.
        var effect := Node2D.new()
        effect.name = "V40Missile%dHit" % missile_id
        effect.set_script(V40_SPEAR_MACE_HIT)
        add_child(effect)
        effect.call("start_at", skill_id, missile_id, world_position)

func _v38_on_demo_hp_committed(skill_id: int, amount: int, world_position: Vector2) -> void:
    # Corrected video ~00:40 shows a red damage number near the post.
    # The numeric value is ONLY the V22 demo amount (10), not JX1 damage.
    if not [322, 323, 325].has(skill_id) or amount <= 0:
        return
    var number := Node2D.new()
    number.name = "V38_DemoHitNumber"
    number.set_script(V38_DEMO_NUMBER)
    add_child(number)
    number.call("start_at", world_position, amount)

func _v39_spawn_mobs() -> void:
    var positions: Array[Vector2] = [Vector2(850, 670), Vector2(1040, 875), Vector2(1195, 695)]
    for index in range(positions.size()):
        var enemy := AnimatableBody2D.new()
        enemy.name = "TrainingMob%d" % (index + 1)
        enemy.set_script(V39_MOB)
        add_child(enemy)
        enemy.call("configure", player, "CAO THỦ %d" % (index + 1), 35 + index * 10, positions[index])
        enemy.connect("defeated", Callable(self, "_v39_on_mob_defeated"))
        enemy.connect("struck_player", Callable(self, "_v39_on_mob_strike"))
        v39_mobs.append(enemy)

func _v39_target_alive(candidate: StaticBody2D) -> bool:
    if not is_instance_valid(candidate):
        return false
    return not candidate.has_method("is_alive") or bool(candidate.call("is_alive"))

func _v39_find_near(world_position: Vector2, limit: float) -> StaticBody2D:
    if v15_vfx_only:
        return null
    var nearest: StaticBody2D
    var best: float = limit * limit
    for candidate in v39_mobs:
        if not _v39_target_alive(candidate):
            continue
        var distance_squared: float = candidate.global_position.distance_squared_to(world_position)
        if distance_squared < best:
            nearest = candidate
            best = distance_squared
    # The original practice dummy remains independently selectable.
    if _v39_target_alive(dummy):
        var distance_squared: float = dummy.global_position.distance_squared_to(world_position)
        if distance_squared < best:
            nearest = dummy
    return nearest

# V22 — All three Thiên Vương weapons use one target-to-cast path.
# Never keep requesting an unreachable waypoint while Space is held.
func _v39_cast_nearest() -> void:
    if not is_instance_valid(player) or v39_respawn > 0.0:
        return
    var candidate: StaticBody2D = _v39_find_near(player.global_position, 680.0)
    if not _v39_target_alive(candidate):
        # No valid enemy: stop chase rather than attacking a deleted instance.
        return
    _cast_towards(candidate.global_position)

func _v39_on_mob_defeated(_mob: StaticBody2D) -> void:
    v39_kills += 1
    if main_combat != null:
        main_combat.set("last_event", "HẠ CAO THỦ (DEMO): %d" % v39_kills)

func _v39_on_mob_strike(amount: int, enemy_world: Vector2) -> void:
    if v15_vfx_only or v23_no_incoming_demo_damage:
        return
    if v39_respawn > 0.0 or not is_instance_valid(player):
        return
    if player.global_position.distance_to(enemy_world) > 95.0:
        return
    v39_player_hp = maxi(0, v39_player_hp - maxi(0, amount))
    if v39_player_hp == 0:
        v39_respawn = 2.5
        player.set("has_destination", false)
        player.set("pending_cast", false)
        if main_combat != null:
            main_combat.set("last_event", "NHÂN VẬT GỤC — HỒI SINH SAU 2.5 GIÂY (DEMO)")

# The native-visual test must not be interrupted by an unrelated 8-damage
# training NPC. I restores the original DEMO incoming-damage path on demand.
func _v23_toggle_incoming_demo_damage() -> void:
    v23_no_incoming_demo_damage = not v23_no_incoming_demo_damage
    if v23_no_incoming_demo_damage:
        v39_player_hp = V39_PLAYER_MAX_HP
        v39_respawn = 0.0
    print("JXNHALAM V23: incoming DEMO mob damage = ",
        "OFF (visual test)" if v23_no_incoming_demo_damage else "ON (training HP)")

func _v39_reset_arena() -> void:
    if main_combat != null:
        main_combat.call("reset_dummy")
    for mob in v39_mobs:
        if is_instance_valid(mob):
            mob.call("reset_training_hp")
    v39_kills = 0
    v39_player_hp = V39_PLAYER_MAX_HP
    v39_respawn = 0.0
    v39_target = null
    player.global_position = Vector2(590, 725)
    player.set("has_destination", false)
    player.set("pending_cast", false)
    player.set("action_remaining", 0.0)

# V21 — For M141, compute the center heading from one SCREEN target.
# The same NativeDirLUT.normalize_delta_1024 + direction_from_factors
# is used inside JX141MissileVisualV3.configure (screen Y -> flat Y*2).
# This unifies actor 8-dir facing with missile 64-dir heading.
# Neither absolute native NPC position nor camera offset is claimed.
func _v21_m141_center_dir64(screen_target: Vector2) -> int:
    if not is_instance_valid(player):
        return 0
    var screen_delta: Vector2 = screen_target - player.global_position
    if screen_delta.length_squared() < 1.0:
        return posmod(int(player.get("facing_dir")) * 8, 64)
    var flat_delta: Vector2 = Vector2(screen_delta.x, screen_delta.y * 2.0)
    var factors: Dictionary = V21_M141_DIR_LUT.normalize_delta_1024(flat_delta)
    if not bool(factors.get("ok", false)):
        return posmod(int(player.get("facing_dir")) * 8, 64)
    var dir64: int = V21_M141_DIR_LUT.direction_from_factors(
        int(factors["x_factor"]), int(factors["y_factor"]))
    return dir64 if dir64 >= 0 else posmod(int(player.get("facing_dir")) * 8, 64)

# V19 — NPC-facing uses the target's FOOT anchor, NOT the DEMO hitbox point
# (world_position + Vector2(0, -45)).  This does not change the projectile
# target, skill range, damage, collision or the preview action clock.
func _v19_face_player_to_npc(npc: StaticBody2D) -> int:
    if not is_instance_valid(player):
        return 0
    if not _v39_target_alive(npc):
        return int(player.get("facing_dir"))
    var npc_delta: Vector2 = npc.global_position - player.global_position
    if npc_delta.length_squared() >= 1.0:
        var current_skill: Dictionary = player.call("get_active_skill")
        if [322, 323, 325].has(int(current_skill.get("legacy_skill_id", 0))):
            # NPC FOOT, never the separate DEMO hit-point y-45.
            # Project the same screen vector into native flat-world orientation
            # used by M141; quantize 64 -> actor 8 only AFTER that conversion.
            player.call("face_native_dir64", _v21_m141_center_dir64(npc.global_position))
        else:
            player.call("face", npc_delta)
        # Keep the action SPR pose synchronized when target changes.
        if player.has_method("_render_frame"):
            player.call("_render_frame")
    return int(player.get("facing_dir"))

func _cast_towards(world_position: Vector2) -> void:
    if v39_respawn > 0.0:
        return
    if v15_vfx_only:
        # Keep the skill's original request_skill/cooldown/cast animation path.
        # Aim inside effective range so the actor never auto-chases an enemy.
        var delta_to_aim: Vector2 = world_position - player.global_position
        if delta_to_aim.length_squared() > 1.0:
            v15_aim_direction = delta_to_aim.normalized()
        var active_skill: Dictionary = player.call("get_active_skill")
        var reach: float = maxf(24.0, JX_GEOMETRY.attack_range_pixels(active_skill) * 0.58)
        v39_target = null
        player.call("request_skill", player.global_position + v15_aim_direction * reach)
        return
    v39_target = _v39_find_near(world_position, 95.0)
    var destination: Vector2 = world_position
    if is_instance_valid(v39_target):
        # JX1 attack command: turn toward the NPC as soon as a new attack
        # command is accepted.  Don't rotate in the middle of another swing.
        if float(player.get("action_remaining")) <= 0.0 and float(player.get("recovery_remaining")) <= 0.0:
            _v19_face_player_to_npc(v39_target)
        # DEMO aim / hitbox remains unchanged.  It is a separate point.
        destination = v39_target.global_position + Vector2(0, -45)
    # Keep the DEMO hitbox destination (foot - 45) unchanged.
    # Range/approach checks use NPC FOOT, not the raised hitbox marker.
    if _v39_target_alive(v39_target):
        player.call("request_skill", destination, v39_target.global_position)
    else:
        player.call("request_skill", destination)

# V20 keeps V19 NPC facing, V18 trace playback, V14 contact matching and
# the original V3 missile visual script. No CTC9XCombatEffect.gd overwrite.
func _v20_register_m141_cast(fx: Node2D) -> void:
    if not is_instance_valid(fx) or not is_instance_valid(player):
        return
    if int(player.get("v42_native_skill_id")) != 325:
        return
    if not bool(player.get("v42_native_visual_active")):
        return
    var raw_schedule: Variant = fx.get("timeline")
    if not raw_schedule is Dictionary:
        return
    var schedule: Dictionary = raw_schedule
    var allocation_tick: int = -1
    for raw_event in schedule.get("events", []):
        if raw_event is Dictionary and int(raw_event.get("missile_id", 0)) == 141:
            allocation_tick = int(raw_event.get("tick", -1))
            break
    if allocation_tick < 0:
        return
    # setup() has already run and processed tick zero; prevent its independent
    # _process clock from racing the actor's four-tick nominal attack clock.
    fx.set_process(false)
    v20_m141_clock_sessions.append({
        "fx": fx,
        "allocation_tick": allocation_tick,
        "cast_sequence": int(player.get("v20_cast_sequence"))
    })

func _v20_advance_m141_allocation_clock() -> void:
    if not is_instance_valid(player):
        return
    for i in range(v20_m141_clock_sessions.size() - 1, -1, -1):
        var ticket: Dictionary = v20_m141_clock_sessions[i]
        var fx: Node2D = ticket.get("fx") as Node2D
        if not is_instance_valid(fx):
            v20_m141_clock_sessions.remove_at(i)
            continue
        var cast_sequence: int = int(ticket.get("cast_sequence", -1))
        if cast_sequence != int(player.get("v20_cast_sequence")):
            # Only an actual newer cast may cancel this session. Player can
            # change to STAND between physics and Main._process during a hitch;
            # that is NOT a cancellation of the M141 allocation event.
            fx.set_process(true)
            v20_m141_clock_sessions.remove_at(i)
            continue
        var allocation_tick: int = int(ticket.get("allocation_tick", -1))
        var elapsed: float = maxf(0.0, float(player.get("v42_native_elapsed")))
        var observed_tick: int = maxi(0, floori(elapsed * CTC_9X_TIMELINE.TICK_HZ + 0.00001))
        var goal_tick: int = mini(observed_tick, allocation_tick)
        var advances: int = 0
        while int(fx.get("clock_tick")) < goal_tick and advances < 48:
            fx.call("_tick")
            advances += 1
        if int(fx.get("clock_tick")) >= allocation_tick:
            # Native visual bridge still receives the original event.
            if int(fx.get("spawned_total")) > 0:
                player.call("v20_confirm_m141_allocation", allocation_tick, cast_sequence)
                if show_debug:
                    var native141: Node2D = fx.get("native141_v3") as Node2D
                    if is_instance_valid(native141) and native141.has_method("diagnostic"):
                        var m141_state: Variant = native141.call("diagnostic")
                        if m141_state is Dictionary:
                            print("TVC325 SYNC: tick=", int(fx.get("clock_tick")),
                                " allocated=", int(fx.get("spawned_total")),
                                " visual_created=", int(m141_state.get("fly_total", 0)),
                                " visual_active=", int(m141_state.get("active_fly", 0)),
                                " trace=", str(m141_state.get("replay_status", "?")))
            # The post-allocation lifetime remains the original V3/V14 path.
            fx.set_process(true)
            v20_m141_clock_sessions.remove_at(i)

func _on_skill_started(skill: Dictionary, destination: Vector2, face_direction: int) -> void:
    if v39_respawn > 0.0:
        return
    # Snapshot the chosen target at cast time (including delayed walk-to-cast).
    var locked_target: StaticBody2D = v39_target
    if not _v39_target_alive(locked_target):
        locked_target = _v39_find_near(destination, 95.0)
    v39_target = null
    # V21: VISUAL aim and DEMO combat destination are deliberately separate.
    # A hitbox/demo cast may target NPC foot + Vector2(0, -45); that offset
    # MUST NOT rotate the actor or all 3 M141 projectiles away from the NPC.
    # For a delayed walk-to-cast, take the NPC's CURRENT foot at cast time.
    var cast_id: int = int(skill.get("legacy_skill_id", 0))
    var v21_visual_destination: Vector2 = destination
    var v19_actor_face_dir: int = face_direction
    if cast_id == 325:
        if not v15_vfx_only and _v39_target_alive(locked_target):
            v21_visual_destination = locked_target.global_position
        var center_dir64: int = _v21_m141_center_dir64(v21_visual_destination)
        player.call("face_native_dir64", center_dir64)
        v19_actor_face_dir = int(player.get("facing_dir"))
        if show_debug:
            print("V21 M141 AIM: dir64=", center_dir64,
                " actor8=", v19_actor_face_dir,
                " source=", "npc_foot" if v21_visual_destination != destination else "screen_target",
                " hitbox_demo_untouched=true")
    elif not v15_vfx_only and _v39_target_alive(locked_target):
        v19_actor_face_dir = _v19_face_player_to_npc(locked_target)
    v14_visual_cast_sequence += 1
    var v14_cast_key: int = v14_visual_cast_sequence
    if cast_id == 322:
        _v33_choose_action_on_successful_cast()
    elif cast_id == 323 or cast_id == 325:
        _v41_choose_action(cast_id)
        var route: Dictionary = V40_VERIFIED_ROUTES.find(cast_id)
        print("V40 CAST %d → CHILD %d → MISSILE %d ×%d allocated [DEMO HIT, 9X ATLAS]" % [
            cast_id, int(route.get("child_id", 0)), int(route.get("missile_id", 0)), int(route.get("total_allocations", 0))])
    var fx := Node2D.new()
    fx.name = "SkillEffect_" + str(skill.get("id", "unknown"))
    var is_other_sect: bool = str(school.get("id", "thien_vuong")) != "thien_vuong"
    var follow_by_source: bool = is_other_sect and int(skill.get("missile_move_kind", -1)) == 5
    fx.set_script(FOLLOW_PREVIEW_CODE if follow_by_source else (SECT_PREVIEW_CODE if is_other_sect else (CTC_9X_EFFECT if bool(skill.get("ctc_9x_many_attack", false)) else SKILL_CODE)))
    add_child(fx)
    if fx.has_method("set_calibration") and visual_qa != null:
        fx.call("set_calibration", visual_qa.call("get_for_skill", int(skill.get("legacy_skill_id", 0))))
    if int(skill.get("legacy_skill_id", 0)) == 322:
        # V30: never mix an AT02 afterimage with the live six-layer AT03 actor.
        fx.set("blade322_echo_enabled", blade322_echo_enabled)
        # Action 9/10 was selected once by _v33_choose_action_on_successful_cast().
    # Prevent V6's old one-shot distance-based HP subtraction. Only V22
    # collision contacts may affect training HP; preview VFX stays unchanged.
    if bool(skill.get("ctc_9x_many_attack", false)):
        fx.set("external_collision_authority", true)
    # Use the same direction the actor now faces for the VFX action atlas.
    # 325: FX receives the SAME NPC-foot point used to lock actor facing.
    # The original `destination` remains unchanged for Player.cast_at,
    # movement range and V22MainCombat.begin_cast (DEMO hitbox/damage).
    var visual_target: StaticBody2D = locked_target if is_instance_valid(locked_target) else dummy
    if follow_by_source and not is_instance_valid(locked_target):
        visual_target = null
    fx.call("setup", player, visual_target,
        v21_visual_destination,
        skill, v19_actor_face_dir, resource_resolver)
    if is_other_sect:
        var spr_info: Dictionary = fx.call("get_diagnostic") if fx.has_method("get_diagnostic") else {}
        var spr_label: String = str(spr_info.get("asset_notice", "UNKNOWN"))
        sect_spr_status[cast_id] = spr_label
        if spr_label != "SOURCE_SPR_LOADED":
            print("JX SPR AUDIT | sect=", str(school.get("id", "?")),
                " | skill=", cast_id, " | ", spr_label,
                " | ", resource_resolver.status())
    if cast_id == 323 and bool(skill.get("ctc_9x_many_attack", false)):
        var m139: Node2D = fx.get("native139_preview") as Node2D
        if is_instance_valid(m139) and m139.has_method("bind_demo_cast"):
            m139.call("bind_demo_cast", v14_cast_key)
    if cast_id == 325 and bool(skill.get("ctc_9x_many_attack", false)):
        # V20: same actor tick for Form12 allocation, without changing
        # V3 animation script, V14 instance correlation or V22 collision.
        _v20_register_m141_cast(fx)
        # CTC.setup may emit tick-zero events; bind those and subsequent events.
        var v14_runtime: Node2D = fx.get("native141_v3") as Node2D
        if is_instance_valid(v14_runtime) and v14_runtime.has_method("bind_demo_cast"):
            v14_runtime.call("bind_demo_cast", v14_cast_key)
    fx.set("show_debug_overlay", show_vfx_diagnostics)
    if v15_vfx_only:
        # Same rendering path; only V22 demo hitbox/HP are suppressed.
        v15_vfx_casts += 1
    elif bool(skill.get("ctc_9x_many_attack", false)) and main_combat != null:
        main_combat.call("begin_cast", skill, player, locked_target, v14_cast_key)

func _v15_set_aim(world_position: Vector2) -> void:
    if not is_instance_valid(player):
        return
    var aim_vector: Vector2 = world_position - player.global_position
    if aim_vector.length_squared() > 1.0:
        v15_aim_direction = aim_vector.normalized()

func _v15_cast_at_aim() -> void:
    if not is_instance_valid(player):
        return
    _v15_set_aim(get_global_mouse_position())
    _cast_towards(player.global_position + v15_aim_direction * 60.0)

func _v18_disable_capture_viewer() -> void:
    if is_instance_valid(v18_capture_viewer):
        v18_capture_viewer.queue_free()
    v18_capture_viewer = null

func _v18_toggle_capture_viewer() -> void:
    if not v15_vfx_only or not is_instance_valid(player):
        print("V18: Press F7 for VFX-only before enabling JX1 capture playback.")
        return
    if int((player.call("get_active_skill") as Dictionary).get("legacy_skill_id", 0)) != 325:
        print("V18: Select Chuy 325 (key 3) before native captured FLY playback.")
        return
    if is_instance_valid(v18_capture_viewer):
        _v18_disable_capture_viewer()
        print("V18: Native evidence viewer OFF. FLY preview restored.")
        return
    var node: Node2D = Node2D.new()
    node.name = "V18_Observed_Client_FLY_ReadOnly"
    node.set_script(V18_CAPTURE_VIEWER)
    add_child(node)
    var result: Dictionary = node.call("configure", player, v18_capture_segment) as Dictionary
    if not bool(result.get("ok", false)):
        push_warning("V18: " + str(result.get("reason", "Cannot open native evidence")))
        node.queue_free()
        return
    v18_capture_viewer = node
    # Prevent previously allocated V14 preview sprites from overlapping capture.
    for session in get_tree().get_nodes_in_group("jx141_visual_v3"):
        if is_instance_valid(session) and session.has_method("clear_demo_preview_visuals"):
            session.call("clear_demo_preview_visuals")
    print("V18: CLIENT LOG FLY playback ON | samples checked: ", int(result.get("samples_verified", 0)),
        " | B toggles; M switches segment. Camera/NPC anchor not yet verified.")

func _v18_next_capture_segment() -> void:
    if not is_instance_valid(v18_capture_viewer):
        return
    v18_capture_viewer.call("next_segment")
    v18_capture_segment = (v18_capture_segment + 1) % 3

func _v15_toggle_vfx_only() -> void:
    if not is_instance_valid(player) or not is_instance_valid(dummy):
        return
    if v15_vfx_only:
        _v18_disable_capture_viewer()
    v15_vfx_only = not v15_vfx_only
    if v15_vfx_only:
        v15_vfx_casts = 0
        _v15_set_aim(get_global_mouse_position())
        # Discard in-flight DEMO probes and casts; no remaining source of damage.
        if is_instance_valid(main_combat):
            main_combat.call("reset_dummy")
            v15_combat_was_processing = main_combat.is_physics_processing()
            main_combat.set_physics_process(false)
        # Prevent V39 AI, collisions and rendering in the test area.
        v15_hidden_actors.clear()
        var actors: Array[StaticBody2D] = []
        actors.append(dummy)
        actors.append_array(v39_mobs)
        for actor in actors:
            if not is_instance_valid(actor):
                continue
            v15_hidden_actors.append({
                "node": actor,
                "visible": actor.visible,
                "process_mode": actor.process_mode,
                "layer": actor.collision_layer,
                "mask": actor.collision_mask
            })
            actor.visible = false
            actor.process_mode = Node.PROCESS_MODE_DISABLED
            actor.collision_layer = 0
            actor.collision_mask = 0
        # Actor can cast again after the current in-flight animation finishes.
        v39_respawn = 0.0
        v39_player_hp = V39_PLAYER_MAX_HP
        v39_target = null
        print("V15 VFX-ONLY ON: no monster AI, no demo collision or HP. F7 toggles; hold Space to cast. Frame origin still preview.")
    else:
        for saved in v15_hidden_actors:
            var actor: StaticBody2D = saved.get("node") as StaticBody2D
            if not is_instance_valid(actor):
                continue
            actor.visible = bool(saved["visible"])
            actor.set("process_mode", int(saved["process_mode"]))
            actor.collision_layer = int(saved["layer"])
            actor.collision_mask = int(saved["mask"])
        v15_hidden_actors.clear()
        if is_instance_valid(main_combat):
            main_combat.set_physics_process(v15_combat_was_processing)
        v39_target = null
        print("V15 VFX-ONLY OFF: demo combat/HP/AI restored.")
    _refresh_v22_status()

func _v15_open_native_trace() -> void:
    if not v15_vfx_only:
        return
    var audit_scene: String = "res://scenes/JX141NativeFlyAudit.tscn"
    if not ResourceLoader.exists(audit_scene, "PackedScene"):
        push_warning("V15: Native FLY audit scene missing. First copy the V12 audit scene and evidence files.")
        return
    # F5 loads main.tscn again; this scene is read-only captured client data.
    get_tree().call_deferred("change_scene_to_file", audit_scene)

func _preview_active_vfx() -> void:
    # Pure rendering check; no mana, cooldown, skill requirements or HP damage.
    # Select the desired weapon with 1/2/3, then press F7.
    if player == null or dummy == null:
        return
    var skill: Dictionary = player.call("get_active_skill")
    if skill.is_empty():
        return
    var impact: Vector2 = dummy.global_position + Vector2(0, -45)
    player.call("face", impact - player.global_position)
    if str(skill.get("combat_delivery", "")) == "melee_attached":
        var diff: Vector2 = dummy.global_position - player.global_position
        var aim: Vector2 = diff.normalized() if diff.length_squared() > 0.001 else Vector2.RIGHT
        var reach: float = maxf(35.0, JX_GEOMETRY.attack_range_pixels(skill) * 0.78)
        impact = player.global_position + aim * minf(reach, diff.length())
    var fx := Node2D.new()
    fx.name = "SkillEffect_Preview_%s" % str(skill.get("id", "unknown"))
    var is_other_sect: bool = str(school.get("id", "thien_vuong")) != "thien_vuong"
    var follow_by_source: bool = is_other_sect and int(skill.get("missile_move_kind", -1)) == 5
    fx.set_script(FOLLOW_PREVIEW_CODE if follow_by_source else (SECT_PREVIEW_CODE if is_other_sect else (CTC_9X_EFFECT if bool(skill.get("ctc_9x_many_attack", false)) else SKILL_CODE)))
    add_child(fx)
    if fx.has_method("set_calibration") and visual_qa != null:
        fx.call("set_calibration", visual_qa.call("get_for_skill", int(skill.get("legacy_skill_id", 0))))
    if int(skill.get("legacy_skill_id", 0)) == 322:
        fx.set("blade322_echo_enabled", blade322_echo_enabled)
    fx.call("setup", player, dummy, impact, skill, int(player.get("facing_dir")), resource_resolver, true)
    if is_other_sect and fx.has_method("get_diagnostic"):
        var spr_info: Dictionary = fx.call("get_diagnostic")
        sect_spr_status[int(skill.get("legacy_skill_id", 0))] = str(spr_info.get("asset_notice", "UNKNOWN"))
    show_vfx_diagnostics = true
    _update_vfx_probe()

func _toggle_blade322_pose_inspector() -> void:
    if blade_pose_inspector == null:
        return
    if use_at03_in_main:
        print("V30 K: only AT02 composite pose inspection supported; use O → C for AT03 original layers")
        return
    var on: bool = not bool(blade_pose_inspector.get("active"))
    if on and player != null:
        var weapon: Dictionary = player.call("get_weapon")
        if str(weapon.get("visual_id", "")) != "blade":
            print("V25: chọn Đao bằng phím 1 trước khi giữ pose")
            return
    blade_pose_inspector.call("set_active", on)
    if blade_pose_button != null:
        blade_pose_button.text = "K · THOÁT POSE" if on else "K · GIỮ POSE 322"
    print("V25 SOURCE FRAME HOLD: ", "ON" if on else "OFF", " | VISUAL QA ONLY, NO CAST/HIT")

func _step_blade322_pose_inspector() -> void:
    if blade_pose_inspector != null and bool(blade_pose_inspector.get("active")):
        blade_pose_inspector.call("step_forward")

func _toggle_blade322_echo() -> void:
    blade322_echo_enabled = not blade322_echo_enabled
    if player != null:
        player.set("blade322_combo_enabled", blade322_echo_enabled)
    if blade_shadow_button != null:
        blade_shadow_button.text = "G · SHADOW: ON" if blade322_echo_enabled else "G · SHADOW: OFF"
    # V24: G takes effect immediately on a current 322 swing, not just next cast.
    for child in get_children():
        if child.name.begins_with("SkillEffect_") and child.has_method("set_blade_echo_enabled"):
            var s: Variant = child.get("skill")
            if s is Dictionary and int(s.get("legacy_skill_id", 0)) == 322:
                child.call("set_blade_echo_enabled", blade322_echo_enabled)
    print("JXNHALAM V37 NATIVE POSE HISTORY (7 SLOT, RENDER-CALL PROXY): ", "ON" if blade322_echo_enabled else "OFF")

func _toggle_blade322_visual_slow() -> void:
    blade322_slow_inspect = not blade322_slow_inspect
    if player != null:
        player.set("blade322_visual_slow", blade322_slow_inspect)
    # V34 322 native timing ignores the old slow/fast visual-preview switch.
    print("V34 U: legacy visual slow switch has no effect on 322 native 18Hz tick clock; combat unchanged")

func _toggle_vfx_diagnostics() -> void:
    show_vfx_diagnostics = not show_vfx_diagnostics
    if vfx_debug_button != null:
        vfx_debug_button.text = "VFX DEBUG: ON" if show_vfx_diagnostics else "VFX DEBUG: OFF"
    _update_vfx_probe()

func _update_vfx_probe() -> void:
    if vfx_probe == null:
        return
    if vfx_debug_button != null:
        vfx_debug_button.text = "VFX DEBUG: ON" if show_vfx_diagnostics else "VFX DEBUG: OFF"
    vfx_probe.visible = show_vfx_diagnostics
    if not show_vfx_diagnostics:
        for child in get_children():
            if child.name.begins_with("SkillEffect_"):
                child.set("show_debug_overlay", false)
                child.queue_redraw()
        return
    var active: Array[String] = []
    for child in get_children():
        if not child.name.begins_with("SkillEffect_") or not child.has_method("get_diagnostic"):
            continue
        child.set("show_debug_overlay", true)
        var report: Dictionary = child.call("get_diagnostic")
        var detail: String = "%s %s %d/%d @%dms dir:%d/%d [%s]" % [
            str(report.get("skill", "")), str(report.get("stage", "")),
            int(report.get("frame", 0)), int(report.get("frames", 0)),
            int(report.get("ctc_frame_ms", 0)),
            int(report.get("direction", 0)), int(report.get("directions", 0)),
            str(report.get("sprite_source", ""))]
        if str(report.get("skill", "")) == "325":
            var visual: Dictionary = report.get("m141_native_v3", {})
            detail += " | M141 created:%d active:%d hit:%d [%s]" % [
                int(visual.get("fly_total", 0)), int(visual.get("active_fly", 0)),
                int(visual.get("impact_sprites", 0)), str(visual.get("replay_status", "?"))]
        active.append(detail)
    if active.is_empty():
        vfx_probe.text = "F7: xem VFX của vũ khí đã chọn (không trừ máu/mana) | V: ẩn chẩn đoán"
    else:
        var details: String = active[0]
        if active.size() > 1:
            details += " | " + active[1]
        vfx_probe.text = "VFX LIVE: " + details



func _on_visual_qa_changed(skill_id: int, config: Dictionary) -> void:
    # Live preview calibration only: existing sprites change immediately.
    for child in get_children():
        if not child.name.begins_with("SkillEffect_") or not child.has_method("set_calibration"):
            continue
        var current: Variant = child.get("skill")
        if current is Dictionary and int(current.get("legacy_skill_id", -1)) == skill_id:
            child.call("set_calibration", config)
