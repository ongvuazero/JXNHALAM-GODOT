extends Node2D
## V44.2 Lua-level active event graph, extracted from ServerBaseline Lua and
## settings/skills.txt. Renderer-only: never mutates damage, MP or cast clock.
## addskilldamage references are NOT animation spawn events.
const LINKED_CODE = preload("res://scripts/JXLuaLinkedVisual.gd")
const GRAPH_PATH: String = "res://data/lua_events/jx_lua_event_graph.json"
const QA_PATH: String = "res://data/lua_events/preview_settings.json"
# Static caches prevent reparsing the source manifest on EVERY Space attack.
static var _cached_manifest: Dictionary = {}
static var _cached_qa: Dictionary = {}

static func load_graph_cached() -> Dictionary:
    if _cached_manifest.is_empty() and FileAccess.file_exists(GRAPH_PATH):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GRAPH_PATH))
        if parsed is Dictionary:
            _cached_manifest = parsed.get("skills", {})
    return _cached_manifest

static func load_qa_cached() -> Dictionary:
    if _cached_qa.is_empty() and FileAccess.file_exists(QA_PATH):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QA_PATH))
        if parsed is Dictionary:
            _cached_qa = parsed
    return _cached_qa

static func source_child_count_at_level(skill_id: int, fallback: int = 1) -> int:
    var qa: Dictionary = load_qa_cached()
    var level_num: int = clampi(int(qa.get("default_skill_level", 20)), 1, 20)
    var d: Dictionary = load_graph_cached().get(str(skill_id), {})
    var counts: Dictionary = d.get("missile_num_levels", {})
    return maxi(1, int(counts.get(str(level_num), fallback)))

# V44.4: canonical JX mapping extracted from settings/skills.txt and
# settings/missles.txt. Overrides stale per-sect VFX paths ONLY at render time.
# Not a gameplay/stat patch; no asset substitutions and no impact on TV casts.
static func authoritative_skill_visual(input_skill: Dictionary) -> Dictionary:
    var legacy_id: int = int(input_skill.get("legacy_skill_id", 0))
    if legacy_id <= 0:
        return input_skill
    var native: Dictionary = load_graph_cached().get(str(legacy_id), {})
    if native.is_empty() or not bool(native.get("is_selected_combat_skill", false)):
        return input_skill
    var checked: Dictionary = input_skill.duplicate(true)
    var canonical: Dictionary = {
        "source_child_skill_id": int(native.get("child_skill_id", 0)),
        "missile_ids": [int(native.get("missile_id", 0))],
        "missile_move_kind": int(native.get("move_kind", -1)),
        "original_precast_spr": str(native.get("precast_spr", "")),
        "original_missile_spr": native.get("anim_paths", []).duplicate()
    }
    var corrections: Array[String] = []
    for field in canonical.keys():
        if checked.get(field) != canonical[field]:
            corrections.append(str(field))
            checked[field] = canonical[field]
    var anim: Dictionary = checked.get("original_anim_info", {}).duplicate(true)
    var info: Array = native.get("anim_infos", [])
    var roles: Array[String] = ["fly", "travel_end", "hit"]
    for role_idx in range(3):
        var role: String = roles[role_idx]
        var source_idx: int = role_idx + 1
        var expected: String = str(info[source_idx]) if source_idx < info.size() else ""
        if str(anim.get(role, "")) != expected:
            corrections.append("original_anim_info." + role)
            anim[role] = expected
    checked["original_anim_info"] = anim
    if not corrections.is_empty():
        push_warning("V44.4 VFX SOURCE GUARD skill %d corrected %s using original JX source mapping" % [legacy_id, str(corrections)])
    return checked

var graph: Dictionary = {}
var settings: Dictionary = {}
var caster: CharacterBody2D
var target: StaticBody2D
var resolver: RefCounted
var parent_skill_id: int = 0
var level: int = 20
var total_spawned: int = 0
var max_spawn: int = 8
var max_depth: int = 2
var missing_links: int = 0
var skipped_duplicate_events: int = 0
var skipped_depth_events: int = 0
var event_log: Array[Dictionary] = []
var visual_nodes_created: int = 0
var missing_visual_links: int = 0
var observed: Dictionary = {}
var parent_closed: bool = false
var lifetime: float = 0.0

func setup(skill_id: int, source: CharacterBody2D, live_target: StaticBody2D,
        asset_reader: RefCounted, qa_level: int = 0) -> void:
    parent_skill_id = skill_id
    caster = source
    target = live_target
    resolver = asset_reader
    graph = load_graph_cached()
    settings = load_qa_cached()
    level = clampi(qa_level if qa_level > 0 else int(settings.get("default_skill_level", 20)), 1, 20)
    max_depth = clampi(int(settings.get("max_nested_event_depth", 2)), 0, 3)
    max_spawn = clampi(int(settings.get("max_linked_sprites_per_cast", 8)), 1, 12)
    top_level = true
    global_position = Vector2.ZERO
    z_as_relative = false
    z_index = 7
    if not graph.has(str(skill_id)):
        push_warning("V44.2 no Lua graph for skill %d" % skill_id)

