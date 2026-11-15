extends RefCounted
## Verified static x86 PE transform for JX1 client renderer.
## represent2.dll: 0x10003BA0; represent3.dll: 0x1000D070.
## Both use the SAME projection; camera offsets are private runtime fields.
## No x/y camera values are fabricated in this helper.
## Result units: client renderer screen-space integer coordinates before later viewport/clipping.

static func _half_trunc_toward_zero(value: int) -> int:
    # x86: cdq / sub eax,edx / sar eax,1  -> integer truncation toward 0.
    var result: int = value >> 1
    if value < 0 and (value & 1) != 0:
        result += 1
    return result

static func project(world_x: int, world_y: int, world_z: int, camera_x: int, camera_y: int) -> Vector2i:
    # Original x86 IMUL 0x377 (887), SAR 10 (1024); signed arithmetic shift.
    var z_reduction: int = (world_z * 887) >> 10
    return Vector2i(world_x - camera_x, _half_trunc_toward_zero(world_y) - z_reduction - camera_y)

static func relative_to_anchor(world_x: int, world_y: int, world_z: int, anchor_x: int, anchor_y: int, anchor_z: int) -> Vector2i:
    # Unknown camera cancels exactly when both positions share a camera state.
    # This is the only PROVEN visual placement that the JX141 V12 audit draws.
    var p: Vector2i = project(world_x, world_y, world_z, 0, 0)
    var a: Vector2i = project(anchor_x, anchor_y, anchor_z, 0, 0)
    return p - a

static func unproject_flat(screen_x: int, screen_y: int, world_z: int, camera_x: int, camera_y: int) -> Vector2i:
    # The inverse Y is not unique for odd world Y due to trunc(Y/2).
    # Only use as a back-projection on the even-Y integer grid.
    var z_reduction: int = (world_z * 887) >> 10
    return Vector2i(screen_x + camera_x, (screen_y + camera_y + z_reduction) * 2)
