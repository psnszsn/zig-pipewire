pub const c = @cImport({
    @cInclude("pipewire/pipewire.h");
    @cInclude("pipewire/extensions/client-node.h");
    @cInclude("pipewire/extensions/metadata.h");
    @cInclude("pipewire/extensions/profiler.h");
    @cInclude("pipewire/extensions/protocol-native.h");
    @cInclude("pipewire/extensions/session-manager.h");
});

pub const Context = @import("context.zig").Context;
pub const Core = @import("core.zig").Core;
pub const Loop = @import("loop.zig").Loop;
pub const MainLoop = @import("main_loop.zig").MainLoop;
pub const Metadata = @import("metadata.zig").Metadata;
pub const Node = @import("node.zig").Node;
pub const Device = @import("device.zig").Device;
pub const Proxy = @import("proxy.zig").Proxy;
pub const Registry = @import("registry.zig").Registry;

pub const ParamInfo = @import("node.zig").ParamInfo;

pub const ObjType = @import("registry.zig").ObjType;

pub const spa = @import("spa.zig");
pub const utils = @import("utils.zig");

    
test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(spa);
    // std.testing.refAllDeclsRecursive(utils);
}
