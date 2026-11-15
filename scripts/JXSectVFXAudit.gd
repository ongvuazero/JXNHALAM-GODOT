extends RefCounted
## V43.6: read-only audit of original SPR asset availability for 9 sects.
## Does not alter gameplay, add fake effects or change JX1 skill selection.
const SECT_REGISTRY: String = "res://data/sects/registry.json"

static func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}

static func _csv(value: Variant) -> String:
    return '"' + str(value).replace('"', '""').replace("\n", " ").replace("\r", " ") + '"'

static func run(resolver: RefCounted) -> Dictionary:
    var lines: PackedStringArray = ["sect,skill_id,skill,stage,status,hash,hash_mode,hash_candidates,source,compression,frames,directions,virtual_path"]
    var totals: Dictionary = {"stages": 0, "ok": 0, "missing": 0, "decode_fail": 0,
        "no_pack": 0, "empty_paths": 0}
    var samples: Array[String] = []
    if resolver == null or not resolver.has_method("probe_spr"):
        return {"error": "NO_RESOLVER", "summary": "Reader not ready"}
    var registry: Dictionary = _read_json(SECT_REGISTRY)
    var signed_hits: int = 0
    var unsigned_hits: int = 0
    for entry in registry.get("sects", []):
        if not entry is Dictionary:
            continue
        var sect: String = str(entry.get("id", ""))
        if sect == "thien_vuong":
            continue # TVC audit appended below using source missile IDs 138/139/141
        var conf: Dictionary = _read_json(str(entry.get("config", "")))
        for weapon in conf.get("weapons", []):
            if not weapon is Dictionary:
                continue
            for skill in weapon.get("skills", []):
                if not skill is Dictionary:
                    continue
                var paths: Array = skill.get("original_missile_spr", [])
                for stage in ["fly", "hit"]:
                    var pos: int = 1 if stage == "fly" else 3
                    var name: String = str(paths[pos]) if pos < paths.size() else ""
                    if name.is_empty() and pos - 1 < paths.size():
                        name = str(paths[pos - 1])
                    if name.is_empty():
                        totals["empty_paths"] = int(totals["empty_paths"]) + 1
                        continue
                    totals["stages"] = int(totals["stages"]) + 1
                    var p: Dictionary = resolver.call("probe_spr", name)
                    var status: String = str(p.get("status", "UNKNOWN"))
                    if status.begins_with("OK_SPR_"):
                        totals["ok"] = int(totals["ok"]) + 1
                        if str(p.get("hash_mode", "")) == "signed_char_cpp":
                            signed_hits += 1
                        elif str(p.get("hash_mode", "")) == "unsigned_byte_legacy":
                            unsigned_hits += 1
                    elif status == "NO_CLIENT_PAK":
                        totals["no_pack"] = int(totals["no_pack"]) + 1
                    elif status == "PAK_ENTRY_DECODE_FAILED":
                        totals["decode_fail"] = int(totals["decode_fail"]) + 1
                    else:
                        totals["missing"] = int(totals["missing"]) + 1
                    if not status.begins_with("OK_SPR_") and samples.size() < 5:
                        samples.append("%s %s %s: %s" % [sect, skill.get("legacy_skill_id", 0), stage, status])
                    var cols: Array = [sect, int(skill.get("legacy_skill_id", 0)),
                        str(skill.get("name", "")), stage, status,
                        "%08X" % max(0, int(p.get("hash", 0))),
                        str(p.get("hash_mode", "")),
                        str(p.get("hash_candidates", [])),
                        str(p.get("source", "")), str(p.get("compression", "")),
                        int(p.get("frames", 0)), int(p.get("directions", 0)), name]
                    var csv_cols: PackedStringArray = []
                    for column in cols:
                        csv_cols.append(_csv(column))
                    lines.append(",".join(csv_cols))
    # The three Thiên Vương missile source slots are explicitly recorded in
    # baseline settings/missles.txt; this is a *lookup* test, not pose validation.
    var tv_rows: Dictionary = {
        138: {"fly": "", "hit": "\\spr\\skill\\tw\\×··ç¾ö.spr"},
        139: {"fly": "\\spr\\skill\\²¹³ä\\mag_npc_¶ÌÃ«.spr", "hit": "\\spr\\skill\\sl\\½ðÁúÌ½×¦.spr"},
        141: {"fly": "\\spr\\skill\\ÉÙÁÖ\\bz_bo1_½ð²¨.spr", "hit": "\\spr\\skill\\²¹³ä\\BZ_é¢1.spr"}
    }
    for mid in tv_rows.keys():
        var tv: Dictionary = tv_rows[mid]
        for stage in ["fly", "hit"]:
            var virtual_name: String = str(tv[stage])
            if virtual_name.is_empty():
                continue
            var probe: Dictionary = resolver.call("probe_spr", virtual_name)
            var values: Array = ["thien_vuong", str(mid), "M%d" % int(mid), stage,
                str(probe.get("status", "UNKNOWN")), "%08X" % max(0, int(probe.get("hash", 0))),
                str(probe.get("hash_mode", "")), str(probe.get("hash_candidates", [])),
                str(probe.get("source", "")), str(probe.get("compression", "")),
                int(probe.get("frames", 0)), int(probe.get("directions", 0)), virtual_name]
            var record: PackedStringArray = []
            for value in values:
                record.append(_csv(value))
            lines.append(",".join(record))
    var path: String = "user://JXNHALAM_VFX_10PHAI_HASH_AUDIT.csv"
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_string("\n".join(lines) + "\n")
        f.close()
    var linked_summary: Dictionary = _run_linked_stage_audit(resolver)
    var report: String = "SPR 9 phai: %d/%d stage, %d missing, %d decode error | signed hash hits:%d unsigned:%d | +TVC rows" % [
        int(totals["ok"]), int(totals["stages"]), int(totals["missing"]),
        int(totals["decode_fail"]), signed_hits, unsigned_hits]
    if not linked_summary.is_empty():
        report += " | Lua stage audit: %d decoded, %d missing/failed, %d not declared" % [
            int(linked_summary.get("ok", 0)), int(linked_summary.get("bad", 0)),
            int(linked_summary.get("not_declared", 0))]
    return {"summary": report, "totals": totals, "report_path": ProjectSettings.globalize_path(path),
        "linked_report_path": str(linked_summary.get("report_path", "")), "samples": samples}

