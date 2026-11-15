extends RefCounted
## Client JX1, game.exe sub_570970 @ 0x570970.
## REQUIRES scene/region metadata; NEVER assumes that native world XY is Godot XY.
## Do not add class_name: V2/V3 projects sometimes contain duplicated probes in payload/.

# Source fields of sub_570970:
# world X = region[+0x98].base_x + scene[+0x3C].cell_w * grid_x + (off_x_fixed >> 10)
# world Y = region[+0x9C].base_y + scene[+0x40].cell_h * grid_y + (off_y_fixed >> 10)
# Right shift is ARITHMETIC (x86 SAR) and therefore rounds negative subpixels downward.
static func region_to_world(data: Dictionary) -> Dictionary:
    var keys: Array[String] = ["region_index", "region_count", "region_base_x",
        "region_base_y", "cell_width", "cell_height", "grid_x", "grid_y",
        "off_x_fixed", "off_y_fixed"]
    for field in keys:
        if not data.has(field):
            return {"ok": false, "reason": "missing " + field}
    var region_index: int = int(data["region_index"])
    var region_count: int = int(data["region_count"])
    if region_index < 0 or region_index >= region_count:
        # Client returns (0,0) on invalid index. Do not mistake that for a real position.
        return {"ok": false, "reason": "invalid region index"}
    var x: int = int(data["region_base_x"]) + int(data["cell_width"]) * int(data["grid_x"]) + (int(data["off_x_fixed"]) >> 10)
    var y: int = int(data["region_base_y"]) + int(data["cell_height"]) * int(data["grid_y"]) + (int(data["off_y_fixed"]) >> 10)
    return {"ok": true, "x": x, "y": y, "source": "game_exe_570970"}

static func resolve_projected_world(data: Dictionary) -> Dictionary:
    # A caller can provide a measured Godot world position, which needs no native-map projection.
    if data.has("godot_world_x") and data.has("godot_world_y"):
        return {"ok": true, "position": Vector2(float(data["godot_world_x"]), float(data["godot_world_y"])), "source": "explicit_godot_world"}
    # Alternatively, require BOTH a native region coordinate AND a measured affine
    # mapping of that native world into the Godot demo. Never use default scale=1.
    var native: Dictionary = region_to_world(data)
    if not bool(native.get("ok", false)):
        return native
    # V9: exact 2x2 affine projection in a caller-supplied camera basis.
    # This includes rotation/shear and is not restricted to two axis scales.
    # A camera transform is dynamic: supply per-frame values when it moves.
    var affine_keys: Array[String] = ["projection_native_origin_x", "projection_native_origin_y",
        "projection_godot_origin_x", "projection_godot_origin_y",
        "projection_basis_xx", "projection_basis_xy",
        "projection_basis_yx", "projection_basis_yy"]
    var has_affine: bool = false
    for field in ["projection_basis_xx", "projection_basis_xy", "projection_basis_yx", "projection_basis_yy"]:
        if data.has(field):
            has_affine = true
    if has_affine:
        for field in affine_keys:
            if not data.has(field):
                return {"ok": false, "reason": "incomplete camera affine: missing " + field}
        var nx: float = float(native["x"]) - float(data["projection_native_origin_x"])
        var ny: float = float(native["y"]) - float(data["projection_native_origin_y"])
        var projected: Vector2 = Vector2(
            float(data["projection_godot_origin_x"]) + float(data["projection_basis_xx"]) * nx + float(data["projection_basis_xy"]) * ny,
            float(data["projection_godot_origin_y"]) + float(data["projection_basis_yx"]) * nx + float(data["projection_basis_yy"]) * ny)
        return {"ok": true, "position": projected, "native_world_x": int(native["x"]),
            "native_world_y": int(native["y"]), "source": "native_world_explicit_camera_affine"}
    var keys: Array[String] = ["projection_native_origin_x", "projection_native_origin_y",
        "projection_godot_origin_x", "projection_godot_origin_y",
        "projection_scale_x", "projection_scale_y"]
    for field in keys:
        if not data.has(field):
            return {"ok": false, "reason": "missing projection " + field,
                "native_world_x": int(native["x"]), "native_world_y": int(native["y"])}
    var origin_native: Vector2 = Vector2(float(data["projection_native_origin_x"]), float(data["projection_native_origin_y"]))
    var origin_godot: Vector2 = Vector2(float(data["projection_godot_origin_x"]), float(data["projection_godot_origin_y"]))
    var scale_xy: Vector2 = Vector2(float(data["projection_scale_x"]), float(data["projection_scale_y"]))
    if scale_xy.x == 0.0 or scale_xy.y == 0.0:
        return {"ok": false, "reason": "zero projection scale"}
    var native_pos: Vector2 = Vector2(float(native["x"]), float(native["y"]))
    return {"ok": true, "position": origin_godot + (native_pos - origin_native) * scale_xy,
        "native_world_x": int(native["x"]), "native_world_y": int(native["y"]),
        "source": "client_region_plus_explicit_projection"}

# Integer fixed-point travel as seen in game.exe missile math; the caller must
# provide an authoritative speed/tick scale for this to represent native motion.
static func delta_fixed1024(x_factor: int, y_factor: int, step_native: int) -> Vector2i:
    return Vector2i((x_factor * step_native) >> 10, (y_factor * step_native) >> 10)


# A camera projection MUST be explicitly present when any native-world position
# is offered. Used to reject partial packets atomically in V9 visual bridge.
static func has_any_native_position_field(data: Dictionary) -> bool:
    for key in ["godot_world_x", "godot_world_y", "region_index", "region_count",
            "region_base_x", "region_base_y", "grid_x", "grid_y",
            "off_x_fixed", "off_y_fixed", "projection_basis_xx", "projection_scale_x"]:
        if data.has(key):
            return true
    return false

# Recover an axis-agnostic 2D affine mapping from THREE non-collinear matched
# native-world and Godot-world points. This is a measured coordinate mapping,
# not a guessed projection for the user's original JX1 map.
# Native anchors: (native_a,b,c), Godot anchors: (godot_a,b,c).
static func calibrate_three_points(native_a: Vector2, native_b: Vector2, native_c: Vector2,
        godot_a: Vector2, godot_b: Vector2, godot_c: Vector2) -> Dictionary:
    var u: Vector2 = native_b - native_a
    var v: Vector2 = native_c - native_a
    var det: float = u.x * v.y - u.y * v.x
    if absf(det) < 0.000001:
        return {"ok": false, "reason": "native anchors collinear"}
    var p: Vector2 = godot_b - godot_a
    var q: Vector2 = godot_c - godot_a
    var xx: float = (p.x * v.y - q.x * u.y) / det
    var xy: float = (q.x * u.x - p.x * v.x) / det
    var yx: float = (p.y * v.y - q.y * u.y) / det
    var yy: float = (q.y * u.x - p.y * v.x) / det
    return {"ok": true,
        "projection_native_origin_x": native_a.x,
        "projection_native_origin_y": native_a.y,
        "projection_godot_origin_x": godot_a.x,
        "projection_godot_origin_y": godot_a.y,
        "projection_basis_xx": xx, "projection_basis_xy": xy,
        "projection_basis_yx": yx, "projection_basis_yy": yy}
