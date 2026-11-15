extends RefCounted
## V35 - Original ActionRenderOrderTab resolver recovered from game.exe V11.
## Source: settings/npcres/男主角贴图顺序表.txt. No heuristic sorting.
## FUN_005C6300 -> FUN_005B0340 -> FUN_005AFBE0:
## First integer in a LineN is exact global SPR frame selector; remainder is
## ordered part IDs. Missing Line -> action DirN -> DEFAULT DirN.
## In this project only six known raw SPR layers are present. Other native part
## slots (hair/shoulder/mantle/horse) are intentionally skipped, not invented.
const TABLE_PATH: String = "res://data/renderer_audit/v35_native_layer_order.json"
const SIX_ID_TO_LAYER: Dictionary = {0: 3, 5: 0, 6: 1, 7: 2, 8: 4, 9: 5}
var table: Dictionary = {}
var warning_text: String = ""

func load_verified_table() -> bool:
    if not FileAccess.file_exists(TABLE_PATH):
        warning_text = "MISSING_V35_NATIVE_ORDER"
        return false
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
    if not decoded is Dictionary:
        warning_text = "BAD_V35_ORDER_JSON"
        return false
    table = decoded
    if str(table.get("format", "")) != "JXNHALAM_V35_ACTION_RENDER_ORDER":
        warning_text = "BAD_V35_ORDER_FORMAT"
        table.clear()
        return false
    for action in ["MeleeWCut", "MeleeWPuncture"]:
        var frames_per_dir: int = 14 if action == "MeleeWCut" else 16
        for d in range(8):
            for f in range(frames_per_dir):
                if _resolve_unchecked(action, d, f, frames_per_dir).size() != 6:
                    warning_text = "INVALID_ORDER_%s_%d_%d" % [action, d, f]
                    table.clear()
                    return false
    return true

func order_for(action: String, direction: int, frame: int, frames_per_dir: int) -> Array[int]:
    if table.is_empty() or direction < 0 or direction >= 8 or frame < 0 or frame >= frames_per_dir:
        return []
    return _resolve_unchecked(action, direction, frame, frames_per_dir)

func _resolve_unchecked(action: String, direction: int, frame: int, frames_per_dir: int) -> Array[int]:
    var defaults: Dictionary = table.get("default_directions", {})
    var actions: Dictionary = table.get("actions", {})
    var config: Dictionary = actions.get(action, {})
    var direction_key: String = str(direction)
    var order_ids: Array = defaults.get(direction_key, [])
    var dir_rows: Dictionary = config.get("direction_overrides", {})
    if dir_rows.has(direction_key):
        order_ids = dir_rows[direction_key]
    var line_rows: Dictionary = config.get("frame_overrides", {})
    var global_source_frame: int = direction * frames_per_dir + frame
    if line_rows.has(str(global_source_frame)):
        order_ids = line_rows[str(global_source_frame)]
    var result: Array[int] = []
    for raw_id in order_ids:
        var native_id: int = int(raw_id)
        if SIX_ID_TO_LAYER.has(native_id):
            var layer_index: int = int(SIX_ID_TO_LAYER[native_id])
            if result.has(layer_index):
                return []
            result.append(layer_index)
    if result.size() != 6:
        return []
    return result
