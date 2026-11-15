extends RefCounted
## Read-only virtual file system. Loose client files override packed files.
## PACK table: 32 byte header + sorted 16-byte index. UCL NRV2B support.
## Non-ASCII raw client paths use data/pak/known_hashes.json (byte-based hashes).
## NRV2B compatibility implementation is derived from the JXNHALAM GPL-2.0+
## PAK research reader; see LICENSE_PAK_READER.txt.
# XPackMethod: legacy (0x01000000 UCL / 0x02000000 BZIP2) and
# newer (0x10000000 UCL / 0x20000000 BZIP2) flags coexist.
# A frame-packed SPR may ALSO carry 0x10000000; inspect its payload.
const METHOD_UCL_OLD: int = 0x01000000
const METHOD_BZIP2_OLD: int = 0x02000000
const METHOD_UCL_NEW: int = 0x10000000
const METHOD_BZIP2_NEW: int = 0x20000000
const METHOD_FRAME: int = 0x10000000
const MAX_ENTRIES: int = 1000000
const MAX_RAW_BYTES: int = 67108864
var roots: Array[String] = []
var archives: Array[Dictionary] = []
var known_hashes: Dictionary = {}
var warnings: Array[String] = []
var cache: Dictionary = {}
var max_cache_entries: int = 16

func _ascii_lower(text: String) -> String:
    var output: String = ""
    for i in range(text.length()):
        var cp: int = text.unicode_at(i)
        if cp >= 65 and cp <= 90:
            output += String.chr(cp + 32)
        else:
            output += String.chr(cp)
    return output

func normalize_path(original: String) -> String:
    var path: String = original.replace("/", "\\")
    path = path.trim_prefix("\\")
    if path.is_empty() or path.contains(":"):
        return ""
    for part in path.split("\\", false):
        if part == ".." or part == ".":
            return ""
    return "\\" + _ascii_lower(path)

func _virtual_hash(normalized: String) -> int:
    if normalized.is_empty():
        return -1
    if known_hashes.has(normalized):
        return int(known_hashes[normalized])
    var raw: PackedByteArray = normalized.to_utf8_buffer()
    for c in raw:
        if int(c) > 127:
            # Avoid incorrectly hashing UTF-8 as legacy GBK/CP936.
            return -1
    var accumulator: int = 0
    for i in range(raw.size()):
        var b: int = int(raw[i])
        if b >= 65 and b <= 90:
            b += 32
        # 0xFFFFFFEF == -17 mod 2^32; avoid signed 64-bit overflow.
        accumulator = (-17 * ((accumulator + (i + 1) * b) % 0x8000000B)) & 0xFFFFFFFF
    return accumulator ^ 0x12345678

func path_hash(original: String) -> int:
    return _virtual_hash(normalize_path(original))

# Original JX C++ FileNameToId(char*, int) hashes 8-bit signed char on
# common MSVC builds. Other PAK tools may use unsigned bytes (/J compiler).
# Keep BOTH candidates and validate the decoded SPR magic after lookup.
# This prevents non-ASCII legacy GBK names being silently hashed only as 0..255.
func _signed_char_hash(normalized: String) -> int:
    if normalized.is_empty():
        return -1
    var accumulator: int = 0
    for i in range(normalized.length()):
        var b: int = normalized.unicode_at(i)
        # This reader intentionally preserves raw GBK as Latin-1 codepoints.
        # Do not invent a hash from UTF-8 encoded Chinese characters.
        if b > 255:
            return -1
        if b >= 128:
            b -= 256
        # C++ unsigned promotion wraps 32-bit BEFORE modulo.
        var summed: int = (accumulator + (i + 1) * b) & 0xFFFFFFFF
        accumulator = (-17 * (summed % 0x8000000B)) & 0xFFFFFFFF
    return accumulator ^ 0x12345678

func hash_candidates(path: String) -> Array[Dictionary]:
    var normalized: String = normalize_path(path)
    var out: Array[Dictionary] = []
    if normalized.is_empty():
        return out
    var signed_id: int = _signed_char_hash(normalized)
    if signed_id >= 0:
        out.append({"hash": signed_id, "hash_mode": "signed_char_cpp"})
    var old_id: int = _virtual_hash(normalized)
    if old_id >= 0 and old_id != signed_id:
        out.append({"hash": old_id, "hash_mode": "unsigned_byte_legacy"})
    return out

