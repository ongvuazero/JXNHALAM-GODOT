extends Node2D
## V18: playback of the client JX1 FLY observations in MAIN gameplay space.
## This is CAPTURE PLAYBACK, not an algorithm generating new JX1 cast trajectories.
## The actor position is an UNVERIFIED alignment anchor, NOT native NPC coordinates.
## Capture timestamps are debugger times, not native animation frame intervals.
## No HIT asset is drawn: source log 1234.txt did not observe HIT.
const DATA_PATH: String = "res://data/JX141_NATIVE_FLY_EVIDENCE_V11.json"
const FLY_ATLAS: Texture2D = preload("res://assets/skill90/jx90_truyphong_sweep.png")
const TILE: int = 256
const NATIVE_WORLD_GRID: int = 32
const NATIVE_FIXED: int = 1024
const NATIVE_STEP: int = 30
const DIR_COUNT: int = 32
const PER_DIR: int = 10
const LOOP_HOLD_SECONDS: float = 0.6 # Viewer-only pause between captured segments.
const GROUP_NAME: String = "jx141_native_evidence_mode"

var _ticks: Array = []
var _sessions: Array = []
var _origins: Array[Vector2i] = []
var _sprites: Dictionary = {}
var _session_index: int = 0
var _cursor: int = 0
var _first_tick_ms: int = 0
var _elapsed_ms: float = 0.0
var _loop_hold_ms: float = 0.0
var _verified: int = 0
var _failures: int = 0
var _status: String = "NOT LOADED"
var _last_rendered: int = 0
var _anchor_at_begin: Vector2 = Vector2.ZERO

func _ready() -> void:
    add_to_group(GROUP_NAME)
    z_index = 1

func configure(actor: Node2D, segment_index: int = 0) -> Dictionary:
    if not is_instance_valid(actor):
        return {"ok": false, "reason": "missing Godot actor"}
    if not FileAccess.file_exists(DATA_PATH):
        return {"ok": false, "reason": "missing evidence JSON from V11/V12: " + DATA_PATH}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not (parsed is Dictionary):
        return {"ok": false, "reason": "invalid evidence JSON"}
    var evidence: Dictionary = parsed as Dictionary
    if str(evidence.get("schema", "")) != "jx141-fly-audit-v11":
        return {"ok": false, "reason": "unexpected evidence schema"}
    if not (evidence.get("ticks", null) is Array) or not (evidence.get("sessions", null) is Array):
        return {"ok": false, "reason": "missing observations/sessions"}
    _ticks = evidence["ticks"] as Array
    _sessions = evidence["sessions"] as Array
    if _ticks.is_empty() or _sessions.is_empty():
        return {"ok": false, "reason": "empty evidence file"}
    if not _validate_evidence():
        return {"ok": false, "reason": "evidence frame/position/origin mismatch; refused to play"}
    _anchor_at_begin = actor.global_position
    global_position = _anchor_at_begin
    select_segment(segment_index)
    _status = "CLIENT FLY CAPTURE (camera / NPC anchor unverified)"
    return {"ok": true, "samples_verified": _verified, "segments": _sessions.size()}

func _validate_evidence() -> bool:
    _origins.clear()
    _verified = 0
    _failures = 0
    # Reject a damaged record instead of silently turning it into an approximate VFX.
    for segment_value in _sessions:
        if not (segment_value is Dictionary):
            _failures += 1
            return false
        var segment: Dictionary = segment_value as Dictionary
        var start_index: int = int(segment.get("start_group", -1))
        var end_index: int = int(segment.get("end_group_exclusive", -1))
        if start_index < 0 or end_index > _ticks.size() or end_index <= start_index:
            _failures += 1
            return false
        var origin: Vector2i = Vector2i.ZERO
        var got_origin: bool = false
        for group_index in range(start_index, end_index):
            var group_value: Variant = _ticks[group_index]
            if not (group_value is Dictionary):
                _failures += 1
                return false
            var group: Dictionary = group_value as Dictionary
            if not (group.get("samples", null) is Array):
                _failures += 1
                return false
            for candidate in group["samples"]:
                if not (candidate is Dictionary):
                    _failures += 1
                    return false
                var s: Dictionary = candidate as Dictionary
                var direction: int = int(s.get("dir64", -1))
                var elapsed: int = int(s.get("elapsed", -1))
                var duration: int = int(s.get("duration", 0))
                if direction < 0 or direction >= 64 or elapsed < 0 or duration <= 0:
                    _failures += 1
                    return false
                var expected_frame: int = posmod(int((direction + 1) / 2), DIR_COUNT) * PER_DIR + int((PER_DIR * elapsed) / duration)
                if expected_frame != int(s.get("frame", -1)):
                    _failures += 1
                    return false
                var gx: int = int(s.get("gx", 0))
                var gy: int = int(s.get("gy", 0))
                var bx: int = int(s.get("bx", 0))
                var by: int = int(s.get("by", 0))
                var ox: int = int(s.get("ox", 0))
                var oy: int = int(s.get("oy", 0))
                var world_x: int = bx + gx * NATIVE_WORLD_GRID + (ox >> 10)
                var world_y: int = by + gy * NATIVE_WORLD_GRID + (oy >> 10)
                if world_x != int(s.get("x", -1)) or world_y != int(s.get("y", -1)):
                    _failures += 1
                    return false
                var origin_fixed: Vector2i = Vector2i(
                    (bx + gx * NATIVE_WORLD_GRID) * NATIVE_FIXED + ox - elapsed * int(s.get("fx", 0)) * NATIVE_STEP,
                    (by + gy * NATIVE_WORLD_GRID) * NATIVE_FIXED + oy - elapsed * int(s.get("fy", 0)) * NATIVE_STEP)
                if not got_origin:
                    origin = origin_fixed
                    got_origin = true
                if origin != origin_fixed:
                    _failures += 1
                    return false
                _verified += 1
        if not got_origin or origin.x % NATIVE_FIXED != 0 or origin.y % NATIVE_FIXED != 0:
            _failures += 1
            return false
        _origins.append(Vector2i(int(origin.x / NATIVE_FIXED), int(origin.y / NATIVE_FIXED)))
    return _failures == 0

