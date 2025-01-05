// Core backend test.
//
// (01) (.title)
//    The window title should update every second with the time elapsed since launch. If so .title works!
// (02) (event.key_press, event.key_release, event.char_input)
//    On key press and key release console should output a key_press event, a key_release event, and a
//    Character input event, with all active modifiers (shift, alt, numlock, etc).
// (03) (.key_repeat)
//    Holding down a key for a few seconds should emit a key_repeat event
// (04) (event.mouse_motion, event.mouse_scroll, event.mouse_press, event.mouse_release)
//    Mouse moving, scrolling, pressing, and releasing should output a mouse_motion, mouse_scroll,
//    mouse_press, and mouse_release event to the console respectively.
// (05) (event.zoom_gesture)
//    IDK HOW TO TEST ZOOM_GESTURE
// (06) (event.focus_gained, event.focus_lost)
//    When the window focus is gained or lost, you should see the event logged in the console
// (07) (event.close)
//    When the window is closed, mach should shut down and a message logged in the console
// (08) (.framebuffer_width, .framebuffer_height, .window_open)
//    There should be a grid of moving squares on the screen and a triangle in the bottom corner. If
//    the squares are more rectangular then there is something wrong. If this looks fine then
//    framebuffer_width, framebuffer_height, and window_open works!
// (09) (.width, .height, event.window_resize)
//    Resizing the window should reflect on the grid of squares. Ensure they stay square. If this is fine then width/height works!
//    Pressing 'r' should reset the window to its original size
//    On command-line passing 'w' or 'h' followed by a number will set the startup width/height
// (11) (.vsync_mode)
//    Pressing 'v' will turn vsync on, pressing 'V' will turn it off. Vsync may be tested by checking
//    the window title bar, which shows the current FPS. If it matches your monitor refresh rate
//    (typically 60, 90, 120, or 144) while on then it is working.
//    On command-line passing 'v' within the first argument enables vsync, default off.
// (12) (.display_mode)
//    Pressing 'f' should go fullscreen, pressing 'F' should go windowed, pressing 'b' should go fullscreen_borderless
//    On command-line passing f, or b will create the window with the respective setting with none being windowed.
// (13) (.cusror_mode)
//    Pressing 'c' hides the cursor, pressing 'l' locks the cursor. Pressing 'C' resets the cursor to normal.
//    On command-line passing c or l will enable create the window with the respective setting with none being normal.
// (14) (.cursor_shape)
//    Pressing 'g' cycles between all 10 cursor shapes
//    On command-line passing g followed by a number (0-9) will select a cursor shape on startup
// (15) (.refresh_rate)
//    Pressing '3' sets refresh rate to 30fps, pressing '6' to 60, and '9' to 90
//    On command-line passing r followed by a number will select a refresh rate on startup (default 0)
// (16) (.decorated)
//    Pressing 'd' will remove window decorations, pressing 'D' will re-add them
//    On command-line passing 'd' will spawn the window without decorations
// (17) (.decoration_color)
//    Pressing 's' will cycle between default/red/green/blue decoration colors
//    On command-line passing 's' followed by number 0-4 will do the same thing
// (18) (.transparent)
//    Pressing 't' will enable transparency, pressing 'T' will disable transparency
//    On command-line passing 't' will spawn the window with transparency

const std = @import("std");
const zigimg = @import("zigimg");
const assets = @import("assets");
const mach = @import("mach");
const gpu = mach.gpu;
const gfx = mach.gfx;
const math = mach.math;

const vec2 = math.vec2;
const vec3 = math.vec3;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

const App = @This();

pub const mach_module = .app;

pub const mach_systems = .{ .main, .init, .tick, .deinit, .deinit2 };

pub const main = mach.schedule(.{
    .{ mach.Core, .init },
    .{ App, .init },
    .{ mach.Core, .main },
});

pub const deinit = mach.schedule(.{
    .{ App, .deinit2 },
});

allocator: std.mem.Allocator,
window: mach.ObjectID,
pipeline: ?*gpu.RenderPipeline = null,
vertex_buffer: *gpu.Buffer = undefined,
uniform_buffer: *gpu.Buffer = undefined,
bind_group: *gpu.BindGroup = undefined,
current_vertex: u32 = 0,
timer: mach.time.Timer,
fps_timer: mach.time.Timer,
window_title: ?[:0]u8 = null,
current_time: u32 = 0,
current_cursor_shape: u32 = 0,
current_decoration: u32 = 0,

fn update_window_title(core: *mach.Core, app: *App) !void {
    if (app.window_title) |title| app.allocator.free(title);
    const frame_time = app.fps_timer.lapPrecise();
    const fps = 1_000_000_000 / frame_time;
    app.window_title = try std.fmt.allocPrintZ(app.allocator, "Mach Core ({d}fps) ({}s)", .{ fps, app.current_time });
    core.windows.set(app.window, .title, app.window_title.?);
}

