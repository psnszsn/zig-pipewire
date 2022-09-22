const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const c = pw.c;

pub const Core = opaque {
    pub fn getRegistry(self: *Core) !*pw.Registry {
        var registry = spa.spa_interface_call_method(
            self,
            c.pw_core_methods,
            "get_registry",
            .{ c.PW_VERSION_REGISTRY, 0 },
        );
        if (registry) |r| {
            return @ptrCast(*pw.Registry, r);
        }
        return error.CreationError;
    }

    pub fn sync(self: *Core, id: u32, seq: c_int) isize {
        return spa.spa_interface_call_method(
            self,
            c.pw_core_methods,
            "sync",
            .{ id, seq },
        );
    }

    extern fn pw_core_disconnect(core: *Core) c_int;
    pub fn disconnect(self: *Core) void {
        _ = pw_core_disconnect(self);
    }

    pub fn asProxy(self: *Core) *pw.Proxy {
        return @ptrCast(*pw.Proxy, self);
    }

    pub const Event = union(enum) {
        done: struct {
            id: u32,
            seq: isize,
            pub fn fromArgs(args_tuple: anytype) @This() {
                return @This(){
                    .id = @intCast(u32, args_tuple[0]),
                    .seq = @intCast(isize, args_tuple[1]),
                };
            }
        },
        param,
    };

    pub fn addListener(
        self: *Core,
        allocator: anytype,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) *utils.Listener {
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_CORE_EVENTS,
            c.struct_pw_core_events,
            Event,
        );

        var listener = utils.Listener.init(allocator, _listener, data) catch unreachable;

        _ = spa.spa_interface_call_method(self, c.pw_core_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });
        return listener;
    }
};
