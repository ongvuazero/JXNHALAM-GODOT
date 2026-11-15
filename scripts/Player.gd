extends CharacterBody2D

## Reusable actor controller for all sects.  Native JX 8-dir frame row order:
##   0=S, 1=SW, 2=W, 3=NW, 4=N, 5=NE, 6=E, 7=SE.
## Position of this CharacterBody2D is the world-space FOOT ANCHOR.
## The SPR importer has already baked per-frame ox/oy offsets into each atlas.
## Character animation never alters the collision/world anchor.

const TILE: int = 192
const FOOT_OFFSET := Vector2(0.0, -64.0)
const MOVE_SPEED: float = 245.0
# V5 training only: accelerated foot motion, not verified as native JX1 movement.
const TEST_MOVE_ACCEL: float = 1380.0
const TEST_MOVE_BRAKE: float = 1920.0
const TEST_NO_MANA_COST: bool = true
const CTC_TIMELINE = preload("res://scripts/CTC9XTimeline.gd")
const JX_GEOMETRY = preload("res://scripts/JXCombatGeometry.gd")
const V34_NATIVE_CLOCK = preload("res://scripts/V34JX322NativeClock.gd")
const V42_NATIVE_CLOCK = preload("res://scripts/V42NativeSpearMaceClock.gd")
# V6.7.6: no invented six-cycle pose loop.  Native atlas order 0..15 is
# displayed exactly once over the PREVIEW cast lock.  This preview duration is
# NOT verified JX client timing; measure the actual client before calibrating.
signal skill_started(skill: Dictionary, destination: Vector2, face_direction: int)
var pending_cast: bool = false
var pending_destination: Vector2 = Vector2.ZERO
# V22: skill intent persists until range is reached, not until the actor
# touches a collision-blocked waypoint with <2px tolerance.
var pending_range_anchor: Vector2 = Vector2.ZERO
var pending_range_radius: float = 48.0
var pending_aim_offset: Vector2 = Vector2.ZERO
var pending_last_retry_msec: int = 0
var pending_blocked_seconds: float = 0.0
var move_speed_pixels: float = MOVE_SPEED

var sect_data: Dictionary = {}
var character_data: Dictionary = {}
var weapon_id: int = 0
var skill_index: int = 0
var facing_dir: int = 0
var state: String = "stand"
var target: Vector2 = Vector2.ZERO
var has_destination: bool = false
var action_remaining: float = 0.0
var recovery_remaining: float = 0.0
var animation_elapsed: float = 0.0
var last_cast_msec: Dictionary = {}
var frame_sprite: Sprite2D
var follow_camera: Camera2D
## Test-only actor resources. Exact server attribute formulas are NOT ported.
var ctc_attack_frame_baseline: int = 18
var ctc_attack_speed_percent: int = 0 # 0 is an explicit test baseline; equipment not ported
var test_player_level: int = 200
var test_mana: float = 300.0
var test_mana_max: float = 300.0
var test_regen_per_second: float = 7.0
var last_skill_error: String = ""
# V23 VISUAL PREVIEW: 16 ORIGINAL atlas frames over 0.48s, independent of
# the existing TEST cast lock/cooldown. Not measured client engine timing.
# No invented repeats, no movement, no coupling to skill hit counts.
const BLADE322_NATIVE_VISUAL_SECONDS: float = 0.48
const BLADE322_INSPECT_SECONDS: float = 0.90 # U = visual-only slow study, not actual combat speed
var blade322_visual_slow: bool = false
var blade322_combo_enabled: bool = true
var blade322_combo_duration: float = 0.0
# Native 322 visual clock; only display frame selection is affected.
# Base JX1 scheduler target = 18Hz, 5 nominal ticks from settings row 322.
var blade322_native_visual_active: bool = false
var blade322_native_elapsed: float = 0.0
var blade322_native_tick: int = 0
# V40 Thương 323 / Chùy 325: single-pass pose atlas over DEMO cast lock.
# AT04/AT06 SPR-derived art exists, but runtime action dispatch/frame timing
# has not been traced for these two skills. Do NOT label this native timing.
var other9x_visual_seconds: float = 0.0
# V41: client action 9/10 selected once per successful Spear/Mace cast.
var v41_native_action: int = 9
## V42 native actor pose sampler. Independent of V22 missile/contact/HP.
var v42_native_visual_active: bool = false
var v42_native_skill_id: int = 0
var v42_native_elapsed: float = 0.0
var v42_native_cycle_ticks: int = 0
var v42_native_child_cycles: int = 0
var v42_native_cycle_index: int = 0
var v42_native_local_tick: int = 0
# V20: one shared NOMINAL cast tick boundary for 325 and M141 allocation.
# This aligns Godot callbacks; real JX1 player animation wall-clock timing
# is not established by the M141 FLY client log.
var v20_cast_sequence: int = 0
var v20_m141_allocation_seen: bool = false
var v20_m141_allocation_tick: int = -1

