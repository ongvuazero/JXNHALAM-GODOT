extends SceneTree
## Godot 4 command-line verification:
## godot --headless --path . -s res://tests/TestVFS.gd
const PAK = preload("res://scripts/JXVirtualFS.gd")
const SPR = preload("res://scripts/JXSPRCodec.gd")
const CURVES = preload("res://scripts/CTCCurveEvaluator.gd")

func _initialize() -> void:
    var errors: Array[String] = []
    var fs = PAK.new()
    fs.configure()
    var demo_path: String = "res://tests/fixtures/DEMO_JX_PACK.pak"
    if not fs.open_pak(demo_path):
        errors.append("Cannot open demo PAK")
    else:
        for path in ["\\settings\\demo.ini", "\\script\\demo.lua", "\\spr\\demo.spr"]:
            var info: Dictionary = fs.locate(path)
            if not bool(info.get("found", false)):
                errors.append("Hash not found: " + path)
                continue
            var raw: PackedByteArray = fs.read_bytes(path)
            if raw.is_empty():
                errors.append("Decode failed: " + path)
        var encoded: PackedByteArray = fs.read_bytes("\\spr\\demo.spr")
        var result: Dictionary = SPR.new().decode_atlas(encoded)
        if result.is_empty():
            errors.append("SPR decoder rejected demo sprite")
        else:
            print("SPR: %s directions, %s frames/dir" % [str(result.get("directions", 0)), str(result.get("frames_per_direction", 0))])
    var override_fs = PAK.new()
    override_fs.configure(ProjectSettings.globalize_path("res://tests/fixtures/loose"))
    override_fs.open_pak(demo_path)
    var got: String = override_fs.read_bytes("\\settings\\demo.ini").get_string_from_ascii()
    if not got.contains("LOOSE_OVERRIDES_PAK"):
        errors.append("Loose file priority regression")
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/baseline/lua_knots_TV_level150.json"))
    var knots: Dictionary = parsed if parsed is Dictionary else {}
    var sample: Dictionary = CURVES.evaluate(knots.get("1060", {}), 1)
    if int(sample.get("skill_cost_v", -1)) != 12:
        errors.append("CTC Lua cost 1060 @ skill-level 1 should equal 12")
    var sample_20: Dictionary = CURVES.evaluate(knots.get("1060", {}), 20)
    if int(sample_20.get("skill_cost_v", -1)) != 80:
        errors.append("CTC Lua cost 1060 @ skill-level 20 should equal 80")
    if errors.is_empty():
        print("V5 TEST PASS: PAK INDEX + SPR DECODE + CTC CURVE")
        quit(0)
    else:
        for e in errors:
            push_error(e)
        quit(1)