fn get_window_decoration_color(id: u32) ?mach.gpu.Color {
    return switch (id) {
        1 => mach.gpu.Color{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        2 => mach.gpu.Color{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
        3 => mach.gpu.Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
        else => null,
    };
}

pub fn init(
    core: *mach.Core,
    app: *App,
    app_mod: mach.Mod(App),
) !void {
    core.on_tick = app_mod.id.tick;
    core.on_exit = app_mod.id.deinit;

    // TODO(allocator): find a better way to get an allocator here
    const allocator = std.heap.c_allocator;

    var width: u32 = 1280;
    var height: u32 = 720;
    var vsync: mach.Core.VSyncMode = .none;
    var display_mode: mach.Core.DisplayMode = .windowed;
    var cursor_mode: mach.Core.CursorMode = .normal;
    var cursor_shape: mach.Core.CursorShape = .arrow;
    var refresh_rate: u32 = 0;
    var decorated: bool = true;
    var default_decoration: ?mach.gpu.Color = null;
    var transparent: bool = false;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len >= 2) for (args[1..]) |arg| {
        var i: u32 = 0;
        while (i < arg.len) {
            switch (arg[i]) {
                'w' => width = try std.fmt.parseInt(u32, arg[(i + 1)..], 0),
                'h' => height = try std.fmt.parseInt(u32, arg[(i + 1)..], 0),
                'v' => vsync = .double,
                'f' => display_mode = .fullscreen,
                'F' => display_mode = .windowed,
                'b' => display_mode = .fullscreen_borderless,
                'c' => cursor_mode = .hidden,
                'l' => cursor_mode = .disabled,
                'g' => {
                    const shape = try std.fmt.parseInt(u32, arg[(i + 1)..], 0);
                    if (shape < 10) {
                        cursor_shape = @enumFromInt(shape);
                    }
                },
                'r' => refresh_rate = try std.fmt.parseInt(u32, arg[(i + 1)..], 0),
                'd' => decorated = false,
                's' => default_decoration = get_window_decoration_color(try std.fmt.parseInt(u32, arg[(i + 1)..], 0)),
                't' => transparent = true,
                else => {},
            }
            i += 1;
        }
    };

    const window = try core.windows.new(.{
        .title = "Mach Core",
        .width = width,
        .height = height,
        .vsync_mode = vsync,
        .display_mode = display_mode,
        .cursor_mode = cursor_mode,
        .cursor_shape = cursor_shape,
        .refresh_rate = refresh_rate,
        .decorated = decorated,
        .decoration_color = default_decoration,
        .transparent = transparent,
    });

    app.* = .{
        .allocator = allocator,
        .window = window,
        .timer = try mach.time.Timer.start(),
        .fps_timer = try mach.time.Timer.start(),
    };

    try update_window_title(core, app);
}

pub fn deinit2() void {
    // Cleanup here, if desired.
}

const wgsl_source = @embedFile("app.wgsl");

const VERTEX_NUM: u32 = 1000;

const Vertex = extern struct {
    position: math.Vec2,
    padding0: u32 = 0,
    padding1: u32 = 0,
    color: math.Vec3,
    padding2: u32 = 0,
};

fn setupPipeline(
    core: *mach.Core,
    app: *App,
) !void {
    const device: *mach.gpu.Device = core.windows.get(app.window, .device);
    const shader_module = device.createShaderModuleWGSL(null, wgsl_source);
    const label = "core-backend-test-pipeline";

    app.vertex_buffer = device.createBuffer(&.{
        .label = label,
        .mapped_at_creation = .false,
        .size = @sizeOf(Vertex) * VERTEX_NUM,
        .usage = .{ .copy_dst = true, .vertex = true },
    });

    app.uniform_buffer = device.createBuffer(&.{
        .label = label,
        .mapped_at_creation = .false,
        .size = @sizeOf(Mat4x4) * 4,
        .usage = .{ .copy_dst = true, .uniform = true },
    });

    const blend_state = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const color_target = gpu.ColorTargetState{
        .format = core.windows.get(app.window, .framebuffer_format),
        .blend = &blend_state,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fragMain",
        .targets = &.{color_target},
    });

    const bind_group_layout = device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .label = label,
            .entries = &.{gpu.BindGroupLayout.Entry.initBuffer(0, .{ .vertex = true }, .uniform, false, 0)},
        }),
    );
    defer bind_group_layout.release();
    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};

    app.bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = bind_group_layout, .entries = &.{
        gpu.BindGroup.Entry.initBuffer(0, app.uniform_buffer, 0, @sizeOf(Mat4x4), 0),
    } }));

    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = label,
        .bind_group_layouts = &bind_group_layouts,
    }));
    defer pipeline_layout.release();

    const vertex_buffer_layout_attributes = [_]mach.gpu.VertexAttribute{
        .{ // Position
            .format = .float32x2,
            .offset = 0,
            .shader_location = 0,
        },
        .{ // Color
            .format = .float32x3,
            .offset = 16,
            .shader_location = 1,
        },
    };

    const vertex_buffer_layout = mach.gpu.VertexBufferLayout{
        .array_stride = @sizeOf(Vertex),
        .attributes = &vertex_buffer_layout_attributes,
        .attribute_count = vertex_buffer_layout_attributes.len,
    };

    app.pipeline = device.createRenderPipeline(&gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .layout = pipeline_layout,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertMain",
            .buffer_count = 1,
            .buffers = &.{vertex_buffer_layout},
        },
        .primitive = gpu.PrimitiveState{
            .topology = .triangle_list,
        },
    });
}