func _ready() -> void:
    collision_layer = 2
    collision_mask = 1
    var foot_shape := CircleShape2D.new()
    foot_shape.radius = 12.0
    var collider := CollisionShape2D.new()
    collider.name = "FootCollider"
    collider.shape = foot_shape
    collider.position = Vector2(0, -12)
    add_child(collider)
    frame_sprite = Sprite2D.new()
    frame_sprite.name = "OriginalSPRAlignedVisual"
    frame_sprite.region_enabled = true
    frame_sprite.position = FOOT_OFFSET
    frame_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    # Explicit painter ordering: ground=0, pose echoes=3, current body/weapon=4,
    # native SPR VFX=5. Do not draw translucent old poses over today's pose.
    frame_sprite.z_as_relative = false
    frame_sprite.z_index = 4
    add_child(frame_sprite)
    follow_camera = Camera2D.new()
    follow_camera.name = "CameraFollowFootAnchor"
    follow_camera.limit_left = 0
    follow_camera.limit_top = 0
    follow_camera.limit_right = 2300
    follow_camera.limit_bottom = 1700
    follow_camera.position_smoothing_enabled = true
    follow_camera.position_smoothing_speed = 8.0
    add_child(follow_camera)
    follow_camera.make_current()
    target = global_position

func set_actor_defaults(defaults: Dictionary) -> void:
    # JX RunSpeed is in legacy units, not Godot pixels per second.
    # The scale keeps V2 movement speed: 10 original -> 245px/sec.
    var legacy_speed: float = float(defaults.get("RunSpeed", 10))
    move_speed_pixels = clampf(legacy_speed * 24.5, 80.0, 600.0)
    ctc_attack_frame_baseline = maxi(1, int(defaults.get("AttackFrame", 18)))

func load_sect(data: Dictionary) -> void:
    sect_data = data
    weapon_id = 0
    skill_index = 0
    var visual_path: String = str(data.get("visual_manifest", ""))
    if visual_path.is_empty() or not FileAccess.file_exists(visual_path):
        push_error("Missing visual manifest for sect: %s" % str(data.get("id", "unknown")))
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(visual_path))
    if not parsed is Dictionary:
        push_error("Invalid visual manifest: " + visual_path)
        return
    character_data = parsed
    last_cast_msec.clear()
    has_destination = false
    pending_cast = false
    action_remaining = 0.0
    recovery_remaining = 0.0
    blade322_combo_duration = 0.0
    blade322_native_visual_active = false
    blade322_native_elapsed = 0.0
    blade322_native_tick = 0
    other9x_visual_seconds = 0.0
    v41_native_action = 9
    _v42_clear_visual_clock()
    _set_state("stand", true)

func get_weapons() -> Array:
    var raw: Variant = sect_data.get("weapons", [])
    if raw is Array:
        return raw
    return []

func get_weapon() -> Dictionary:
    var weapons: Array = get_weapons()
    if weapon_id < 0 or weapon_id >= weapons.size():
        return {}
    var weapon: Variant = weapons[weapon_id]
    if weapon is Dictionary:
        return weapon
    return {}

func get_active_skill() -> Dictionary:
    var weapon: Dictionary = get_weapon()
    var skills: Variant = weapon.get("skills", [])
    if skills is Array and not skills.is_empty():
        var i: int = posmod(skill_index, skills.size())
        if skills[i] is Dictionary:
            return skills[i]
    return {}

