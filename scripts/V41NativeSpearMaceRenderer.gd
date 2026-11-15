extends Node2D
## V41: compose 323/325 actors from independently decoded original SPR layers.
## The per-frame layer order is compiled directly from ActionRenderOrderTab.
## Coordinates are each source SPR's OffsetX/Y in its common 320x320 canvas.
## Never reposition a hand/weapon according to an atlas crop or body bbox.
## Source sprites must be present; otherwise preserve V40 atlas as a labelled fallback.
const SOURCE_DATA = "res://data/renderer_audit/v41_spear_mace_source_composer.json"
const DECODER = preload("res://scripts/V28SPRFrameDecoder.gd")
const V42_NATIVE_CLOCK = preload("res://scripts/V42NativeSpearMaceClock.gd")
const MAX_CACHED_TEXTURES: int = 96
# The conversion between the legacy 320x320 canvas and Godot foot anchor is
# computed once from the original standing Body frame. It is never shifted
# per attack frame, direction, or weapon. This is an explicit Godot transform,
# not an unproven client world-pivot claim.
const CANVAS_HALF: float = 160.0
const SOURCE_STAND_DIRECTION: int = 6  # direction bucket E; source row 7

var actor: CharacterBody2D
var old_atlas: Sprite2D
var reader = DECODER.new()
var profiles: Dictionary = {}
var source_metadata: Dictionary = {}
var source_directory: String = "res://data/spr/npcres/man/"
var loaded: Dictionary = {}  # weapon:state -> {sources: Array, profile: Dictionary}
var failed: Dictionary = {}  # unavailable bundle -> precise failure reason
var layer_nodes: Array[Sprite2D] = []
var texture_cache: Dictionary = {}
var texture_lru: Array[String] = []
var last_key: String = ""
var atlas_was_hidden: bool = false
var last_error: String = ""

func configure(player: CharacterBody2D) -> void:
	actor = player
	old_atlas = player.get_node_or_null("OriginalSPRAlignedVisual") as Sprite2D
	z_as_relative = false
	z_index = 4
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_DATA))
	if not source is Dictionary or str(source.get("format", "")) != "jxnhalam.v41_spear_mace_native_composer":
		last_error = "V41_PROFILE_MISSING_OR_INVALID"
		return
	profiles = source.get("weapons", {})
	source_directory = str(source.get("source_dir", source_directory))
	var metadata_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(source.get("metadata", ""))))
	if not metadata_value is Dictionary:
		last_error = "V41_OFFSET_METADATA_UNAVAILABLE"
		return
	source_metadata = metadata_value
	var anchor: Dictionary = _source_foot_anchor()
	if anchor.is_empty():
		last_error = "V42_STANDARD_BODY_SOURCE_ANCHOR_INVALID"
		return
	position = Vector2(float(anchor["x"]), float(anchor["y"]))
	for i in range(6):
		var part := Sprite2D.new()
		part.name = "SourceLayer%d" % i
		part.centered = true
		part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		part.z_as_relative = false
		part.z_index = 4
		part.visible = false
		add_child(part)
		layer_nodes.append(part)
	reload_sources()


func _source_foot_anchor() -> Dictionary:
	# Both 323/325 use the same Body standing geometry. Compare the two
	# original per-frame boxes; this is a single fixed conversion, not BBOX
	# re-alignment during attacks (which would make limbs/weapon jump).
	var canonical: Array = []
	for suffix in ["ST05", "ST06"]:
		var filename: String = "ClientData/spr/npcres/man/MA_BD_001_" + suffix + ".spr"
		var entry: Dictionary = source_metadata.get(filename, {})
		var frames: Array = entry.get("frame_offsets_xywh", [])
		var frames_per_dir: int = int(int(entry.get("frames", 0)) / 8)
		var index: int = SOURCE_STAND_DIRECTION * frames_per_dir
		if frames_per_dir <= 0 or index >= frames.size():
			return {}
		var box: Array = frames[index]
		if box.size() != 4:
			return {}
		if canonical.is_empty():
			canonical = box
		elif canonical != box:
			return {}
	return {"x": CANVAS_HALF - (float(canonical[0]) + float(canonical[2]) / 2.0),
		"y": CANVAS_HALF - (float(canonical[1]) + float(canonical[3]))}

