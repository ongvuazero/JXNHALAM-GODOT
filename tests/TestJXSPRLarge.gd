extends SceneTree
## Test a synthetic 1080-frame raw JX SPR without needing a client PAK.
const CODEC = preload("res://scripts/JXSPRCodec.gd")

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var raw: PackedByteArray = _make_spr(1080)
    var codec: RefCounted = CODEC.new()
    var decoded: Dictionary = codec.call("decode_atlas", raw)
    if decoded.is_empty() or not bool(decoded.get("lazy_frames", false)):
        printerr("V44.6 FAIL: 1080-frame SPR not accepted as lazy source")
        quit(1)
        return
    if int(decoded.get("frames_per_direction", 0)) != 1080:
        printerr("V44.6 FAIL: source frame count changed")
        quit(1)
        return
    var first: Texture2D = codec.call("get_lazy_frame", decoded, 0, 0)
    var last: Texture2D = codec.call("get_lazy_frame", decoded, 1079, 0)
    if first == null or last == null:
        printerr("V44.6 FAIL: first/last frame unavailable")
        quit(1)
        return
    var image: Image = last.get_image()
    var green: Color = image.get_pixel(0, 0)
    if green.g < 0.9 or green.r > 0.1 or green.a < 0.9:
        printerr("V44.6 FAIL: palette/offset decode mismatch: " + str(green))
        quit(1)
        return
    var short: Dictionary = codec.call("decode_atlas", _make_spr(8))
    if short.is_empty() or bool(short.get("lazy_frames", false)):
        printerr("V44.6 FAIL: legacy atlas regression")
        quit(1)
        return
    print("V44.6 PASS: 1080-frame SPR lazy first/last, palette, legacy 8-frame atlas")
    quit(0)

func _make_spr(frames: int) -> PackedByteArray:
    var colors: int = 2
    var table_at: int = 32 + colors * 3
    var data_at: int = table_at + frames * 8
    var frame_bytes: int = 11  # 8-byte frame header + (run=1, alpha=255, palette=1)
    var raw: PackedByteArray = PackedByteArray()
    raw.resize(data_at + frames * frame_bytes)
    raw[0] = 83
    raw[1] = 80
    raw[2] = 82
    raw[3] = 0
    raw.encode_u16(4, 1)
    raw.encode_u16(6, 1)
    raw.encode_u16(12, frames)
    raw.encode_u16(14, colors)
    raw.encode_u16(16, 1)
    raw.encode_u16(18, 1)
    raw[35] = 0
    raw[36] = 255
    raw[37] = 0
    for i in range(frames):
        var record_at: int = table_at + i * 8
        var payload_at: int = data_at + i * frame_bytes
        raw.encode_u32(record_at, i * frame_bytes)
        raw.encode_u32(record_at + 4, frame_bytes)
        raw.encode_u16(payload_at, 1)
        raw.encode_u16(payload_at + 2, 1)
        raw.encode_s16(payload_at + 4, 0)
        raw.encode_s16(payload_at + 6, 0)
        raw[payload_at + 8] = 1
        raw[payload_at + 9] = 255
        raw[payload_at + 10] = 1
    return raw
