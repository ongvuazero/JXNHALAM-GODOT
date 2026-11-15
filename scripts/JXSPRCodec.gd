extends RefCounted
## SPR\0 indexed palette decoder for reassembled raw and frame-packed SPR.
## Sprite sheets are cached in-memory. The original per-frame (ox,oy) stays
## relative to the original SPR canvas, not an inferred center.
const MAX_FRAMES: int = 512
const MAX_LAZY_FRAMES: int = 4096
const MAX_LAZY_TEXTURES: int = 48
var _lazy_cache: Dictionary = {}
var _lazy_cache_order: Array[String] = []
const MAX_CANVAS: int = 1024
const MAX_TEXTURE_SIDE: int = 8192

func decode_atlas(raw: PackedByteArray, tile_size: int = 0) -> Dictionary:
    if raw.size() < 40 or not (raw[0] == 83 and raw[1] == 80 and raw[2] == 82 and raw[3] == 0):
        return {}
    var width: int = raw.decode_u16(4)
    var height: int = raw.decode_u16(6)
    var frames: int = raw.decode_u16(12)
    var colors: int = raw.decode_u16(14)
    var directions: int = raw.decode_u16(16)
    var interval: int = raw.decode_u16(18)
    if width < 1 or height < 1 or width > MAX_CANVAS or height > MAX_CANVAS:
        return {}
    if frames < 1 or frames > MAX_LAZY_FRAMES or colors < 1 or colors > 256 or directions < 1 or directions > 32:
        return {}
    # Some JX assets contain 16 directional frames plus a 17th transparent
    # 1x1 placeholder. Keep all source offsets anchored to the ORIGINAL
    # table (17 entries) and ignore only a rigorously validated placeholder.
    # Never discard an actual animation frame to make division succeed.
    var table_at: int = 32 + colors * 3
    var data_at: int = table_at + frames * 8
    if data_at > raw.size():
        return {}
    var frame_count: int = frames
    var trailing_padding: int = 0
    if frames % directions != 0:
        if frames % directions != 1:
            return {}
        var last_info: int = table_at + (frames - 1) * 8
        var last_offset: int = raw.decode_u32(last_info)
        var last_size: int = raw.decode_u32(last_info + 4)
        var last_start: int = data_at + last_offset
        if last_start + last_size > raw.size():
            last_start = last_offset
        if last_size != 10 or last_start < data_at or last_start + last_size > raw.size():
            return {}
        if raw.decode_u16(last_start) != 1 or raw.decode_u16(last_start + 2) != 1:
            return {}
        if raw[last_start + 8] != 1 or raw[last_start + 9] != 0:
            return {}
        frame_count -= 1
        trailing_padding = 1
    if tile_size <= 0:
        tile_size = int(ceil(float(maxi(width, height)) / 64.0)) * 64
    if width > tile_size or height > tile_size:
        return {}
    var per_dir: int = frame_count / directions
    # Large SPRs (e.g. 1080-frame Tang Men missile 161) cannot fit in a
    # horizontal 8192px atlas. Keep the source frame table intact and decode
    # ONLY the current frame on demand. Existing small SPRs use old atlas.
    if frames > MAX_FRAMES or per_dir * tile_size > MAX_TEXTURE_SIDE or directions * tile_size > MAX_TEXTURE_SIDE:
        var lazy_source: Dictionary = {
            "texture": _placeholder_texture(tile_size),
            "frames_per_direction": per_dir,
            "directions": directions,
            "anim_ms": interval if interval > 0 else 100,
            "source_width": width,
            "source_height": height,
            "tile_size": tile_size,
            "original_frames": frames,
            "ignored_padding_frames": trailing_padding,
            "lazy_frames": true,
            "codec": "SPR_RAW_PALETTE_LAZY",
            "lazy_raw": raw,
            "lazy_colors": colors,
            "lazy_table_at": table_at,
            "lazy_data_at": data_at,
            "lazy_frame_count": frame_count,
            "lazy_key": str(hash(raw)) + ":" + str(raw.size())
        }
        # Validate at least one actual frame before accepting a PAK hit.
        # A valid header/table alone cannot prove a usable sprite.
        if get_lazy_frame(lazy_source, 0, 0) == null:
            return {}
        return lazy_source
    var atlas: Image = Image.create(per_dir * tile_size, directions * tile_size, false, Image.FORMAT_RGBA8)
    atlas.fill(Color.TRANSPARENT)
    var original_pivots: Array = []
    for i in range(frame_count):
        var offset: int = raw.decode_u32(table_at + i * 8)
        var payload_length: int = raw.decode_u32(table_at + i * 8 + 4)
        var start: int = data_at + offset
        if start + payload_length > raw.size():
            start = offset
        if start < 0 or start + payload_length > raw.size() or payload_length < 8:
            return {}
        var fw: int = raw.decode_u16(start)
        var fh: int = raw.decode_u16(start + 2)
        var ox: int = raw.decode_s16(start + 4)
        var oy: int = raw.decode_s16(start + 6)
        if fw < 1 or fh < 1 or fw * fh > MAX_CANVAS * MAX_CANVAS:
            return {}
        var pixels: PackedByteArray = PackedByteArray()
        pixels.resize(fw * fh * 4)
        var read_at: int = start + 8
        var end_at: int = start + payload_length
        var at_pixel: int = 0
        while at_pixel < fw * fh and read_at + 1 < end_at:
            var run_count: int = int(raw[read_at])
            var alpha: int = int(raw[read_at + 1])
            read_at += 2
            if run_count == 0:
                continue
            if at_pixel + run_count > fw * fh:
                return {}
            if alpha != 0:
                if read_at + run_count > end_at:
                    return {}
                for j in range(run_count):
                    var palette_idx: int = int(raw[read_at + j])
                    if palette_idx >= colors:
                        return {}
                    var pix: int = (at_pixel + j) * 4
                    var pal: int = 32 + palette_idx * 3
                    pixels[pix] = raw[pal]
                    pixels[pix + 1] = raw[pal + 1]
                    pixels[pix + 2] = raw[pal + 2]
                    pixels[pix + 3] = alpha
                read_at += run_count
            at_pixel += run_count
        if at_pixel != fw * fh:
            return {}
        var source_frame: Image = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, pixels)
        var canvas: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
        canvas.fill(Color.TRANSPARENT)
        canvas.blit_rect(source_frame, Rect2i(0, 0, fw, fh), Vector2i(ox, oy))
        var direction: int = i / per_dir
        var frame_index: int = i % per_dir
        var at_x: int = frame_index * tile_size + (tile_size - width) / 2
        var at_y: int = direction * tile_size + (tile_size - height) / 2
        atlas.blit_rect(canvas, Rect2i(0, 0, width, height), Vector2i(at_x, at_y))
        original_pivots.append({"x": ox, "y": oy, "width": fw, "height": fh})
    return {
        "texture": ImageTexture.create_from_image(atlas),
        "frames_per_direction": per_dir,
        "directions": directions,
        "anim_ms": interval if interval > 0 else 100,
        "source_width": width,
        "source_height": height,
        "frame_offsets": original_pivots,
        "tile_size": tile_size,
        "codec": "SPR_RAW_PALETTE",
        "original_frames": frames,
        "ignored_padding_frames": trailing_padding
    }

