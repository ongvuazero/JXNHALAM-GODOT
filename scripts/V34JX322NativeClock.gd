extends RefCounted
## V34: Native actor-frame sampling for successful skill 322/form-12 cast.
## Evidence: game.exe F17D35DF...; V9 FUN_005C6300 consumes NPC+F4/F8;
## V10 FUN_00528020 runs nominal 18-Hz game steps; FUN_00575960 increments F8.
## Baseline settings/skills.txt row 322: MslsGenerate=1, MslsGenerateData=5,
## WaitTime=0, ChildSkillNum=1 -> total_ticks=5 (for this dataset only).
## IMPORTANT: 0/1/2 NPC passes/step from FUN_00539B40 are not emulated:
## their producer/sync policy is not understood. This is NOMINAL timing, not
## guaranteed JX1 wall-clock duration. No combat/skill cooldown coupling.

const HZ: float = 18.0
const STEP_SECONDS: float = 1.0 / HZ
const TOTAL_TICKS_322: int = 5

static func nominal_seconds(total_ticks: int = TOTAL_TICKS_322) -> float:
    return float(maxi(1, total_ticks)) * STEP_SECONDS

static func tick_at_elapsed(elapsed: float, total_ticks: int = TOTAL_TICKS_322) -> int:
    var total: int = maxi(1, total_ticks)
    return clampi(int(floor(maxf(0.0, elapsed) * HZ)), 0, total - 1)

static func frame_in_direction(frame_count: int, current_tick: int,
        total_ticks: int = TOTAL_TICKS_322) -> int:
    var count: int = maxi(1, frame_count)
    var ticks: int = maxi(1, total_ticks)
    var selected_tick: int = clampi(current_tick, 0, ticks - 1)
    return clampi(int(floor(float(count * selected_tick) / float(ticks))), 0, count - 1)
