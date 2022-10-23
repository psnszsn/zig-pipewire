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

    extern fn pw_proxy_get_bound_id(proxy: *Proxy) u32; 
    pub fn getBoundId(self: *Proxy) u32{
        return pw_proxy_get_bound_id(self);
    }

    pub fn downcast(self: *Proxy, comptime T: type) *T {
        return @ptrCast(*T, self);
    }

    extern fn pw_proxy_destroy(self: *Proxy) void;
    pub fn destroy(self: *Proxy) void {
        pw_proxy_destroy(self);
    }
};
