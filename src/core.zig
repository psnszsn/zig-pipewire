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
            // ?*c.struct_pw_registry,
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
            // ?*c.struct_pw_registry,
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
    ) utils.Hook(Event, DataType) {
        const D = utils.Hook(Event, DataType).D;
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_CORE_EVENTS,
            c.struct_pw_core_events,
            Event,
        );

        var listener = allocator.create(c.struct_spa_hook) catch unreachable;
        listener.* = std.mem.zeroes(c.struct_spa_hook);
        var fn_and_data = allocator.create(D) catch unreachable;
        fn_and_data.* = .{ .f = _listener, .d = data };

        _ = spa.spa_interface_call_method(self, c.pw_core_methods, "add_listener", .{
            listener,
            &c_events,
            fn_and_data,
        });
        return utils.Hook(Event, DataType){
            .hook = listener,
            .cb = fn_and_data,
        };
    }
};
