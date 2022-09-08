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
    ) *utils.Listener(Event, DataType) {
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_METADATA_EVENTS,
            c.struct_pw_metadata_events,
            Event,
        );

        var listener = utils.Listener(Event, DataType).init(allocator, _listener, data) catch unreachable;
        _ = spa.spa_interface_call_method(self, c.pw_metadata_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });
        return listener;
    }
};