func set_weapon(next_weapon: int) -> void:
    if next_weapon < 0 or next_weapon >= get_weapons().size():
        return
    weapon_id = next_weapon
    skill_index = 0
    has_destination = false
    pending_cast = false
    action_remaining = 0.0
    recovery_remaining = 0.0
    blade322_combo_duration = 0.0
    blade322_native_visual_active = false
    blade322_native_elapsed = 0.0
    blade322_native_tick = 0
    other9x_visual_seconds = 0.0
    _v42_clear_visual_clock()
    _set_state("stand", true)


func cycle_skill(direction_step: int) -> void:
    var skills: Variant = get_weapon().get("skills", [])
    if skills is Array and skills.size() > 1:
        skill_index = posmod(skill_index + direction_step, skills.size())

func move_to(world_position: Vector2) -> void:
    if action_remaining > 0.0 or recovery_remaining > 0.0:
        return
    target = Vector2(clampf(world_position.x, 25.0, 2275.0), clampf(world_position.y, 100.0, 1600.0))
    has_destination = true
    pending_cast = false

func face(delta_position: Vector2) -> void:
    if delta_position.length_squared() < 1.0:
        return
    # In screen coordinates, +y is SOUTH and +x is EAST.
    # atan2: E=0, S=90, W=180, N=-90. Native SPR row 0 is SOUTH.
    # Therefore: E->6, S->0, W->2, N->4.
    var sector: int = roundi(delta_position.angle() / (PI / 4.0))
    facing_dir = posmod(sector + 6, 8)

# V21 — Set the character's SPR 8-direction row from the SAME native
# 64-direction heading used for M141. 0=S, 16=W, 32=N, 48=E.
# Rows 0=S, 1=SW, 2=W, 3=NW, 4=N, 5=NE, 6=E, 7=SE.
# This only selects the rendered facing row. No action state/timer reset.
func face_native_dir64(dir64: int) -> void:
    facing_dir = posmod(floori(float(posmod(dir64, 64) + 4) / 8.0), 8)
    if is_instance_valid(frame_sprite):
        _render_frame()

# V22: optional range anchor lets an NPC foot control distance while the
# existing hitbox destination remains a separate (DEMO) visual/damage point.
func request_skill(world_position: Vector2, range_anchor: Variant = null) -> void:
    var skill: Dictionary = get_active_skill()
    if skill.is_empty() or action_remaining > 0.0 or recovery_remaining > 0.0:
        return
    if not _check_skill_requirements(skill):
        return
    var foot: Vector2 = world_position
    if range_anchor is Vector2:
        foot = range_anchor
    var effective_radius: float = JX_GEOMETRY.attack_range_pixels(skill)
    # Self/buff skills cast at player; no chase and no cursor requirement.
    if bool(skill.get("target_self", false)):
        cancel_pending_skill_approach()
        if cast_at(global_position):
            skill_started.emit(skill, global_position, facing_dir)
        return
    pending_destination = world_position
    pending_range_anchor = foot
    pending_range_radius = effective_radius
    pending_aim_offset = world_position - foot
    pending_last_retry_msec = 0
    pending_blocked_seconds = 0.0
    if global_position.distance_to(foot) <= effective_radius:
        cancel_pending_skill_approach()
        if cast_at(world_position, foot):
            skill_started.emit(skill, world_position, facing_dir)
        return
    pending_cast = true
    _rebuild_pending_approach_waypoint()

func cancel_pending_skill_approach() -> void:
    pending_cast = false
    has_destination = false
    pending_blocked_seconds = 0.0
    velocity = Vector2.ZERO

func refresh_pending_skill_target(new_foot: Vector2) -> void:
    if not pending_cast:
        return
    if new_foot.distance_squared_to(pending_range_anchor) < 1.0:
        return
    pending_range_anchor = new_foot
    pending_destination = new_foot + pending_aim_offset
    _rebuild_pending_approach_waypoint()

func _rebuild_pending_approach_waypoint() -> void:
    var delta_to_npc: Vector2 = pending_range_anchor - global_position
    var distance: float = delta_to_npc.length()
    if distance < 0.001:
        target = global_position
    else:
        # Reach the range boundary before any body collision blocks the route.
        var stand_off: float = clampf(pending_range_radius * 0.70,
            20.0, maxf(24.0, pending_range_radius - 8.0))
        target = pending_range_anchor - delta_to_npc / distance * stand_off
    target = Vector2(clampf(target.x, 25.0, 2275.0), clampf(target.y, 100.0, 1600.0))
    has_destination = true

