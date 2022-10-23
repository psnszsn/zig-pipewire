const std = @import("std");
const fileNS = @This();

pub inline fn round_down_n(num: usize, algn: usize) usize {
    return num & ~(algn - 1);
}
pub inline fn round_up_n(num: usize, algn: usize) usize {
    return round_down_n(num + (algn - 1), algn);
}

pub const Builder = struct {
    data: std.ArrayList(u8),
    parents: [4]usize = [_]usize{0} ** 4,
    depth: usize = 0,
    needs_obj_body: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Builder) void {
        self.data.deinit();
    }
    pub fn reset(self: *Builder) void {
        self.data.clearAndFree();
        self.depth = 0;
    }

    pub inline fn pushVal(self: *Builder, v: anytype) !void {
        const bytes = std.mem.asBytes(&v);
        return self.pushBytes(bytes);
    }

    pub fn updateParentSize(self: *Builder) void {
        const pi = self.parents[self.depth - 1];
        self.parent().size = @intCast(u32, self.data.items.len - pi - @sizeOf(SpaPod));
    }

    pub fn pushBytes(self: *Builder, bytes: []const u8) !void {
        try self.data.appendSlice(bytes);
        self.updateParentSize();
    }

    pub fn pushString(self: *Builder, bytes: []const u8) !void {
        try self.data.appendSlice(bytes);
        try self.data.appendSlice(&[_]u8{0});
        self.updateParentSize();
    }
    pub fn pushArray(self: *Builder, slice: anytype) !void {
        std.debug.assert(std.meta.trait.isIndexable(@TypeOf(slice)));
        const Elem = std.meta.Elem(@TypeOf(slice));

        inline for (@typeInfo(ArrayBody.ArraySlice).Union.fields) |union_field| {
            if (std.meta.Child(union_field.field_type) == Elem) {
                const child_spa_type: spa_type = @field(spa_type, union_field.name);
                try self.push(child_spa_type);
                self.parent().size = @sizeOf(Elem);
                self.depth -= 1;
                try self.pushVal(slice.*);
                return;
            }
        }
        // unreachable;
        @panic("Invalid slice type");
        // @compileError("Invalid slice type");
    }

    pub fn pad(self: *Builder) !void {
        const len = self.data.items.len;
        const r = round_up_n(len, 8);
        try self.data.appendNTimes(0, r - len);
        self.depth -= 1;
        if (self.depth > 0) self.updateParentSize();
    }

    pub fn push(self: *Builder, typ: spa_type) !void {
        const v = SpaPod{ .size = 0, .type = typ };
        const index = self.data.items.len;
        self.parents[self.depth] = index;
        self.depth += 1;
        try self.pushVal(v);

        switch (typ) {
            .Object => {
                self.needs_obj_body = true;
            },
            else => {},
        }
    }

    pub fn pushProp(self: *Builder, key: anytype) !void {
        if (self.needs_obj_body) {
            switch (@TypeOf(key)) {
                SpaPropType => {
                    const body = ObjBody{ .type = .OBJECT_Props, .id = 2 };
                    try self.pushVal(body);
                },
                RouteParam => {
                    const body = ObjBody{ .type = .OBJECT_ParamRoute, .id = 13 };
                    try self.pushVal(body);
                },
                else => unreachable,
            }
            self.needs_obj_body = false;
        }
        const Prop = extern struct { key: @TypeOf(key), flags: u32 };
        const p = Prop{ .key = key, .flags = 0 };
        try self.pushVal(p);
    }

    pub fn add(self: *Builder, typ: spa_type, args: anytype) !void {
        // const active_tag = @intToEnum(std.meta.Tag(SpaPodBody), @enumToInt(typ));
        const active_tag = std.meta.stringToEnum(std.meta.Tag(SpaPodBody), @tagName(typ)) orelse unreachable;

        try self.push(typ);
        switch (active_tag) {
            .String => {
                if (comptime std.meta.trait.isSliceOf(.Int)(@TypeOf(args[0]))) {
                    try self.pushString(args[0]);
                } else {
                    unreachable;
                }
            },
            .Object => {
                const fields = std.meta.fields(@TypeOf(args));
                inline for (fields) |f, i| {
                    if (comptime std.meta.trait.isTuple(f.field_type)) {
                        try self.pushProp(args[i][0]);
                        try @call(.{}, self.add, args[i][1]);
                    } else {
                        unreachable;
                    }
                }
            },
            .Bool => {
                if (@typeInfo(@TypeOf(args[0])) == .Bool) {
                    const repl: u32 = if (args[0]) 1 else 0;
                    try self.pushVal(repl);
                } else {
                    unreachable;
                }
            },
            .Array => {
                const T = @TypeOf(args[0]);
                if (comptime std.meta.trait.isIndexable(T) and !std.meta.trait.isTuple(T) ) {
                    try self.pushArray(args[0]);
                } else {
                    unreachable;
                }
            },
            inline else => {
                try self.pushVal(args[0]);
            },
        }
        try self.pad();
    }

    pub fn deref(self: *const Builder) *SpaPod {
        return @ptrCast(*SpaPod, @alignCast(@alignOf(*SpaPod), &self.data.items[0]));
    }

    pub fn parent(self: *const Builder) *SpaPod {
        const i = self.parents[self.depth - 1];
        return @ptrCast(*SpaPod, @alignCast(@alignOf(*SpaPod), &self.data.items[i]));
    }
};

