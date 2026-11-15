extends RefCounted
## V6.4: Three 9x skills. PAK decode success and bundled PNG fallback
## are separate statuses. A hash match alone does not count as decoded.
const FALLBACKS: Dictionary = {
    "322:AnimFile4": "res://assets/skill90/jx90_potian_impact.png",
    "323:AnimFile4": "res://assets/skill90/jx90_truytinh_impact.png",
    "325:AnimFile2": "res://assets/skill90/jx90_truyphong_sweep.png",
    "325:AnimFile4": "res://assets/skill90/jx90_truyphong_impact.png"
}
# V6.4.1: Only VFX stages that the playable 9x skill actually uses are
# mandatory. Original missile metadata is kept for reference even if an
# AnimFile2 path belongs to an obsolete/unused projectile stage.
static func _required_tags(sid: int) -> Array[String]:
    match sid:
        322: return ["AnimFile4"] # Dao: hit is used; no projectile
        323: return ["AnimFile4"] # Thuong: melee hit; AnimFile2 is NOT fired
        325: return ["AnimFile2", "AnimFile4"] # Chuy: local sweep + hit
        _: return []

static func run(resolver: RefCounted, baseline: RefCounted) -> Dictionary:
    var records: Array[Dictionary] = []
    var mapping: Array = [[322, 138, "DAO"], [323, 139, "THUONG"], [325, 141, "CHUY"]]
    for item in mapping:
        var sid: int = int(item[0])
        var mid: int = int(item[1])
        var missile: Dictionary = baseline.by_missile.get(str(mid), {})
        var used_tags: Array[String] = _required_tags(sid)
        for tag in ["AnimFile2", "AnimFile4"]:
            var virtual_path: String = str(missile.get(tag, ""))
            if virtual_path.is_empty():
                continue # 322's source has no AnimFile2, not an error.
            var row: Dictionary = {"faction": "THIEN_VUONG_9X",
                "weapon": str(item[2]), "skill_id": sid, "missile_id": mid,
                "part": tag, "status": "NOT_FOUND", "native_status": "NOT_FOUND",
                "virtual_path": virtual_path, "source_pak": "", "size": 0,
                "fallback_png": str(FALLBACKS.get("%d:%s" % [sid, tag], "")),
                "required_for_9x_combat": tag in used_tags,
                "source_kind": "", "source_file": "", "frames_total": 0,
                "directions": 0, "frames_per_direction": 0,
                "declared_frames": 0, "declared_directions": 0,
                "declared_interval_ticks": 0, "source_frame_mismatch": false,
                "render_frames_per_direction": 0}
            # AnimFile2 -> AnimFileInfo2, AnimFile4 -> AnimFileInfo4.
            var original_info: String = str(missile.get("AnimFileInfo%s" % tag.trim_prefix("AnimFile"), ""))
            var info_fields: PackedStringArray = original_info.split(",", false)
            if info_fields.size() == 3:
                if info_fields[0].strip_edges().is_valid_int() and info_fields[1].strip_edges().is_valid_int() and info_fields[2].strip_edges().is_valid_int():
                    row["declared_frames"] = int(info_fields[0].strip_edges())
                    row["declared_directions"] = int(info_fields[1].strip_edges())
                    row["declared_interval_ticks"] = int(info_fields[2].strip_edges())
            var loc: Dictionary = resolver.fs.locate(virtual_path)
            var decoded: Dictionary = resolver.load_spr(virtual_path)
            if not decoded.is_empty():
                var origin: Dictionary = decoded.get("source", {})
                var origin_kind: String = str(origin.get("kind", "unknown")).to_upper()
                row["native_status"] = "OK_SPR_" + origin_kind
                row["status"] = str(row["native_status"])
                row["source_kind"] = origin_kind
                row["source_file"] = str(origin.get("pak", origin.get("file", "")))
                row["source_pak"] = str(origin.get("pak", ""))
                row["size"] = int(decoded.get("byte_size", 0))
                row["directions"] = int(decoded.get("directions", 0))
                row["frames_per_direction"] = int(decoded.get("frames_per_direction", 0))
                row["frames_total"] = int(decoded.get("original_frames", 0))
                var df: int = int(row.get("declared_frames", 0))
                var dd: int = int(row.get("declared_directions", 0))
                var actual_d: int = int(decoded.get("directions", 1))
                row["source_frame_mismatch"] = df > 0 and (df != int(decoded.get("original_frames", 0)) or dd != actual_d)
                row["render_frames_per_direction"] = mini(maxi(1, int(df / maxi(1, dd))), int(decoded.get("frames_per_direction", 1))) if df > 0 and dd > 0 else int(decoded.get("frames_per_direction", 1))
            elif bool(loc.get("found", false)):
                row["native_status"] = "NATIVE_DECODE_FAILED"
                row["source_pak"] = str(loc.get("pak", ""))
                row["source_kind"] = str(loc.get("kind", "")).to_upper()
                row["source_file"] = str(loc.get("pak", loc.get("file", "")))
            else:
                row["native_status"] = str(loc.get("error", "NOT_FOUND"))
            var fallback: String = str(row["fallback_png"])
            if not str(row["status"]).begins_with("OK_SPR_"):
                if not fallback.is_empty() and FileAccess.file_exists(fallback):
                    row["status"] = "BUNDLED_9X_FALLBACK"
                elif not bool(row["required_for_9x_combat"]):
                    row["status"] = "OPTIONAL_UNUSED_FOR_MELEE"
                else:
                    row["status"] = "MISSING_REQUIRED_9X_VFX"
            records.append(row)
    var required_total: int = 0
    var required_usable: int = 0
    var native_ok: int = 0
    var pak_ok: int = 0
    var loose_ok: int = 0
    var bundled_ok: int = 0
    var fallback_ok: int = 0
    var unused_optional: int = 0
    for row in records:
        if bool(row.get("required_for_9x_combat", false)):
            required_total += 1
            if str(row["status"]).begins_with("OK_SPR_"):
                native_ok += 1
                required_usable += 1
                match str(row.get("source_kind", "")):
                    "PAK": pak_ok += 1
                    "LOOSE": loose_ok += 1
                    "BUNDLED_SPR": bundled_ok += 1
            elif str(row["status"]) == "BUNDLED_9X_FALLBACK":
                fallback_ok += 1
                required_usable += 1
        else:
            unused_optional += 1
    return {"records": records, "archives": resolver.fs.archives.size(),
        "required_total": required_total, "required_usable": required_usable,
        "native_ok": native_ok, "pak_ok": pak_ok,
        "loose_ok": loose_ok, "bundled_ok": bundled_ok,
        "fallback_ok": fallback_ok,
        "unused_optional": unused_optional,
        "vfs_warnings": resolver.fs.warnings.duplicate()}

static func save(report: Dictionary) -> String:
    var output: String = "user://JXNHALAM_V6_4_9X_ASSET_AUDIT.csv"
    var f: FileAccess = FileAccess.open(output, FileAccess.WRITE)
    if f == null:
        return "ERROR: cannot write audit"
    var headers: PackedStringArray = ["faction","weapon","skill_id","missile_id",
        "part","status","native_status","virtual_path","source_pak",
        "size","fallback_png","required_for_9x_combat",
        "source_kind","source_file","directions","frames_per_direction","frames_total",
        "declared_frames","declared_directions","declared_interval_ticks","source_frame_mismatch","render_frames_per_direction"]
    f.store_csv_line(headers)
    for record in report.get("records", []):
        var values: PackedStringArray = []
        for key in headers:
            values.append(str(record.get(key, "")))
        f.store_csv_line(values)
    f.close()
    return ProjectSettings.globalize_path(output)
