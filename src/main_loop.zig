const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const c = pw.c;

pub const MainLoop = opaque {
    extern fn pw_main_loop_new(props: ?*const c.struct_spa_dict) ?*MainLoop;
    pub fn new() !*MainLoop {
        // var loop = @ptrCast(?*MainLoop, c.pw_main_loop_new(null));
        var loop = pw_main_loop_new(null);
        return loop orelse error.CreationError;
    }

    extern fn pw_main_loop_get_loop(loop: *MainLoop) *pw.Loop;
    pub fn getLoop(self: *MainLoop) *pw.Loop {
        return pw_main_loop_get_loop(self);
    }
    extern fn pw_main_loop_run(loop: *MainLoop) c_int;
    pub fn run(self: *MainLoop) void {
        _ = pw_main_loop_run(self);
    }

    pub fn run_(self: *MainLoop) !void {
        const os = std.os;
        const pw_epoll_fd = self.getLoop().getFd();
        std.debug.print("Hello\n", .{});
        var running = true;
        const epollfd = try os.epoll_create1(os.linux.EPOLL.CLOEXEC);
        defer os.close(epollfd);

        var event = os.linux.epoll_event{
            .events = os.linux.EPOLL.IN,
            .data = .{ .ptr = @ptrToInt(self) },
        };
        try os.epoll_ctl(epollfd, os.linux.EPOLL.CTL_ADD, pw_epoll_fd, &event);

        var events: [5]os.linux.epoll_event = undefined;
        while (running) {
            // std.debug.print("Polling...\n", .{});
            const event_count = os.epoll_wait(epollfd, events[0..], -1);
            // std.debug.print("{} events ready.\n", .{event_count});
            var i: usize = 0;
            while (i < event_count) : (i += 1) {
                const l = @intToPtr(*MainLoop, events[i].data.ptr);
                _ = l.getLoop().iterate() catch |err| {
                    if (err == error.Interrupted) continue;
                    std.debug.print("ITERATE ERROR\n", .{});
                };
                // const fd = events[i].data.fd;

            }
        }
        std.debug.print("{}\n", .{epollfd});
    }

    extern fn pw_main_loop_quit(loop: *MainLoop) c_int;
    pub fn quit(self: *MainLoop) void {
        _ = pw_main_loop_quit(self);
    }

    extern fn pw_main_loop_destroy(loop: *MainLoop) void;
    pub fn destroy(self: *MainLoop) void {
        pw_main_loop_destroy(self);
    }
};
