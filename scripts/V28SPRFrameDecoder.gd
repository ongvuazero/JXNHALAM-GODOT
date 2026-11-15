extends RefCounted
## V28 one-frame decoder. Reads only requested original frame, not 112x320 atlas
## per layer. Matches the same palette/RLE method in JXSPRCodec.gd.
## Note: bytes extracted from client are unchanged; decoding is read-only.
const MAX_FILE_BYTES: int = 32 * 1024 * 1024
const MAX_DIM: int = 1024

func open_source(path: String, expected_frames: int = 112) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"error": "MISSING_SOURCE", "path": path}
    var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
    if raw.size() < 48 or raw.size() > MAX_FILE_BYTES:
        return {"error": "BAD_FILE_SIZE"}
    if raw[0] != 83 or raw[1] != 80 or raw[2] != 82 or raw[3] != 0:
        return {"error": "NOT_SPR"}
    var w: int = raw.decode_u16(4)
    var h: int = raw.decode_u16(6)
    var n: int = raw.decode_u16(12)
    var colors: int = raw.decode_u16(14)
    var directions: int = raw.decode_u16(16)
    if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM or colors < 1 or colors > 256:
        return {"error": "INVALID_HEADER"}
    if directions != 8 or (n != expected_frames and n != expected_frames + 1):
        return {"error": "UNEXPECTED_DIRECTIONS_OR_COUNT"}
    var table_at: int = 32 + colors * 3
    var payload_at: int = table_at + n * 8
    if payload_at > raw.size():
        return {"error": "TRUNCATED_TABLE"}
    return {"raw": raw, "width": w, "height": h, "frames": n, "colors": colors,
        "directions": directions, "table_at": table_at, "payload_at": payload_at}

func frame_image(source: Dictionary, index: int) -> Dictionary:
    if source.has("error") or source.is_empty():
        return {"error": "INVALID_SOURCE"}
    var raw: PackedByteArray = source["raw"]
    var table_at: int = int(source["table_at"])
    var data_at: int = int(source["payload_at"])
    if index < 0 or index >= int(source["frames"]):
        return {"error": "OUT_OF_FRAME_RANGE"}
    var entry: int = table_at + index * 8
    var off: int = raw.decode_u32(entry)
    var length: int = raw.decode_u32(entry + 4)
    var at: int = data_at + off
    if at + length > raw.size():
        at = off
    if length < 8 or at < data_at or at + length > raw.size():
        return {"error": "BAD_FRAME_RANGE"}
    var fw: int = raw.decode_u16(at)
    var fh: int = raw.decode_u16(at + 2)
    var ox: int = raw.decode_s16(at + 4)
    var oy: int = raw.decode_s16(at + 6)
    var w: int = int(source["width"])
    var h: int = int(source["height"])
    if fw <= 0 or fh <= 0 or fw > MAX_DIM or fh > MAX_DIM or fw * fh > 1048576:
        return {"error": "BAD_FRAME_DIMENSIONS"}
    var pixels: PackedByteArray = PackedByteArray()
    pixels.resize(fw * fh * 4)
    var read_at: int = at + 8
    var end_at: int = at + length
    var pixel_index: int = 0
    while pixel_index < fw * fh and read_at + 1 < end_at:
        var count: int = int(raw[read_at])
        var alpha: int = int(raw[read_at + 1])
        read_at += 2
        if count == 0:
            continue
        if pixel_index + count > fw * fh:
            return {"error": "BAD_RUN_LENGTH"}
        if alpha != 0:
            if read_at + count > end_at:
                return {"error": "TRUNCATED_PALETTE_INDICES"}
            for j in range(count):
                var idx: int = int(raw[read_at + j])
                if idx >= int(source["colors"]):
                    return {"error": "INVALID_PALETTE_INDEX"}
                var pi: int = (pixel_index + j) * 4
                var pal: int = 32 + idx * 3
                pixels[pi] = raw[pal]
                pixels[pi + 1] = raw[pal + 1]
                pixels[pi + 2] = raw[pal + 2]
                pixels[pi + 3] = alpha
            read_at += count
        pixel_index += count
    if pixel_index != fw * fh:
        return {"error": "INCOMPLETE_PIXELS"}
    var frame: Image = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, pixels)
    var canvas: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
    canvas.fill(Color.TRANSPARENT)
    # preserve original frame's source-space placement (SPR header ox/oy)
    canvas.blit_rect(frame, Rect2i(0,0,fw,fh), Vector2i(ox,oy))
    return {"image": canvas, "texture": ImageTexture.create_from_image(canvas),
        "offset": [ox,oy,fw,fh], "canvas": [w,h]}
