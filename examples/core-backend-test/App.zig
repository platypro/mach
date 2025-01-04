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

pub fn init(
    core: *mach.Core,
    app: *App,
    app_mod: mach.Mod(App),
) !void {
    core.on_tick = app_mod.id.tick;
    core.on_exit = app_mod.id.deinit;

    const window = try core.windows.new(.{
        .title = "Mach Core",
    });

    // TODO(allocator): find a better way to get an allocator here
    const allocator = std.heap.c_allocator;

    app.* = .{
        .allocator = allocator,
        .window = window,
    };
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

pub fn tick(
    core: *mach.Core,
    app: *App,
) !void {
    const label = @tagName(mach_module) ++ ".tick";
    while (core.nextEvent()) |event| {
        switch (event) {
            .window_open => try setupPipeline(core, app),
            .close => core.exit(),
            else => {},
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
        var x: f32 = 0.0;
        var x_toggle: bool = false;
        while ((x + SQUARE_SIZE) < fb_width) {
            var y: f32 = 0.0;
            var y_toggle: bool = x_toggle;
            while ((y + SQUARE_SIZE) < fb_height) {
                const color = if (y_toggle) vec3(1.0, 0.0, 0.0) else vec3(0.0, 1.0, 0.0);
                drawRect(core, app, x, x + SQUARE_SIZE, y, y + SQUARE_SIZE, color);
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
}
