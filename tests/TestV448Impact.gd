extends SceneTree
const IMPACT = preload("res://scripts/JXSpecialImpactVFX.gd")
const MOTION = preload("res://scripts/JXMissileMotion.gd")

func _initialize() -> void:
    var fails: Array[String] = []
    if not MOTION.segment_hits_circle(Vector2.ZERO, Vector2(100,0), Vector2(60,0), 6.0):
        fails.append("segment crossing")
    if MOTION.segment_hits_circle(Vector2.ZERO, Vector2(100,0), Vector2(60,30), 6.0):
        fails.append("segment must miss distant target")
    var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    image.fill(Color.WHITE)
    var texture := ImageTexture.create_from_image(image)
    var src := {"hit": {"texture": texture,"directions": 1,"frames_per_direction": 1,"tile_size":32}}
    var effect := Node2D.new()
    effect.set_script(IMPACT)
    root.add_child(effect)
    effect.call("setup",src,{"original_anim_info":{}},Vector2(85,30),Vector2.RIGHT,null)
    if effect.global_position != Vector2(85,30): fails.append("impact world origin")
    if str(effect.get("stage")) != "hit": fails.append("impact stage")
    effect.call("_process", 0.2)
    if not effect.is_queued_for_deletion(): fails.append("impact cleanup")
    if fails.is_empty():
        print("V44.8 IMPACT QA PASS: per-contact SPR position, stage, expiry and collision geometry")
        quit(0)
    else:
        printerr("V44.8 IMPACT QA FAIL: ",fails)
        quit(1)