func configure(extra_root: String = "") -> void:
    roots.clear()
    archives.clear()
    warnings.clear()
    cache.clear()
    var possible: Array[String] = []
    if not extra_root.is_empty():
        # Accept both client root (.../JX1) and direct PAK folder (.../JX1/data).
        # Roots are scanned by root/data, so normalize the latter to its parent.
        var path_hint: String = extra_root.replace("\\", "/").trim_suffix("/")
        if path_hint.get_file().to_lower() == "data":
            possible.append(path_hint.get_base_dir())
        else:
            possible.append(path_hint)
    possible.append(OS.get_executable_path().get_base_dir())
    possible.append(ProjectSettings.globalize_path("res://"))
    for r in possible:
        var normalized_root: String = r.simplify_path()
        if not roots.has(normalized_root):
            roots.append(normalized_root)
    var hash_file: String = "res://data/pak/known_hashes.json"
    if FileAccess.file_exists(hash_file):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(hash_file))
        if parsed is Dictionary:
            known_hashes = parsed
    for root in roots:
        var data_dir: String = root.path_join("data")
        if not DirAccess.dir_exists_absolute(data_dir):
            data_dir = root.path_join("Data")
        if not DirAccess.dir_exists_absolute(data_dir):
            continue
        var names: PackedStringArray = DirAccess.get_files_at(data_dir)
        var paks: Array[String] = []
        for filename in names:
            if filename.get_extension().to_lower() == "pak":
                paks.append(filename)
        paks.sort()
        # Original KPakList::Open reads [Package] 0,1,2... and
        # KPakList::FindElemFile returns the FIRST matching archive.
        # It is not alphabetical reverse order; preserve package.ini order.
        var order: Array[String] = _read_package_order(root, data_dir)
        var accounted: Dictionary = {}
        for name in order:
            var picked: String = ""
            for candidate in paks:
                if candidate.to_lower() == name.to_lower():
                    picked = candidate
                    break
            if not picked.is_empty():
                open_pak(data_dir.path_join(picked))
                accounted[picked.to_lower()] = true
            else:
                warnings.append("package.ini missing archive: " + name)
        # Unlisted PAKs are last-choice only; exact client patch precedence
        # for unlisted archives is unspecified, never silently override.
        for name in paks:
            if not accounted.has(name.to_lower()):
                open_pak(data_dir.path_join(name))
        if order.is_empty() and paks.size() > 1:
            warnings.append("No package.ini order: sorted PAK fallback, precedence UNVERIFIED")
    if archives.is_empty():
        warnings.append("No client data/*.pak mounted. Built-in PNG atlas remains available.")

func _read_package_order(root: String, data_dir: String) -> Array[String]:
    var output: Array[String] = []
    var candidate_paths: Array[String] = [
        root.path_join("package.ini"), data_dir.path_join("package.ini"),
        root.path_join("pak1024.ini")
    ]
    for cfg in candidate_paths:
        if not FileAccess.file_exists(cfg):
            continue
        var file: FileAccess = FileAccess.open(cfg, FileAccess.READ)
        if file == null:
            continue
        var section: String = ""
        var numbered: Dictionary = {}
        while not file.eof_reached():
            var line: String = file.get_line().strip_edges()
            if line.begins_with("[") and line.ends_with("]"):
                section = line.substr(1, line.length() - 2).to_lower()
            elif section == "package" and line.contains("="):
                var pieces: PackedStringArray = line.split("=", true, 1)
                var key: String = pieces[0].strip_edges()
                var value: String = pieces[1].strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
                if key.is_valid_int() and int(key) >= 0:
                    # No arbitrary file paths from package.ini; only named PAKs
                    # inside the chosen client's data folder.
                    var filename: String = value.get_file()
                    if filename.to_lower().ends_with(".pak") and not filename.contains(":"):
                        numbered[int(key)] = filename
        file.close()
        if not numbered.is_empty():
            var ids: Array = numbered.keys()
            ids.sort()
            for key in ids:
                output.append(str(numbered[key]))
            return output
    return output

