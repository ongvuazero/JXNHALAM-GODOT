extends RefCounted
## Source-derived client SPR weapon-layer bounding boxes for 325 AT06/AT07.
## An approximate attachment point ONLY: the metadata lacks pixel-level hammer
## head classification, so we use each weapon layer's farthest bbox corner.
## Not a JX1-tested VFX offset. No changes to damage or missile physics.
const PATH: String = "res://data/renderer_audit/v4223_hammer_swing_bbox_anchors.json"
var actions: Dictionary = {}
var source_ok: bool = false

func _init() -> void:
    if not FileAccess.file_exists(PATH):
        return
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
    if raw is Dictionary and str(raw.get("format", "")) == "jxnhalam.v4223_hammer_original_weapon_bbox_anchors":
        actions = raw.get("actions", {})
        source_ok = not actions.is_empty()

func sample(action: int, face: int, phase: float, visual_channel: int) -> Vector2:
    var action_rows: Dictionary = actions.get(str(action), {})
    var rows: Array = action_rows.get(str(posmod(face, 8)), [])
    if rows.size() != 4:
        return Vector2.ZERO
    var p: float = clampf(phase, 0.0, 3.0)
    var i: int = floori(p)
    var next: int = mini(i + 1, rows.size() - 1)
    var ch: int = clampi(visual_channel, 0, 2)
    var now: Array = rows[i][ch]
    var later: Array = rows[next][ch]
    if now.size() != 2 or later.size() != 2:
        return Vector2.ZERO
    return Vector2(float(now[0]),float(now[1])).lerp(
        Vector2(float(later[0]),float(later[1])),p-float(i))