func _physics_pending_skill(delta: float) -> void:
    var distance_to_npc: float = global_position.distance_to(pending_range_anchor)
    if distance_to_npc <= pending_range_radius:
        has_destination = false
        velocity = Vector2.ZERO
        _set_state("stand")
        var now: int = Time.get_ticks_msec()
        if now >= pending_last_retry_msec:
            pending_last_retry_msec = now + 45
            var selected_skill: Dictionary = get_active_skill()
            # Keep pending while cooldown is active; do NOT start running again.
            if cast_at(pending_destination, pending_range_anchor):
                skill_started.emit(selected_skill, pending_destination, facing_dir)
        return
    if not has_destination or global_position.distance_to(target) < 3.0:
        _rebuild_pending_approach_waypoint()
    var diff: Vector2 = target - global_position
    var distance: float = diff.length()
    var wanted_velocity: Vector2 = diff.normalized() * minf(move_speed_pixels,
        sqrt(2.0 * TEST_MOVE_BRAKE * maxf(distance, 0.0)))
    velocity = velocity.move_toward(wanted_velocity, TEST_MOVE_ACCEL * delta)
    face(pending_range_anchor - global_position)
    _set_state("run")
    var before: Vector2 = global_position
    move_and_slide()
    if global_position.distance_squared_to(before) < 0.04:
        pending_blocked_seconds += delta
    else:
        pending_blocked_seconds = 0.0
    # Never run against a wall forever. The user can reposition and retry.
    if pending_blocked_seconds >= 0.65:
        cancel_pending_skill_approach()
        last_skill_error = "TARGET BLOCKED (TEST)"
        _set_state("stand")

func _check_skill_requirements(skill: Dictionary) -> bool:
    last_skill_error = ""
    var needed: int = int(skill.get("level_required", 0))
    if test_player_level < needed:
        last_skill_error = "LV %d REQUIRED (TEST LV %d)" % [needed, test_player_level]
        return false
    var cost: float = float(skill.get("mana_cost_preview", 0.0))
    if not TEST_NO_MANA_COST and test_mana < cost:
        last_skill_error = "NOT ENOUGH MANA (TEST)"
        return false
    return true

