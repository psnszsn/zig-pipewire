const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const Listener = utils.Listener;
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
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) *Listener(Event, DataType) {
        // const D = struct { f: @TypeOf(_listener), d: *DataType };
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_NODE_EVENTS,
            c.struct_pw_node_events,
            Event,
        );
        var listener = Listener(Event, DataType).init(allocator, _listener, data) catch unreachable;

        _ = spa.spa_interface_call_method(self, c.pw_node_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });
        return listener;
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
