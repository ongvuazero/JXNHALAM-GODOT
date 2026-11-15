extends Node2D
## JXNHALAM V17 — READ-ONLY native FLY audit with fixed-point missile launch reconstruction.
## F6 on res://scenes/JX141NativeFlyAudit.tscn. NO modifications to Main/Player/combat.
## Observation groups follow debugger capture order, NOT the JX1 engine frame clock.
## View is anchored WORLD coordinates with adjustable INSPECTION zoom, NOT client camera pixels.
## HIT/AnimFile4 and AnimFileB4 were not observed in 1234.txt and are NEVER synthesized here.
## Reconstructed launch coordinates are native MISSILE WORLD position, not NPC foot or camera.
## Exact origin rule (verified against original client logs):
## launch_x_fixed = (region_base_x + grid_x * 32) * 1024 + offset_x - elapsed * factor_x * 30
## launch_y_fixed = (region_base_y + grid_y * 32) * 1024 + offset_y - elapsed * factor_y * 30

const DATA_PATH: String = "res://data/JX141_NATIVE_FLY_EVIDENCE_V11.json"
const ATLAS: Texture2D = preload("res://assets/skill90/jx90_truyphong_sweep.png")
const FrameProbe = preload("res://scripts/JX141NativeFrameProbe.gd")
const NativeCoordinates = preload("res://scripts/JX141NativeCoordinates.gd")
const NativeCamera = preload("res://scripts/JX141NativeCamera.gd")
const TILE_SIZE: float = 256.0
const FRAMES_PER_DIRECTION: int = 10
const TOTAL_FRAMES: int = 320
const DEFAULT_GROUP_SECONDS: float = 0.12 # viewer-only speed, never native time
# DBG GetTickCount timestamps are observations; debugging may delay sampling.
# They are NOT original JX1 animation tick durations or captured camera FPS.
const TRAIL_LOOKBACK_MS: int = 1000 # visualization history window, NOT native missile lifetime.
const TRAIL_MAX_GAP_MS: int = 200 # visualization gap guard, NOT native disappearance.
const NATIVE_FIXED_SCALE: int = 1024
const NATIVE_GRID_SIZE: int = 32
const NATIVE_STEP_FACTOR: int = 30 # verified 136/136 distinct client displacement steps, not a px/s speed


var _ticks: Array = []
var _sessions: Array = []
var _sprites: Dictionary = {}
var _world_layer: Node2D
var _label: Label
var _status: Label
var _session_index: int = 0
var _current_group: int = 0
var _zoom: float = 1.6 # magnification of audit image only, not a native scale.
var _show_trails: bool = true
var _show_launch_rays: bool = true
var _native_launch_by_segment: Array = []
var _origin_pass: int = 0
var _origin_fail: int = 0
var _use_observation_clock: bool = true
var _visible_max_per_group: int = 0

var _playing: bool = false
var _play_accumulator: float = 0.0
var _world_origin: Vector2 = Vector2.ZERO
var _anchor_world_z: int = 0
var _frame_pass: int = 0
var _frame_fail: int = 0
var _world_pass: int = 0
var _world_fail: int = 0
var _file_status: String = ""

func _ready() -> void:
    _world_layer = Node2D.new()
    _world_layer.name = "ObservedWorldRelativeSprites"
    add_child(_world_layer)
    _label = Label.new()
    _label.name = "AuditHeader"
    _label.position = Vector2(18, 10)
    _label.add_theme_font_size_override("font_size", 17)
    _label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.87))
    add_child(_label)
    _status = Label.new()
    _status.name = "AuditFooter"
    _status.position = Vector2(18, 550)
    _status.add_theme_font_size_override("font_size", 14)
    _status.add_theme_color_override("font_color", Color(0.96, 0.84, 0.57))
    add_child(_status)
    _read_evidence()

