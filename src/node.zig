const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const Listener = utils.Listener;
const c = pw.c;

pub const Node = opaque {
    pub const Event = union(enum) {
        info: *const NodeInfo,
        param: struct {
            seq: c_int,
            id: u32,
            index: u32,
            next: u32,
            spa_pod: *const spa.SpaPod,
        },
    };

    pub fn addListener(
        self: *Node,
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) *Listener {
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_NODE_EVENTS,
            c.struct_pw_node_events,
            Event,
        );
        var listener = Listener.init(allocator, _listener, data) catch unreachable;

        _ = spa.spa_interface_call_method(self, c.pw_node_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });
        return listener;
    }

    pub fn enumParams(self: *Node, seq: c_int, id: ParamInfo.ParamType, index: u32, num: u32, filter: ?*spa.SpaPod) isize {
        return spa.spa_interface_call_method(
            self,
            c.pw_node_methods,
            "enum_params",
            .{ seq, @enumToInt(id), index, num, @ptrCast(?*c.struct_spa_pod, filter) },
        );
    }

    pub fn setParam(self: *Node, id: u32, flags: u32, pod: *const spa.SpaPod) isize {
        return spa.spa_interface_call_method(
            self,
            c.pw_node_methods,
            "set_param",
            .{ id, flags, @ptrCast(?*const c.struct_spa_pod, pod) },
        );
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
    @"error": [*:0]const u8,
    props: *spa.SpaDict,
    params: [*]ParamInfo,
    n_params: u32,
    pub fn getParamInfos(self: *const NodeInfo) []ParamInfo {
        if (self.n_params == 0) return &[_]ParamInfo{};
        return self.params[0..self.n_params];
    }
};
pub const ParamInfo = extern struct {
    pub const ParamType = enum(u32) {
        Invalid,
        PropInfo,
        Props,
        EnumFormat,
        Format,
        Buffers,
        Meta,
        IO,
        EnumProfile,
        Profile,
        EnumPortConfig,
        PortConfig,
        EnumRoute,
        Route,
        Control,
        Latency,
        ProcessLatency,
    };
    id: ParamType,
    flags: u32,
    user: u32,
    padding: [5]u32,
    const SERIAL = 1 << 0;
    const READ = 1 << 1;
    const WRITE = 1 << 2;
    pub fn isRead(self: ParamInfo) bool {
        return self.flags & READ;
    }
    pub fn isWrite(self: ParamInfo) bool {
        return self.flags & WRITE;
    }
};
