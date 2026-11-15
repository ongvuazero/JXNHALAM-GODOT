extends RefCounted
const PAK_FS = preload("res://scripts/JXVirtualFS.gd")
const SPR_CODEC = preload("res://scripts/JXSPRCodec.gd")
var fs
var codec
var sprite_cache: Dictionary = {}
var attempted: Dictionary = {}
var failures: Dictionary = {}
var last_client_root: String = ""
var original_spr_preferred: bool = true

func setup(root: String = "") -> void:
    last_client_root = root
    sprite_cache.clear()
    attempted.clear()
    failures.clear()
    fs = PAK_FS.new()
    fs.configure(root)
    codec = SPR_CODEC.new()

# Original JX SPR bytes shipped in V6.4/source_spr, originally extracted
# from user-provided ClientData.zip. Numeric keys come from the source-path
# GBK byte hash registry, NOT from UTF-8 filename conversion.
# Priority: client loose SPR -> client PAK SPR -> bundled original SPR ->
# (handled by SkillEffect) pre-rendered PNG atlas.
const BUNDLED_9X_SPR_BY_HASH: Dictionary = {
    2446487682: "res://assets/skill90/source_spr/jx90_potian_impact.spr",
    2667851309: "res://assets/skill90/source_spr/jx90_truytinh_impact.spr",
    3147144842: "res://assets/skill90/source_spr/jx90_truyphong_sweep.spr",
    1313618360: "res://assets/skill90/source_spr/jx90_truyphong_impact.spr"
}

func load_spr(virtual_path: String) -> Dictionary:
    if not original_spr_preferred or virtual_path.is_empty() or fs == null:
        return {}
    var normalized: String = fs.normalize_path(virtual_path)
    if normalized.is_empty():
        return {}
    if sprite_cache.has(normalized):
        return sprite_cache[normalized]
    if attempted.has(normalized):
        return {}
    attempted[normalized] = true
    # Each byte-hash candidate is decoded independently; do not assume an
    # index hit is a valid SPR, or confuse signed/unsigned GBK path hashes.
    var candidates: Array[Dictionary] = fs.locate_candidates(virtual_path)
    var client_loc: Dictionary = fs.locate(virtual_path)
    for location in candidates:
        var bytes: PackedByteArray = fs.read_location(location)
        if bytes.is_empty():
            continue
        var client_image: Dictionary = codec.decode_atlas(bytes)
        if client_image.is_empty():
            continue
        client_image["source"] = location
        client_image["byte_size"] = bytes.size()
        sprite_cache[normalized] = client_image
        return client_image
    # This is still original SPR source, not a PNG or a PAK entry.
    # Missing optional AnimFile2 is deliberately not mapped.
    var hash_id: int = fs.path_hash(virtual_path)
    var bundled_path: String = str(BUNDLED_9X_SPR_BY_HASH.get(hash_id, ""))
    if not bundled_path.is_empty() and FileAccess.file_exists(bundled_path):
        var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(bundled_path)
        var source_image: Dictionary = codec.decode_atlas(source_bytes)
        if not source_image.is_empty():
            source_image["source"] = {
                "found": true, "kind": "bundled_spr", "file": bundled_path,
                "path": normalized, "hash": hash_id
            }
            source_image["byte_size"] = source_bytes.size()
            source_image["client_lookup"] = client_loc
            sprite_cache[normalized] = source_image
            return source_image
    failures[normalized] = "NOT_IN_PAK" if candidates.is_empty() else "PAK_ENTRY_DECODE_FAILED"
    return {}

func draw_source_frame(sprite: Sprite2D, data: Dictionary, frame: int, direction: int) -> bool:
    if not bool(data.get("lazy_frames", false)):
        return false
    if sprite == null or codec == null:
        return true
    var tex: Texture2D = codec.get_lazy_frame(data, frame, direction)
    if tex == null:
        sprite.visible = false
        return true
    sprite.texture = tex
    sprite.region_enabled = false
    return true

func probe_spr(path: String) -> Dictionary:
    if fs == null or codec == null:
        return {"status": "NO_READER", "path": path}
    var probe: Dictionary = fs.file_probe(path)
    var decoded: Dictionary = load_spr(path)
    if not decoded.is_empty():
        var src: Dictionary = decoded.get("source", {})
        probe["status"] = "OK_SPR_" + str(src.get("kind", "?"))
        probe["frames"] = int(decoded.get("original_frames", 0))
        probe["decoder_mode"] = str(decoded.get("codec", ""))
        probe["directions"] = int(decoded.get("directions", 0))
        probe["hash_mode"] = str(src.get("hash_mode", probe.get("hash_mode", "")))
        probe["hash"] = int(src.get("hash", probe.get("hash", -1)))
        probe["source"] = str(src.get("pak", src.get("file", "")))
    elif int(probe.get("pack_count", 0)) == 0:
        probe["status"] = "NO_CLIENT_PAK"
    elif bool(probe.get("found", false)):
        probe["status"] = "PAK_ENTRY_DECODE_FAILED"
    elif int(probe.get("hash", -1)) < 0:
        probe["status"] = "NON_ASCII_HASH_MISSING"
    else:
        probe["status"] = "SPR_NOT_IN_PAK"
    return probe

func status() -> String:
    if fs == null:
        return "PakFS unavailable"
    return fs.describe() + " | decoded SPR: %d | missing: %d" % [sprite_cache.size(), failures.size()]