fn push_vertices(queue: *gpu.Queue, app: *App, verts: []const Vertex) void {
    const vert_size: u32 = @intCast(verts.len * @sizeOf(Vertex));
    queue.writeBuffer(app.vertex_buffer, app.current_vertex, verts);
    app.current_vertex += vert_size;
}

fn drawRect(core: *mach.Core, app: *App, x1: f32, x2: f32, y1: f32, y2: f32, color: Vec3) void {
    const queue: *gpu.Queue = core.windows.get(app.window, .queue);

    const vertices = &.{
        Vertex{ .color = color, .position = vec2(x1, y1) },
        Vertex{ .color = color, .position = vec2(x2, y1) },
        Vertex{ .color = color, .position = vec2(x1, y2) },
        Vertex{ .color = color, .position = vec2(x2, y1) },
        Vertex{ .color = color, .position = vec2(x1, y2) },
        Vertex{ .color = color, .position = vec2(x2, y2) },
    };
    push_vertices(queue, app, vertices);
}

fn print_key_event(title: []const u8, key: ?[]const u8, mods: ?mach.Core.KeyMods, pos: ?mach.Core.Position) void {
    std.debug.print("{s} event", .{title});
    if (key) |k| {
        std.debug.print(" {s}", .{k});
    }

    if (pos) |p| {
        std.debug.print(" ({d},{d})", .{ p.x, p.y });
    }

    if (mods) |m| {
        inline for (@typeInfo(mach.Core.KeyMods).@"struct".fields) |mod_field| {
            if (mod_field.type != bool) {
                continue;
            }
            if (@field(m, mod_field.name)) {
                std.debug.print(" (mod {s})", .{mod_field.name});
            }
        }
    }

    std.debug.print("\n", .{});
}

