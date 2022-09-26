const std = @import("std");

pub inline fn round_down_n(num: usize, algn: usize) usize {
    return num & ~(algn - 1);
}
pub inline fn round_up_n(num: usize, algn: usize) usize {
    return round_down_n(num + (algn - 1), algn);
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
        key: SpaPropType,
        flags: u32,
        value: SpaPod,
        pub fn size(self: *const Prop) usize {
            return @sizeOf(Prop) + self.value.size;
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

    pub fn prop_iterator(self: *const ObjBody, body_size: usize) SpaPodPropIterator {
        const first_ptr = @ptrToInt(self) + @sizeOf(SpaPod);
        const first = @intToPtr(*const Prop, first_ptr);
        return .{
            .current = first,
            .body = self,
            .body_size = body_size,
        };
    }
};

pub const ArrayBody = extern struct {
    child: SpaPod,
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
    Long: *i64,
    Bool: *bool,
    Array: *ArrayBody,
    Struct: *StructBody,
};

pub const SpaPod = extern struct {
    size: u32,
    type: spa_type,

    pub fn toJsonTree(self: *const SpaPod, allocator: std.mem.Allocator) !std.json.ValueTree {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const allc = arena.allocator();
        const root = try self.toJsonValue(allc);
        return .{
            .arena = arena,
            .root = root,
        };
    }
    fn toJsonValue(self: *const SpaPod, allocator: std.mem.Allocator) !std.json.Value {
        switch (self.body()) {
            .String => |s| {
                return std.json.Value{ .String = try allocator.dupe(u8, std.mem.span(s)) };
            },
            .Float => |f| {
                return std.json.Value{ .Float = f.* };
            },
            .Double => |f| {
                return std.json.Value{ .Float = f.* };
            },
            .Int => |i| {
                return std.json.Value{ .Integer = i.* };
            },
            .Long => |i| {
                return std.json.Value{ .Integer = i.* };
            },
            .Bool => |f| {
                return std.json.Value{ .Bool = f.* };
            },
            .Array => |_| {
                var arr = std.json.Array.init(allocator);
                return std.json.Value{ .Array = arr };
            },
            .Object => |o| {
                var om = std.json.ObjectMap.init(allocator);
                var it = o.prop_iterator(self.size);
                while (it.next()) |c| {
                    const key = @tagName(c.key);
                    const val = try c.value.toJsonValue(allocator);
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
                        key = try allocator.dupe(u8, std.mem.span(c.body().String));
                        i += 1;
                        continue;
                    }
                    const val = try c.toJsonValue(allocator);
                    try om.putNoClobber(key, val);
                    i += 1;
                }
                return std.json.Value{ .Object = om };
            },
        }
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

    pub fn body(self: *const SpaPod) SpaPodBody {
        const body_ptr = @ptrToInt(self) + @sizeOf(SpaPod);
        inline for (@typeInfo(SpaPodBody).Union.fields) |union_field| {
            if (std.mem.eql(u8, @tagName(self.type), union_field.name)) {
                const b = @intToPtr(union_field.field_type, body_ptr);
                return @unionInit(SpaPodBody, union_field.name, b);
            }
        }
        unreachable;
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

const SpaPropType = enum(u32) {
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
