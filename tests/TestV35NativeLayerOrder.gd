extends SceneTree
## godot --headless --path Godot_Project --script res://tests/TestV35NativeLayerOrder.gd
const RULES = preload("res://scripts/V35NativeLayerOrder.gd")

func _initialize() -> void:
    var resolver = RULES.new()
    if not resolver.load_verified_table():
        push_error("V35 missing/bad verified source table: " + resolver.warning_text)
        quit(1)
        return
    var cases: Array = [
        ["MeleeWCut", 6, 5, 14, [4, 1, 0, 3, 2, 5]], # E/6 frame89 -> DEFAULT Dir7
        ["MeleeWCut", 0, 5, 14, [2, 0, 1, 5, 4, 3]], # Line5 global selector 5
        ["MeleeWCut", 4, 6, 14, [5, 4, 1, 0, 3, 2]], # global selector 62
        ["MeleeWPuncture", 0, 0, 16, [2, 0, 1, 4, 3, 5]],
        ["MeleeWPuncture", 4, 8, 16, [5, 4, 1, 0, 3, 2]], # global 72
    ]
    for test in cases:
        var observed: Array[int] = resolver.order_for(str(test[0]), int(test[1]), int(test[2]), int(test[3]))
        var expected: Array = test[4]
        if observed != expected:
            push_error("V35 incorrect order for %s dir=%d frame=%d: %s != %s" % [test[0], test[1], test[2], str(observed), str(expected)])
            quit(1)
            return
    for action in ["MeleeWCut", "MeleeWPuncture"]:
        var count: int = 14 if action == "MeleeWCut" else 16
        for d in range(8):
            for f in range(count):
                var order: Array[int] = resolver.order_for(action, d, f, count)
                if order.size() != 6:
                    push_error("V35 invalid six-part order %s/%d/%d" % [action, d, f])
                    quit(1)
                    return
    print("V35 PASS: source table 8 dirs + 112 AT03 & 128 AT02 frame selectors; six-part painter order")
    quit(0)
