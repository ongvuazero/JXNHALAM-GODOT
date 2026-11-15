extends Control
## V26: visualize ORIGINAL 320x320 source-SPR frame bounding rectangles.
## This is NOT a layered compositor: only the bbox metadata is present.
var layers: Array = []
var direction_index: int = 6
var frame_index: int = 0
var frames_per_direction: int = 16
var show_boxes: bool = true
var selected_layer_index: int = -1 # -1: show all

func update_from_profile(profile: Dictionary, dir_index: int, frame: int) -> void:
    layers = profile.get("layers", [])
    direction_index = dir_index
    frame_index = frame
    frames_per_direction = int(profile.get("frames_per_dir", 1))
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(0, 0, 320, 320), Color("#162830"), true)
    for n in range(0, 321, 40):
        draw_line(Vector2(n, 0), Vector2(n, 320), Color(0.50, 0.65, 0.69, 0.12))
        draw_line(Vector2(0, n), Vector2(320, n), Color(0.50, 0.65, 0.69, 0.12))
    draw_rect(Rect2(0, 0, 320, 320), Color(0.6, 0.7, 0.74, 0.6), false, 1.0)
    if not show_boxes:
        return
    var flat_index: int = direction_index * frames_per_direction + frame_index
    for i in range(layers.size()):
        if selected_layer_index != -1 and selected_layer_index != i:
            continue
        var layer: Dictionary = layers[i]
        var source: Array = layer.get("frame_offsets_xywh", [])
        if flat_index < 0 or flat_index >= source.size():
            continue
        var coords: Array = source[flat_index]
        if coords.size() != 4:
            continue
        var region: Rect2 = Rect2(float(coords[0]), float(coords[1]), float(coords[2]), float(coords[3]))
        if region.size.x <= 0 or region.size.y <= 0:
            continue
        var color: Color = Color(str(layer.get("color", "#ffffff")))
        draw_rect(region, Color(color.r, color.g, color.b, 0.08), true)
        draw_rect(region, color, false, 1.5)