# V44.6: F10 scans PARENT and Lua-linked CHILD assets by their own skill ID.
# Missing AnimFile4 is not repaired by borrowing AnimFile3 or another skill.
# Distinguish NOT DECLARED from PAK absent/codec failure and avoid fake FX.
static func _run_linked_stage_audit(resolver: RefCounted) -> Dictionary:
    var graph_path: String = "res://data/lua_events/jx_lua_event_graph.json"
    var qa_path: String = "res://data/lua_events/preview_settings.json"
    var root_json: Dictionary = _read_json(graph_path)
    var graph: Dictionary = root_json.get("skills", {})
    if graph.is_empty():
        return {}
    var qa: Dictionary = _read_json(qa_path)
    var level: int = clampi(int(qa.get("default_skill_level", 20)), 1, 20)
    var header: String = "sect,parent_skill_id,skill_id,part,trigger,missile_id,move_kind,stage,status,frames,directions,decoder_mode,source,virtual_path,notes"
    var lines: PackedStringArray = [header]
    var stat: Dictionary = {"ok": 0, "bad": 0, "not_declared": 0}
    var visited: Dictionary = {}
    var registry: Dictionary = _read_json(SECT_REGISTRY)
    for sect_entry in registry.get("sects", []):
        if not sect_entry is Dictionary:
            continue
        var school: String = str(sect_entry.get("id", ""))
        if school == "thien_vuong":
            continue
        var conf: Dictionary = _read_json(str(sect_entry.get("config", "")))
        for weapon in conf.get("weapons", []):
            if not weapon is Dictionary:
                continue
            for original in weapon.get("skills", []):
                if not original is Dictionary:
                    continue
                var parent_id: int = int(original.get("legacy_skill_id", 0))
                if parent_id <= 0:
                    continue
                var native_parent: Dictionary = graph.get(str(parent_id), {})
                if native_parent.is_empty():
                    continue
                var parent_tag: String = school + ":" + str(parent_id) + ":parent"
                if not visited.has(parent_tag):
                    visited[parent_tag] = true
                    _append_skill_stages(lines, stat, resolver, school, parent_id,
                        parent_id, "parent", "cast", native_parent)
                var at_level: Dictionary = native_parent.get("event_levels", {})
                var events: Array = at_level.get(str(level), native_parent.get("events", []))
                for event_data in events:
                    if not event_data is Dictionary:
                        continue
                    var child_id: int = int(event_data.get("skill_id", 0))
                    var trigger: String = str(event_data.get("trigger", ""))
                    if child_id <= 0:
                        continue
                    var child_tag: String = school + ":" + str(parent_id) + ":" + str(child_id) + ":" + trigger
                    if visited.has(child_tag):
                        continue
                    visited[child_tag] = true
                    var native_child: Dictionary = graph.get(str(child_id), {})
                    if native_child.is_empty():
                        var row_missing: Array = [school, parent_id, child_id, "linked", trigger,
                            -1, -1, "ALL", "CHILD_SKILL_METADATA_MISSING", 0, 0, "", "", "", "Lua graph has no child definition"]
                        var missing_csv: PackedStringArray = []
                        for value in row_missing:
                            missing_csv.append(_csv(value))
                        lines.append(",".join(missing_csv))
                        stat["bad"] = int(stat["bad"]) + 1
                        continue
                    _append_skill_stages(lines, stat, resolver, school, parent_id,
                        child_id, "linked", trigger, native_child)
    var path: String = "user://JXNHALAM_VFX_LINKED_10PHAI_RUNTIME.csv"
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_string("\n".join(lines) + "\n")
        f.close()
    stat["report_path"] = ProjectSettings.globalize_path(path)
    stat["rows"] = maxi(0, lines.size() - 1)
    return stat

