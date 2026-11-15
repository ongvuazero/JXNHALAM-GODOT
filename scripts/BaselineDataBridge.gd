extends "res://scripts/ClientDataBridge.gd"

## V4: authority = JX Linux 6.0 CTC (20121991) server baseline.
## Client SPR/atlas is visual data only; root settings must not silently replace
## the authoritative gameplay values. Lua curves are INSPECTION-ONLY, not run.
const RUNTIME_PATH: String = "res://data/baseline/gameplay_runtime.json"
const FACTIONS_PATH: String = "res://data/baseline/10_factions.json"
const KNOTS_PATH: String = "res://data/baseline/lua_knots_TV_level150.json"
const KNOTS_9X_PATH: String = "res://data/baseline/lua_knots_TV_9x.json"
const CURVE_ENGINE = preload("res://scripts/CTCCurveEvaluator.gd")

var baseline_meta: Dictionary = {}
var baseline_factions: Array = []
var baseline_entries: Array = []
var tv_lua_knots: Dictionary = {}
var tv_9x_knots: Dictionary = {}

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        load_warning += "Missing baseline JSON: " + path + "\n"
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if parsed is Dictionary:
        return parsed
    load_warning += "Invalid baseline JSON: " + path + "\n"
    return {}

func load_client_data() -> bool:
    load_warning = ""
    var r: Dictionary = _read_json(RUNTIME_PATH)
    var c: Dictionary = _read_json(FACTIONS_PATH)
    var k: Dictionary = _read_json(KNOTS_PATH)
    if r.is_empty() or c.is_empty():
        return false
    by_skill = r.get("skills", {})
    by_missile = r.get("missiles", {})
    actor_defaults = r.get("actor_defaults", {})
    # Directly read the server .txt if present. On exported builds without
    # bundled .txt, the byte-faithful JSON snapshot is a deterministic fallback.
    var candidates: Array[String] = [
        OS.get_executable_path().get_base_dir().path_join("ServerBaseline"),
        ProjectSettings.globalize_path("res://").path_join("ServerBaseline"),
        "res://ServerBaseline"
    ]
    for candidate in candidates:
        var sp: String = candidate.path_join("settings/skills.txt")
        var mp: String = candidate.path_join("settings/missles.txt")
        var bp: String = candidate.path_join("settings/npc/player/basevalue.ini")
        if not FileAccess.file_exists(sp) or not FileAccess.file_exists(mp):
            continue
        var s_read: Dictionary = _read_tab_file(sp, "SkillId")
        var m_read: Dictionary = _read_tab_file(mp, "MissleId")
        if s_read.is_empty() or m_read.is_empty():
            continue
        var expected: Dictionary = r.get("sha256", {})
        if FileAccess.get_sha256(sp) != str(expected.get("settings/skills.txt", "")) or FileAccess.get_sha256(mp) != str(expected.get("settings/missles.txt", "")):
            load_warning += "WARNING: server baseline text modified; original reference checksums no longer match.\n"
        by_skill = s_read
        by_missile = m_read
        actor_defaults = _read_actor_defaults(bp)
        root_dir = candidate
        source_paths = {"skills":sp,"missles":mp,"basevalue":bp}
        break
    baseline_meta = r
    baseline_factions = c.get("factions", [])
    baseline_entries = c.get("entries", [])
    tv_lua_knots = k
    tv_9x_knots = _read_json(KNOTS_9X_PATH)
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/manifest.json"))
    vfx_manifest = decoded if decoded is Dictionary else {}
    if source_paths.is_empty():
        root_dir = "res://data/baseline"
        source_paths = {"skills":"snapshot:res://data/baseline/gameplay_runtime.json",
            "missles":"snapshot:res://data/baseline/gameplay_runtime.json", "basevalue":"snapshot:res://data/baseline/gameplay_runtime.json"}
    return not by_skill.is_empty() and not by_missile.is_empty()

func get_counts() -> String:
    return "SERVER SKILL:%d  MISSILE:%d | 10 PHAI:%d" % [
        int(baseline_meta.get("skill_rows_total", 0)),
        int(baseline_meta.get("missile_rows_total", 0)),
        baseline_factions.size()
    ]

