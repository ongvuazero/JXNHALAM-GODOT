extends RefCounted
## V27: read-only original client PAK/loose SPR extractor for six AT03 layers.
## Uses the existing JXVirtualFS.gd hash/package.ini/UCL/frame-packed implementation.
## Writes ONLY verified, previously missing SPR to the project's audit folder.
## Does NOT patch or modify the user's original JX client or gameplay.
const VFS = preload("res://scripts/JXVirtualFS.gd")
const PROFILES: String = "res://data/renderer_audit/blade_004_action_profiles.json"
const OUTPUT: String = "res://data/spr/npcres/man/"
const REPORT: String = "res://data/renderer_audit/V27_AT03_EXTRACTION_REPORT.txt"
const MAX_SPR_BYTES: int = 32 * 1024 * 1024

func _validate_raw_spr(raw: PackedByteArray, expected_per_dir: int) -> String:
    if raw.size() < 48 or raw.size() > MAX_SPR_BYTES:
        return "SPR_TOO_SMALL_OR_LARGE"
    if raw[0] != 83 or raw[1] != 80 or raw[2] != 82 or raw[3] != 0:
        return "NOT_SPR_SIGNATURE"
    var width: int = raw.decode_u16(4)
    var height: int = raw.decode_u16(6)
    var frames: int = raw.decode_u16(12)
    var colors: int = raw.decode_u16(14)
    var directions: int = raw.decode_u16(16)
    if width < 1 or height < 1 or width > 1024 or height > 1024:
        return "SPR_CANVAS_OUT_OF_RANGE"
    if colors < 1 or colors > 256 or directions != 8:
        return "SPR_BAD_PALETTE_OR_DIRECTIONS"
    # A known JX extra transparent frame may follow the 8*14 valid frames.
    # Never silently discard a genuine extra frame.
    var proper_count: int = expected_per_dir * directions
    if frames != proper_count and frames != proper_count + 1:
        return "SPR_UNEXPECTED_FRAME_COUNT_%d_EXPECTED_%d" % [frames, proper_count]
    var table: int = 32 + colors * 3
    var pixels_at: int = table + frames * 8
    if pixels_at > raw.size():
        return "SPR_FRAME_TABLE_TRUNCATED"
    for i in range(frames):
        var at: int = table + i * 8
        var offset: int = raw.decode_u32(at)
        var length: int = raw.decode_u32(at + 4)
        var frame_at: int = pixels_at + offset
        if frame_at + length > raw.size():
            frame_at = offset # alternate absolute-offset variant used by JXSPRCodec
        if length < 8 or frame_at < pixels_at or frame_at + length > raw.size():
            return "SPR_FRAME_PAYLOAD_BAD_%d" % i
        var frame_w: int = raw.decode_u16(frame_at)
        var frame_h: int = raw.decode_u16(frame_at + 2)
        if frame_w < 1 or frame_h < 1 or frame_w > width or frame_h > height:
            return "SPR_FRAME_SIZE_BAD_%d" % i
    if frames == proper_count + 1:
        var last_at: int = table + proper_count * 8
        var last_offset: int = raw.decode_u32(last_at)
        var last_size: int = raw.decode_u32(last_at + 4)
        var last_start: int = pixels_at + last_offset
        if last_start + last_size > raw.size():
            last_start = last_offset
        if last_size != 10 or raw.decode_u16(last_start) != 1 or raw.decode_u16(last_start + 2) != 1:
            return "EXTRA_FRAME_NOT_KNOWN_SENTINEL"
    return "OK"

