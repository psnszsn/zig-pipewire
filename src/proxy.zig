const std = @import("std");
const Tuple = std.meta.Tuple;

pub const Proxy = opaque {
    extern fn pw_proxy_get_user_data(proxy: *Proxy) ?*anyopaque;
    pub fn getUserData(self: *Proxy, comptime DataType: type) *DataType {
        return @ptrCast(
            *DataType,
            @alignCast(@alignOf(DataType), pw_proxy_get_user_data(self)),
        );
    }

    extern fn pw_proxy_get_type(proxy: *Proxy, version: *u32) [*:0]const u8;
    pub fn getType(self: *Proxy) Tuple(&.{ [:0]const u8, u32 }) {
        var version: u32 = undefined;
        var typ = pw_proxy_get_type(self, &version);
        return .{ std.mem.span(typ), version };
    }

    pub fn downcast(self: *Proxy, comptime T: type) *T {
        return @ptrCast(*T, self);
    }
};
