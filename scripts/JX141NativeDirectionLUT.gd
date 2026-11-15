extends RefCounted
## JXNHALAM M141 Native Direction V4 (NO class_name)
## Exact 64-dir integer lookup taken from game.exe, pointers 0x68523C (X) and 0x685238 (Y).
## LUT alone is NOT the per-instance x_factor/y_factor on every server trace.
## When supplied at allocation, runtime x_factor/y_factor always takes precedence.
const X_FACTORS = [
        0,  -100,  -199,  -297,  -391,  -482,  -568,  -649,
     -724,  -791,  -851,  -903,  -946,  -979, -1004, -1019,
    -1024, -1019, -1004,  -979,  -946,  -903,  -851,  -791,
     -724,  -649,  -568,  -482,  -391,  -297,  -199,  -100,
        0,   100,   199,   297,   391,   482,   568,   649,
      724,   791,   851,   903,   946,   979,  1004,  1019,
     1024,  1019,  1004,   979,   946,   903,   851,   791,
      724,   649,   568,   482,   391,   297,   199,   100
]
const Y_FACTORS = [
     1024,  1019,  1004,   979,   946,   903,   851,   791,
      724,   649,   568,   482,   391,   297,   199,   100,
        0,  -100,  -199,  -297,  -391,  -482,  -568,  -649,
     -724,  -791,  -851,  -903,  -946,  -979, -1004, -1019,
    -1024, -1019, -1004,  -979,  -946,  -903,  -851,  -791,
     -724,  -649,  -568,  -482,  -391,  -297,  -199,  -100,
        0,   100,   199,   297,   391,   482,   568,   649,
      724,   791,   851,   903,   946,   979,  1004,  1019
]

static func native_lut(dir64: int) -> Vector2i:
    var d: int = posmod(dir64, 64)
    return Vector2i(int(X_FACTORS[d]), int(Y_FACTORS[d]))

static func direction_from_factors(x_factor: int, y_factor: int) -> int:
    # Recovered client algorithm: sub_566380, integer Y/length projection
    # against 0..32 of the original fixed-point cosine lookup table.
    # Do not call for unknown/zero input. No atan2/float sector rounding.
    if x_factor == 0 and y_factor == 0:
        return -1
    var dx: float = float(x_factor)
    var dy: float = float(y_factor)
    var length: float = sqrt(dx * dx + dy * dy)
    var ratio: int = int(dy * 1024.0 / length) # signed integer truncation
    var sector: int = 0
    var error: int = absi(int(Y_FACTORS[0]) - ratio)
    for i in range(1, 33):
        var candidate: int = absi(int(Y_FACTORS[i]) - ratio)
        if candidate < error:
            error = candidate
            sector = i
    if x_factor >= 0:
        return posmod(64 - sector, 64)
    return sector

static func resolve(dir64: int, event: Dictionary) -> Dictionary:
    var v: Vector2i = native_lut(dir64)
    var source: String = "client_exe_64dir_lut"
    # This takes priority even when it differs from the coarse 64-direction label.
    if event.has("native_x_factor") and event.has("native_y_factor"):
        v = Vector2i(int(event["native_x_factor"]), int(event["native_y_factor"]))
        source = "runtime_native_x_y"
    elif event.has("x_factor") and event.has("y_factor"):
        v = Vector2i(int(event["x_factor"]), int(event["y_factor"]))
        source = "runtime_x_y"
    if v.x == 0 and v.y == 0:
        return {"ok": false, "source": source, "reason": "zero_vector", "dir64": posmod(dir64, 64)}
    return {"ok": true, "source": source, "dir64": posmod(dir64, 64),
        "x_factor": v.x, "y_factor": v.y,
        "factor_dir64": direction_from_factors(v.x, v.y),
        "unit": Vector2(float(v.x), float(v.y)).normalized(),
        "position_parity_verified": false}

# V5 - Geometry-derived fixed-point factors for 2D positions.
# Base rule documented by game.exe 0x5EBC10 and 0x5B38F0:
#     factor_x = trunc((target_x - origin_x) * 1024 / integer_length)
#     factor_y = trunc((target_y - origin_y) * 1024 / integer_length)
# Exact Form 2 sub-target construction is still not fully recovered; offsets
# for 3 allocations below are TRACE-BASED and labelled as such.
static func normalize_delta_1024(delta: Vector2) -> Dictionary:
    var dx: int = roundi(delta.x)
    var dy: int = roundi(delta.y)
    var squared: int = dx * dx + dy * dy
    if squared <= 0:
        return {"ok": false, "reason": "zero_source_to_target"}
    # Reverse-engineered engine uses float sqrt then int conversion.  Small
    # rounding-edge behavior is not yet verified for all possible inputs.
    var distance: int = maxi(1, int(sqrt(float(squared))))
    return {"ok": true, "x_factor": int(float(dx * 1024) / float(distance)),
        "y_factor": int(float(dy * 1024) / float(distance)),
        "distance_raw": distance, "source": "source_target_fixed1024"}