func open_pak(path: String) -> bool:
    var f: FileAccess = FileAccess.open(path, FileAccess.READ)
    if f == null:
        warnings.append("Cannot open PAK: " + path)
        return false
    var length: int = f.get_length()
    if length < 32:
        f.close()
        warnings.append("Short PAK: " + path)
        return false
    var signature: String = f.get_buffer(4).get_string_from_ascii()
    var count: int = f.get_32()
    var index_at: int = f.get_32()
    var data_at: int = f.get_32()
    f.close()
    if signature != "PACK" or count < 0 or count > MAX_ENTRIES or index_at < 32 or index_at + count * 16 > length:
        warnings.append("Unsupported PAK index: " + path)
        return false
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    file.seek(index_at)
    var content: PackedByteArray = file.get_buffer(count * 16)
    file.close()
    if content.size() != count * 16:
        warnings.append("Truncated PAK index: " + path)
        return false
    var entries: Dictionary = {}
    for i in range(count):
        var at: int = i * 16
        var hash_id: int = content.decode_u32(at)
        var data_offset: int = content.decode_u32(at + 4)
        var raw_size: int = content.decode_u32(at + 8)
        var info: int = content.decode_u32(at + 12)
        entries[hash_id] = [data_offset, raw_size, info]
    archives.append({"path": path, "entries": entries, "size": length, "count": count, "data_at": data_at})
    return true

func _loose_path(normalized: String) -> String:
    var rel: String = normalized.trim_prefix("\\").replace("\\", "/")
    for root in roots:
        for location in [root, root.path_join("data"), root.path_join("Data")]:
            var full: String = location.path_join(rel)
            if FileAccess.file_exists(full):
                return full
    return ""

# Return every matching PAK entry, respecting package.ini precedence.
# On a duplicate hash across incompatible client builds, the SPR decoder can
# try the next candidate instead of caching an unrelated byte stream.
func locate_candidates(path: String) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    var clean: String = normalize_path(path)
    if clean.is_empty():
        return results
    var loose: String = _loose_path(clean)
    if not loose.is_empty():
        results.append({"found": true, "kind": "loose", "file": loose,
            "path": clean, "hash_mode": "loose_file"})
    var candidates: Array[Dictionary] = hash_candidates(clean)
    for archive_index in range(archives.size()):
        var archive: Dictionary = archives[archive_index]
        for candidate in candidates:
            var hash_id: int = int(candidate["hash"])
            if archive["entries"].has(hash_id):
                results.append({"found": true, "kind": "pak", "archive_index": archive_index,
                    "hash": hash_id, "hash_mode": str(candidate["hash_mode"]),
                    "path": clean, "pak": archive["path"]})
    return results

func locate(path: String) -> Dictionary:
    var clean: String = normalize_path(path)
    if clean.is_empty():
        return {"found": false, "error": "INVALID_PATH"}
    var hits: Array[Dictionary] = locate_candidates(clean)
    if not hits.is_empty():
        return hits[0]
    var candidates: Array[Dictionary] = hash_candidates(clean)
    if candidates.is_empty():
        return {"found": false, "error": "NON_ASCII_HASH_NOT_REGISTERED", "path": clean}
    return {"found": false, "error": "NOT_FOUND", "hash": int(candidates[0]["hash"]),
        "path": clean, "hash_candidates": candidates}

func _next_bit(src: PackedByteArray, state: Dictionary) -> int:
    var bits: int = int(state["bits"])
    var position: int = int(state["pos"])
    if (bits & 0x7F) != 0:
        bits *= 2
    else:
        if position >= src.size():
            return -1
        bits = 2 * int(src[position]) + 1
        position += 1
    state["bits"] = bits
    state["pos"] = position
    return (bits >> 8) & 1

func _decode_ucl(src: PackedByteArray, raw_size: int) -> PackedByteArray:
    var output: PackedByteArray = PackedByteArray()
    var state: Dictionary = {"pos": 0, "bits": 0}
    var last_offset: int = 1
    var limit: int = maxi(1024, 2 * raw_size + 100)
    for _step in range(limit):
        var first: int = _next_bit(src, state)
        if first < 0:
            return PackedByteArray()
        while first == 1:
            var position: int = int(state["pos"])
            if position >= src.size() or output.size() >= raw_size:
                return PackedByteArray()
            output.append(src[position])
            state["pos"] = position + 1
            first = _next_bit(src, state)
            if first < 0:
                return PackedByteArray()
        var offset: int = 1
        var finished: bool = false
        for _i in range(100):
            var b: int = _next_bit(src, state)
            var stop: int = _next_bit(src, state)
            if b < 0 or stop < 0:
                return PackedByteArray()
            offset = 2 * offset + b
            if stop == 1:
                finished = true
                break
        if not finished:
            return PackedByteArray()
        if offset == 2:
            offset = last_offset
        else:
            var p: int = int(state["pos"])
            if p >= src.size():
                return PackedByteArray()
            offset = (offset - 3) * 256 + int(src[p])
            state["pos"] = p + 1
            if offset == 0xFFFFFFFF:
                return output if output.size() == raw_size else PackedByteArray()
            last_offset = offset + 1
            offset = last_offset
        var c: int = _next_bit(src, state)
        var d: int = _next_bit(src, state)
        if c < 0 or d < 0:
            return PackedByteArray()
        var length: int = 2 * c + d
        if length == 0:
            length = 1
            finished = false
            for _j in range(100):
                var b2: int = _next_bit(src, state)
                var stop2: int = _next_bit(src, state)
                if b2 < 0 or stop2 < 0:
                    return PackedByteArray()
                length = 2 * length + b2
                if stop2 == 1:
                    finished = true
                    break
            if not finished:
                return PackedByteArray()
            length += 2
        if offset > 0xD00:
            length += 1
        if offset <= 0 or offset > output.size() or output.size() + length + 1 > raw_size:
            return PackedByteArray()
        for _repeat in range(length + 1):
            output.append(output[output.size() - offset])
    return PackedByteArray()