func select_segment(segment_index: int) -> void:
    if _sessions.is_empty():
        return
    _clear_sprites()
    _session_index = posmod(segment_index, _sessions.size())
    var segment: Dictionary = _sessions[_session_index] as Dictionary
    _cursor = int(segment["start_group"])
    _first_tick_ms = int((_ticks[_cursor] as Dictionary).get("debugger_tick_ms", 0))
    _elapsed_ms = 0.0
    _loop_hold_ms = 0.0
    _last_rendered = 0
    # Lock anchor to the actor's world position at the moment this mode started.
    # This is a Godot QA registration, not a recovered native NPC-to-camera offset.
    global_position = _anchor_at_begin
    _draw_observed_group(_ticks[_cursor] as Dictionary)
    _cursor += 1
    queue_redraw()

func next_segment() -> void:
    select_segment(_session_index + 1)

func _process(delta: float) -> void:
    if _ticks.is_empty() or _sessions.is_empty():
        return
    var segment: Dictionary = _sessions[_session_index] as Dictionary
    var end_index: int = int(segment["end_group_exclusive"])
    if _cursor >= end_index:
        _loop_hold_ms += maxf(delta, 0.0) * 1000.0
        if _loop_hold_ms >= LOOP_HOLD_SECONDS * 1000.0:
            select_segment(_session_index)
        return
    _elapsed_ms += maxf(delta, 0.0) * 1000.0
    # The observation timestamp is only a replay schedule. Do not pretend it
    # is the client's internal frame clock; do not extrapolate unobserved frames.
    var safety: int = 0
    while _cursor < end_index and safety < 512:
        var group: Dictionary = _ticks[_cursor] as Dictionary
        if float(int(group.get("debugger_tick_ms", 0)) - _first_tick_ms) > _elapsed_ms:
            break
        _draw_observed_group(group)
        _cursor += 1
        safety += 1

func _native_screen(world_x: int, world_y: int, world_z: int) -> Vector2:
    # Identical relative transform seen in both renderer implementations.
    # Absolute camera translation cancels for positions within one capture.
    return Vector2(float(world_x), float(int(world_y / 2) - ((world_z * 887) >> 10)))

func _draw_observed_group(group: Dictionary) -> void:
    var origin: Vector2i = _origins[_session_index]
    var origin_screen: Vector2 = _native_screen(origin.x, origin.y, 10)
    var visible_ids: Dictionary = {}
    var shown: int = 0
    for candidate in group.get("samples", []):
        if not (candidate is Dictionary):
            continue
        var s: Dictionary = candidate as Dictionary
        var ptr: String = str(s.get("ptr", ""))
        if ptr.is_empty():
            continue
        visible_ids[ptr] = true
        var sprite: Sprite2D
        if _sprites.has(ptr) and is_instance_valid(_sprites[ptr]):
            sprite = _sprites[ptr] as Sprite2D
        else:
            sprite = Sprite2D.new()
            sprite.name = "JX_NATIVE_FLY_" + ptr
            sprite.texture = FLY_ATLAS
            sprite.region_enabled = true
            sprite.region_rect = Rect2(0.0, 0.0, 256.0, 256.0)
            sprite.centered = true
            sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
            add_child(sprite)
            _sprites[ptr] = sprite
        var absolute_frame: int = int(s.get("frame", 0))
        sprite.region_rect = Rect2(float(posmod(absolute_frame, PER_DIR) * TILE),
            float(int(absolute_frame / PER_DIR) * TILE), float(TILE), float(TILE))
        sprite.position = _native_screen(int(s["x"]), int(s["y"]), int(s.get("z", 10))) - origin_screen
        sprite.visible = true
        shown += 1
    # Missing from the client draw calls for this group => NOT drawn as FLY.
    # This is based on actual renderer samples, not DEMO collision state.
    for ptr in _sprites.keys():
        if not visible_ids.has(ptr):
            var missing: Sprite2D = _sprites[ptr] as Sprite2D
            if is_instance_valid(missing):
                missing.visible = false
                missing.queue_free()
            _sprites.erase(ptr)
    _last_rendered = shown

func _clear_sprites() -> void:
    for child in _sprites.values():
        if is_instance_valid(child):
            (child as Sprite2D).visible = false
            (child as Sprite2D).queue_free()
    _sprites.clear()

func _draw() -> void:
    draw_circle(Vector2.ZERO, 3.0, Color(0.15, 0.95, 0.75, 0.9))
    draw_line(Vector2(-10, 0), Vector2(10, 0), Color(0.15, 0.95, 0.75, 0.6), 1.0)
    draw_line(Vector2(0, -10), Vector2(0, 10), Color(0.15, 0.95, 0.75, 0.6), 1.0)

func status_line() -> String:
    if _sessions.is_empty():
        return "NATIVE EVIDENCE: " + _status
    var segment: Dictionary = _sessions[_session_index] as Dictionary
    var start: int = int(segment["start_group"])
    var end: int = int(segment["end_group_exclusive"])
    return "JX1 FLY CAPTURE %d/%d | group %d/%d | sprites %d | %d samples VERIFIED | camera & NPC anchor UNKNOWN" % [
        _session_index + 1, _sessions.size(), maxi(0, _cursor - start), end - start,
        _last_rendered, _verified]

func _exit_tree() -> void:
    _clear_sprites()