static func rotate_fixed1024(base: Vector2i, delta_dir64: int) -> Vector2i:
    var offset: Vector2i = native_lut(delta_dir64)
    # x' = (x*cos + y*(-sin)); y' = (y*cos - x*(-sin))
    return Vector2i(int(float(base.x * offset.y + base.y * offset.x) / 1024.0),
        int(float(base.y * offset.y - base.x * offset.x) / 1024.0))

static func resolve_from_geometry(dir64: int, event: Dictionary,
        origin: Vector2, aimed_target: Vector2) -> Dictionary:
    # Explicit runtime factors are AUTHORITATIVE when available.
    if (event.has("native_x_factor") and event.has("native_y_factor")) or (event.has("x_factor") and event.has("y_factor")):
        return resolve(dir64, event)
    # JXNHALAM V8: optional native cast-center factors from authoritative trace.
    # This is a FIXED-POINT rotation model, not a claim about the final integer
    # rounding of the client's individual sub-target normalization.
    # Measured: 46/46 native parent casts have dir center-8, center, center+8;
    # rotation predicts 92 side factors within 1/1024 of captured values.
    # If the caller supplies the individual per-instance factors, the early
    # resolve(...) above is always used instead (zero approximation).
    var sub_count_native: int = int(event.get("sub_count", 1))
    var sub_index_native: int = int(event.get("sub_index", 0))
    if (sub_count_native == 3 and sub_index_native >= 0 and sub_index_native < 3
            and event.has("native_cast_center_x_factor")
            and event.has("native_cast_center_y_factor")):
        var native_center := Vector2i(int(event["native_cast_center_x_factor"]),
            int(event["native_cast_center_y_factor"]))
        if native_center != Vector2i.ZERO:
            var rotated: Vector2i = rotate_fixed1024(native_center, (sub_index_native - 1) * 8)
            return {"ok": true, "source": "native_center_fixed_rotation_approx",
                "dir64": posmod(dir64, 64),
                "factor_dir64": direction_from_factors(rotated.x, rotated.y),
                "x_factor": rotated.x, "y_factor": rotated.y,
                "unit": Vector2(rotated).normalized(),
                "side_factor_rounding_max_trace_error": 1,
                "side_factor_rounding_exact": false,
                "form2_per_instance_generation_verified": false,
                "position_parity_verified": false}
    var delta: Vector2 = aimed_target - origin
    if event.has("native_source_x") and event.has("native_source_y") and event.has("native_target_x") and event.has("native_target_y"):
        delta = Vector2(float(event["native_target_x"]) - float(event["native_source_x"]),
            float(event["native_target_y"]) - float(event["native_source_y"]))
    var base: Dictionary = normalize_delta_1024(delta)
    if not bool(base.get("ok", false)):
        return resolve(dir64, {})
    var sub_count: int = int(event.get("sub_count", 1))
    var sub_index: int = int(event.get("sub_index", 0))
    # -8 / 0 / +8 was observed in all 46 M141 parent casts in server log V4.
    # Exact sub-target coordinates and last-unit integer rounding remain unknown.
    var delta_dir64: int = 0
    if sub_count == 3:
        delta_dir64 = (sub_index - 1) * 8
    var factors: Vector2i = rotate_fixed1024(Vector2i(int(base["x_factor"]), int(base["y_factor"])), delta_dir64)
    if factors == Vector2i.ZERO:
        return resolve(dir64, {})
    var computed_dir: int = direction_from_factors(factors.x, factors.y)
    return {"ok": true, "source": "form2_geometry_preview_fixed1024",
        "dir64": posmod(dir64, 64), "factor_dir64": computed_dir,
        "x_factor": factors.x, "y_factor": factors.y,
        "unit": Vector2(float(factors.x), float(factors.y)).normalized(),
        "position_parity_verified": false,
        "form2_per_instance_generation_verified": false}

# Static parity helper; useful for feeding captured JX1 traces without Godot
# world coordinates or a camera. Each result is a fixed-point vector pair.
static func form2_triplet_from_center(center_x_factor: int, center_y_factor: int) -> Array[Vector2i]:
    var mid := Vector2i(center_x_factor, center_y_factor)
    var trio: Array[Vector2i] = []
    for offset64 in [-8, 0, 8]:
        trio.append(rotate_fixed1024(mid, offset64))
    return trio

# Non-invasive trace comparison: zero error for center, ±1 factor unit for
# all 92 side vectors in the 46 server casts inspected on 2026-11-13.
# 'expected' must be 3 actual Vector2i pairs ordered by MISSILE_FLY life=0.
static func compare_form2_trace(expected: Array[Vector2i]) -> Dictionary:
    if expected.size() != 3:
        return {"ok": false, "reason": "expected three server vectors"}
    var predicted: Array[Vector2i] = form2_triplet_from_center(expected[1].x, expected[1].y)
    var max_error: int = 0
    var errors: Array[Vector2i] = []
    for i in range(3):
        var diff: Vector2i = expected[i] - predicted[i]
        errors.append(diff)
        max_error = maxi(max_error, maxi(absi(diff.x), absi(diff.y)))
    return {"ok": true, "predicted": predicted, "errors": errors,
        "maximum_fixed1024_error": max_error,
        "exact_integer_parity": max_error == 0}
