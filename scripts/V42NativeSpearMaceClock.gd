extends RefCounted
## V42 — Native actor animation phase for Tianwang 323 and 325.
## EXE: 005E99A0 mode-1 wait formula; 0057B470 resets action duration;
## 00575960 advances NPC+F8, 005C6300 selects native source frame;
## V10 scheduler nominal 18Hz. Source-data conditional, NOT a damage clock.
## For skill 323, the five child cycles each select a new action 9 or 10
## via 0057B470 -> g_Random(2). Godot approximates its RNG.
const DATA_PATH: String = "res://data/renderer_audit/v42_native_spear_mace_timing.json"
const HZ: float = 18.0

static func load_skill(skill_id: int) -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not source is Dictionary or str(source.get("format", "")) != "jxnhalam.v42_native_form12_actor_clock":
        return {}
    if int(source.get("scheduler_hz_nominal", 0)) != 18:
        return {}
    var all_skills: Dictionary = source.get("skills", {})
    var profile: Dictionary = all_skills.get(str(skill_id), {})
    if profile.is_empty() or int(profile.get("skill_id", -1)) != skill_id:
        return {}
    if int(profile.get("skill_style", -1)) != 1 or int(profile.get("missles_form", -1)) != 12:
        return {}
    if int(profile.get("generate_mode", -1)) != 1 or int(profile.get("char_anim_id", -1)) != 9:
        return {}
    var cycle_ticks: int = int(profile.get("cycle_ticks", 0))
    var cycles: int = int(profile.get("child_casts", 0))
    if cycle_ticks < 1 or cycles < 1 or cycle_ticks > 100 or cycles > 100:
        return {}
    if cycle_ticks != int(profile.get("generate_step", 0)) + int(profile.get("wait_ticks", 0)):
        return {}
    return profile

static func phase_at_elapsed(elapsed: float, cycle_ticks: int, child_casts: int) -> Dictionary:
    var ticks_per_cycle: int = maxi(1, cycle_ticks)
    var cycles: int = maxi(1, child_casts)
    var elapsed_ticks: int = maxi(0, int(floor(maxf(0.0, elapsed) * HZ)))
    var total_ticks: int = ticks_per_cycle * cycles
    if elapsed_ticks >= total_ticks:
        return {"completed": true, "cycle": cycles - 1, "tick": ticks_per_cycle - 1,
            "elapsed_ticks": elapsed_ticks, "total_ticks": total_ticks}
    return {"completed": false, "cycle": int(floor(float(elapsed_ticks) / float(ticks_per_cycle))),
        "tick": elapsed_ticks % ticks_per_cycle, "elapsed_ticks": elapsed_ticks,
        "total_ticks": total_ticks}

static func frame_for(count: int, local_tick: int, ticks_per_cycle: int) -> int:
    var frames: int = maxi(1, count)
    var tick_count: int = maxi(1, ticks_per_cycle)
    var tick: int = clampi(local_tick, 0, tick_count - 1)
    return clampi(int(floor(float(frames * tick) / float(tick_count))), 0, frames - 1)

static func total_seconds(cycle_ticks: int, child_casts: int) -> float:
    return float(maxi(1, cycle_ticks) * maxi(1, child_casts)) / HZ