func _read_evidence() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _file_status = "MISSING EVIDENCE FILE: " + DATA_PATH
        _refresh_status()
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not (parsed is Dictionary):
        _file_status = "INVALID EVIDENCE JSON"
        _refresh_status()
        return
    var source: Dictionary = parsed
    if str(source.get("schema", "")) != "jx141-fly-audit-v11":
        _file_status = "WRONG EVIDENCE SCHEMA"
        _refresh_status()
        return
    if not (source.get("ticks") is Array) or not (source.get("sessions") is Array):
        _file_status = "MISSING TICKS OR SESSIONS"
        _refresh_status()
        return
    _ticks = source["ticks"] as Array
    _sessions = source["sessions"] as Array
    if _ticks.is_empty() or _sessions.is_empty():
        _file_status = "EVIDENCE IS EMPTY"
        _refresh_status()
        return
    _validate_samples()
    _validate_launch_origins()
    _file_status = "TRACE LOADED (READ ONLY)"
    _enter_session(0)

func _validate_samples() -> void:
    # Regression against original renderer observations, not against a guessed camera.
    _frame_pass = 0
    _frame_fail = 0
    _world_pass = 0
    _world_fail = 0
    for item in _ticks:
        if not (item is Dictionary):
            continue
        var group: Dictionary = item as Dictionary
        if not (group.get("samples") is Array):
            continue
        for candidate in group["samples"]:
            if not (candidate is Dictionary):
                continue
            var s: Dictionary = candidate as Dictionary
            var d: int = int(s.get("dir64", -1))
            var elapsed: int = int(s.get("elapsed", -1))
            var duration: int = int(s.get("duration", 0))
            var frame_result: Dictionary = FrameProbe.inspect(TOTAL_FRAMES, 32, d, elapsed, duration, 1, false)
            var frame_ok: bool = bool(frame_result.get("ok", false)) and int(frame_result.get("absolute_frame", -1)) == int(s.get("frame", -2))
            if frame_ok:
                _frame_pass += 1
            else:
                _frame_fail += 1
            # Run the exact projection helper shipped in the user's V9/V10 code.
            # Region count=64 is a test harness bound; actual region index and base are captured.
            var pos_result: Dictionary = NativeCoordinates.region_to_world({
                "region_index": int(s.get("region", -1)), "region_count": 64,
                "region_base_x": int(s.get("bx", 0)), "region_base_y": int(s.get("by", 0)),
                "cell_width": 32, "cell_height": 32,
                "grid_x": int(s.get("gx", 0)), "grid_y": int(s.get("gy", 0)),
                "off_x_fixed": int(s.get("ox", 0)), "off_y_fixed": int(s.get("oy", 0))
            })
            if bool(pos_result.get("ok", false)) and int(pos_result.get("x", -1)) == int(s.get("x", -2)) and int(pos_result.get("y", -1)) == int(s.get("y", -2)):
                _world_pass += 1
            else:
                _world_fail += 1

func _inferred_launch_fixed(sample: Dictionary) -> Vector2i:
    # Reconstruct from *unrounded* client fixed-point XY. Never use observed
    # rounded world X/Y or image coordinates for this regression.
    var fixed_x: int = (int(sample.get("bx", 0)) + int(sample.get("gx", 0)) * NATIVE_GRID_SIZE) * NATIVE_FIXED_SCALE + int(sample.get("ox", 0))
    var fixed_y: int = (int(sample.get("by", 0)) + int(sample.get("gy", 0)) * NATIVE_GRID_SIZE) * NATIVE_FIXED_SCALE + int(sample.get("oy", 0))
    var life_tick: int = int(sample.get("elapsed", 0))
    return Vector2i(
        fixed_x - life_tick * int(sample.get("fx", 0)) * NATIVE_STEP_FACTOR,
        fixed_y - life_tick * int(sample.get("fy", 0)) * NATIVE_STEP_FACTOR)

