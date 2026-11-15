extends SceneTree
const FX = preload("res://scripts/SkillEffect.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var actor := CharacterBody2D.new()
    actor.position = Vector2(100, 300)
    root.add_child(actor)
    var practice := StaticBody2D.new()
    practice.position = Vector2(400, 300)
    root.add_child(practice)
    var fx := Node2D.new()
    fx.name = "SkillEffect_Preview_Test"
    fx.set_script(FX)
    root.add_child(fx)
    await process_frame
    var data: Dictionary = {"id":"TEST_SPEAR", "release_ms":100,
        "fly_speed":500, "hit_ms":200, "end_ms":100,
        "socket_y":-45, "vfx":{"fly":"tw_150_qiangtian_zd", "hit":"tw_150_qiangtian_bz"}}
    fx.call("setup",actor,practice,Vector2(400,255),data,6,null,true)
    var errors: Array[String] = []
    if str(fx.call("get_diagnostic").get("stage", "")) != "cast":
        errors.append("initial stage not cast")
    fx._process(0.11)
    if str(fx.call("get_diagnostic").get("stage", "")) != "fly":
        errors.append("release did not enter fly stage")
    fx._process(2.0)
    if str(fx.call("get_diagnostic").get("stage", "")) != "hit":
        errors.append("flight did not enter impact stage")
    fx._process(0.5)
    if str(fx.call("get_diagnostic").get("stage", "")) != "end":
        errors.append("impact did not switch to fade stage")
    if not bool(fx.call("get_diagnostic").get("preview_only", false)):
        errors.append("diagnostic must never damage target")
    if errors.is_empty():
        print("V6.3 TEST PASS: casting, flight, impact, preview-only, fade")
        quit(0)
    else:
        for error in errors:
            push_error(error)
        quit(1)
