extends SceneTree
## Explicit diagnostic only. Does not edit PAKs, project files, or client_root.txt.
## Uses the same ClientAssetResolver that gameplay uses.
const READER = preload("res://scripts/ClientAssetResolver.gd")
const GRAPH = preload("res://scripts/JXLuaEventVFX.gd")
const OUTPUT: String = "user://JXNHALAM_V443_LUA_STAGE_PAK_AUDIT.csv"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var root_path: String = ""
    if FileAccess.file_exists("res://client_root.txt"):
        root_path = FileAccess.get_file_as_string("res://client_root.txt").strip_edges().replace("\\", "/")
        root_path = root_path.trim_prefix('"').trim_suffix('"')
    var resolver: RefCounted = READER.new()
    resolver.call("setup", root_path)
    var graph: Dictionary = GRAPH.load_graph_cached()
    var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
    if file == null:
        push_error("V44.3: cannot write Lua stage CSV at user://")
        quit(2)
        return
    file.store_csv_line(PackedStringArray([
        "skill_id", "source_type", "lua_source", "move_kind", "stage",
        "declared_spr", "pak_status", "hash_mode", "original_frames",
        "directions", "source_path", "notes"
    ]))
    var selected: Dictionary = {}
    var linked: Dictionary = {}
    for k in graph.keys():
        var row: Dictionary = graph[k]
        if bool(row.get("is_selected_combat_skill", false)):
            selected[k] = true
            for event in row.get("event_levels", {}).get("20", []):
                linked[str(event.get("skill_id", ""))] = true
    var keys: Array = graph.keys()
    keys.sort()
    var success: int = 0
    var missing: int = 0
    var no_stage: int = 0
    var count: int = 0
    for k in keys:
        var skill: Dictionary = graph[k]
        var paths: Array = skill.get("anim_paths", [])
        var precast: String = str(skill.get("precast_spr", ""))
        if precast.is_empty() and paths.size() > 0:
            precast = str(paths[0])
        var stages: Dictionary = {
            "precast": precast,
            "fly": str(paths[1]) if paths.size() > 1 else "",
            "travel_end": str(paths[2]) if paths.size() > 2 else "",
            "hit": str(paths[3]) if paths.size() > 3 else ""
        }
        var kind: String = "selected" if selected.has(k) else "linked" if linked.has(k) else "graph_only"
        for role in ["precast", "fly", "travel_end", "hit"]:
            var path: String = str(stages[role])
            var result: Dictionary = {}
            var state: String = "UNDECLARED"
            if path.is_empty():
                no_stage += 1
            else:
                result = resolver.call("probe_spr", path)
                state = str(result.get("status", "UNKNOWN"))
                if state.begins_with("OK_SPR_"):
                    success += 1
                else:
                    missing += 1
            count += 1
            file.store_csv_line(PackedStringArray([
                k, kind, str(skill.get("lua_script", "")), str(skill.get("move_kind", -1)),
                role, path, state, str(result.get("hash_mode", "")),
                str(result.get("frames", 0)), str(result.get("directions", 0)),
                str(result.get("source", "")),
                "No native timing/scale claim; a PAK hit only proves SPR decode"
            ]))
    file.close()
    print("V44.3 LUA PAK AUDIT | graph nodes=", graph.size(), " | rows=", count,
        " | SPR decoded=", success, " | missing=", missing,
        " | stage undefined=", no_stage)
    print("CSV: ", ProjectSettings.globalize_path(OUTPUT))
    quit(0)