func _validate_launch_origins() -> void:
    # A capture segment may have many renders, casts and reused missile slots.
    # Accept one launch origin ONLY if every original observation in that segment
    # reproduces the exact same FIXED-POINT X,Y, with zero fractional remainder.
    # This is evidence validation, not a guessed player origin or screen camera.
    _native_launch_by_segment.clear()
    _origin_pass = 0
    _origin_fail = 0
    for session_item in _sessions:
        var session: Dictionary = session_item as Dictionary
        var first_fixed: Vector2i = Vector2i.ZERO
        var reference_found: bool = false
        var valid: bool = true
        var group_count: int = 0
        for group_index in range(int(session["start_group"]), int(session["end_group_exclusive"])):
            var group: Dictionary = _ticks[group_index] as Dictionary
            for candidate in group.get("samples", []):
                if not (candidate is Dictionary):
                    _origin_fail += 1
                    valid = false
                    continue
                var sample: Dictionary = candidate as Dictionary
                var inferred_fixed: Vector2i = _inferred_launch_fixed(sample)
                if not reference_found:
                    first_fixed = inferred_fixed
                    reference_found = true
                var exact: bool = (
                    inferred_fixed == first_fixed
                    and inferred_fixed.x % NATIVE_FIXED_SCALE == 0
                    and inferred_fixed.y % NATIVE_FIXED_SCALE == 0)
                if exact:
                    _origin_pass += 1
                else:
                    _origin_fail += 1
                    valid = false
                group_count += 1
        if not reference_found:
            valid = false
        _native_launch_by_segment.append({
            "valid": valid,
            "fixed_x": first_fixed.x,
            "fixed_y": first_fixed.y,
            "world_x": first_fixed.x / NATIVE_FIXED_SCALE,
            "world_y": first_fixed.y / NATIVE_FIXED_SCALE,
            "count": group_count
        })

func _enter_session(index: int) -> void:
    if _sessions.is_empty():
        return
    _session_index = posmod(index, _sessions.size())
    var session: Dictionary = _sessions[_session_index]
    var launch: Dictionary = _native_launch_by_segment[_session_index] as Dictionary
    if bool(launch.get("valid", false)):
        # Replace V16's median-center marker with the proven MISSILE launch world X/Y.
        _world_origin = Vector2(float(launch["world_x"]), float(launch["world_y"]))
    else:
        # Never assert a native origin when evidence verification fails.
        _world_origin = Vector2(float(session["world_anchor_x"]), float(session["world_anchor_y"]))
    # Anchor Z is the observed M141 sprite world height, NOT the NPC height.
    var start_group: Dictionary = _ticks[int(session["start_group"])] as Dictionary
    var start_samples: Array = start_group.get("samples", []) as Array
    _anchor_world_z = 0
    if not start_samples.is_empty() and start_samples[0] is Dictionary:
        _anchor_world_z = int((start_samples[0] as Dictionary).get("z", 0))
    _playing = false
    _play_accumulator = 0.0
    _current_group = int(session["start_group"])
    _display_group()

func _advance(step: int) -> void:
    if _sessions.is_empty():
        return
    var session: Dictionary = _sessions[_session_index]
    _current_group = clampi(_current_group + step, int(session["start_group"]), int(session["end_group_exclusive"]) - 1)
    _display_group()

func _make_sprite(key: String) -> Sprite2D:
    var sprite: Sprite2D = Sprite2D.new()
    sprite.name = "M141_CAPTURE_" + key
    sprite.texture = ATLAS
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.region_enabled = true
    sprite.centered = true
    sprite.scale = Vector2.ONE
    _world_layer.add_child(sprite)
    _sprites[key] = sprite
    return sprite

