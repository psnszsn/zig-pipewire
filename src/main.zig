const std = @import("std");
const ArrayList = std.ArrayList;
const pw = @import("pipewire.zig");

const Global = struct {
    id: u32,
    permissions: u32,
    typ: pw.ObjType,
    listener: ?*pw.utils.Listener = null,
    version: u32,
    props: std.StringArrayHashMap([]const u8),
    pub fn deinit(self: *Global) void {
        if (self.listener) |l| {
            l.deinit();
        }

        var it = self.props.iterator();
        while (it.next()) |prop| {
            // std.debug.print("key: {s}\n", .{prop.key_ptr.*});
            self.props.allocator.free(prop.key_ptr.*);
            self.props.allocator.free(prop.value_ptr.*);
        }
        self.props.deinit();
    }
};

const RemoteData = struct {
    allocator: std.mem.Allocator,
    registry: *pw.Registry,
    core: *pw.Core,
    loop: *pw.MainLoop,
    globals: std.AutoHashMap(u32, Global),
    default_sink_id: ?u32 = null,
    pub fn deinit(self: *RemoteData) void {
        var it = self.globals.valueIterator();
        while (it.next()) |g| {
            g.deinit();
        }
        self.globals.deinit();
    }
};

pub fn coreListener(data: *RemoteData, event: pw.Core.Event) void {
    _ = data;
    _ = event;
    // data.deinit();
    // data.loop.quit();
    std.debug.print("DONE\n", .{});
}
pub fn nodeListener(data: *RemoteData, event: pw.Node.Event) void {
    switch (event) {
        .info => |e| {
            var g = data.globals.getPtr(e.id).?;
            std.debug.assert(g.typ == .Node);

            std.debug.print("INFO {} - {?s} - {} props - {} params\n", .{
                e.id,
                g.props.get("node.name"),
                e.props.asSlice().len,
                e.n_params,
            });

            if (e.props.n_items > 0) {
                g.props = blk: {
                    var it = g.props.iterator();
                    while (it.next()) |prop| {
                        // std.debug.print("key: {s}\n", .{prop.key_ptr.*});
                        g.props.allocator.free(prop.key_ptr.*);
                        g.props.allocator.free(prop.value_ptr.*);
                    }
                    g.props.deinit();
                    break :blk e.props.toArrayHashMap(data.allocator);
                };
            }
        },
        .param => |param| {
            std.debug.print("PARAM {} \n", .{param});
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
        // tree.root.dump();

        if (std.mem.eql(u8, prop.key, "default.audio.sink")) {
            const default_sink = tree.root.Object.get("name").?.String;

            var it = data.globals.valueIterator();
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

pub fn registryListener(data: *RemoteData, event: pw.Registry.Event) void {
    switch (event) {
        .global => |e| {
            if (e.typ == .Profiler) return;

            data.globals.putNoClobber(e.id, .{
                .id = e.id,
                .typ = e.typ,
                .permissions = e.permissions,
                .version = e.version,
                .props = e.props.toArrayHashMap(data.allocator),
            }) catch unreachable;

            var proxy = data.registry.bind(e) catch unreachable;
            var g = data.globals.getPtr(e.id) orelse unreachable;

            std.debug.print("GLOBAL added : id:{} type:{} v:{}\n", .{ e.id, e.typ, e.version });
            switch (e.typ) {
                .Node => {
                    std.debug.print("props: {}\n\n", .{e.props});
                    var node = proxy.downcast(pw.Node);
                    var listener = node.addListener(data.allocator, RemoteData, data, nodeListener);
                    g.listener = listener;
                },
                .Metadata => {
                    std.debug.print("METADATA: \n", .{});
                    var metadata = proxy.downcast(pw.Metadata);
                    var listener = metadata.addListener(data.allocator, RemoteData, data, metadataListener);
                    g.listener = listener;
                },
                else => {},
            }
        },
        .global_remove => |e| {
            var kv = data.globals.fetchRemove(e.id).?;
            var g = kv.value;
            std.debug.print("GLOBAL REMOVED  {} {} {?s}!!!!!!!\n", .{ e.id, g.typ, g.props.get("node.name") });
            g.deinit();
        },
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    pw.c.pw_init(null, null);
    defer pw.c.pw_deinit();

    std.debug.print("{s}\n{s}\n", .{
        pw.c.pw_get_headers_version(),
        pw.c.pw_get_library_version(),
    });
    std.log.info("All your codebase are belong to us.", .{});

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
        .globals = @TypeOf(rd.globals).init(allocator),
        .allocator = allocator,
        .registry = registry,
        .core = core,
        .loop = loop,
    };

    // TODO: Do not assume passed type is a pointer
    var regitry_hook = registry.addListener(allocator, RemoteData, rd, registryListener);
    defer regitry_hook.deinit();

    // _ = core.sync(pw.c.PW_ID_CORE, 0);

    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);
    std.debug.print("default sink: {?s}\n", .{
        rd.globals.get(rd.default_sink_id.?).?.props.get("node.name"),
    });
    // try loop.run_();
    // loop.run_();
}

pub fn roundtrip(loop: *pw.MainLoop, core: *pw.Core, allocator: std.mem.Allocator) !void {
    // var done = false;
    _ = core.sync(pw.c.PW_ID_CORE, 0);
    const l = struct {
        pub fn coreListener(_loop: *pw.MainLoop, event: pw.Core.Event) void {
            _ = event;
            // data.deinit();
            _loop.quit();
            std.debug.print("DONE\n", .{});
        }
    }.coreListener;

    var core_hook = core.addListener(allocator, pw.MainLoop, loop, &l);
    defer core_hook.deinit();

    loop.run_();
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