pub fn tick(
    core: *mach.Core,
    app: *App,
) !void {
    const label = @tagName(mach_module) ++ ".tick";
    while (core.nextEvent()) |event| {
        switch (event) {
            .window_open => try setupPipeline(core, app),
            .close => {
                std.debug.print("event.close\n", .{});
                core.exit();
            },
            .key_press => |ev| print_key_event("key_press", @tagName(ev.key), ev.mods, null),
            .key_release => |ev| print_key_event("key_release", @tagName(ev.key), ev.mods, null),
            .key_repeat => |ev| print_key_event("key_repeat", @tagName(ev.key), ev.mods, null),
            .char_input => |ev| {
                std.debug.print("char_input ({u})\n", .{ev.codepoint});

                switch (ev.codepoint) {
                    'r' => {
                        core.windows.set(app.window, .width, 1280);
                        core.windows.set(app.window, .height, 720);
                    },
                    'v' => core.windows.set(app.window, .vsync_mode, .none),
                    'V' => core.windows.set(app.window, .vsync_mode, .double),
                    'f' => core.windows.set(app.window, .display_mode, .fullscreen),
                    'F' => core.windows.set(app.window, .display_mode, .windowed),
                    'b' => core.windows.set(app.window, .display_mode, .fullscreen_borderless),
                    'c' => core.windows.set(app.window, .cursor_mode, .hidden),
                    'l' => core.windows.set(app.window, .cursor_mode, .disabled),
                    'C' => core.windows.set(app.window, .cursor_mode, .normal),
                    'g' => {
                        const cursor_max: u32 = @intCast(@typeInfo(mach.Core.CursorShape).@"enum".fields.len);
                        app.current_cursor_shape = (app.current_cursor_shape + 1) % cursor_max;
                        const cursor: mach.Core.CursorShape = @enumFromInt(app.current_cursor_shape);
                        std.debug.print("Cursor Set: ({},{s})\n", .{ app.current_cursor_shape, @tagName(cursor) });
                        core.windows.set(app.window, .cursor_shape, cursor);
                    },
                    '3' => core.windows.set(app.window, .refresh_rate, 30),
                    '6' => core.windows.set(app.window, .refresh_rate, 60),
                    '9' => core.windows.set(app.window, .refresh_rate, 90),
                    'd' => core.windows.set(app.window, .decorated, false),
                    'D' => core.windows.set(app.window, .decorated, true),
                    's' => {
                        app.current_decoration = (app.current_decoration + 1) % 4;
                        core.windows.set(app.window, .decoration_color, get_window_decoration_color(app.current_decoration));
                    },
                    't' => core.windows.set(app.window, .transparent, true),
                    'T' => core.windows.set(app.window, .transparent, false),
                    else => {},
                }
            },
            .mouse_motion => |ev| print_key_event("mouse_motion", null, null, ev.pos),
            .mouse_press => |ev| print_key_event("mouse_press", @tagName(ev.button), ev.mods, ev.pos),
            .mouse_release => |ev| print_key_event("mouse_release", @tagName(ev.button), ev.mods, ev.pos),
            .mouse_scroll => |ev| std.debug.print("mouse_scroll ({d},{d})\n", .{ ev.xoffset, ev.yoffset }),
            .zoom_gesture => |ev| switch (ev.phase) {
                .began => std.debug.print("zoom_gesture Started {d}\n", .{ev.zoom}),
                .ended => std.debug.print("zoom_gesture Ended {d}\n", .{ev.zoom}),
            },
            .focus_gained => std.debug.print("focus_gained\n", .{}),
            .focus_lost => std.debug.print("focus_lost\n", .{}),
            .window_resize => {}, //TODO
        }
    }

    if (app.pipeline) |pipeline| {
        const window = core.windows.getValue(app.window);

        const queue: *gpu.Queue = core.windows.get(app.window, .queue);
        queue.writeBuffer(
            app.uniform_buffer,
            0,
            &[_]Mat4x4{Mat4x4.projection2D(.{
                .left = 0,
                .right = @floatFromInt(window.framebuffer_width),
                .top = 0,
                .bottom = @floatFromInt(window.framebuffer_height),
                .near = -0.1,
                .far = 1.0,
            })},
        );

        // Grab the back buffer of the swapchain
        // TODO(Core)
        const back_buffer_view = window.swap_chain.getCurrentTextureView().?;
        defer back_buffer_view.release();

        // Create a command encoder
        const encoder = window.device.createCommandEncoder(&.{ .label = label });
        defer encoder.release();

        // Begin render pass
        const sky_blue = gpu.Color{ .r = 0.776, .g = 0.988, .b = 1, .a = 1 };
        const color_attachments = [_]gpu.RenderPassColorAttachment{.{
            .view = back_buffer_view,
            .clear_value = sky_blue,
            .load_op = .clear,
            .store_op = .store,
        }};
        const render_pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
            .label = label,
            .color_attachments = &color_attachments,
        }));

        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, app.bind_group, &.{});

        const fb_width: f32 = @floatFromInt(window.framebuffer_width);
        const fb_height: f32 = @floatFromInt(window.framebuffer_height);
        const SQUARE_SIZE = 100;

        app.current_vertex = 0;

        // Draw rect grid
        const wiggle = (app.timer.read() * 30.0);
        var x: f32 = 0.0;
        var x_toggle: bool = false;
        while ((x + SQUARE_SIZE) < fb_width) {
            var y: f32 = 0.0;
            var y_toggle: bool = x_toggle;
            while ((y + SQUARE_SIZE) < fb_height) {
                const color = if (y_toggle) vec3(1.0, 0.0, 0.0) else vec3(0.0, 1.0, 0.0);
                drawRect(core, app, x + wiggle, x + SQUARE_SIZE + wiggle, y + wiggle, y + SQUARE_SIZE + wiggle, color);
                y += SQUARE_SIZE;
                y_toggle = !y_toggle;
            }
            x += SQUARE_SIZE;
            x_toggle = !x_toggle;
        }

        // Draw corner ornaments
        const corner_color = vec3(0.5, 0.5, 0.5);
        const corner_ornament_vertices = [_]Vertex{
            .{ .color = corner_color, .position = vec2(fb_width, fb_height) },
            .{ .color = corner_color, .position = vec2(fb_width - 25.0, fb_height) },
            .{ .color = corner_color, .position = vec2(fb_width, fb_height - 25.0) },
        };
        push_vertices(window.queue, app, &corner_ornament_vertices);

        render_pass.setVertexBuffer(0, app.vertex_buffer, 0, app.current_vertex);
        render_pass.draw(app.current_vertex / @sizeOf(Vertex), 1, 0, 0);

        // Finish render pass
        render_pass.end();
        var command = encoder.finish(&.{ .label = label });
        window.queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        render_pass.release();
    }

    if (app.timer.read() > 1.0) {
        app.current_time += 1;
        app.timer.reset();
    }
    try update_window_title(core, app);
}
