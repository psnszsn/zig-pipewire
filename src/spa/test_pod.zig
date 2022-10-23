
const std = @import("std");
const pod = @import("pod.zig");
const Builder = pod.Builder;
const SpaPropType = pod.SpaPropType;

extern fn build_bool(buffer: [*]u8, len: usize, boolean: bool) c_int;
extern fn build_string(buffer: [*]u8, len: usize, string: [*:0]const u8) c_int;
extern fn build_test_object(buffer: [*]u8, len: usize) c_int;
test "object" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    const string: [:0]const u8 = "hw:0";

    try b.add(.Object, .{
        .{ SpaPropType.device, .{ .String, .{string} } },
        .{ SpaPropType.frequency, .{ .Float, .{@as(f32, 440)} } },
    });

    var c_buf = [_]u8{0} ** 64;
    _ = build_test_object(&c_buf, 64);

    try std.testing.expectEqualSlices(u8, &c_buf, b.data.items);
}

test "bool" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.add(.Bool, .{true});
    try std.testing.expectEqual(b.deref().size, 4);

    var c_buf = [_]u8{0} ** 16;
    try std.testing.expectEqual(build_bool(&c_buf, 16, true), 0);

    try std.testing.expectEqualSlices(u8, &c_buf, b.data.items);
}
test "string" {
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();
    const string: [:0]const u8 = "123456789";

    try b.add(.String, .{string});

    var c_buf = [_]u8{0} ** 24;
    try std.testing.expectEqual(build_string(&c_buf, 24, string.ptr), 0);

    try std.testing.expectEqualSlices(u8, &c_buf, b.data.items);
}

extern fn build_array(buffer: [*]u8, len: usize, child_size: u32, child_type: pod.spa_type, n_elems: u32, elems: *anyopaque) c_int;
test "array" {
    var array = [_]i32{10, 15, 19} ;
    var b = Builder.init(std.testing.allocator);
    defer b.deinit();

    try b.add(.Array, .{&array});

    var c_buf = [_]u8{0} ** 32;
    try std.testing.expectEqual(build_array(&c_buf, 32, @sizeOf(i32), .Int, array.len, &array ), 0);

    std.debug.print("\nc: {any}\n", .{c_buf});
    std.debug.print("d: {any}\n", .{b.data.items});
    
    try std.testing.expectEqualSlices(u8, &c_buf, b.data.items);
}