func _decode_frame_packed_spr(payload: PackedByteArray, codec_method: int) -> PackedByteArray:
    # Original XPackFile::GetSprHeader and GetSprFrame:
    # SPRHEAD[32] + palette[Colors * 3] + XPackSprFrameInfo[Frames * 8]
    # + concatenated frame payloads. Negative lSize means a raw frame.
    # Convert frame-packed SPR into standard SPR + SPROFFS table and frames.
    if payload.size() < 32 or payload[0] != 83 or payload[1] != 80 or payload[2] != 82 or payload[3] != 0:
        return PackedByteArray()
    var count: int = payload.decode_u16(12)
    var colors: int = payload.decode_u16(14)
    if count < 1 or count > 512 or colors < 1 or colors > 256:
        return PackedByteArray()
    var header_size: int = 32 + colors * 3
    var info_size: int = count * 8
    var source_start: int = header_size + info_size
    if source_start > payload.size():
        return PackedByteArray()
    var decoded_frames: Array[PackedByteArray] = []
    var position: int = source_start
    var total: int = 0
    for i in range(count):
        var at: int = header_size + i * 8
        var stored_len: int = int(payload.decode_u32(at))
        var frame_len: int = int(payload.decode_s32(at + 4))
        if stored_len < 1 or stored_len > MAX_RAW_BYTES or position + stored_len > payload.size():
            return PackedByteArray()
        var frame_blob: PackedByteArray = payload.slice(position, position + stored_len)
        position += stored_len
        var unpacked: PackedByteArray = PackedByteArray()
        if frame_len < 0:
            if -frame_len != stored_len:
                return PackedByteArray()
            unpacked = frame_blob
        elif codec_method == METHOD_UCL_NEW or codec_method == METHOD_UCL_OLD:
            if frame_len < 8 or frame_len > MAX_RAW_BYTES:
                return PackedByteArray()
            unpacked = _decode_ucl(frame_blob, frame_len)
        elif codec_method == 0 and frame_len == stored_len:
            unpacked = frame_blob
        else:
            return PackedByteArray()
        if unpacked.size() < 8 or total + unpacked.size() > MAX_RAW_BYTES:
            return PackedByteArray()
        total += unpacked.size()
        decoded_frames.append(unpacked)
    var result: PackedByteArray = payload.slice(0, header_size)
    var source_offset: int = 0
    for frame in decoded_frames:
        var offset_bytes: PackedByteArray = PackedByteArray()
        offset_bytes.resize(8)
        offset_bytes.encode_u32(0, source_offset)
        offset_bytes.encode_u32(4, frame.size())
        result.append_array(offset_bytes)
        source_offset += frame.size()
    for frame in decoded_frames:
        result.append_array(frame)
    return result

