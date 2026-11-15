extends SceneTree
## Run from Godot 4.6: godot --headless --path Godot_Project --script res://tests/TestV33ActionSelector.gd
const SELECTOR = preload("res://scripts/V33JX322ActionSelector.gd")

func _initialize() -> void:
    var cases: Array = [
        [0, 0, 10],  # random=0 -> action 10
        [1, 0, 9],   # random=1 -> action 9
        [-1, 1, 9],  # Y QA force AT03
        [-1, 2, 10]  # Y QA force AT02
    ]
    for c in cases:
        var actual: int = int(SELECTOR.resolve_action(int(c[0]), int(c[1])))
        if actual != int(c[2]):
            push_error("V33 ACTION FAIL: %s => %d" % [str(c), actual])
            quit(1)
            return
    print("V33 ACTION PASS: random 0/1 and two QA overrides (4 cases)")
    quit(0)