func parent_fly_delay_seconds() -> float:
    # skills.txt FlyEventTime is in legacy ticks in this QA adapter.
    # Conversion at 18Hz is provisional, NOT verified client event time.
    var d: Dictionary = graph.get(str(parent_skill_id), {})
    var tick_levels: Dictionary = d.get("fly_event_ticks_levels", {})
    var raw: int = maxi(0, int(tick_levels.get(str(level), d.get("fly_event_time_raw", 0))))
    return float(raw) / 18.0

func emit_parent(trigger: String, origin: Vector2, heading: Vector2,
        missile_ordinal: int = -1) -> void:
    # A CollideEvent can occur once PER actual missile hit. Callers may provide
    # the missile ordinal; ordinary cast events still use -1 (once per cast).
    _emit_for_skill(parent_skill_id, trigger, origin, heading, [parent_skill_id], missile_ordinal)

func _on_child_event(skill_id: int, trigger: String, origin: Vector2,
        heading: Vector2, chain: Array) -> void:
    _emit_for_skill(skill_id, trigger, origin, heading, chain)

func _emit_for_skill(skill_id: int, trigger: String, origin: Vector2,
        heading: Vector2, chain: Array, missile_ordinal: int = -1) -> void:
    if total_spawned >= max_spawn:
        return
    if chain.size() >= max_depth + 1:
        skipped_depth_events += 1
        return
    var data: Dictionary = graph.get(str(skill_id), {})
    if data.is_empty():
        return
    var per_level: Dictionary = data.get("event_levels", {})
    var events: Array = per_level.get(str(level), data.get("events", []))
    for ev in events:
        if str(ev.get("trigger", "")) != trigger:
            continue
        var next_id: int = int(ev.get("skill_id", 0))
        if next_id <= 0 or chain.has(next_id) or total_spawned >= max_spawn:
            continue
        var linked: Dictionary = graph.get(str(next_id), {})
        if linked.is_empty():
            missing_links += 1
            print("V44.2 UNRESOLVED LUA EVENT | ", skill_id, " -> ", next_id, " on ", trigger)
            continue
        # One occurrence per skill/trigger/path within this cast. Native repeat
        # event counts are NOT proven by the Lua table alone.
        var occurrence: String = str(skill_id) + ":" + trigger + ":" + str(next_id) + ":" + str(chain) + ":" + str(missile_ordinal)
        if observed.has(occurrence):
            skipped_duplicate_events += 1
            continue
        observed[occurrence] = true
        total_spawned += 1
        event_log.append({"source": skill_id, "trigger": trigger, "target": next_id,
            "ordinal": missile_ordinal, "level": level, "depth": chain.size(),
            "x": origin.x, "y": origin.y})
        var child := Node2D.new()
        child.name = "JX_LuaLinkedSkill_%d_depth_%d" % [next_id, chain.size()]
        child.set_script(LINKED_CODE)
        add_child(child)
        child.connect("source_event", Callable(self, "_on_child_event"))
        var new_path: Array = chain.duplicate()
        new_path.append(next_id)
        print("V44.2 LUA CHAIN | ", chain, " -> ", next_id,
            " | event=", trigger, " | level=", level,
            " | passive_damage_links_not_rendered=true")
        child.call("setup", linked, caster, target, origin, heading, resolver,
            new_path, float(settings.get("linked_flight_qa_px_s", 420.0)),
            float(settings.get("linked_follow_qa_turn_rate", 9.0)), level,
            trigger)
        if bool(child.call("visual_available")):
            visual_nodes_created += 1
        else:
            missing_visual_links += 1

func mark_parent_finished() -> void:
    parent_closed = true

func _process(delta: float) -> void:
    lifetime += maxf(delta, 0.0)
    if lifetime > 7.0 or (parent_closed and get_child_count() == 0):
        queue_free()

func get_diagnostic() -> Dictionary:
    return {"parent_skill": parent_skill_id, "level": level,
        # An event allocation is NOT proof that the linked SPR rendered.
        "event_visuals_spawned": visual_nodes_created,
        "linked_events_allocated": total_spawned,
        "missing_visual_links": missing_visual_links,
        "missing_link_defs": missing_links,
        "skipped_duplicates": skipped_duplicate_events,
        "skipped_depth": skipped_depth_events,
        "event_log": event_log.duplicate(true),
        "script_graph_loaded": not graph.is_empty(), "native_visual_timing_verified": false}
