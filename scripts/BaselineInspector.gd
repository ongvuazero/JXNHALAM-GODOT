extends CanvasLayer
const CURVE_ENGINE = preload("res://scripts/CTCCurveEvaluator.gd")

## Lightweight in-game provenance viewer.  Does not execute baseline Lua.
var db: RefCounted
var ui_panel: PanelContainer
var text_box: RichTextLabel
var faction_index: int = 1
var skill_index: int = 0
var visible_open: bool = false

func initialize(database: RefCounted) -> void:
    db = database
    var factions: Array = db.call("list_factions")
    for i in range(factions.size()):
        if str(factions[i].get("code", "")) == "tianwang":
            faction_index = i
            break
    layer = 20
    ui_panel = PanelContainer.new()
    ui_panel.name = "BaselineInspectorUI"
    ui_panel.position = Vector2(225, 70)
    ui_panel.size = Vector2(840, 555)
    ui_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(ui_panel)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.055, 0.075, 0.103, 0.98)
    style.border_color = Color(0.55, 0.68, 0.75)
    style.set_border_width_all(1)
    style.set_content_margin_all(15.0)
    ui_panel.add_theme_stylebox_override("panel", style)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(805, 525)
    scroll.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_panel.add_child(scroll)
    text_box = RichTextLabel.new()
    text_box.bbcode_enabled = true
    text_box.fit_content = true
    text_box.selection_enabled = true
    text_box.scroll_active = false
    text_box.custom_minimum_size = Vector2(780, 520)
    text_box.add_theme_font_size_override("normal_font_size", 17)
    scroll.add_child(text_box)
    ui_panel.visible = false
    _refresh()

func toggle() -> void:
    visible_open = not visible_open
    ui_panel.visible = visible_open
    if visible_open:
        _refresh()

func is_open() -> bool:
    return visible_open

func cycle_faction(step: int) -> void:
    var factions: Array = db.call("list_factions")
    if factions.is_empty():
        return
    faction_index = posmod(faction_index + step, factions.size())
    skill_index = 0
    _refresh()

func cycle_skill(step: int) -> void:
    var f: Dictionary = _current_faction()
    var skills: Array = db.call("list_faction_skills", str(f.get("code", "")))
    if skills.is_empty():
        return
    skill_index = posmod(skill_index + step, skills.size())
    _refresh()

func _current_faction() -> Dictionary:
    var factions: Array = db.call("list_factions")
    return factions[faction_index] if faction_index >= 0 and faction_index < factions.size() else {}

func _refresh() -> void:
    if db == null or text_box == null:
        return
    var fc: Dictionary = _current_faction()
    if fc.is_empty():
        return
    var skills: Array = db.call("list_faction_skills", str(fc.get("code", "")))
    var lines: Array[String] = [
        "[b]JXNHALAM V5 · SERVER CTC + PAK[/b]",
        "Server: Jx_Linux_6.0 CTC(20121991) | ĐỌC BẢNG SỐ LUA, CHƯA THỰC THI LUA ĐỘNG",
        "[color=#91d0e3]PAGEUP / PAGEDOWN[/color] đổi phái · [color=#91d0e3]← / →[/color] đổi skill · F4 đóng",
        "[b]PHÁI:[/b] %s (%s) | %d skill được ghép ID từ bảng client V3" % [str(fc.get("name", "")), str(fc.get("code", "")), skills.size()],
        "[color=#eabf84]9 phái còn lại: đã nhập dữ liệu, chưa có đủ atlas nhân vật để chơi.[/color]",
        ""
    ]
    if skills.is_empty():
        text_box.text = "\n".join(lines)
        return
    var e: Dictionary = skills[skill_index]
    var raw: Dictionary = e.get("server_raw", {})
    var links: Dictionary = e.get("links", {})
    var mid: Array = links.get("missile_candidates", [])
    lines.append("[b]SKILL %d / %d:[/b] %s | SkillId %s" % [skill_index + 1, skills.size(), str(e.get("display_name_from_client_catalog", "")), str(e.get("skill_id", ""))])
    for k in ["SkillStyle", "ReqLevel", "MaxLevel", "AttackRadius", "EqtLimit", "CostValue", "TimePerCast", "WaitTime", "CharAnimId", "ChildSkillId", "LvlSetScript"]:
        lines.append("  %s: %s" % [k, str(raw.get(k, ""))])
    lines.append("  Skill chain (server): %s" % str(links.get("skill_chain", [])))
    lines.append("  Missile candidates: %s" % str(mid))
    lines.append("  Link warnings: %s" % str(links.get("warnings", [])))
    lines.append("  Referenced SPR paths: %d" % e.get("sprites", []).size())
    var path_count: int = 0
    for p in e.get("sprites", []):
        if path_count >= 3:
            break
        lines.append("    %s = %s" % [str(p.get("field", "")), str(p.get("path_8bit_latin1", ""))])
        path_count += 1
    lines.append("")
    var lua: Dictionary = db.call("get_lua_knots", int(e.get("skill_id", 0)))
    if not lua.is_empty():
        lines.append("[b]LUA %s — ĐƯỜNG CONG GỐC (CHỈ XEM)[/b]" % str(lua.get("lua_table", "")))
        var props: Dictionary = lua.get("properties", {})
        var count: int = 0
        for k in props:
            var item: Dictionary = props[k]
            lines.append("  %s: %s" % [str(k), str(item.get("points_in_source_order", [])).substr(0, 105)])
            count += 1
            if count >= 13:
                break
    else:
        lines.append("[color=#eabf84]Chưa trích bảng đường cong Lua của skill này; nguồn Lua gốc có trong ServerBaseline/.[/color]")
    lines.append("")
    if not lua.is_empty():
        var calculated: Dictionary = CURVE_ENGINE.evaluate(lua, 1)
        lines.append("[b]Giá trị bảng LUA tại skill level 1:[/b] %s" % str(calculated))
    lines.append("[color=#eabf84]Chỉ số Lua đơn giản đã tính được; damage lên cọc vẫn là DEMO, chưa đúng toàn bộ combat server.[/color]")
    text_box.text = "\n".join(lines)
