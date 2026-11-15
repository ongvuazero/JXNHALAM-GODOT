# JXNHALAM client JX1 — stage selection forensic model, NOT game combat code.
# Evidence: game.exe 0x5B2960, 0x5B2E10, 0x5B3290, 0x5B2F50, 0x5FEBF0.
extends RefCounted
class_name JX141StateModel
const FrameProbe = preload("res://scripts/JX141NativeFrameProbe.gd")

# Event index N maps to AnimFile(N+1) by 0x5B2960 stride 0xD4.
const STAGES = ["AnimFile1", "AnimFile2", "AnimFile3", "AnimFile4"]
const MAIN_STATE: int = 1

static func event_slot(event_index: int) -> String:
    if event_index < 0 or event_index > 3:
        return "INVALID"
    return STAGES[event_index]

static func main_sprite_allowed(missile_state: int) -> bool:
    # 0x5FEBFE: cmp main-render-state, 1; only state==1 draws main SPR.
    return missile_state == MAIN_STATE

static func visual_frame(total_frames: int, directions: int, dir64: int, age: int, duration: int, use_interval: bool = false, interval: int = 1) -> Dictionary:
    return FrameProbe.inspect(total_frames, directions, dir64, age, duration, interval, use_interval)

static func test_sample_directions() -> PackedInt32Array:
    # Three distinct native server directions; NOT interpolated position in screen space.
    return PackedInt32Array([3, 11, 19])
