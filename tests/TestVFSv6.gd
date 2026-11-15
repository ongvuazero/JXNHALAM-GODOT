extends SceneTree
const PAK = preload("res://scripts/JXVirtualFS.gd")
const SPR = preload("res://scripts/JXSPRCodec.gd")

func _initialize() -> void:
    var errors: Array[String] = []
    var fs = PAK.new()
    fs.configure()
    if not fs.open_pak("res://tests/fixtures/DEMO_FRAME_PACKED.pak"):
        errors.append("FRAME_PACKED: open failed")
    else:
        var reconstructed: PackedByteArray = fs.read_bytes("\\spr\\demo_framepacked.spr")
        var expected: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/DEMO_SPR_CANONICAL.bin")
        if reconstructed != expected:
            errors.append("FRAME_PACKED: reconstructed original SPR differs")
        var decoded: Dictionary = SPR.new().decode_atlas(reconstructed)
        if decoded.is_empty() or int(decoded.get("frames_per_direction", 0)) != 2:
            errors.append("FRAME_PACKED: sprite decode failed")
    # Regression: client SPR 17 frames / 16 dirs, last is transparent 1x1.
    var padded: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/DEMO_SPR_17FRAME_SENTINEL.bin")
    var padded_atlas: Dictionary = SPR.new().decode_atlas(padded)
    if padded_atlas.is_empty():
        errors.append("SPR_SENTINEL: 17/16 asset rejected")
    elif int(padded_atlas.get("directions", 0)) != 16 or int(padded_atlas.get("frames_per_direction", 0)) != 1 or int(padded_atlas.get("ignored_padding_frames", 0)) != 1:
        errors.append("SPR_SENTINEL: incorrect 16-direction padding handling")
    var root: String = ProjectSettings.globalize_path("res://tests/fixtures/priority_client")
    var ordered = PAK.new()
    ordered.configure(root)
    var actual: String = ordered.read_bytes("\\settings\\priority.ini").get_string_from_ascii()
    if actual != "PRIORITY_LOOSE_OVER_PAK":
        errors.append("LOOSE_PRIORITY: expected loose override, got " + actual)
    # Temporarily read from a PAK without loose folder by querying private
    # _extract in package.ini order. KPakList uses the FIRST matching PAK.
    var h: int = ordered.path_hash("\\settings\\priority.ini")
    if ordered.archives.size() < 2:
        errors.append("PACKAGE_INI: expected two PAKs")
    else:
        var first: String = ordered._extract(ordered.archives[0], h).get_string_from_ascii()
        var second: String = ordered._extract(ordered.archives[1], h).get_string_from_ascii()
        if first != "PRIORITY_PATCH_0" or second != "PRIORITY_BASE_1":
            errors.append("PACKAGE_INI: wrong archive order")
    if errors.is_empty():
        print("V6.1 TEST PASS: FRAME_PACKED_SPR, SPR_SENTINEL_17_16, PAK order, loose precedence")
        quit(0)
    else:
        for issue in errors:
            push_error(issue)
        quit(1)
