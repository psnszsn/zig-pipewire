const std = @import("std");
const pw = @import("pipewire.zig");
const c = pw.c;
const utils = pw.utils;
const spa = @import("spa.zig");
const Proxy = pw.Proxy;

pub const Registry = opaque {
    // void *data, uint32_t id,
    // uint32_t permissions, const char *type, uint32_t version,
    // const struct spa_dict *props
    pub const Global = struct {
        id: u32,
        permissions: u32,
        typ: ObjType,
        version: u32,
        props: *const spa.SpaDict,
        pub fn fromArgs(args_tuple: anytype) Global {
            return Global{
                .id = @intCast(u32, args_tuple[0]),
                .permissions = @intCast(u32, args_tuple[1]),
                .typ = ObjType.fromString(std.mem.span(@intToPtr([*c]const u8, args_tuple[2]))),
                .version = @intCast(u32, args_tuple[3]),
                .props = @intToPtr(*const spa.SpaDict, args_tuple[4]),
            };
        }
    };
    pub const Event = union(enum) {
        global: Global,
        global_remove: struct { id: u32 },
    };

    pub fn addListener(
        self: *Registry,
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: *DataType,
        comptime _listener: *const fn (data: *DataType, event: Event) void,
    ) *utils.Listener {
        const c_events = comptime utils.generateEventsStruct(
            c.PW_VERSION_REGISTRY_EVENTS,
            c.struct_pw_registry_events,
            Event,
        );

        var listener = utils.Listener.init(allocator, _listener, data) catch unreachable;

        _ = spa.spa_interface_call_method(self, c.pw_registry_methods, "add_listener", .{
            &listener.spa_hook,
            &c_events,
            &listener.cb,
        });

        return listener;
    }

    pub fn bind(self: *Registry, object: Global) !*Proxy {
        var proxy = spa.spa_interface_call_method(
            self,
            c.pw_registry_methods,
            "bind",
            .{ object.id, object.typ.toString().ptr, object.typ.clientVersion(), 0 },
        );

        if (proxy) |r| {
            return @ptrCast(*Proxy, r);
        }
        return error.CreationError;
    }
    extern fn pw_proxy_destroy(self: *Registry) void;
    pub fn destroy(self: *Registry) void {
        pw_proxy_destroy(self);
    }
};

pub const ObjType = enum {
    Client,
    ClientEndpoint,
    ClientNode,
    ClientSession,
    Core,
    Device,
    Endpoint,
    EndpointLink,
    EndpointStream,
    Factory,
    Link,
    Metadata,
    Module,
    Node,
    Port,
    Profiler,
    Registry,
    Session,

    Other,

    pub fn fromString(string: []const u8) ObjType {
        const prefix = "PipeWire:Interface:";
        if (std.mem.startsWith(u8, string, prefix)) {
            const name = string[prefix.len..];
            if (std.meta.stringToEnum(ObjType, name)) |e| {
                return e;
            }
        }
        return ObjType.Other;
    }
    pub fn toString(self: ObjType) [:0]const u8 {
        inline for (std.meta.fields(ObjType)) |f| {
            if (comptime std.mem.eql(u8, f.name, "Other")) {
                break;
            }
            if (@enumToInt(self) == f.value) {
                return "PipeWire:Interface:" ++ f.name;
            }
        }
        @panic("Other obj type");
    }

    pub fn clientVersion(self: ObjType) u32 {
        inline for (std.meta.fields(ObjType)) |f| {
            if (comptime std.mem.eql(u8, f.name, "Other")) {
                break;
            }
            if (@enumToInt(self) == f.value) {
                const v = comptime blk: {
                    var result: []const u8 = "PW_VERSION";
                    for (f.name) |char| {
                        if (std.ascii.isUpper(char)) {
                            result = result ++ "_";
                        }
                        result = result ++ [1]u8{std.ascii.toUpper(char)};
                    }
                    break :blk result;
                };
                return @field(c, v);
            }
        }
        @panic("Other obj type");
    }
};
