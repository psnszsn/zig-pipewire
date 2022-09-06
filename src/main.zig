const std = @import("std");
const ArrayList = std.ArrayList;
const pw = @import("pipewire.zig");

const Global = struct {
    id: u32,
    permissions: u32,
    typ: pw.ObjType,
    listener: ?*anyopaque = null,
    version: u32,
    props: std.StringArrayHashMap([]const u8),
    pub fn deinit(self: *Global) void {
        if (self.listener) |l_ptr| {
            if (self.typ == .Node) {
                var listener = @ptrCast(
                    *pw.utils.Listener(pw.Node.Event, RemoteData),
                    l_ptr,
                );
                listener.deinit();
            }
        }

        var it = self.props.iterator();
        while (it.next()) |prop| {
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
    default_sink: ?[]const u8 = null,
    pub fn deinit(self: *RemoteData) void {
        var it = self.globals.valueIterator();
        while (it.next()) |g| {
            g.deinit();
        }
        self.globals.deinit();
    }
};

pub fn coreListener(data: *RemoteData, event: pw.Core.Event) void {
    // _ = data;
    _ = event;
    // data.deinit();
    data.loop.quit();
    std.debug.print("DONE\n", .{});
}
pub fn nodeListener(data: *RemoteData, event: pw.Node.Event) void {
    _ = data;
    switch (event) {
        .info => |e| {
            var g = data.globals.get(e.id).?;
            // std.debug.assert(g.props == e.props);
            // std.debug.print("{} \n", .{e.props});
            _ = g;
            // var len = std.mem.len(e.props.*.items);
            std.debug.print("INFO {}\n", .{e});
            // std.debug.print("INFO {?s}\n", .{g.props.get("node.name")});
            for (e.props.asSlice()) |prop| {
                const c_key = std.mem.span(prop.key);
                const c_val = std.mem.span(prop.value);
                // if (std.mem.eql(u8, c_key, "application.name")) {
                //     continue;
                // }
                if (g.props.get(c_key)) |old| {
                    if (!std.mem.eql(u8, old, c_val)) {
                        const val = data.allocator.dupe(u8, std.mem.span(prop.value)) catch unreachable;
                        g.props.put(c_key, val) catch unreachable;
                        std.debug.print("UPDATE: key:{s} OLD:{s} NEW:{s}\n", .{ c_key, old, val });
                        data.allocator.free(old);
                    } else {
                        std.debug.print("EXISTING: key:{s} VAL:{s}\n", .{ c_key, c_val });
                    }
                } else {
                    const key = data.allocator.dupe(u8, c_key) catch unreachable;
                    const val = data.allocator.dupe(u8, c_val) catch unreachable;
                    std.debug.print("NEW: key:{s} VAL:{s}\n", .{ key, val });
                    g.props.put(key, val) catch unreachable;
                }
                // std.debug.print("INFO {?s}\n", .{g.props.get("node.name")});
                // std.debug.print("{s}\n", .{key});
                // if (std.mem.eql(u8, c_key, "node.name")) {
                //     std.debug.print("{s}\n", .{prop.value});
                // }
            }
            std.debug.print("\n", .{});
        },
        .param => |param| {
            std.debug.print("PARAM {} \n", .{param});
        },
    }
}
pub fn metadataListener(data: *RemoteData, event: pw.Metadata.Event) void {
    _ = data;
    _ = event;
    const prop = event.property;
    // if (prop.key == null) {
    //     std.debug.print("remove: id:{} all keys\n", .{prop.id});
    // } else if (prop.value == null) {
    //     std.debug.print("remove: id:{} key:{}\n", .{prop.id, prop.key});
    // } else {
    if (prop.type != null and std.mem.eql(u8, prop.type.?, "Spa:String:JSON")) {
        var parser = std.json.Parser.init(data.allocator, false);
        defer parser.deinit();
        var tree = parser.parse(prop.value) catch unreachable;
        defer tree.deinit();
        // tree.root.dump();

        if (std.mem.eql(u8, prop.key, "default.audio.sink")) {
            const default_sink = tree.root.Object.get("name").?.String;
            // data.default_sink = data.allocator.dupe(u8, default_sink);
            data.default_sink = default_sink;
            std.debug.print("SINK {s}\n", .{default_sink});
        }
    }
    std.debug.print("update: id:{} key:{s} value:{s} type:{?s}\n", .{ prop.id, prop.key, prop.value, prop.type });

    // }
}

pub fn registryListener(data: *RemoteData, event: pw.Registry.Event) void {
    switch (event) {
        .global => |e| {
            if (e.typ == .Profiler) return;

            if (data.globals.fetchPut(e.id, .{
                .id = e.id,
                .typ = e.typ,
                .permissions = e.permissions,
                .version = e.version,
                .props = e.props.toArrayHashMap(data.allocator),
            }) catch unreachable) |old| {
                var v = old.value;
                std.debug.print("GLOBAL REPLACED {?s}\n", .{v.props.get("node.name")});
                v.deinit();
            }
            var proxy = data.registry.bind(e) catch unreachable;
            // std.debug.print("{s}\n", .{proxy.get_type()[0]});
            _ = proxy;
            _ = e.typ.clientVersion();
            // std.debug.print("{s}\n", .{data.globals.items[data.globals.items.len - 1].typ});

            var g = data.globals.getPtr(e.id) orelse unreachable;

            switch (e.typ) {
                .Node => {
                    std.debug.print("object: id:{} type:{} v:{}\n", .{ e.id, e.typ, e.version });
                    std.debug.print("props: {}\n\n", .{e.props});
                    var node = proxy.downcast(pw.Node);
                    var listener = node.addListener(data.allocator, RemoteData, data, nodeListener);
                    g.listener = listener;
                    _ = data.core.sync(pw.c.PW_ID_CORE, 0);
                },
                .Metadata => {
                    // std.debug.print("METADATA: \n", .{});
                    // var metadata = proxy.downcast(pw.Metadata);
                    // metadata.addListener(data.allocator, RemoteData, data, metadataListener);
                },
                else => {},
            }
        },
        .global_remove => |e| {
            var kv = data.globals.fetchRemove(e.id).?;
            var g = kv.value;
            // std.debug.print("GLOBAL REMOVED {} {?s}!!!!!!!\n", .{g.typ, g.props.get("node.name")});
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
    _ = registry;
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

    var regitry_hook = registry.addListener(allocator, RemoteData, rd, registryListener);
    defer regitry_hook.deinit();
    _ = regitry_hook;

    var core_hook = core.addListener(allocator, RemoteData, rd, coreListener);
    defer core_hook.deinit();
    _ = core_hook;
    _ = core.sync(pw.c.PW_ID_CORE, 0);

    // try loop.run_();
    loop.run_();
}
test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
