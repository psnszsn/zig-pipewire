const std = @import("std");
const ArrayList = std.ArrayList;
const pw = @import("pipewire");

const Global = struct {
    id: u32,
    permissions: u32,
    typ: pw.ObjType,
    listener: ?*pw.utils.Listener = null,
    proxy: *pw.Proxy,
    version: u32,
    // pod: ?*const pw.spa.SpaPod = null,
    props: std.StringArrayHashMap([]const u8),
    params: std.ArrayList(*const pw.spa.SpaPod),
    pub fn deinit(self: *Global) void {
        self.listener.?.deinit();
        self.proxy.destroy();
    }
};


const RemoteData = struct {
    allocator: std.mem.Allocator,
    registry: *pw.Registry,
    core: *pw.Core,
    loop: *pw.MainLoop,
    globals: std.SegmentedList(Global, 128),
    default_sink_id: ?u32 = null,
    pub fn deinit(self: *RemoteData) void {
        var it = self.globals.iterator(0);
        while (it.next()) |g| {
            g.deinit();
        }
        self.globals.deinit(self.allocator);
    }
    pub fn getGlobalById(self: *RemoteData, id: u32) *Global {
        var it = self.globals.iterator(0);
        while (it.next()) |g| {
            if (g.id == id) {
                return g;
            }
        }
        unreachable;
    }
};

pub fn registryListener(data: *RemoteData, event: pw.Registry.Event) void {
    switch (event) {
        .global => |e| {
            if (e.typ != .Node and e.typ != .Device and e.typ != .Metadata) return;
            // if (e.typ == .Device) return;

            var g = data.globals.addOne(data.allocator) catch unreachable;
            g.* = .{
                .id = e.id,
                .typ = e.typ,
                .permissions = e.permissions,
                .proxy = data.registry.bind(e) catch unreachable,
                .version = e.version,
                .props = e.props.toArrayHashMap(data.allocator),
                .params = @TypeOf(g.params).init(data.allocator),
            };

            switch (e.typ) {
                .Node => {
                    var node = g.proxy.downcast(pw.Node);
                    var listener = node.addListener(data.allocator, Global, g, nodeListener);
                    g.listener = listener;
                },
                .Device => {
                    var dev = g.proxy.downcast(pw.Device);
                    var listener = dev.addListener(data.allocator, Global, g, deviceListener);
                    g.listener = listener;
                },
                .Metadata => {
                    var meta = g.proxy.downcast(pw.Metadata);
                    var listener = meta.addListener(data.allocator, RemoteData, data, metadataListener);
                    g.listener = listener;
                },
                else => unreachable,
            }
        },
        .global_remove => {
            unreachable;
        },
    }
}
pub fn nodeListener(g: *Global, event: pw.Node.Event) void {
    switch (event) {
        .info => |e| {
            std.debug.assert(g.typ == .Node);

            std.debug.print("INFO {} - {?s} - {} props - {} params\n", .{
                e.id,
                g.props.get("node.name"),
                e.props.asSlice().len,
                e.n_params,
            });

            if (e.props.n_items > 0) {
                g.props = e.props.toArrayHashMap(g.props.allocator);
            }
        },
        .param => unreachable,
    }
}

pub fn deviceListener(g: *Global, event: pw.Device.Event) void {
    switch (event) {
        .info => |e| {
            std.debug.assert(g.typ == .Device);

            std.debug.print("DEVICE INFO {} - {?s} - {} props - {} params\n", .{
                e.id,
                g.props.get("device.name"),
                e.props.asSlice().len,
                e.n_params,
            });

            if (e.props.n_items > 0) {
                g.props = e.props.toArrayHashMap(g.props.allocator);
            }
            var dev = g.proxy.downcast(pw.Device);
            for (e.getParamInfos()) |pi| {
                if (pi.id == .Route) {
                    g.params.clearAndFree();
                    _ = dev.enumParams(0, pi.id, 0, 0, null);
                }
            }
        },
        .param => |param| {
            g.params.append(param.spa_pod) catch unreachable;
        },
    }
}

pub fn metadataListener(data: *RemoteData, event: pw.Metadata.Event) void {
    const prop = event.property;
    if (prop.type != null and std.mem.eql(u8, prop.type.?, "Spa:String:JSON")) {
        var parser = std.json.Parser.init(data.allocator, false);
        defer parser.deinit();
        var tree = parser.parse(prop.value) catch unreachable;
        defer tree.deinit();

        if (std.mem.eql(u8, prop.key, "default.audio.sink")) {
            const default_sink = tree.root.Object.get("name").?.String;

            var it = data.globals.iterator(0);
            while (it.next()) |g| {
                if (g.typ == .Node) {
                    if (g.props.get("node.name")) |name| {
                        if (std.mem.eql(u8, name, default_sink)) {
                            data.default_sink_id = g.id;
                            break;
                        }
                    }
                }
            } else {
                unreachable;
            }
        }
    }
}


pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    pw.c.pw_init(null, null);
    defer pw.c.pw_deinit();

    std.debug.print("{s}\n{s}\n", .{
        pw.c.pw_get_headers_version(),
        pw.c.pw_get_library_version(),
    });

    var loop = try pw.MainLoop.new();
    defer loop.destroy();

    var context = try pw.Context.new(loop.getLoop());
    defer context.destroy();

    var core = try context.connect(@sizeOf(RemoteData));
    defer core.disconnect();

    var registry = try core.getRegistry();
    defer registry.destroy();

    const rd = core.asProxy().getUserData(RemoteData);
    defer rd.deinit();
    rd.* = .{
        .globals = .{},
        .allocator = allocator,
        .registry = registry,
        .core = core,
        .loop = loop,
    };

    // TODO: Do not assume passed type is a pointer
    var regitry_hook = registry.addListener(allocator, RemoteData, rd, registryListener);
    defer regitry_hook.deinit();

    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);

    // var default_sink = rd.globals.get(rd.default_sink_id.?).?;
    // var node = default_sink.proxy.downcast(pw.Node);

    // const default_sink = rd.getGlobalById();
    const default_sink = rd.getGlobalById(rd.default_sink_id.?);
    const device_id = std.fmt.parseInt(u32, default_sink.props.get("device.id").?, 10) catch unreachable;
    const device = rd.getGlobalById(device_id);
    const profile_device = std.fmt.parseInt(u32, default_sink.props.get("card.profile.device").?, 10) catch unreachable;
    var route_index: i32 = undefined;
    var route_device: i32 = undefined;
    var mute: bool = undefined;
    for (device.params.items) |param| {
        const obj = param.body().Object;
        // const obj = device.params.items[0].body().Object;
        var it = obj.prop_iterator();
        while (it.next()) |curr| {
            const key = @intToEnum(pw.spa.pod.RouteParam, curr.key);
            if (key == .index) {
                route_index = curr.value.body().Int.*;
            } else if (key == .device) {
                route_device = curr.value.body().Int.*;
            } else if (key == .props) {
                const obj2 = curr.value.body().Object;
                var it2 = obj2.prop_iterator();
                while (it2.next()) |curr_prop| {
                    const key2 = @intToEnum(pw.spa.pod.SpaPropType, curr_prop.key);
                    if (key2 == .mute) {
                        mute = curr_prop.value.body().Bool.* == 1;
                    }
                }
            }
        }

        if (route_device == profile_device) break;


    }

    std.debug.print("default sink: {} {?s} {}\n", .{
        rd.default_sink_id.?,
        default_sink.props.get("node.name"),
        device.id,
    });
    var builder = pw.spa.pod.Builder.init(rd.allocator);
    defer builder.deinit();

    const RouteParam = pw.spa.pod.RouteParam;
    const PropType = pw.spa.pod.SpaPropType;

    try builder.add(.Object, .{
        .{ RouteParam.index, .{ .Int, .{route_index} } },
        .{ RouteParam.device, .{ .Int, .{route_device} } },
        .{
            RouteParam.props, .{
                .Object, .{
                    .{ PropType.mute, .{ .Bool, .{!mute} } },
                },
            },
        },
        .{ RouteParam.save, .{ .Bool, .{true} } },
    });

    // const json = try builder.deref().toJsonTree(rd.allocator);
    // json.root.dump();

    _ = device.proxy.downcast(pw.Device).setParam(pw.c.SPA_PARAM_Route, 0, builder.deref());

    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);
}

pub fn roundtrip(loop: *pw.MainLoop, core: *pw.Core, allocator: std.mem.Allocator) !void {
    _ = core.sync(pw.c.PW_ID_CORE, 0);
    const l = struct {
        pub fn coreListener(_loop: *pw.MainLoop, event: pw.Core.Event) void {
            _ = event;
            _loop.quit();
            std.debug.print("DONE\n", .{});
        }
    }.coreListener;

    var core_hook = core.addListener(allocator, pw.MainLoop, loop, &l);
    defer core_hook.deinit();

    loop.run();
}
