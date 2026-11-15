extends Node2D
## V31 visual QA: source BODY BBOX and 320x320 canvas center.
## BBOX bottom is NOT a measured anatomical foot or verified JX1 anchor.
var body_xywh: Array = []
var show_guides: bool = true

func update_bbox(coords: Array, show_markers: bool) -> void:
    body_xywh = coords.duplicate()
    show_guides = show_markers
    queue_redraw()

func _draw() -> void:
    if not show_guides or body_xywh.size() != 4:
        return
    var center_color: Color = Color(0.40, 0.80, 0.94, 0.60)
    var bbox_color: Color = Color(1.0, 0.75, 0.26, 0.90)
    # Sprite2D centered, source canvas=320. All points transformed into local
    # -160..160 coordinates; never move the gameplay actor or its collision.
    draw_line(Vector2(-37, 0), Vector2(37, 0), center_color, 1.0)
    draw_line(Vector2(0, -37), Vector2(0, 37), center_color, 1.0)
    var box: Rect2 = Rect2(float(body_xywh[0]) - 160.0, float(body_xywh[1]) - 160.0,
        float(body_xywh[2]), float(body_xywh[3]))
    draw_rect(box, bbox_color, false, 1.0)
    var bottom_center: Vector2 = Vector2(box.position.x + box.size.x * 0.5, box.end.y)
    draw_line(bottom_center + Vector2(-21, 0), bottom_center + Vector2(21, 0), bbox_color, 2.0)
    draw_line(bottom_center + Vector2(0, -12), bottom_center + Vector2(0, 12), bbox_color, 1.5)
    draw_circle(bottom_center, 2.5, bbox_color)
