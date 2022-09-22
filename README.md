# zig-pipewire

Zig 0.10 bindings for pipewire

## Usage

* In your `build.zig`:

```zig
const pipewire = std.build.Pkg{
    .name = "pipewire",
    .source = .{.path = "path/to/src/pipewire.zig"}
};
```

```zig
exe.linkLibC();
exe.linkSystemLibrary("libpipewire-0.3");
exe.addPackage(pipewire);
```

* In your `main.zig`:

```zig
const pipewire = @import("pipewire");
```