func _create_skill(catalog_entry: Dictionary, template: Dictionary) -> Dictionary:
    # V3 catalog's missile_ids came from a DIFFERENT client table. Remove it.
    # Reconstruct the chain exclusively from the server baseline instead.
    var fresh: Dictionary = catalog_entry.duplicate(true)
    fresh["missile_ids"] = ""
    var skill: Dictionary = super._create_skill(fresh, template)
    if skill.is_empty():
        return skill
    var id: int = int(catalog_entry.get("id", 0))
    var raw: Dictionary = by_skill.get(str(id), {})
    skill["authoritative_data"] = "JX_LINUX_6.0_CTC_20121991_SERVER"
    skill["legacy_attack_radius_units_unverified"] = true
    skill["level_required"] = _int(raw, "ReqLevel")
    skill["skill_style_raw"] = _int(raw, "SkillStyle")
    skill["lvl_settings"] = []
    for i in range(1, 21):
        var key: String = "LvlSetting%d" % i
        var val: String = "LvlData%d" % i
        if not str(raw.get(key, "")).is_empty():
            skill["lvl_settings"].append({"field": str(raw.get(key, "")), "value_source": str(raw.get(val, ""))})
    if tv_lua_knots.has(str(id)):
        skill["lua_table"] = str(tv_lua_knots[str(id)].get("lua_table", ""))
        skill["mastery_level"] = 1  # Configurable test mastery, not player level.
        skill["lua_properties_level_1"] = CURVE_ENGINE.evaluate(tv_lua_knots[str(id)], 1)
        skill["lua_curves_are_partial_runtime"] = true
        # For JX_LINUX_6_CTC three supported skills, the authored Lua table
        # defines skill_cost_v; use that numeric point, not a hand-written cost.
        var evaluated: Dictionary = skill["lua_properties_level_1"]
        if evaluated.has("skill_cost_v"):
            skill["mana_cost_preview"] = int(round(float(evaluated["skill_cost_v"])))
    # Keep dummy damage visibly distinct from unimplemented server combat.
    skill["damage_is_debug_only"] = true
    return skill

func list_factions() -> Array:
    return baseline_factions

func list_faction_skills(faction_code: String) -> Array:
    var items: Array = []
    for e in baseline_entries:
        if e is Dictionary and str(e.get("faction", "")) == faction_code:
            items.append(e)
    return items

func get_skill_entry(faction_code: String, skill_id: int) -> Dictionary:
    for e in baseline_entries:
        if e is Dictionary and str(e.get("faction", "")) == faction_code and int(e.get("skill_id", -1)) == skill_id:
            return e
    return {}

func get_lua_knots(skill_id: int) -> Dictionary:
    return tv_lua_knots.get(str(skill_id), {})