static func _append_skill_stages(lines: PackedStringArray, stat: Dictionary,
        resolver: RefCounted, sect: String, parent_id: int, skill_id: int,
        part: String, trigger: String, native: Dictionary) -> void:
    var paths: Array = native.get("anim_paths", [])
    var stages: Array = [
        ["precast", str(native.get("precast_spr", ""))],
        ["anim1", str(paths[0]) if paths.size() > 0 else ""],
        ["fly", str(paths[1]) if paths.size() > 1 else ""],
        ["travel_end", str(paths[2]) if paths.size() > 2 else ""],
        ["hit", str(paths[3]) if paths.size() > 3 else ""]
    ]
    for row_stage in stages:
        var role: String = str(row_stage[0])
        var path: String = str(row_stage[1])
        var status: String = "NOT_DECLARED"
        var frames: int = 0
        var dirs: int = 0
        var decoder: String = ""
        var source: String = ""
        var notes: String = ""
        if path.is_empty():
            stat["not_declared"] = int(stat["not_declared"]) + 1
        else:
            var probe: Dictionary = resolver.call("probe_spr", path)
            status = str(probe.get("status", "UNKNOWN"))
            frames = int(probe.get("frames", 0))
            dirs = int(probe.get("directions", 0))
            decoder = str(probe.get("decoder_mode", ""))
            source = str(probe.get("source", ""))
            if status.begins_with("OK_SPR_"):
                stat["ok"] = int(stat["ok"]) + 1
            else:
                stat["bad"] = int(stat["bad"]) + 1
        if part == "linked" and (trigger == "collide" or trigger == "vanish") and role == "precast" and not path.is_empty():
            notes = "PRECAST_SKIPPED_FOR_CONTACT_TRIGGER; source may be reused by another school"
        if role == "hit" and path.is_empty():
            notes = "No native AnimFile4; do not reuse AnimFile3 as HIT"
        var values: Array = [sect, parent_id, skill_id, part, trigger,
            int(native.get("missile_id", 0)), int(native.get("move_kind", -1)),
            role, status, frames, dirs, decoder, source, path, notes]
        var fields: PackedStringArray = []
        for value in values:
            fields.append(_csv(value))
        lines.append(",".join(fields))
