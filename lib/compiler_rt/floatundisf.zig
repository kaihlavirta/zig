const builtin = @import("builtin");
const common = @import("./common.zig");
const floatFromInt = @import("./float_from_int.zig").floatFromInt;

pub const panic = common.panic;

comptime {
    if (common.want_aeabi) {
        @export(&__aeabi_ul2f, .{ .name = "__aeabi_ul2f", .linkage = common.linkage, .visibility = common.visibility });
    } else {
        @export(&__floatundisf, .{ .name = if (common.want_windows_arm_abi) "__u64tos" else "__floatundisf", .linkage = common.linkage, .visibility = common.visibility });
    }
}

pub fn __floatundisf(a: u64) callconv(.c) f32 {
    return floatFromInt(f32, a);
}

fn __aeabi_ul2f(a: u64) callconv(.{ .arm_aapcs = .{} }) f32 {
    return floatFromInt(f32, a);
}
