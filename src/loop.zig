const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const c = pw.c;

pub const Loop = extern struct {
    system: [*c]c.struct_spa_system,
    loop: [*c]c.struct_spa_loop,
    control: [*c]c.struct_spa_loop_control,
    utils: [*c]c.struct_spa_loop_utils,

    pub fn getFd(self: *Loop) i32 {
        const fd = spa.spa_interface_call_method(self.control, c.spa_loop_control_methods, "get_fd", .{});
        std.debug.print("FD: {}\n", .{fd});
        return fd;
    }
    pub fn iterate(self: *Loop) !isize {
        spa.spa_interface_call_method(self.control, c.spa_loop_control_methods, "enter", .{});
        defer spa.spa_interface_call_method(self.control, c.spa_loop_control_methods, "leave", .{});

        const res = spa.spa_interface_call_method(self.control, c.spa_loop_control_methods, "iterate", .{-1});
        if (res < 0) switch (std.os.errno(res)) {
            .INTR => return error.Interrupted,
            else => |err| return std.os.unexpectedErrno(err),
        };
        return res;
    }
};