func _extract(archive: Dictionary, hash_id: int) -> PackedByteArray:
    var entry: Array = archive["entries"].get(hash_id, [])
    if entry.is_empty():
        return PackedByteArray()
    var at: int = int(entry[0])
    var raw_size: int = int(entry[1])
    var info: int = int(entry[2])
    # XPackFile: new method uses top nibble, legacy uses old high byte.
    # Previously 0x10000000 was always interpreted as a frame-packed SPR,
    # which breaks ordinary UCL payloads (the most important JX mobile case).
    var new_method: int = info & 0xF0000000
    var old_method: int = info & 0x0F000000
    var method: int = new_method if new_method != 0 else old_method
    var packed_size: int = info & 0x07FFFFFF if new_method != 0 else info & 0x00FFFFFF
    if at < 0 or raw_size > MAX_RAW_BYTES or (raw_size < 1 and method != METHOD_FRAME) or packed_size < 1 or at + packed_size > int(archive["size"]):
        warnings.append("Entry too large/out of range: %08X" % hash_id)
        return PackedByteArray()
    var f: FileAccess = FileAccess.open(str(archive["path"]), FileAccess.READ)
    if f == null:
        return PackedByteArray()
    f.seek(at)
    var content: PackedByteArray = f.get_buffer(packed_size)
    f.close()
    if content.size() != packed_size:
        return PackedByteArray()
    var result: PackedByteArray = PackedByteArray()
    if method == 0:
        result = content
    elif method == METHOD_UCL_OLD or method == METHOD_UCL_NEW:
        # Frame-packed SPR has plaintext SPR\0 header and a frame table;
        # ordinary UCL does NOT. Try frame assembly only if header matches.
        if method == METHOD_UCL_NEW and content.size() >= 4 and content[0] == 83 and content[1] == 80 and content[2] == 82 and content[3] == 0:
            result = _decode_frame_packed_spr(content, METHOD_UCL_NEW)
            if not result.is_empty():
                return result
            if packed_size == raw_size:
                # Some client packages flag an already assembled SPR as UCL.
                # Accept it only when the payload is byte-for-byte raw sized.
                return content
        result = _decode_ucl(content, raw_size)
    elif method == METHOD_BZIP2_OLD or method == METHOD_BZIP2_NEW:
        warnings.append("BZIP2 PAK entry needs offline export: %08X" % hash_id)
        return PackedByteArray()
    else:
        warnings.append("Unsupported PAK compression %08X for hash %08X" % [method, hash_id])
        return PackedByteArray()
    if result.size() != raw_size:
        warnings.append("Decoded length mismatch for hash: %08X" % hash_id)
        return PackedByteArray()
    return result

func read_location(found: Dictionary) -> PackedByteArray:
    if not bool(found.get("found", false)):
        return PackedByteArray()
    var key: String = str(found.get("file", "")) if str(found.get("kind", "")) == "loose" else "%d:%08X" % [int(found.get("archive_index", -1)), int(found.get("hash", 0))]
    if cache.has(key):
        return cache[key]
    var result: PackedByteArray = PackedByteArray()
    if str(found.get("kind", "")) == "loose":
        result = FileAccess.get_file_as_bytes(str(found["file"]))
    else:
        result = _extract(archives[int(found["archive_index"])], int(found["hash"]))
    if not result.is_empty():
        if cache.size() >= max_cache_entries:
            cache.clear()
        cache[key] = result
    return result

func read_bytes(path: String) -> PackedByteArray:
    for location in locate_candidates(path):
        var candidate: PackedByteArray = read_location(location)
        if not candidate.is_empty():
            return candidate
    return PackedByteArray()

func describe() -> String:
    var count: int = 0
    for pak in archives:
        count += int(pak["count"])
    return "PAK mounted: %d | index entries: %d | client roots: %d | warnings: %d" % [archives.size(), count, roots.size(), warnings.size()]

func file_probe(path: String) -> Dictionary:
    var normalized: String = normalize_path(path)
    var candidates: Array[Dictionary] = hash_candidates(normalized)
    var hits: Array[Dictionary] = locate_candidates(path)
    var found: Dictionary = hits[0] if not hits.is_empty() else {}
    var first_hash: int = int(candidates[0]["hash"]) if not candidates.is_empty() else -1
    var data: Dictionary = {"path": normalized,
        "hash": int(found.get("hash", first_hash)),
        "hash_mode": str(found.get("hash_mode", "NONE")),
        "hash_candidates": candidates, "matched_candidates": hits.size(),
        "found": not hits.is_empty(), "error": "" if not hits.is_empty() else "NOT_FOUND",
        "pack_count": archives.size(),
        "source": str(found.get("pak", found.get("file", ""))), "compression": ""}
    if not hits.is_empty() and str(found.get("kind", "")) == "pak":
        var archive: Dictionary = archives[int(found["archive_index"])]
        var entry: Array = archive["entries"].get(int(found["hash"]), [])
        if entry.size() == 3:
            var flags: int = int(entry[2])
            var new_method: int = flags & 0xF0000000
            var old_method: int = flags & 0x0F000000
            var method: int = new_method if new_method != 0 else old_method
            data["compression"] = "%08X" % method
            data["compressed_bytes"] = flags & 0x07FFFFFF if new_method != 0 else flags & 0x00FFFFFF
            data["unpacked_bytes"] = int(entry[1])
    return data
