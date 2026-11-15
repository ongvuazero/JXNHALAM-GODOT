extends RefCounted

## Runtime reader of external loose JX client settings/ (overrides legacy Data/settings/). Does not convert or overwrite
## skills.txt / missles.txt. Numeric and ASCII header cells are used as authored.
## Names of Thiên Vương are obtained from the verified UTF-8 skill catalog, because
## the old file mixes Vietnamese TCVN3 and Chinese GBK in the SAME table.
## This is a data adapter, NOT a complete implementation of original JX Lua combat.

var root_dir: String = ""
var by_skill: Dictionary = {}
var by_missile: Dictionary = {}
var load_warning: String = ""
var vfx_manifest: Dictionary = {}
var actor_defaults: Dictionary = {}

func _read_tab_file(file_path: String, id_field: String) -> Dictionary:
    var result: Dictionary = {}
    if not FileAccess.file_exists(file_path):
        load_warning += "MISSING: " + file_path + "\n"
        return result
    var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        load_warning += "CANNOT OPEN: " + file_path + "\n"
        return result
    var raw: PackedByteArray = file.get_buffer(file.get_length())
    file.close()
    # Legacy files are NOT UTF-8. Using ASCII byte mapping preserves 0-127 fields,
    # integer values, script paths, identifiers, and original raw strings for trace.
    var lines: PackedStringArray = raw.get_string_from_ascii().split("\n", false)
    if lines.size() < 2:
        return result
    var header: PackedStringArray = lines[0].trim_suffix("\r").split("\t", true)
    for line_index in range(1, lines.size()):
        var line: String = lines[line_index].trim_suffix("\r")
        if line.is_empty():
            continue
        var values: PackedStringArray = line.split("\t", true)
        var row: Dictionary = {}
        for i in range(mini(header.size(), values.size())):
            row[header[i]] = values[i]
        var key: String = str(row.get(id_field, "")).strip_edges()
        if key.is_valid_int():
            result[key] = row
    return result

# External loose files override the old Data/settings copy (V3 compatibility only).
# Note: PAK archives in Data/ are not supported by this adapter yet.
# During F5, Godot uses project_root/settings/; exported builds use exe_dir/settings/.
var source_paths: Dictionary = {}

func _client_roots() -> Array[String]:
    var exe_dir: String = OS.get_executable_path().get_base_dir()
    var project_dir: String = ProjectSettings.globalize_path("res://")
    var roots: Array[String] = [exe_dir, project_dir]
    for r in [exe_dir, project_dir]:
        roots.append(r.path_join("Data"))  # V3 legacy loose files only, NOT PAK.
        roots.append(r.path_join("data"))
    return roots

func _find_loose_path(relative_path: String) -> String:
    var clean: String = relative_path.replace("\\", "/").trim_prefix("/")
    for segment in clean.split("/", false):
        if segment == ".." or segment == ".":
            return ""
    for root in _client_roots():
        var p: String = root.path_join(clean)
        if FileAccess.file_exists(p):
            return p
    return ""

func resolve_legacy_script_path(raw_path: String) -> String:
    # Resolve only. This does not execute original JX Lua scripts or their formulas.
    var clean: String = raw_path.replace("\\", "/").trim_prefix("/")
    if not clean.begins_with("script/"):
        clean = "script/" + clean
    return _find_loose_path(clean)

func load_client_data() -> bool:
    load_warning = ""
    source_paths.clear()
    by_skill.clear()
    by_missile.clear()
    var skill_file: String = _find_loose_path("settings/skills.txt")
    var missile_file: String = _find_loose_path("settings/missles.txt")
    var base_file: String = _find_loose_path("settings/npc/player/basevalue.ini")
    if skill_file.is_empty() or missile_file.is_empty():
        load_warning = "Missing loose settings/skills.txt or settings/missles.txt beside EXE/project. Data/*.pak reader is NOT implemented."
        return false
    source_paths = {"skills": skill_file, "missles": missile_file, "basevalue": base_file}
    root_dir = skill_file.get_base_dir().get_base_dir()
    by_skill = _read_tab_file(skill_file, "SkillId")
    by_missile = _read_tab_file(missile_file, "MissleId")
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/manifest.json"))
    if decoded is Dictionary:
        vfx_manifest = decoded
    actor_defaults = _read_actor_defaults(base_file)
    return not by_skill.is_empty() and not by_missile.is_empty()

