extends SceneTree
const FX = preload("res://scripts/SkillEffect.gd")
const BRIDGE = preload("res://scripts/BaselineDataBridge.gd")
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var errors: Array[String] = []
    var bridge = BRIDGE.new()
    if not bridge.load_client_data():
        errors.append("CTC baseline not loaded")
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sects/thien_vuong.json"))
    var sect: Dictionary = bridge.inject_client_skills(raw)
    var w: Array = sect.get("weapons", [])
    var expected: Array[int] = [322,323,325]
    if w.size()!=3:
        errors.append("expected three weapon slots")
    for i in range(mini(3,w.size())):
        var s: Dictionary = w[i]["skills"][0]
        if int(s.get("legacy_skill_id",0))!=expected[i]:
            errors.append("wrong skill index %d" % i)
        if str(s.get("combat_delivery",""))!="melee_attached":
            errors.append("9x skill must be melee")
        if str(s.get("id","")).contains("150"):
            errors.append("150 slot detected")
        if int(s.get("mana_cost_preview",-1))!=[15,10,10][i]:
            errors.append("mana curve mismatch %d" % i)
    var actor:=CharacterBody2D.new()
    actor.position=Vector2(100,300)
    root.add_child(actor)
    var practice:=StaticBody2D.new()
    practice.position=Vector2(400,300)
    root.add_child(practice)
    var fx:=Node2D.new()
    fx.set_script(FX)
    root.add_child(fx)
    await process_frame
    var active: Dictionary = w[1]["skills"][0] if w.size()>1 else {}
    fx.call("setup", actor,practice,Vector2(400,255),active,6,null,true)
    fx._process(0.5)
    var st: String = str(fx.call("get_diagnostic").get("stage",""))
    if st != "hit":
        errors.append("melee attack expected hit stage, got "+st)
    if fx.global_position.distance_to(actor.global_position)>150.0:
        errors.append("melee effect moved too far from caster")
    if errors.is_empty():
        print("V6.4 9X PASS: 322/323/325, curves, melee contact, no 150")
        quit(0)
    else:
        for e in errors: push_error(e)
        quit(1)