func _display_group() -> void:
    if _ticks.is_empty():
        return
    for child in _sprites.values():
        if is_instance_valid(child):
            (child as Sprite2D).visible = false
    var group: Dictionary = _ticks[_current_group]
    var samples: Array = group["samples"] as Array
    for candidate in samples:
        if not (candidate is Dictionary):
            continue
        var s: Dictionary = candidate as Dictionary
        var key: String = str(s["ptr"])
        var sprite: Sprite2D
        if _sprites.has(key):
            sprite = _sprites[key] as Sprite2D
        else:
            sprite = _make_sprite(key)
        var absolute_frame: int = int(s["frame"])
        if absolute_frame < 0 or absolute_frame >= TOTAL_FRAMES:
            sprite.visible = false
            continue
        var atlas_col: int = posmod(absolute_frame, FRAMES_PER_DIRECTION)
        var atlas_row: int = floori(float(absolute_frame) / float(FRAMES_PER_DIRECTION))
        sprite.region_rect = Rect2(float(atlas_col) * TILE_SIZE, float(atlas_row) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
        # Exact original screen projection RELATIVE to the observed anchor.
        # Runtime camera X/Y cancel; position on the user's real JX1 window
        # cannot be claimed until those camera offsets are recorded.
        var projected_delta: Vector2i = NativeCamera.relative_to_anchor(
            int(s["x"]), int(s["y"]), int(s.get("z", 0)),
            int(_world_origin.x), int(_world_origin.y), _anchor_world_z)
        sprite.position = Vector2(projected_delta)
        sprite.visible = true
    _apply_view()
    _refresh_status()
    queue_redraw()

func _apply_view() -> void:
    var sz: Vector2 = get_viewport_rect().size
    _world_layer.position = Vector2(sz.x * 0.5, sz.y * 0.56)
    _world_layer.scale = Vector2(_zoom, _zoom)

func _relative_observed_screen(s: Dictionary) -> Vector2:
    # Shared calculation with the frame renderer, including the signed Y rounding.
    var p: Vector2i = NativeCamera.relative_to_anchor(
        int(s["x"]), int(s["y"]), int(s.get("z", 0)),
        int(_world_origin.x), int(_world_origin.y), _anchor_world_z)
    return Vector2(p)

func _draw_observed_trails(center: Vector2) -> void:
    if not _show_trails or _ticks.is_empty() or _sessions.is_empty():
        return
    # Each trace segment was separated by the original capture analysis.
    # We never join different segments or invent missing frames/positions.
    var session: Dictionary = _sessions[_session_index]
    var last_tick: int = int((_ticks[_current_group] as Dictionary)["debugger_tick_ms"])
    var start: int = int(session["start_group"])
    var last_by_ptr: Dictionary = {}
    var colors: Array[Color] = [
        Color(0.98, 0.63, 0.40, 0.78),
        Color(0.43, 0.88, 0.81, 0.78),
        Color(0.70, 0.73, 0.99, 0.78)]
    for group_index in range(start, _current_group + 1):
        var group: Dictionary = _ticks[group_index] as Dictionary
        var current_tick: int = int(group["debugger_tick_ms"])
        if last_tick - current_tick > TRAIL_LOOKBACK_MS:
            continue
        for candidate in group.get("samples", []):
            if not (candidate is Dictionary):
                continue
            var s: Dictionary = candidate as Dictionary
            var ptr: String = str(s.get("ptr", ""))
            var rel: Vector2 = _relative_observed_screen(s)
            var screen_pt: Vector2 = center + rel * _zoom
            var color: Color = colors[posmod(int(s.get("slot", 0)), colors.size())]
            if last_by_ptr.has(ptr):
                var prev: Dictionary = last_by_ptr[ptr] as Dictionary
                var dt: int = current_tick - int(prev["tick"])
                # Separate breaks in observation; no interpolation across gaps.
                if dt >= 0 and dt <= TRAIL_MAX_GAP_MS:
                    var prev_rel: Vector2 = prev["pos"] as Vector2
                    var other_pt: Vector2 = center + prev_rel * _zoom
                    if screen_pt.distance_to(other_pt) > 0.1:
                        draw_line(other_pt, screen_pt, color, 2.2, true)
            last_by_ptr[ptr] = {"tick": current_tick, "pos": rel}
    # Only mark the ACTUALLY observed live render inputs of this group.
    var current: Dictionary = _ticks[_current_group] as Dictionary
    for candidate in current.get("samples", []):
        if not (candidate is Dictionary):
            continue
        var s: Dictionary = candidate as Dictionary
        var p: Vector2 = center + _relative_observed_screen(s) * _zoom
        var color: Color = colors[posmod(int(s.get("slot", 0)), colors.size())]
        draw_circle(p, 3.0, color)

func _draw_launch_rays(center: Vector2) -> void:
    if not _show_launch_rays or _ticks.is_empty() or _sessions.is_empty():
        return
    var launch: Dictionary = _native_launch_by_segment[_session_index] as Dictionary
    if not bool(launch.get("valid", false)):
        return
    var current: Dictionary = _ticks[_current_group] as Dictionary
    for candidate in current.get("samples", []):
        if not (candidate is Dictionary):
            continue
        var s: Dictionary = candidate as Dictionary
        var rel: Vector2 = _relative_observed_screen(s)
        var endpoint: Vector2 = center + rel * _zoom
        draw_line(center, endpoint, Color(0.96, 0.79, 0.43, 0.47), 1.3, true)
        draw_circle(endpoint, 2.5, Color(1.0, 0.86, 0.54, 0.72))
    # This circle IS the inferred common MISSILE origin, not a sprite/pivot offset.
    draw_arc(center, 8.0, 0.0, TAU, 24, Color(0.45, 1.0, 0.62, 0.98), 2.0, true)
    draw_circle(center, 2.0, Color(0.45, 1.0, 0.62, 0.98))

func _refresh_status() -> void:
    if _ticks.is_empty() or _sessions.is_empty():
        _label.text = "JX1 M141 / NATIVE FLY OBSERVATION — " + _file_status
        _status.text = "No client camera transform or HIT animation was captured."
        return
    var session: Dictionary = _sessions[_session_index]
    var g: Dictionary = _ticks[_current_group]
    var local_step: int = _current_group - int(session["start_group"]) + 1
    var current_tick: Dictionary = _ticks[_current_group] as Dictionary
    var first_tick: Dictionary = _ticks[int(session["start_group"])] as Dictionary
    var relative_ms: int = int(current_tick["debugger_tick_ms"]) - int(first_tick["debugger_tick_ms"])
    var visible_now: int = (current_tick["samples"] as Array).size()
    var timing_mode: String = "DBG OBSERVED TIME" if _use_observation_clock else "VIEWER 0.12s/GROUP"
    var launch: Dictionary = _native_launch_by_segment[_session_index] as Dictionary
    var launch_status: String = (
        "MISSILE LAUNCH world (%d,%d) fixed residual 0/1024" % [int(launch.get("world_x", 0)), int(launch.get("world_y", 0))]
        if bool(launch.get("valid", false)) else "LAUNCH NOT VERIFIED — showing V16 inspection anchor")
    var lines: Array[String] = [
        "JX1 M141 — V17 VERIFIED MISSILE LAUNCH / OBSERVED FLY ONLY",
        "Capture %d/%d | Group %d/%d | FLY drawn: %d | t+%dms DBG | Zoom %.2fx" % [_session_index + 1, _sessions.size(), local_step, int(session["observed_group_count"]), visible_now, relative_ms, _zoom],
        launch_status + " | NOT NPC origin / camera pixels",
        "Origin fixed-point regression %d PASS / %d FAIL | Camera ABS: UNKNOWN | HIT clock: UNKNOWN" % [_origin_pass, _origin_fail],
        "Frame %d PASS / %d FAIL | World XY %d PASS / %d FAIL | %s" % [_frame_pass, _frame_fail, _world_pass, _world_fail, timing_mode],
        "LEFT/RIGHT group | TAB segment | P play | H trails | O launch rays | T clock | UP/DOWN zoom"
    ]
    _label.text = "\n".join(PackedStringArray(lines))
    var parts: Array[String] = ["Green cross = reconstructed M141 launch (exact client fixed XY). No client camera/NPC foot/HIT captured."]
    for candidate in g["samples"]:
        var s: Dictionary = candidate as Dictionary
        var relative_screen: Vector2i = NativeCamera.relative_to_anchor(
            int(s["x"]), int(s["y"]), int(s.get("z", 0)),
            int(_world_origin.x), int(_world_origin.y), _anchor_world_z)
        parts.append("slot %02d | dir64 %02d | frame %03d | life %d/%d | rel (%d,%d) | ptr %s" % [
            int(s["slot"]), int(s["dir64"]), int(s["frame"]), int(s.get("elapsed",-1)),
            int(s.get("duration",-1)), relative_screen.x, relative_screen.y, str(s["ptr"])])
    _status.text = "\n".join(PackedStringArray(parts))

func _process(delta: float) -> void:
    _apply_view()
    if not _playing or _sessions.is_empty():
        return
    _play_accumulator += maxf(delta, 0.0)
    var session: Dictionary = _sessions[_session_index]
    if _current_group + 1 >= int(session["end_group_exclusive"]):
        _playing = false
        _refresh_status()
        return
    # Step on actual debugger observation timestamps; never interpolate or invent
    # native missile updates. Debugger overhead may distort this wall-clock cadence.
    var limit: int = 0
    while _current_group + 1 < int(session["end_group_exclusive"]) and limit < 64:
        var next_group: Dictionary = _ticks[_current_group + 1] as Dictionary
        var this_group: Dictionary = _ticks[_current_group] as Dictionary
        var observed_dt: int = max(0, int(next_group["debugger_tick_ms"]) - int(this_group["debugger_tick_ms"]))
        var required_seconds: float = float(observed_dt) / 1000.0 if _use_observation_clock else DEFAULT_GROUP_SECONDS
        if _play_accumulator < required_seconds:
            break
        _play_accumulator -= required_seconds
        _current_group += 1
        _display_group()
        limit += 1
    if _current_group + 1 >= int(session["end_group_exclusive"]):
        _playing = false
        _refresh_status()

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    var key: InputEventKey = event as InputEventKey
    if not key.pressed or key.echo:
        return
    match key.keycode:
        KEY_RIGHT:
            _playing = false
            _advance(1)
        KEY_LEFT:
            _playing = false
            _advance(-1)
        KEY_TAB:
            _enter_session(_session_index + 1)
        KEY_HOME:
            _enter_session(_session_index)
        KEY_P:
            _playing = not _playing
            _play_accumulator = 0.0
            if _playing and not _sessions.is_empty():
                var last_index: int = int((_sessions[_session_index] as Dictionary)["end_group_exclusive"]) - 1
                if _current_group >= last_index:
                    _enter_session(_session_index)
                    _playing = true
            _refresh_status()
        KEY_H:
            _show_trails = not _show_trails
            queue_redraw()
            _refresh_status()
        KEY_O:
            _show_launch_rays = not _show_launch_rays
            queue_redraw()
            _refresh_status()
        KEY_T:
            _use_observation_clock = not _use_observation_clock
            _play_accumulator = 0.0
            _refresh_status()
        KEY_UP:
            _zoom = minf(3.0, _zoom * 1.25)
            _display_group()
        KEY_DOWN:
            _zoom = maxf(0.25, _zoom / 1.25)
            _display_group()
        _:
            return
    get_viewport().set_input_as_handled()

func _draw() -> void:
    var sz: Vector2 = get_viewport_rect().size
    draw_rect(Rect2(Vector2.ZERO, sz), Color(0.075,0.12,0.13), true)
    var center: Vector2 = Vector2(sz.x * 0.5, sz.y * 0.56)
    var gap: float = 64.0 * _zoom
    # Simple visual grid; its scale is a viewer control, not native camera calibration.
    for i in range(-22, 23):
        var x: float = center.x + float(i) * gap
        if x >= 0.0 and x <= sz.x:
            draw_line(Vector2(x,130),Vector2(x,sz.y),Color(0.2,0.3,0.3,0.4),1.0)
        var y: float = center.y + float(i) * gap
        if y >= 130.0 and y <= sz.y:
            draw_line(Vector2(0,y),Vector2(sz.x,y),Color(0.2,0.3,0.3,0.4),1.0)
    _draw_observed_trails(center)
    _draw_launch_rays(center)
    draw_line(center-Vector2(14,0),center+Vector2(14,0), Color(0.96,0.81,0.45,0.8),2.0)
    draw_line(center-Vector2(0,14),center+Vector2(0,14), Color(0.96,0.81,0.45,0.8),2.0)
    draw_rect(Rect2(0,0,sz.x,136),Color(0.025,0.045,0.05,0.95),true)
    draw_rect(Rect2(0,535,sz.x,sz.y-535),Color(0.025,0.045,0.05,0.95),true)
