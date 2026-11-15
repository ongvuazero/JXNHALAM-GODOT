extends Node2D
signal visual_decode_failed(reason: String)
## V35: Source-mapped native six-layer draw order for JX action 9 / MeleeWCut.
## When cast action 10 is selected, the original AT02 atlas stays visible.
## Evidence: client dispatch path writes NPC action 9/10 after g_Random(2).
## This renderer has no RNG and never independently chooses an action.
## This is only a rendering overlay; it NEVER alters cast, damage, mana, hits,
## collision, movement, or action/recovery timelines.
const DECODER = preload("res://scripts/V28SPRFrameDecoder.gd")
const V34_NATIVE_CLOCK = preload("res://scripts/V34JX322NativeClock.gd")
const NATIVE_ORDER = preload("res://scripts/V35NativeLayerOrder.gd")
const DATA_PATH: String = "res://data/renderer_audit/blade_004_action_profiles.json"
const SOURCE_DIR: String = "res://data/spr/npcres/man/"
const EXPECTED_FRAMES: int = 14
const EXPECTED_DIRS: int = 8
# Raw decoder bakes each SPR OffsetX/Y into the same 320x320 canvas.
# Godot's actor origin is the foot, unlike the client object origin. This
# one-time world-origin translation is calibrated from facing E/6 BD bottom
# y=202 (V31); it is NOT a native EXE pivot formula. Do not re-anchor per frame.
const ACTOR_FOOT_TO_NATIVE_CANVAS_Y: float = 160.0 - 202.0
const CACHE_MAX: int = 36 # Six complete frames x six layers.
const LAYER_IDS: Array[String] = ["BD_001", "LH_001", "RH_001", "HD_001", "LW_000", "RW_004"]

var actor: CharacterBody2D
var reference_sprite: Sprite2D
var enabled: bool = false
var at03_sources_loaded: bool = false
var sources: Array[Dictionary] = []
var layer_sprites: Array[Sprite2D] = []
var reader = DECODER.new()
var native_order = NATIVE_ORDER.new()
var cache: Dictionary = {}
var cache_order: Array[String] = []
var last_face: int = -1
var last_frame: int = -1
var hiding_reference: bool = false
var warning_text: String = ""

func configure(character: CharacterBody2D) -> void:
	actor = character
	reference_sprite = character.get_node_or_null("OriginalSPRAlignedVisual") as Sprite2D
	if reference_sprite == null:
		warning_text = "NO_ACTOR_SPRITE"
		return
	position = Vector2(0.0, ACTOR_FOOT_TO_NATIVE_CANVAS_Y)
	z_as_relative = false
	z_index = 4
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not payload is Dictionary:
		warning_text = "NO_PROFILE_JSON"
		return
	var profile: Dictionary = {}
	for entry in payload.get("actions", []):
		if entry is Dictionary and str(entry.get("id", "")) == "AT03":
			profile = entry
			break
	var layer_defs: Array = profile.get("layers", [])
	if layer_defs.size() != 6:
		warning_text = "BAD_LAYER_PROFILE"
		return
	for i in range(6):
		if str(layer_defs[i].get("layer", "")) != LAYER_IDS[i]:
			warning_text = "UNEXPECTED_LAYER_ORDER"
			sources.clear()
			return
		var name: String = str(layer_defs[i].get("source_spr", ""))
		var source: Dictionary = reader.open_source(SOURCE_DIR + name, 112)
		if source.has("error"):
			warning_text = "%s: %s" % [name, str(source.get("error", "UNKNOWN"))]
			sources.clear()
			return
		if int(source.get("width", -1)) != 320 or int(source.get("height", -1)) != 320:
			warning_text = "SOURCE_CANVAS_NOT_320: " + name
			sources.clear()
			return
		sources.append(source)
	if not native_order.load_verified_table():
		warning_text = native_order.warning_text
		sources.clear()
		return
	for i in range(6):
		var sprite := Sprite2D.new()
		sprite.name = "AT03Layer%d" % i
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_as_relative = false
		sprite.z_index = 4 # all siblings share global z=4; move_child sets native painter order
		sprite.visible = false
		add_child(sprite)
		layer_sprites.append(sprite)
	# Decode one complete frame now. set_enabled() cannot expose a blank/partial
	# actor on the first attack, and later failures still fall back atomically.
	if not _draw_native_frame(0, 0):
		for sprite in layer_sprites:
			sprite.queue_free()
		layer_sprites.clear()
		sources.clear()
		return
	at03_sources_loaded = true