# `face_anchor` affects ONLY the actor's first rendered facing row.
# World_position remains the unchanged DEMO hitbox/skill destination.
func cast_at(world_position: Vector2, face_anchor: Variant = null) -> bool:
    var skill: Dictionary = get_active_skill()
    if skill.is_empty() or action_remaining > 0.0 or recovery_remaining > 0.0:
        return false
    var skill_id: String = str(skill.get("id", ""))
    var now: int = Time.get_ticks_msec()
    var last_time: int = int(last_cast_msec.get(skill_id, -100000))
    var cooldown: int = int(skill.get("cooldown_ms", 850))
    if bool(skill.get("ctc_9x_many_attack", false)):
        # V43.4: Skill 322 samples FIVE nominal actor ticks (V34), while the
        # old preview mistakenly locked movement/cooldown for EIGHTEEN ticks.
        # This created a ~0.72s stand-still gap on held Space. Do not alter
        # the proven 3 M138 allocations or the 323/325 combat route.
        var lock_trace: Dictionary = CTC_TIMELINE.build(skill, ctc_attack_frame_baseline, ctc_attack_speed_percent)
        var lock_ticks: int = int(lock_trace.get("action_lock_ticks", 18))
        var current_legacy_id: int = int(skill.get("legacy_skill_id", 0))
        if current_legacy_id == 322:
            lock_ticks = V34_NATIVE_CLOCK.TOTAL_TICKS_322
        elif current_legacy_id == 325:
            # The 325 actor has ONE 4-tick native child cycle, not the generic
            # 18-tick baseline. Only the 325 attack lock/auto-chain is changed.
            var hammer_profile: Dictionary = V42_NATIVE_CLOCK.load_skill(325)
            if not hammer_profile.is_empty():
                lock_ticks = maxi(1, int(hammer_profile.get("cycle_ticks", 4)) * int(hammer_profile.get("child_casts", 1)))
        cooldown = ceili(float(lock_ticks) * 1000.0 / CTC_TIMELINE.TICK_HZ)
    if now - last_time < cooldown:
        last_skill_error = "COOLDOWN (TEST)"
        return false
    if not _check_skill_requirements(skill):
        return false
    if not TEST_NO_MANA_COST:
        test_mana = maxf(0.0, test_mana - float(skill.get("mana_cost_preview", 0.0)))
    last_cast_msec[skill_id] = now
    # Increment only for a successful cast, after cooldown/mana checks.
    # Prevent old visual sessions from releasing a newer actor swing.
    v20_cast_sequence += 1
    var chosen_face_point: Vector2 = world_position
    if face_anchor is Vector2:
        chosen_face_point = face_anchor
    face(chosen_face_point - global_position)
    if bool(skill.get("ctc_9x_many_attack", false)):
        var cast_timeline: Dictionary = CTC_TIMELINE.build(skill, ctc_attack_frame_baseline, ctc_attack_speed_percent)
        var action_ticks: int = int(cast_timeline.get("action_lock_ticks", 18))
        var current_legacy_id: int = int(skill.get("legacy_skill_id", 0))
        if current_legacy_id == 322:
            action_ticks = V34_NATIVE_CLOCK.TOTAL_TICKS_322
        elif current_legacy_id == 325:
            var hammer_profile: Dictionary = V42_NATIVE_CLOCK.load_skill(325)
            if not hammer_profile.is_empty():
                action_ticks = maxi(1, int(hammer_profile.get("cycle_ticks", 4)) * int(hammer_profile.get("child_casts", 1)))
        action_remaining = float(action_ticks) / CTC_TIMELINE.TICK_HZ
        recovery_remaining = 0.0
    else:
        action_remaining = float(skill.get("character_cast_ms", skill.get("cast_ms", 425))) / 1000.0
        recovery_remaining = float(skill.get("recovery_ms", 0)) / 1000.0
    has_destination = false
    pending_cast = false
    velocity = Vector2.ZERO
    # V34: skill 322 uses the EXE-derived nominal 18-Hz logic-tick frame
    # selection, not the old 0.48s/0.90s preview interpolator. Combat lock,
    # mana, missile dispatch and cooldown above remain unchanged.
    if int(skill.get("legacy_skill_id", 0)) == 322:
        blade322_native_visual_active = true
        blade322_native_elapsed = 0.0
        blade322_native_tick = 0
        blade322_combo_duration = V34_NATIVE_CLOCK.nominal_seconds()
    else:
        blade322_native_visual_active = false
        blade322_combo_duration = 0.0
    # Client form-12 action clock is independent of the still-DEMO cast lock.
    # 323: 5 cycles x 3 native logic ticks; 325: 1 cycle x 4 native ticks.
    # The first 9/10 choice comes from Main._v41_choose_action after cast success.
    var native_id: int = int(skill.get("legacy_skill_id", 0))
    var native_profile: Dictionary = V42_NATIVE_CLOCK.load_skill(native_id) if native_id in [323, 325] else {}
    _v42_clear_visual_clock()
    if not native_profile.is_empty():
        v42_native_visual_active = true
        v42_native_skill_id = native_id
        v42_native_cycle_ticks = int(native_profile.get("cycle_ticks", 0))
        v42_native_child_cycles = int(native_profile.get("child_casts", 0))
        other9x_visual_seconds = V42_NATIVE_CLOCK.total_seconds(v42_native_cycle_ticks, v42_native_child_cycles)
    else:
        # Only when the verified client-data clock is unavailable: legacy preview.
        other9x_visual_seconds = maxf(0.05, action_remaining) if native_id in [323, 325] else 0.0
    _set_state("attack" if bool(skill.get("ctc_9x_many_attack", false)) else "cast", true)
    return true

func basic_attack() -> void:
    if action_remaining > 0.0 or recovery_remaining > 0.0:
        return
    blade322_native_visual_active = false
    blade322_combo_duration = 0.0
    other9x_visual_seconds = 0.0
    _v42_clear_visual_clock()
    var anim: Dictionary = character_data.get(str(get_weapon().get("visual_id", "")), {}).get("attack", {})
    action_remaining = float(anim.get("frames_per_direction", 12)) * float(anim.get("anim_ms", 75)) / 1000.0
    recovery_remaining = 0.0
    has_destination = false
    velocity = Vector2.ZERO
    _set_state("attack", true)