func _read_actor_defaults(file_path: String) -> Dictionary:
    var defaults: Dictionary = {"RunSpeed": 10, "WalkSpeed": 5, "AttackFrame": 18, "CastFrame": 18}
    if not FileAccess.file_exists(file_path):
        return defaults
    var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        return defaults
    var section: String = ""
    while not file.eof_reached():
        var line: String = file.get_line().strip_edges()
        if line.begins_with("[") and line.ends_with("]"):
            section = line.substr(1, line.length()-2)
        elif section == "Common" and line.contains("="):
            var parts: PackedStringArray = line.split("=", true, 1)
            if parts.size() == 2 and parts[1].strip_edges().is_valid_int():
                defaults[parts[0].strip_edges()] = int(parts[1].strip_edges())
    file.close()
    return defaults

func get_counts() -> String:
    return "SKILLS:%d | MISSILES:%d" % [by_skill.size(), by_missile.size()]

func _int(row: Dictionary, field: String, fallback: int = 0) -> int:
    var raw_value: String = str(row.get(field, "")).strip_edges()
    return int(raw_value) if raw_value.is_valid_int() else fallback

func _find_missile_ids(skill_id: int) -> Array[int]:
    var found: Array[int] = []
    var frontier: Array[int] = [skill_id]
    var seen: Dictionary = {}
    # Restrict depth to the direct skill->child->missile chain. Client skill tables
    # often reuse IDs across SKILL and MISSILE domains; do not recurse infinitely.
    for depth in range(3):
        var next_frontier: Array[int] = []
        for candidate in frontier:
            if seen.has(candidate):
                continue
            seen[candidate] = true
            var row: Dictionary = by_skill.get(str(candidate), {})
            if row.is_empty():
                continue
            var child: int = _int(row, "ChildSkillId")
            if child == 0:
                continue
            if by_missile.has(str(child)) and (_int(row, "SkillStyle") == 0 or depth == 2):
                if not found.has(child):
                    found.append(child)
            elif by_skill.has(str(child)) and depth < 2:
                next_frontier.append(child)
        frontier = next_frontier
    return found

func _sprite_key(original_path: String) -> String:
    if original_path.is_empty():
        return ""
    var normalized: String = original_path.replace("\\", "/")
    var basename: String = normalized.get_file().get_basename()
    return basename if vfx_manifest.has(basename) else ""

func _vfx_for_missile(missile: Dictionary) -> Dictionary:
    var fly: String = _sprite_key(str(missile.get("AnimFile2", "")))
    if fly.is_empty():
        fly = _sprite_key(str(missile.get("AnimFile1", "")))
    var hit: String = _sprite_key(str(missile.get("AnimFile4", "")))
    if hit.is_empty():
        hit = _sprite_key(str(missile.get("AnimFile3", "")))
    return {"cast": fly, "fly": fly, "hit": hit, "end": hit}

