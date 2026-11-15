extends SceneTree
## Optional check of an EXTERNAL real client without copying PAK files:
## 1. put absolute original client path in client_root.txt beside project.godot
## 2. godot --headless --path . -s res://tests/TestRealPak.gd
const PAK = preload("res://scripts/JXVirtualFS.gd")
func _initialize() -> void:
    var root: String = ""
    if FileAccess.file_exists("res://client_root.txt"):
        root = FileAccess.get_file_as_string("res://client_root.txt").strip_edges().replace("\\", "/")
    if root.is_empty():
        print("SKIP: create client_root.txt pointing to original JX client")
        quit(0)
        return
    var fs = PAK.new()
    fs.configure(root)
    print(fs.describe())
    var found_count: int = 0
    for path in ["\\spr\\skill\\1502\\tw\\tw_150_qiangtian_zd.spr", "\\spr\\skill\\1502\\tw\\tw_150_qiangtian_bz.spr"]:
        var info: Dictionary = fs.locate(path)
        print(path, " ", info)
        if bool(info.get("found", false)):
            found_count += 1
    print("REAL PAK HASH-LOOKUP COUNT: ", found_count, "/2. Content decode may vary.")
    quit(0)