# V44.6: one-frame streaming path for long original SPRs.
# Only used when atlas size/frame count would exceed our safe bounds.
func _placeholder_texture(size: int) -> Texture2D:
    var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    return ImageTexture.create_from_image(img)

func get_lazy_frame(decoded: Dictionary, frame: int, direction: int) -> Texture2D:
    if not bool(decoded.get("lazy_frames", false)):
        return null
    var per_dir: int = int(decoded.get("frames_per_direction", 0))
    var dirs: int = int(decoded.get("directions", 0))
    if per_dir < 1 or dirs < 1:
        return null
    var local_frame: int = clampi(frame, 0, per_dir - 1)
    var local_dir: int = posmod(direction, dirs)
    var index: int = local_dir * per_dir + local_frame
    if index < 0 or index >= int(decoded.get("lazy_frame_count", 0)):
        return null
    var key: String = str(decoded.get("lazy_key", "")) + ":" + str(index)
    if _lazy_cache.has(key):
        return _lazy_cache[key] as Texture2D
    var raw: PackedByteArray = decoded.get("lazy_raw", PackedByteArray())
    var table_at: int = int(decoded.get("lazy_table_at", 0))
    var data_at: int = int(decoded.get("lazy_data_at", 0))
    var colors: int = int(decoded.get("lazy_colors", 0))
    var width: int = int(decoded.get("source_width", 0))
    var height: int = int(decoded.get("source_height", 0))
    var tile_size: int = int(decoded.get("tile_size", 0))
    if raw.is_empty() or colors < 1 or tile_size < 1 or width < 1 or height < 1:
        return null
    var record_at: int = table_at + index * 8
    if record_at + 8 > raw.size():
        return null
    var offset: int = raw.decode_u32(record_at)
    var payload_length: int = raw.decode_u32(record_at + 4)
    var start: int = data_at + offset
    if start + payload_length > raw.size():
        start = offset
    if start < data_at or payload_length < 8 or start + payload_length > raw.size():
        return null
    var fw: int = raw.decode_u16(start)
    var fh: int = raw.decode_u16(start + 2)
    var ox: int = raw.decode_s16(start + 4)
    var oy: int = raw.decode_s16(start + 6)
    if fw < 1 or fh < 1 or fw > MAX_CANVAS or fh > MAX_CANVAS:
        return null
    var pixels: PackedByteArray = PackedByteArray()
    pixels.resize(fw * fh * 4)
    var read_at: int = start + 8
    var end_at: int = start + payload_length
    var at_pixel: int = 0
    while at_pixel < fw * fh and read_at + 1 < end_at:
        var run_count: int = int(raw[read_at])
        var alpha: int = int(raw[read_at + 1])
        read_at += 2
        if run_count == 0:
            continue
        if at_pixel + run_count > fw * fh:
            return null
        if alpha != 0:
            if read_at + run_count > end_at:
                return null
            for j in range(run_count):
                var pal_idx: int = int(raw[read_at + j])
                if pal_idx >= colors:
                    return null
                var pix: int = (at_pixel + j) * 4
                var pal: int = 32 + pal_idx * 3
                pixels[pix] = raw[pal]
                pixels[pix + 1] = raw[pal + 1]
                pixels[pix + 2] = raw[pal + 2]
                pixels[pix + 3] = alpha
            read_at += run_count
        at_pixel += run_count
    if at_pixel != fw * fh:
        return null
    var source_frame: Image = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, pixels)
    var canvas: Image = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
    canvas.fill(Color.TRANSPARENT)
    canvas.blit_rect(source_frame, Rect2i(0, 0, fw, fh),
        Vector2i(ox + (tile_size - width) / 2, oy + (tile_size - height) / 2))
    var tex: Texture2D = ImageTexture.create_from_image(canvas)
    _lazy_cache[key] = tex
    _lazy_cache_order.append(key)
    while _lazy_cache_order.size() > MAX_LAZY_TEXTURES:
        var evicted: String = _lazy_cache_order.pop_front()
        _lazy_cache.erase(evicted)
    return tex
