const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const c = pw.c;

pub const Metadata = opaque {
    pub const Event = union(enum) {
        property: struct {
            id: u32,
            key: [:0]const u8,
            type: ?[:0]const u8,
            value: [:0]const u8,
        },
    };
    pub fn addListener(
        self: *Metadata,
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) void {
        const D = struct { f: @TypeOf(_listener), d: *DataType };
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_METADATA_EVENTS,
            c.struct_pw_metadata_events,
            Event,
        );
        var listener = allocator.create(c.struct_spa_hook) catch unreachable;
        listener.* = std.mem.zeroes(c.struct_spa_hook);
        var fn_and_data = allocator.create(D) catch unreachable;
        fn_and_data.* = .{ .f = _listener, .d = data };

        _ = spa.spa_interface_call_method(self, c.pw_metadata_methods, "add_listener", .{
            listener,
            &c_events,
            fn_and_data,
        });
    }
};
