extends RefCounted
## V3.5 / V3.6 verified on jxser_6.0_fix_27-2-2024.tgz.
## Allocations, not successful hits / damage / rendered sprites.
## Verified for 322/323/325 ONLY; other skills may use other paths.
const DISTINCT_BUFF_SKILL_ID: int = 1427
const ROUTE: String = "DO_MANY_ATTACK"
const SKILLS: Dictionary = {
    322: {"child_id": 326, "child_casts": 1, "missile_id": 138,
        "missiles_per_child": 3, "total_allocations": 3, "combat_route": ROUTE},
    323: {"child_id": 327, "child_casts": 5, "missile_id": 139,
        "missiles_per_child": 1, "total_allocations": 5, "combat_route": ROUTE},
    325: {"child_id": 408, "child_casts": 1, "missile_id": 141,
        "missiles_per_child": 3, "total_allocations": 3, "combat_route": ROUTE},
}

static func find(skill_id: int) -> Dictionary:
    return SKILLS.get(skill_id, {}).duplicate(true)