test {
    _ = @import("test_pod.zig");
}

pub const ObjBody = extern struct {
    type: spa_type,
    id: u32,

    pub const SpaPodPropIterator = struct {
        current: *const Prop,
        body: *const ObjBody,
        body_size: usize,
        pub fn next(self: *SpaPodPropIterator) ?*const Prop {
            if (!self.current.is_inside(self.body, self.body_size)) {
                return null;
            }
            defer self.current = self.current.next();
            return self.current;
        }
    };
    pub const Prop = extern struct {
        key: u32,
        flags: u32,
        value: SpaPod,
        pub fn size(self: *const Prop) usize {
            return @sizeOf(Prop) + self.value.size;
        }
        pub fn name(self: *const Prop, obj_type: spa_type) [:0]const u8 {
            switch (obj_type) {
                .OBJECT_Props => {
                    return @tagName(@intToEnum(SpaPropType, self.key));
                },
                inline else => |t| {
                    if (comptime std.mem.startsWith(u8, @tagName(t), "OBJECT_Param")) {
                        const enumName = @tagName(t)[12..] ++ "Param";
                        if (@hasDecl(fileNS, enumName)) {
                            const EnumType = @field(fileNS, enumName);
                            return @tagName(@intToEnum(EnumType, self.key));
                        }
                    }
                },
            }
            unreachable;
        }

        pub fn next(self: *const Prop) *const Prop {
            const next_ptr = @ptrToInt(self) + round_up_n(self.size(), 8);
            return @intToPtr(*const Prop, next_ptr);
        }
        pub fn is_inside(self: *const Prop, body: *const ObjBody, body_size: usize) bool {
            const start = @ptrToInt(self) + @sizeOf(Prop);
            const end = @ptrToInt(self) + self.size();
            const max = @ptrToInt(body) + body_size;
            return start <= max and end <= max;
        }
    };

    pub fn prop_iterator(self: *const ObjBody) SpaPodPropIterator {
        const first_ptr = @ptrToInt(self) + @sizeOf(SpaPod);
        const first = @intToPtr(*const Prop, first_ptr);
        const parent = @intToPtr(*const SpaPod, @ptrToInt(self) - @sizeOf(SpaPod));
        return .{
            .current = first,
            .body = self,
            .body_size = parent.size,
        };
    }
};