func reload_sources() -> void:
	_hide_layers()
	loaded.clear()
	failed.clear()
	texture_cache.clear()
	texture_lru.clear()
	last_key = ""
	for weapon_key in ["spear", "hammer"]:
		var actions: Dictionary = profiles.get(weapon_key, {})
		for state_key in ["stand", "run", "attack9", "attack10"]:
			var profile: Dictionary = actions.get(state_key, {})
			var bundle_id: String = weapon_key + ":" + state_key
			var expected: int = int(profile.get("frames_per_dir", 0)) * 8
			var filenames: Array = profile.get("source_spr", [])
			if expected <= 0 or filenames.size() < 5 or filenames.size() > 6:
				failed[bundle_id] = "INVALID_SOURCE_PROFILE"
				continue
			var bundle_sources: Array = []
			var reason: String = ""
			for name_value in filenames:
				var filename: String = str(name_value)
				var absolute_key: String = "ClientData/spr/npcres/man/" + filename
				var metadata: Dictionary = source_metadata.get(absolute_key, {})
				if metadata.is_empty() or int(metadata.get("frames", -1)) != expected:
					reason = "BAD_SOURCE_METADATA: " + filename
					break
				var opened: Dictionary = reader.open_source(source_directory + filename, expected)
				if opened.has("error"):
					reason = "%s: %s" % [filename, str(opened.get("error", "UNKNOWN"))]
					break
				if int(opened.get("width", 0)) != 320 or int(opened.get("height", 0)) != 320:
					reason = "BAD_CANVAS_320: " + filename
					break
				bundle_sources.append(opened)
			if reason.is_empty() and bundle_sources.size() == filenames.size():
				loaded[bundle_id] = {"profile": profile, "sources": bundle_sources}
			else:
				failed[bundle_id] = reason

func missing_files() -> Array[String]:
	var names: Array[String] = []
	for weapon_key in ["spear", "hammer"]:
		var actions: Dictionary = profiles.get(weapon_key, {})
		for state_key in ["stand", "run", "attack9", "attack10"]:
			var profile: Dictionary = actions.get(state_key, {})
			for value in profile.get("source_spr", []):
				var filename: String = str(value)
				if not FileAccess.file_exists(source_directory + filename) and not names.has(filename):
					names.append(filename)
	return names

func is_weapon_ready(weapon_key: String) -> bool:
	for state_key in ["stand", "run", "attack9", "attack10"]:
		if not loaded.has(weapon_key + ":" + state_key):
			return false
	return true

func selected_state_ready(weapon_key: String) -> bool:
	var action_state: String = _state_key()
	return loaded.has(weapon_key + ":" + action_state)

func status_for(weapon_key: String) -> String:
	if weapon_key != "spear" and weapon_key != "hammer":
		return "NATIVE COMPOSER: ĐAO KHÔNG THAY ĐỔI"
	var missing: int = 0
	for state_key in ["stand", "run", "attack9", "attack10"]:
		if not loaded.has(weapon_key + ":" + state_key):
			missing += 1
	return "V41 %s: RAW SPR %s" % [weapon_key.to_upper(), "ĐỦ 4/4" if missing == 0 else "THIẾU %d BỘ (ATLAS FALLBACK)" % missing]

func _state_key() -> String:
	if actor == null:
		return "stand"
	var state_value: String = str(actor.get("state"))
	if state_value == "attack":
		return "attack10" if int(actor.get("v41_native_action")) == 10 else "attack9"
	if state_value == "run":
		return "run"
	return "stand"

