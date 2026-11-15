extends RefCounted
## V33 JX1 client skill 322 native-action selector (visual choice only).
## Ghidra game.exe SHA256 f17d35df...:
##   VA 0057B55B g_Random(2)
##   VA 0057B568 add eax, 0x0A
##   VA 0057B56F mov [esi+0xF0], eax
##   random=0 -> NPC action 10 (Attack2/AT02 for male 1H blade);
##   random!=0 -> NPC action 9 (Attack1/AT03 for male 1H blade).
## This has been traced on a successful skill-322 cast path, NOT every JX path.
## RNG sampling is done by Main.gd once after player.skill_started.
## AUTO uses Godot randi_range(0,1), not a claim of exact original PRNG.

const QA_AUTO: int = 0
const QA_FORCE_9: int = 1
const QA_FORCE_10: int = 2

static func resolve_action(sample: int, qa_mode: int = QA_AUTO) -> int:
    if qa_mode == QA_FORCE_9:
        return 9
    if qa_mode == QA_FORCE_10:
        return 10
    return 10 if sample == 0 else 9