pub const ArrayBody = extern struct {
    child: SpaPod,
    pub const ArraySlice = union(enum) {
        Float: []f32,
        Double: []f64,
        Int: []i32,
        Id: []u32,
        Long: []i64,
        Bool: []bool,
        fn toJsonValue(self: ArraySlice, allocator: std.mem.Allocator) !std.json.Value {
            var arr = std.json.Array.init(allocator);
            switch (self) {
                .Float => |f| {
                    for (f) |c| {
                        const val = std.json.Value{ .Float = c };
                        try arr.append(val);
                    }
                },
                inline .Int, .Id => |f| {
                    for (f) |c| {
                        const val = std.json.Value{ .Integer = c };
                        try arr.append(val);
                    }
                },
                else => unreachable,
            }
            return std.json.Value{ .Array = arr };
        }
    };

    pub fn asSlice(self: *const ArrayBody) ArraySlice {
        const first_ptr = @ptrToInt(self) + @sizeOf(ArrayBody);
        const parent = @intToPtr(*const SpaPod, @ptrToInt(self) - @sizeOf(SpaPod));
        const len = (parent.size - @sizeOf(ArrayBody)) / self.child.size;

        const active_tag = std.meta.stringToEnum(std.meta.Tag(ArraySlice), @tagName(self.child.type)) orelse unreachable;
        switch (active_tag) {
            inline else => |t| {
                const subtype = std.meta.TagPayload(ArraySlice, t);
                comptime var ti = @typeInfo(subtype);
                ti.Pointer.size = .Many;
                const b = @intToPtr(@Type(ti), first_ptr);
                return @unionInit(ArraySlice, @tagName(t), b[0..len]);
            },
        }
    }
};

pub const StructBody = opaque {
    pub const Iterator = struct {
        current: *const SpaPod,
        parent: *const SpaPod,
        pub fn next(self: *Iterator) ?*const SpaPod {
            if (!self.current.is_inside(self.parent)) {
                return null;
            }
            defer self.current = self.current.next();
            return self.current;
        }
    };
    pub fn iterator(self: *const StructBody) Iterator {
        const first_ptr = @ptrToInt(self);
        const first = @intToPtr(*const SpaPod, first_ptr);
        const parent = @intToPtr(*const SpaPod, first_ptr - @sizeOf(SpaPod));
        return .{
            .current = first,
            .parent = parent,
        };
    }
};

pub const SpaPodBody = union(enum) {
    Object: *ObjBody,
    String: [*:0]u8,
    Float: *f32,
    Double: *f64,
    Int: *i32,
    Id: *u32,
    Long: *i64,
    Bool: *u32,
    Array: *ArrayBody,
    Struct: *StructBody,

    fn toJsonValue(self: SpaPodBody, allocator: std.mem.Allocator) !std.json.Value {
        switch (self) {
            .String => |s| {
                return std.json.Value{ .String = try allocator.dupe(u8, std.mem.span(s)) };
            },
            inline .Float, .Double => |f| {
                return std.json.Value{ .Float = f.* };
            },
            inline .Int, .Long, .Id => |i| {
                return std.json.Value{ .Integer = i.* };
            },
            .Bool => |f| {
                return std.json.Value{ .Bool = f.* == 1 };
            },
            .Array => |ab| {
                const as = ab.asSlice();
                return as.toJsonValue(allocator);
            },
            .Object => |o| {
                var om = std.json.ObjectMap.init(allocator);
                var it = o.prop_iterator();
                while (it.next()) |c| {
                    const key = c.name(o.type);
                    const val = try c.value.body().toJsonValue(allocator);
                    try om.put(key, val);
                }
                return std.json.Value{ .Object = om };
            },
            .Struct => |s| {
                var om = std.json.ObjectMap.init(allocator);
                var it = s.iterator();

                var key: []u8 = undefined;
                var i: usize = 0;
                while (it.next()) |c| {
                    if (i % 2 == 0) {
                        if (c.body() == .String) {
                            key = try allocator.dupe(u8, std.mem.span(c.body().String));
                            i += 1;
                        }
                        continue;
                    }
                    const val = try c.body().toJsonValue(allocator);
                    try om.putNoClobber(key, val);
                    i += 1;
                }
                return std.json.Value{ .Object = om };
            },
        }
    }
};