func _create_skill(catalog_entry: Dictionary, template: Dictionary) -> Dictionary:
    var legacy_id: int = int(catalog_entry.get("id", 0))
    var row: Dictionary = by_skill.get(str(legacy_id), {})
    if row.is_empty():
        return {}
    var listed: String = str(catalog_entry.get("missile_ids", ""))
    var missile_ids: Array[int] = []
    for piece in listed.split(",", false):
        var idtext: String = piece.strip_edges()
        if idtext.is_valid_int():
            var m: int = int(idtext)
            if by_missile.has(str(m)) and not missile_ids.has(m):
                missile_ids.append(m)
    if missile_ids.is_empty():
        missile_ids = _find_missile_ids(legacy_id)
    var missile: Dictionary = by_missile.get(str(missile_ids[0]), {}) if not missile_ids.is_empty() else {}
    var vfx: Dictionary = _vfx_for_missile(missile)
    var has_vfx: bool = not str(vfx.get("fly", "")).is_empty() or not str(vfx.get("hit", "")).is_empty()
    var attack_radius: int = _int(row, "AttackRadius")
    var target_self: bool = _int(row, "TargetSelf") != 0 and _int(row, "TargetEnemy") == 0
    var frames: int = _int(row, "TimePerCast")
    # JX values are NOT necessarily milliseconds. Legacy->Godot scaling is provisional.
    var cooldown: int = maxi(300, frames * 40) if frames > 0 else 850
    var projectile_speed: int = _int(missile, "Speed")
    var skill: Dictionary = {
        "id": "jx_%d" % legacy_id,
        "legacy_skill_id": legacy_id,
        "name": str(catalog_entry.get("name", "Skill %d" % legacy_id)),
        "attack_radius_raw": attack_radius,
        "attack_radius": maxf(48.0, float(attack_radius)),
        "child_skill_id": _int(row, "ChildSkillId"),
        "child_skill_num": _int(row, "ChildSkillNum", 1),
        "character_anim_id": _int(row, "CharAnimId"),
        "wait_time_raw": _int(row, "WaitTime"),
        "skill_cost_type": _int(row, "SkillCostType"),
        "cost_value_raw": _int(row, "CostValue"),
        "weapon_limit": _int(row, "EqtLimit"),
        "style": _int(row, "SkillStyle"),
        "is_melee": _int(row, "IsMelee") == 1,
        "target_self": target_self,
        "target_enemy": _int(row, "TargetEnemy") != 0,
        "level_required": _int(row, "ReqLevel"),
        "cooldown_raw": frames,
        "cooldown_ms": cooldown,
        "missile_ids": missile_ids,
        "missile_move_kind": _int(missile, "MoveKind"),
        "missile_speed_raw": projectile_speed,
        "missile_lifetime_raw": _int(missile, "LifeTime"),
        "collision_range_raw": _int(missile, "CollidRange"),
        "fly_speed": maxi(200, projectile_speed * 25) if projectile_speed > 0 else 850,
        "cast_ms": int(template.get("cast_ms", 425)),
        "release_ms": int(template.get("release_ms", 425)),
        "character_cast_ms": int(template.get("character_cast_ms", 900)),
        "recovery_ms": 100,
        "hit_ms": 380,
        "end_ms": 280,
        "damage": int(template.get("damage", 60)),
        "damage_is_debug_only": true,
        "hit_radius": maxi(48, _int(missile, "DmgRange", 1) * 28),
        "socket_x": int(template.get("socket_x", 0)),
        "socket_y": int(template.get("socket_y", -83)),
        "vfx": vfx,
        "has_vfx": has_vfx,
        "original_precast_spr": str(row.get("PreCastSpr", "")),
        "original_missile_spr": [str(missile.get("AnimFile1", "")), str(missile.get("AnimFile2", "")), str(missile.get("AnimFile3", "")), str(missile.get("AnimFile4", ""))],
        "lvl_script": str(row.get("LvlSetScript", "")),
    }
    return skill

func inject_client_skills(sect: Dictionary) -> Dictionary:
    # Nine school research catalogs are generated from numeric JX1 source rows.
    # Do NOT rewrite them using the Thiên Vương-only catalog.
    if str(sect.get("id", "")) != "thien_vuong":
        return sect.duplicate(true)
    # Retain original V2 animations. Only combat parameters come directly from Data.
    var out: Dictionary = sect.duplicate(true)
    if by_skill.is_empty():
        return out
    var catalog_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sects/thien_vuong_full_skill_catalog.json"))
    if not catalog_variant is Dictionary:
        return out
    var cat: Array = catalog_variant.get("skills", [])
    var branches: Array[String] = ["THUONG", "DAO", "CHUY"]
    var weapons: Array = out.get("weapons", [])
    for i in range(mini(weapons.size(), branches.size())):
        var weapon: Dictionary = weapons[i]
        var previous: Array = weapon.get("skills", [])
        var template: Dictionary = previous[0] if not previous.is_empty() and previous[0] is Dictionary else {}
        var new_skills: Array = []
        for record in cat:
            if not record is Dictionary or str(record.get("branch", "")) != branches[i]:
                continue
            var id: int = int(record.get("id", 0))
            var base: Dictionary = by_skill.get(str(id), {})
            if _int(base, "SkillStyle") == 3:
                continue # passive skill; preserved in source data, not cast-able yet
            var prepared: Dictionary = _create_skill(record, template)
            if not prepared.is_empty():
                new_skills.append(prepared)
        if not new_skills.is_empty():
            weapon["skills"] = new_skills
            weapon["using_original_client_data"] = true
            weapons[i] = weapon
    out["weapons"] = weapons
    out["source_client_data"] = root_dir
    return out