# V6.4: user-selected 9x-only bar. Original server list remains intact for F4.
# Never include V6.3's 150 skills in playable slots.
func inject_client_skills(sect: Dictionary) -> Dictionary:
    if str(sect.get("id", "")) != "thien_vuong":
        return sect.duplicate(true)
    var out: Dictionary = sect.duplicate(true)
    if by_skill.is_empty():
        return out
    var exact_ids: Dictionary = {"blade": 322, "spear": 323, "hammer": 325}
    var exact_names: Dictionary = {322: "Phá Thiên Trảm", 323: "Truy Tinh Trục Nguyệt", 325: "Truy Phong Quyết"}
    var weapons: Array = out.get("weapons", [])
    for i in range(weapons.size()):
        var weapon: Dictionary = weapons[i]
        var visual_id: String = str(weapon.get("visual_id", ""))
        if not exact_ids.has(visual_id):
            continue
        var legacy_id: int = int(exact_ids[visual_id])
        var original_skills: Array = weapon.get("skills", [])
        var template: Dictionary = original_skills[0] if not original_skills.is_empty() else {}
        var catalog: Dictionary = {"id": legacy_id, "name": exact_names[legacy_id], "branch": visual_id}
        var active_skill: Dictionary = _create_skill(catalog, template)
        if active_skill.is_empty():
            push_error("CTC 9X missing original skill %d" % legacy_id)
            continue
        # Preserve authored 9x animation modes and timeline (not 150 projectile).
        active_skill["id"] = "tv_9x_%d" % legacy_id
        active_skill["name"] = str(exact_names[legacy_id])
        active_skill["combat_delivery"] = "melee_attached"
        active_skill["is_melee"] = true
        active_skill["vfx"] = template.get("vfx", {})
        active_skill["cast_ms"] = template.get("cast_ms", 350)
        active_skill["release_ms"] = template.get("release_ms", 350)
        active_skill["character_cast_ms"] = template.get("character_cast_ms", 780)
        active_skill["recovery_ms"] = template.get("recovery_ms", 130)
        active_skill["hit_ms"] = template.get("hit_ms", 300)
        active_skill["end_ms"] = template.get("end_ms", 130)
        active_skill["hit_radius"] = template.get("hit_radius", 92)
        active_skill["socket_y"] = template.get("socket_y", -70)
        # CTC V6.5: preserve exact visual metadata and nested cast graph.
        # Critically, SPR header frame-interval (milliseconds) is NOT the
        # collision animation interval from missles.txt (legacy engine ticks).
        var primary_row: Dictionary = by_skill.get(str(legacy_id), {})
        var child_skill_id: int = _int(primary_row, "ChildSkillId")
        var secondary_row: Dictionary = by_skill.get(str(child_skill_id), {})
        var missile_chain: Array = active_skill.get("missile_ids", [])
        var primary_missile_id: int = int(missile_chain[0]) if not missile_chain.is_empty() else 0
        var original_missile: Dictionary = by_missile.get(str(primary_missile_id), {})
        active_skill["original_anim_info"] = {
            "fly": str(original_missile.get("AnimFileInfo2", "")),
            "hit": str(original_missile.get("AnimFileInfo4", ""))
        }
        active_skill["ctc_18_tick_vfx"] = true
        # V3.5/V3.6: confirmed route DoManyAttack for this set of skills.
        # Do NOT associate MisslesForm=12 with OnRunAttack by name.
        active_skill["ctc_9x_many_attack"] = true
        active_skill["ctc_9x_run_attack"] = false
        active_skill["server_route_evidence"] = "V3.5 allocations + V3.6 dispatch, server 2024"
        active_skill["buff_1427_separate"] = true
        active_skill["source_nested_cast"] = {
            "parent_id": legacy_id, "parent_child_id": child_skill_id,
            "parent_child_num": _int(primary_row, "ChildSkillNum"),
            "parent_melee_form": _int(primary_row, "MisslesForm"),
            "parent_wait_ticks": _int(primary_row, "WaitTime"),
            "parent_generate_style": _int(primary_row, "MslsGenerate"),
            "parent_generate_data_ticks": _int(primary_row, "MslsGenerateData"),
            "secondary_child_num": _int(secondary_row, "ChildSkillNum"),
            "secondary_missles_form": _int(secondary_row, "MisslesForm"),
            "secondary_param1": _int(secondary_row, "Param1"),
            "secondary_param2": _int(secondary_row, "Param2"),
            "secondary_wait_ticks": _int(secondary_row, "WaitTime"),
            "secondary_generate_style": _int(secondary_row, "MslsGenerate"),
            "secondary_generate_data_ticks": _int(secondary_row, "MslsGenerateData"),
            "missile_id": primary_missile_id
        }
        # The legacy graph may create 3/5 missiles. Do not assume they are
        # five identical hit effects or invent impact coordinates/damage.
        active_skill["asset_source"] = "CTC skill/missile metadata + bundled original SPR; runtime geometry/timing unverified"
        if tv_9x_knots.has(str(legacy_id)):
            var knot: Dictionary = tv_9x_knots[str(legacy_id)]
            var properties: Dictionary = CURVE_ENGINE.evaluate(knot, 1)
            active_skill["lua_table"] = str(knot.get("lua_table", ""))
            active_skill["lua_properties_level_1"] = properties
            active_skill["lua_curves_are_partial_runtime"] = true
            if properties.has("skill_cost_v"):
                active_skill["mana_cost_preview"] = int(round(float(properties["skill_cost_v"])))
        # No arbitrary damage formula: practice dummy damage stays marked DEMO.
        active_skill["damage_is_debug_only"] = true
        weapon["skills"] = [active_skill]
        weapon["using_original_server_data"] = true
        weapons[i] = weapon
    out["weapons"] = weapons
    out["source_client_data"] = root_dir
    return out