pub const SpaPod = extern struct {
    size: u32,
    type: spa_type,

    pub fn toJsonTree(self: *const SpaPod, allocator: std.mem.Allocator) !std.json.ValueTree {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const allc = arena.allocator();
        const root = try self.body().toJsonValue(allc);
        return .{
            .arena = arena,
            .root = root,
        };
    }

    pub fn next(self: *const SpaPod) *const SpaPod {
        const next_ptr = @ptrToInt(self) + round_up_n(@sizeOf(SpaPod) + self.size, 8);
        return @intToPtr(*const SpaPod, next_ptr);
    }
    pub fn is_inside(self: *const SpaPod, parent: *const SpaPod) bool {
        const start = @ptrToInt(self);
        const end = @ptrToInt(self) + self.size;
        const max = @ptrToInt(parent) + parent.size;
        return start <= max and end <= max;
    }

    pub fn copy(self: *const SpaPod, allocator: std.mem.Allocator) !*SpaPod {
        const size = @sizeOf(SpaPod) + self.size;
        const ptr = @ptrCast([*]const u8, self);
        const mem = ptr[0..size];
        const mem2 = try allocator.dupe(u8, mem);
        return @ptrCast(*SpaPod, @alignCast(@alignOf(*SpaPod), mem2.ptr));
    }
    pub fn deinit(self: *SpaPod, allocator: std.mem.Allocator) void {
        var size = @sizeOf(SpaPod) + self.size;
        var ptr = @ptrCast([*]const u8, self);
        var mem = ptr[0..size];
        allocator.free(mem);
    }

    pub fn body(self: *const SpaPod) SpaPodBody {
        const body_ptr = @ptrToInt(self) + @sizeOf(SpaPod);

        const active_tag = std.meta.stringToEnum(std.meta.Tag(SpaPodBody), @tagName(self.type)) orelse unreachable;
        switch (active_tag) {
            inline else => |t| {
                const subtype = std.meta.TagPayload(SpaPodBody, t);
                const b = @intToPtr(subtype, body_ptr);
                return @unionInit(SpaPodBody, @tagName(t), b);
            },
        }
    }
};
pub const spa_type = enum(u32) {
    // /* Basic types */
    START = 0x00000,
    None,
    Bool,
    Id,
    Int,
    Long,
    Float,
    Double,
    String,
    Bytes,
    Rectangle,
    Fraction,
    Bitmap,
    Array,
    Struct,
    Object,
    Sequence,
    Pointer,
    Fd,
    Choice,
    Pod,
    _LAST,

    // /* Pointers */
    POINTER_START = 0x10000,
    POINTER_Buffer,
    POINTER_Meta,
    POINTER_Dict,
    _POINTER_LAST,

    // /* Events */
    EVENT_START = 0x20000,
    EVENT_Device,
    EVENT_Node,
    _EVENT_LAST,

    // /* Commands */
    COMMAND_START = 0x30000,
    COMMAND_Device,
    COMMAND_Node,
    _COMMAND_LAST,

    // /* Objects */
    OBJECT_START = 0x40000,
    OBJECT_PropInfo,
    OBJECT_Props,
    OBJECT_Format,
    OBJECT_ParamBuffers,
    OBJECT_ParamMeta,
    OBJECT_ParamIO,
    OBJECT_ParamProfile,
    OBJECT_ParamPortConfig,
    OBJECT_ParamRoute,
    OBJECT_Profiler,
    OBJECT_ParamLatency,
    OBJECT_ParamProcessLatency,
    _OBJECT_LAST,

    // /* vendor extensions */
    VENDOR_PipeWire = 0x02000000,

    VENDOR_Other = 0x7f000000,
};

pub const ParamType = enum {
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

pub const RouteParam = enum(u32) {
    START,
    index,
    direction,
    device,
    name,
    description,
    priority,
    available,

    info,

    profiles,
    props,
    devices,
    profile,
    save,
};

pub const SpaPropType = enum(u32) {
    START,

    unknown,

    START_Device = 0x100,
    device,
    deviceName,
    deviceFd,
    card,
    cardName,

    minLatency,
    maxLatency,
    periods,
    periodSize,
    periodEvent,
    live,
    rate,
    quality,
    bluetoothAudioCodec,

    START_Audio = 0x10000,
    waveType,
    frequency,
    volume,
    mute,
    patternType,
    ditherType,
    truncate,
    channelVolumes,

    volumeBase,
    volumeStep,
    channelMap,

    monitorMute,
    monitorVolumes,

    latencyOffsetNsec,
    softMute,
    softVolumes,

    iec958Codecs,

    START_Video = 0x20000,
    brightness,
    contrast,
    saturation,
    hue,
    gamma,
    exposure,
    gain,
    sharpness,

    START_Other = 0x80000,
    params,

    START_CUSTOM = 0x1000000,
};
