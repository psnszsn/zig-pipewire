const std = @import("std");
const pw = @import("pipewire.zig");
const c = pw.c;

pub const Context = opaque {
    extern fn pw_context_new(main_loop: *pw.Loop, props: [*c]c.struct_pw_properties, user_data_size: usize) ?*Context;
    pub fn new(loop: *pw.Loop) !*Context {
        var context = pw_context_new(loop, null, 0);
        return context orelse error.CreationError;
    }

    extern fn pw_context_connect(context: *pw.Context, properties: [*c]c.struct_pw_properties, user_data_size: usize) ?*pw.Core;
    pub fn connect(self: *Context, user_data_size: usize) !*pw.Core {
        return pw_context_connect(self, null, user_data_size) orelse error.CreationError;
    }
    extern fn pw_context_destroy(self: *Context) void;
    pub fn destroy(self: *Context) void {
        pw_context_destroy(self);
    }
};