func _physics_process(delta: float) -> void:
    if TEST_NO_MANA_COST:
        test_mana = test_mana_max
    else:
        test_mana = minf(test_mana_max, test_mana + test_regen_per_second * delta)
    animation_elapsed += delta
    # One source of truth for AT02 atlas and AT03 6-layer renderer.
    # This models NOMINAL 18-Hz steps only; EXE network-sync 0/2 passes
    # cannot be reproduced without understanding its correction state.
    if blade322_native_visual_active:
        blade322_native_elapsed += maxf(0.0, delta)
        blade322_native_tick = V34_NATIVE_CLOCK.tick_at_elapsed(blade322_native_elapsed)
    if v42_native_visual_active:
        v42_native_elapsed += maxf(0.0, delta)
        var phase: Dictionary = V42_NATIVE_CLOCK.phase_at_elapsed(
            v42_native_elapsed, v42_native_cycle_ticks, v42_native_child_cycles)
        if bool(phase.get("completed", false)):
            if v42_native_skill_id == 325:
                # Timeline dispatches Form12->408->M141 at the fourth
                # nominal tick.  Don't return to STAND before Main has
                # actually dispatched the three allocation events.
                v42_native_local_tick = maxi(0, v42_native_cycle_ticks - 1)
                var nominal_end: float = V42_NATIVE_CLOCK.total_seconds(
                    v42_native_cycle_ticks, v42_native_child_cycles)
                var visual_guard: float = 1.0 / V42_NATIVE_CLOCK.HZ
                # One more render tick is a Godot visual guard only;
                # it is NOT a measured JX1 sprite-animation delay.
                var release_pose: bool = (
                    (v20_m141_allocation_seen and
                    v42_native_elapsed >= nominal_end + visual_guard)
                    or v42_native_elapsed >= nominal_end + 2.0 * visual_guard
                )
                if release_pose:
                    v42_native_visual_active = false
                    if state == "attack":
                        _set_state("stand")
            else:
                v42_native_visual_active = false
                if state == "attack":
                    _set_state("stand")
        else:
            var new_cycle: int = int(phase.get("cycle", 0))
            if new_cycle > v42_native_cycle_index:
                # 0057B590 calls 0057B470 again for each next child action.
                # Select action once per native child cycle, never per frame/missile.
                # EXE RNG remains an approximation (Godot randi_range(0,1)).
                for _cycle in range(v42_native_cycle_index + 1, new_cycle + 1):
                    v41_native_action = 10 if randi_range(0, 1) == 0 else 9
                v42_native_cycle_index = new_cycle
            v42_native_local_tick = int(phase.get("tick", 0))
    if action_remaining > 0.0:
        action_remaining -= delta
        velocity = Vector2.ZERO
        if action_remaining <= 0.0:
            if recovery_remaining > 0.0:
                _set_state("stand")
            else:
                _set_state("stand")
    elif recovery_remaining > 0.0:
        recovery_remaining -= delta
        velocity = Vector2.ZERO
        if recovery_remaining <= 0.0:
            _set_state("stand")
    elif pending_cast:
        # Range check takes precedence over exact waypoint arrival.
        _physics_pending_skill(delta)
    elif has_destination:
        var diff: Vector2 = target - global_position
        var distance: float = diff.length()
        if distance <= 2.0:
            has_destination = false
            velocity = Vector2.ZERO
            _set_state("stand")
            # Manual click-to-move arrived; skill approaches are handled above.
        else:
            face(diff)
            # Desired speed decreases near destination to remove the snap-to-stop.
            # This is a feel-oriented training adjustment, not a decoded JX curve.
            var braking_speed: float = sqrt(2.0 * TEST_MOVE_BRAKE * distance)
            var target_speed: float = minf(move_speed_pixels, braking_speed)
            var wanted_velocity: Vector2 = diff / distance * target_speed
            velocity = velocity.move_toward(wanted_velocity, TEST_MOVE_ACCEL * delta)
            if velocity.length() * delta > distance:
                velocity = diff / maxf(delta, 0.00001)
            _set_state("run")
            move_and_slide()
    else:
        # V5 calculated braking velocity but did not apply it to movement.
        # Finish the deceleration in physics instead of snapping visually.
        velocity = velocity.move_toward(Vector2.ZERO, TEST_MOVE_BRAKE * delta)
        if velocity.length_squared() > 1.0:
            _set_state("run")
            move_and_slide()
        else:
            velocity = Vector2.ZERO
            _set_state("stand")
    # The client samples tick 0..4, then leaves this VISUAL attack phase.
    # Parent cast lock/cooldown can continue independently (unchanged V33).
    if blade322_native_visual_active and blade322_native_elapsed >= V34_NATIVE_CLOCK.nominal_seconds():
        blade322_native_visual_active = false
        blade322_combo_duration = 0.0
        if state == "attack":
            _set_state("stand")
    elif state == "attack" and blade322_combo_duration > 0.0 and animation_elapsed >= blade322_combo_duration:
        # Legacy non-native preview only; this branch is not used by 322 V34.
        blade322_combo_duration = 0.0
        _set_state("stand")
    _render_frame()

