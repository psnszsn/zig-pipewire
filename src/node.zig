const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const c = pw.c;

pub const Node = opaque {
    pub const Event = union(enum) {
        info: *const NodeInfo,
        // param,
        param: struct {
            seq: c_int,
            id: u32,
            index: u32,
            next: u32,
            spa_pod: *const spa.SpaPod,
        },
        // static void event_param(void *_data, int seq, uint32_t id,
        // uint32_t index, uint32_t next, const struct spa_pod *param)

    };

    pub fn addListener(
        self: *Node,
        allocator: anytype,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) void {
        const D = struct { f: @TypeOf(_listener), d: *DataType };
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_NODE_EVENTS,
            c.struct_pw_node_events,
            Event,
        );
        var listener = allocator.create(c.struct_spa_hook) catch unreachable;
        listener.* = std.mem.zeroes(c.struct_spa_hook);
        var fn_and_data = allocator.create(D) catch unreachable;
        fn_and_data.* = .{ .f = _listener, .d = data };

        _ = spa.spa_interface_call_method(self, c.pw_node_methods, "add_listener", .{
            listener,
            &c_events,
            fn_and_data,
        });
    }
};
pub const NodeInfo = extern struct {
    id: u32,
    max_input_ports: u32,
    max_output_ports: u32,
    change_mask: u64,
    n_input_ports: u32,
    n_output_ports: u32,
    state: c.enum_pw_node_state,
    @"error": [*c]const u8,
    props: *spa.SpaDict,
    params: [*c]c.struct_spa_param_info,
    n_params: u32,
};
