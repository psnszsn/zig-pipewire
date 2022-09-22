const std = @import("std");
pub const SpaPod = @import("spa/pod.zig").SpaPod;
const c = @cImport({
    @cInclude("pipewire/pipewire.h");
});

fn SpaMethodReturnType(comptime methods_struct: type, comptime method_name: []const u8) type {
    const T = @typeInfo(methods_struct).Struct;
    inline for (T.fields) |field| {
        if (comptime std.mem.eql(u8, method_name, field.name)) {
            const t = @typeInfo(field.field_type).Optional.child;
            const t2 = @typeInfo(t).Pointer.child;
            const t3 = @typeInfo(t2).Fn.return_type orelse unreachable;
            return t3;
        }
    }
}

pub fn spa_interface_call_method(
    ptr: *anyopaque,
    comptime methods_struct: type,
    comptime method_name: []const u8,
    args: anytype,
) SpaMethodReturnType(methods_struct, method_name) {
    var interface = @ptrCast(
        *c.spa_interface,
        @alignCast(@alignOf(c.spa_interface), ptr),
    );

    var funcs = @ptrCast(
        *const methods_struct,
        @alignCast(
            @alignOf(methods_struct),
            (interface.cb).funcs,
        ),
    );

    const f = @field(funcs, method_name) orelse unreachable;
    return @call(.{}, f, .{interface.cb.data} ++ args);
}

test {
    const struct_obj = extern struct { proxy: extern struct { interface: extern struct {
        type: [*:0]const u8,
        version: u32,
        cb: extern struct {
            funcs: ?*const anyopaque,
            data: ?*anyopaque,
        },
    } } };

    const struct_methods = extern struct {
        version: u32,
        hello: ?*const fn (?*anyopaque, i32) callconv(.C) c_int,
    };

    const methods = struct_methods{ .version = 0, .hello = struct {
        pub fn hello(obj: ?*anyopaque, arg: i32) callconv(.C) c_int {
            _ = obj;
            return arg + 1;
        }
    }.hello };

    const obj = struct_obj{ .proxy = .{ .interface = .{
        .type = "obj",
        .version = 0,
        .cb = .{
            .funcs = @ptrCast(?*const anyopaque, &methods),
            .data = null,
        },
    } } };

    const ret = spa_interface_call_method(&obj, struct_methods, "hello", .{8});
    try std.testing.expectEqual(ret, 9);
}

pub const SpaDict = extern struct {
    pub const Item = extern struct {
        key: [*:0]const u8,
        value: [*:0]const u8,
    };
    flags: u32,
    n_items: u32,
    items: [*]const Item,
    pub fn asSlice(self: SpaDict) []const Item {
        return self.items[0..self.n_items];
    }
    pub fn toArrayHashMap(self: SpaDict, allocator: std.mem.Allocator) std.StringArrayHashMap([]const u8) {
        var hm = std.StringArrayHashMap([]const u8).init(allocator);
        for (self.asSlice()) |item| {
            const key = allocator.dupe(u8, std.mem.span(item.key)) catch unreachable;
            const val = allocator.dupe(u8, std.mem.span(item.value)) catch unreachable;
            hm.putNoClobber(key, val) catch unreachable;
        }
        return hm;
    }
    pub fn format(
        self: SpaDict,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        for (self.asSlice()) |item| {
            try writer.print("{s}, ", .{item.key});
        }

        try writer.print("{} items ", .{self.n_items});
    }
};
