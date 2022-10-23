const std = @import("std");
const pw = @import("pipewire.zig");
const spa = @import("spa.zig");
const utils = pw.utils;
const Listener = utils.Listener;
const c = pw.c;

pub const Device = opaque {
    pub const Event = union(enum) {
        info: *const DeviceInfo,
        param: struct {
            seq: c_int,
            id: u32,
            index: u32,
            next: u32,
            spa_pod: *const spa.SpaPod,
        },
    };

    pub fn addListener(
        self: *Device,
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) *Listener {
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_DEVICE_EVENTS,
            c.struct_pw_device_events,
            Event,
        );
        var listener = Listener.init(allocator, _listener, data) catch unreachable;

        _ = spa.spa_interface_call_method(self, c.pw_device_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });
        return listener;
    }

    pub fn enumParams(self: *Device, seq: c_int, id: pw.ParamInfo.ParamType, index: u32, num: u32, filter: ?*spa.SpaPod) isize {
        return spa.spa_interface_call_method(
            self,
            c.pw_device_methods,
            "enum_params",
            .{ seq, @enumToInt(id), index, num, @ptrCast(?*c.struct_spa_pod, filter) },
        );
    }
    pub fn setParam(self: *Device, id: u32, flags: u32, pod: *const spa.SpaPod) isize {
        return spa.spa_interface_call_method(
            self,
            c.pw_device_methods,
            "set_param",
            .{ id, flags, @ptrCast(?*const c.struct_spa_pod, pod) },
        );
    }

    // pub fn setParam(self: *Node, id: u32, flags: u32, pod: *const spa.SpaPod) isize {
    //     return spa.spa_interface_call_method(
    //         self,
    //         c.pw_node_methods,
    //         "set_param",
    //         .{ id, flags, @ptrCast(?*const c.struct_spa_pod, pod) },
    //     );
    // }
};

pub const DeviceInfo = extern struct {
    id: u32,
    change_mask: u64,
    props: *spa.SpaDict,
    params: [*]pw.ParamInfo,
    n_params: u32,
    pub fn getParamInfos(self: *const DeviceInfo) []pw.ParamInfo {
        if (self.n_params == 0) return &[_]pw.ParamInfo{};
        return self.params[0..self.n_params];
    }
};

