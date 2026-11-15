extends RefCounted
## Safe, deterministic evaluation of piecewise numeric data extracted from
## source Lua tables. This is NOT a general-purpose Lua VM or a damage formula.
## Only plain numeric series with points_in_source_order are supported.

static func interpolate(points: Array, mastery_level: int) -> float:
    var ordered: Array[Vector2] = []
    for pair in points:
        if pair is Array and pair.size() == 2:
            ordered.append(Vector2(float(pair[0]), float(pair[1])))
    if ordered.is_empty():
        return 0.0
    ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    if mastery_level <= ordered[0].x:
        return ordered[0].y
    for i in range(1, ordered.size()):
        var hi: Vector2 = ordered[i]
        if mastery_level <= hi.x:
            var lo: Vector2 = ordered[i - 1]
            var part: float = float(mastery_level - lo.x) / maxf(1.0, hi.x - lo.x)
            return lerpf(lo.y, hi.y, part)
    return ordered[ordered.size() - 1].y

static func evaluate(table: Dictionary, mastery_level: int) -> Dictionary:
    var output: Dictionary = {}
    var properties: Dictionary = table.get("properties", {})
    for key in properties.keys():
        var info: Variant = properties[key]
        if not info is Dictionary:
            continue
        var points: Variant = info.get("points_in_source_order", [])
        if points is Array and not points.is_empty():
            output[str(key)] = interpolate(points, mastery_level)
    return output