func extract(client_root: String) -> Dictionary:
    var summary: Dictionary = {"found": 0, "existing": 0, "missing": 0, "invalid": 0, "written": 0, "errors": [], "details": []}
    var location: String = client_root.strip_edges().replace("\\", "/")
    if location.is_empty():
        summary["errors"].append("EMPTY_CLIENT_DIRECTORY")
        return summary
    var root: String = location.simplify_path()
    if root.is_empty() or not DirAccess.dir_exists_absolute(root):
        summary["errors"].append("CLIENT_FOLDER_INVALID: " + location)
        return summary
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES))
    if not parsed is Dictionary:
        summary["errors"].append("PROFILES_JSON_INVALID")
        return summary
    var actions: Array = parsed.get("actions", [])
    var action: Dictionary = {}
    for entry in actions:
        if str(entry.get("id", "")) == "AT03":
            action = entry
            break
    if action.is_empty():
        summary["errors"].append("AT03_ACTION_NOT_IN_PROFILES")
        return summary
    var expected: int = int(action.get("frames_per_dir", 0))
    if expected != 14:
        summary["errors"].append("AT03_EXPECTED_FRAME_COUNT_WRONG")
        return summary
    # The picker may point at the game root OR at its `data` directory.
    # Convert a selected data folder to the parent so package.ini is found.
    if root.get_file().to_lower() == "data":
        var has_pak: bool = false
        for filename in DirAccess.get_files_at(root):
            if filename.get_extension().to_lower() == "pak":
                has_pak = true
                break
        if has_pak:
            root = root.get_base_dir()
    var fs = VFS.new()
    fs.configure(root)
    summary["archives"] = fs.archives.size()
    summary["file_index_summary"] = fs.describe()
    summary["pak_warnings"] = fs.warnings.duplicate()

    var dir_path: String = ProjectSettings.globalize_path(OUTPUT)
    var dir_err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
    if dir_err != OK:
        summary["errors"].append("CANNOT_CREATE_AUDIT_OUTPUT_DIR (%d)" % dir_err)
        return summary
    for layer in action.get("layers", []):
        var name: String = str(layer.get("source_spr", ""))
        if name.is_empty() or name.get_file() != name or not name.to_lower().ends_with("_at03.spr"):
            summary["invalid"] = int(summary["invalid"]) + 1
            summary["details"].append("INVALID_PROFILE_FILENAME: " + name)
            continue
        var virtual_path: String = "\\spr\\npcres\\man\\" + name
        var dest: String = OUTPUT + name
        if FileAccess.file_exists(dest):
            var existing: PackedByteArray = FileAccess.get_file_as_bytes(dest)
            var checked: String = _validate_raw_spr(existing, expected)
            if checked == "OK":
                summary["existing"] = int(summary["existing"]) + 1
                summary["details"].append("EXISTING_VALID: " + name + " (khong ghi de)")
            else:
                summary["invalid"] = int(summary["invalid"]) + 1
                summary["details"].append("EXISTING_INVALID: " + name + " / " + checked + " (khong ghi de)")
            continue
        var info: Dictionary = fs.locate(virtual_path)
        if not bool(info.get("found", false)):
            summary["missing"] = int(summary["missing"]) + 1
            summary["details"].append("NOT_FOUND: " + name + "  hash=" + str(info.get("hash", "?")))
            continue
        var bytes: PackedByteArray = fs.read_bytes(virtual_path)
        var verdict: String = _validate_raw_spr(bytes, expected)
        if verdict != "OK":
            summary["invalid"] = int(summary["invalid"]) + 1
            summary["details"].append("BAD_PAYLOAD: " + name + " " + verdict + " / " + str(info.get("pak", info.get("file", ""))))
            continue
        summary["found"] = int(summary["found"]) + 1
        # Never overwrite an original on disk. Source files are copied, not moved.
        var out: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
        if out == null:
            summary["errors"].append("WRITE_FAILED: " + dest)
            continue
        out.store_buffer(bytes)
        out.close()
        summary["written"] = int(summary["written"]) + 1
        var digest: HashingContext = HashingContext.new()
        digest.start(HashingContext.HASH_SHA256)
        digest.update(bytes)
        var sha: String = digest.finish().hex_encode()
        summary["details"].append("EXTRACTED: %s / %d bytes / SHA256=%s / from=%s" % [name, bytes.size(), sha, str(info.get("pak", info.get("file", "")))])
    summary["result"] = "AT03: %d new, %d existing, %d missing, %d invalid; %d PAK indexes" % [int(summary["written"]), int(summary["existing"]), int(summary["missing"]), int(summary["invalid"]), fs.archives.size()]
    summary["client_root"] = root
    var lines: PackedStringArray = ["JXNHALAM V27 AT03 SOURCE-SPR AUDIT", str(summary["result"]), "client_root=" + root, "", "DETAIL:"]
    for msg in summary["details"]:
        lines.append(str(msg))
    for warning in fs.warnings:
        lines.append("PAK_WARNING: " + str(warning))
    for error in summary["errors"]:
        lines.append("ERROR: " + str(error))
    var report: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
    if report != null:
        report.store_string("\n".join(lines) + "\n")
        report.close()
    return summary