func set_enabled(value: bool) -> bool:
	if value and not at03_sources_loaded:
		push_warning("V29 AT03 needs six SPR in data/spr/npcres/man/: " + warning_text)
		return false
	enabled = value
	if not enabled:
		_hide_at03()
	return enabled

func _process(_delta: float) -> void:
	if not at03_sources_loaded or not is_instance_valid(actor) or not is_instance_valid(reference_sprite):
		return
	var weapon: Dictionary = actor.call("get_weapon")
	var skill: Dictionary = actor.call("get_active_skill")
	var show_at03: bool = enabled
	if str(weapon.get("visual_id", "")) != "blade":
		show_at03 = false
	if int(skill.get("legacy_skill_id", 0)) != 322:
		show_at03 = false
	if str(actor.get("state")) != "attack":
		show_at03 = false
	if not bool(actor.get("blade322_native_visual_active")):
		show_at03 = false
	if not show_at03:
		_hide_at03()
		return
	var facing: int = clampi(int(actor.get("facing_dir")), 0, EXPECTED_DIRS - 1)
	# Same native NPC tick as Player AT02. Frames are re-sampled according
	# to FUN_005C6300; not animation_elapsed / arbitrary preview duration.
	var frame: int = V34_NATIVE_CLOCK.frame_in_direction(EXPECTED_FRAMES,
		int(actor.get("blade322_native_tick")))
	if facing != last_face or frame != last_frame:
		if not _draw_native_frame(facing, frame):
			var failure: String = warning_text if not warning_text.is_empty() else "UNKNOWN_FRAME_DECODE_ERROR"
			enabled = false
			at03_sources_loaded = false # Do not retry corrupt source every cast.
			_hide_at03()
			visual_decode_failed.emit(failure)
			return
		last_face = facing
		last_frame = frame
	if not hiding_reference:
		reference_sprite.visible = false
		hiding_reference = true
	for layer in layer_sprites:
		layer.visible = true

func _draw_native_frame(facing: int, frame: int) -> bool:
	# The native resolver is called with direction bucket and GLOBAL source
	# frame (dir*14+local), not row number or cast/tick index.
	var draw_order: Array[int] = native_order.order_for("MeleeWCut", facing, frame, EXPECTED_FRAMES)
	if draw_order.size() != 6:
		warning_text = "INVALID_NATIVE_ORDER dir %d frame %d" % [facing, frame]
		return false
	var next_textures: Array[Texture2D] = []
	for i in range(6):
		var key: String = "%d:%d:%d" % [i, facing, frame]
		var cached: Dictionary = cache.get(key, {})
		var texture: Texture2D = cached.get("texture") as Texture2D
		if texture == null:
			var result: Dictionary = reader.frame_image(sources[i], facing * EXPECTED_FRAMES + frame)
			if result.has("error"):
				warning_text = "DECODE_FAIL layer %d dir %d frame %d: %s" % [i, facing, frame, str(result["error"])]
				push_warning(warning_text)
				return false
			texture = result.get("texture") as Texture2D
			if texture == null:
				warning_text = "NULL_TEXTURE layer %d dir %d frame %d" % [i, facing, frame]
				return false
			cache[key] = {"texture": texture}
			cache_order.append(key)
			if cache_order.size() > CACHE_MAX:
				cache.erase(cache_order.pop_front())
		next_textures.append(texture)
	if next_textures.size() != 6:
		warning_text = "INCOMPLETE_COMPOSITE dir %d frame %d" % [facing, frame]
		return false
	# All 6 textures are common-size canvases containing the ORIGINAL per-frame
	# OffsetX/Y from the SPR, so their local positions must stay identical.
	# Do not use the BD bbox bottom (which changes with poses) as an animation
	# pivot. Fixed Godot foot translation is configured once at startup.
	# Commit textures and draw order only after all six frames decoded.
	for i in range(6):
		layer_sprites[i].texture = next_textures[i]
	# Godot draws equal-z sibling CanvasItems in scene-tree order. Reorder the
	# six layer nodes according to native ID traversal (bottom -> top).
	for rank in range(6):
		move_child(layer_sprites[draw_order[rank]], rank)
	return true

func _hide_at03() -> void:
	for layer in layer_sprites:
		layer.visible = false
	if hiding_reference and is_instance_valid(reference_sprite):
		reference_sprite.visible = true
	hiding_reference = false
	last_face = -1
	last_frame = -1

func _exit_tree() -> void:
	_hide_at03()

func status() -> String:
	if not at03_sources_loaded:
		return "AT03 UNAVAILABLE; AT02 FALLBACK: " + warning_text
	return "AT03 native per-frame 6-layer order + source offsets, fixed Godot foot calibration; ACTION " + ("9 (AT03)" if enabled else "10 / idle (AT02)")