func _process(_delta: float) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(old_atlas):
		return
	var weapon: Dictionary = actor.call("get_weapon")
	var weapon_key: String = str(weapon.get("visual_id", ""))
	if weapon_key != "spear" and weapon_key != "hammer":
		_hide_layers()
		return
	var selected: String = weapon_key + ":" + _state_key()
	if not loaded.has(selected):
		_hide_layers()
		return
	var bundle: Dictionary = loaded[selected]
	var profile: Dictionary = bundle.get("profile", {})
	var count: int = int(profile.get("frames_per_dir", 0))
	var direction: int = clampi(int(actor.get("facing_dir")), 0, 7)
	var index: int = 0
	if _state_key().begins_with("attack"):
		if bool(actor.get("v42_native_visual_active")):
			# Exact frame index formula: floor(frames_per_dir * tick / action_ticks).
			# Raw SPR layer placement and draw order remain V41, metadata-checked.
			index = V42_NATIVE_CLOCK.frame_for(count,
				int(actor.get("v42_native_local_tick")), int(actor.get("v42_native_cycle_ticks")))
		else:
			var duration: float = maxf(0.05, float(actor.get("other9x_visual_seconds")))
			index = mini(count - 1, int(clampf(float(actor.get("animation_elapsed")) / duration, 0.0, 0.999999) * count))
	else:
		var char_data: Dictionary = actor.get("character_data")
		var char_weapon: Dictionary = char_data.get(weapon_key, {})
		var legacy_anim: Dictionary = char_weapon.get("run" if _state_key() == "run" else "stand", {})
		var interval: float = maxf(20.0, float(legacy_anim.get("anim_ms", 90)))
		index = int(float(actor.get("animation_elapsed")) * 1000.0 / interval) % count
	var global_frame: int = direction * count + index
	var requested_key: String = "%s:%d" % [selected, global_frame]
	if requested_key != last_key:
		if not _draw_source_frame(selected, bundle, global_frame):
			failed[selected] = last_error
			loaded.erase(selected)
			_hide_layers()
			push_warning("V41 NATIVE SPR FALLBACK: " + last_error)
			return
		last_key = requested_key
	old_atlas.visible = false
	atlas_was_hidden = true
	var active_filenames: Array = profile.get("source_spr", [])
	var sprites_count: int = active_filenames.size()
	for i in range(layer_nodes.size()):
		layer_nodes[i].visible = i < sprites_count

func _draw_source_frame(bundle_id: String, bundle: Dictionary, global_frame: int) -> bool:
	var profile: Dictionary = bundle.get("profile", {})
	var originals: Array = profile.get("source_spr", [])
	var sources: Array = bundle.get("sources", [])
	var orders: Array = profile.get("order_by_global_frame", [])
	if global_frame < 0 or global_frame >= orders.size() or originals.size() != sources.size():
		last_error = "INVALID_FRAME_OR_ORDER: %s %d" % [bundle_id, global_frame]
		return false
	var draw_order: Array = orders[global_frame]
	if draw_order.size() != sources.size():
		last_error = "BAD_DRAW_ORDER: %s %d" % [bundle_id, global_frame]
		return false
	var textures: Array[Texture2D] = []
	for i in range(sources.size()):
		var filename: String = str(originals[i])
		var key: String = "%s:%d:%d" % [bundle_id, global_frame, i]
		var texture: Texture2D = texture_cache.get(key) as Texture2D
		if texture == null:
			var decoded: Dictionary = reader.frame_image(sources[i], global_frame)
			if decoded.has("error"):
				last_error = "RAW_DECODER %s %d: %s" % [filename, global_frame, str(decoded.get("error"))]
				return false
			# Compare actual per-frame source coordinates, not inferred PNG bbox.
			var metadata: Dictionary = source_metadata.get("ClientData/spr/npcres/man/" + filename, {})
			var offsets: Array = metadata.get("frame_offsets_xywh", [])
			var actual: Array = decoded.get("offset", [])
			if global_frame >= offsets.size() or actual.size() != 4:
				last_error = "NO_FRAME_OFFSET_METADATA: %s %d" % [filename, global_frame]
				return false
			var expected: Array = offsets[global_frame]
			for c in range(4):
				if int(expected[c]) != int(actual[c]):
					last_error = "SOURCE_OFFSET_MISMATCH %s frame %d component %d: %d != %d" % [filename, global_frame, c, int(actual[c]), int(expected[c])]
					return false
			texture = decoded.get("texture") as Texture2D
			if texture == null:
				last_error = "DECODED_TEXTURE_NULL: " + filename
				return false
			texture_cache[key] = texture
			texture_lru.append(key)
			if texture_lru.size() > MAX_CACHED_TEXTURES:
				texture_cache.erase(texture_lru.pop_front())
		textures.append(texture)
	# Atomic commit: no partial pose even when any layer fails validation.
	for i in range(textures.size()):
		layer_nodes[i].texture = textures[i]
	for rank in range(draw_order.size()):
		move_child(layer_nodes[int(draw_order[rank])], rank)
	return true

func _hide_layers() -> void:
	for sprite in layer_nodes:
		sprite.visible = false
	if atlas_was_hidden and is_instance_valid(old_atlas):
		old_atlas.visible = true
	atlas_was_hidden = false
	last_key = ""

func _exit_tree() -> void:
	_hide_layers()