func _set_state(next_state: String, force: bool = false) -> void:
    if state == next_state and not force:
        return
    state = next_state
    animation_elapsed = 0.0
    var visuals: Dictionary = character_data.get(str(get_weapon().get("visual_id", "")), {})
    var anim: Dictionary = visuals.get(state, {})
    if anim.is_empty():
        anim = visuals.get("stand", {})
    var texture_path: String = str(anim.get("file", ""))
    if not texture_path.is_empty():
        frame_sprite.texture = load(texture_path) as Texture2D
    _render_frame()

func _render_frame() -> void:
    if frame_sprite == null or frame_sprite.texture == null:
        return
    var visuals: Dictionary = character_data.get(str(get_weapon().get("visual_id", "")), {})
    var anim: Dictionary = visuals.get(state, {})
    if anim.is_empty():
        anim = visuals.get("stand", {})
    var count: int = maxi(1, int(anim.get("frames_per_direction", 1)))
    var interval: float = maxf(20.0, float(anim.get("anim_ms", 90)))
    var index: int = int(animation_elapsed * 1000.0 / interval) % count
    if state == "attack" and v42_native_visual_active:
        index = V42_NATIVE_CLOCK.frame_for(count, v42_native_local_tick, v42_native_cycle_ticks)
    elif state == "attack" and other9x_visual_seconds > 0.0 and not blade322_native_visual_active:
        # Unverified fallback preview only if native source clock is absent.
        var fraction: float = clampf(animation_elapsed / other9x_visual_seconds, 0.0, 0.999999)
        index = mini(count - 1, int(fraction * float(count)))
    if state == "attack" and blade322_native_visual_active:
        # Attack2/AT02 has 16 source frames per direction; 5 native logic
        # ticks select 0,3,6,9,12 instead of linear 0..15 at preview FPS.
        index = V34_NATIVE_CLOCK.frame_in_direction(count, blade322_native_tick)
    elif state == "attack" and blade322_combo_duration > 0.0:
        # Unverified legacy preview for other cases; not used by 322 V34.
        var progress: float = clampf(animation_elapsed / blade322_combo_duration, 0.0, 0.999999)
        index = mini(count - 1, int(progress * float(count)))
    frame_sprite.region_rect = Rect2(index * TILE, facing_dir * TILE, TILE, TILE)

# Main calls this only after the exact session has executed its
# CTC9XTimeline allocation tick. No new FX, hitbox, mana or damage.
func v20_confirm_m141_allocation(event_tick: int, cast_sequence: int) -> void:
    if cast_sequence != v20_cast_sequence:
        return
    if v42_native_skill_id != 325 or not v42_native_visual_active:
        return
    if event_tick < 0 or v20_m141_allocation_seen:
        return
    v20_m141_allocation_seen = true
    v20_m141_allocation_tick = event_tick

func _v42_clear_visual_clock() -> void:
    v20_m141_allocation_seen = false
    v20_m141_allocation_tick = -1
    v42_native_visual_active = false
    v42_native_skill_id = 0
    v42_native_elapsed = 0.0
    v42_native_cycle_ticks = 0
    v42_native_child_cycles = 0
    v42_native_cycle_index = 0
    v42_native_local_tick = 0
