# Framebuffer Compositor Implementation

## Step 1: Renderer Utilities

Before the compositor, you need a few reusable WebGL primitives.

### `src/renderer/renderer.odin`

This package owns the unit quad (one VAO reused everywhere) and the shader cache.

```odin
package renderer

import gl "vendor:wasm/WebGL"

Unit_Quad :: struct {
    vao: gl.VertexArray,
    vbo: gl.Buffer,
    ebo: gl.Buffer,
}

quad: Unit_Quad

init_quad :: proc() {
    quad.vao = gl.CreateVertexArray()
    gl.BindVertexArray(quad.vao)

    vertices := [16]f32{
    //  x    y    u    v
        0.0, 0.0, 0.0, 0.0,  // bottom-left
        1.0, 0.0, 1.0, 0.0,  // bottom-right
        0.0, 1.0, 0.0, 1.0,  // top-left
        1.0, 1.0, 1.0, 1.0,  // top-right
    }

    quad.vbo = gl.CreateBuffer()
    gl.BindBuffer(gl.ARRAY_BUFFER, quad.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)

    indices := [6]u16{0, 1, 2, 2, 1, 3}

    quad.ebo = gl.CreateBuffer()
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

    // Attribute 0: position (x, y) — stride 16 bytes (4 floats), offset 0
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 4 * size_of(f32), 0)

    // Attribute 1: texcoord (u, v) — stride 16 bytes, offset 8 bytes
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 4 * size_of(f32), 2 * size_of(f32))

    gl.BindVertexArray(gl.VertexArray(0))
}

draw_quad :: proc() {
    gl.BindVertexArray(quad.vao)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
    gl.BindVertexArray(gl.VertexArray(0))
}
```

**Why:** Creates the unit quad once at init. Every quad in the app (compositor, rectangles, windows) reuses this one VAO.

**How the vertices work:** Each vertex has 4 floats — position (x, y) and texture coordinate (u, v). Position goes from 0 to 1 (a "unit" quad). The compositor shader transforms this to the right screen position using a matrix. The texcoords let it sample from an FBO texture.

---

## Step 2: Compositor Package

### `src/compositor/surface.odin`

```odin
package compositor

import gl "vendor:wasm/WebGL"

Surface_Id :: distinct u32
Surface_Render_Fn :: #type proc(surface: ^Surface, dt: f32)

Layer_Kind :: enum u8 {
    Background,
    Bottom,
    Desktop,
    Top,
    Overlay,
}

Surface :: struct {
    id:            Surface_Id,
    active:        bool,
    x, y:          i32,
    width, height: i32,
    layer:         Layer_Kind,
    z_index:       i32,
    fbo:           gl.Framebuffer,
    color_texture: gl.Texture,
    visible:       bool,
    opacity:       f32,
    dirty:         bool,
    render_fn:     Surface_Render_Fn,
}

init_surface :: proc(s: ^Surface, width, height: i32) {
    s.width = width
    s.height = height
    s.visible = true
    s.opacity = 1.0
    s.dirty = true

    s.color_texture = gl.CreateTexture()
    gl.BindTexture(gl.TEXTURE_2D, s.color_texture)
    gl.TexImage2D(
        gl.TEXTURE_2D, 0, gl.RGBA,
        width, height, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, nil,
    )
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    s.fbo = gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, s.fbo)
    gl.FramebufferTexture2D(
        gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0,
        gl.TEXTURE_2D, s.color_texture, 0,
    )

    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
    gl.BindTexture(gl.TEXTURE_2D, gl.Texture(0))
}
```

**What `init_surface` does:**
1. Creates an empty texture of the given size — the "piece of paper" the surface draws onto
2. Creates an FBO and attaches that texture — binding this FBO redirects all draw calls into that texture
3. Sets texture filtering to LINEAR and wrapping to CLAMP_TO_EDGE (standard for render targets)

### `src/compositor/compositor.odin`

```odin
package compositor

import gl "vendor:wasm/WebGL"
import "../renderer"

MAX_SURFACES :: 64

Compositor :: struct {
    surfaces:           [MAX_SURFACES]Surface,
    surface_count:      u32,
    composite_program:  gl.Program,
    u_transform:        i32,
    u_texture:          i32,
    u_opacity:          i32,
    canvas_w, canvas_h: i32,
}

state: Compositor

init :: proc(composite_program: gl.Program) {
    state.composite_program = composite_program
    state.u_transform = gl.GetUniformLocation(composite_program, "u_transform")
    state.u_texture   = gl.GetUniformLocation(composite_program, "u_texture")
    state.u_opacity   = gl.GetUniformLocation(composite_program, "u_opacity")
}

create_surface :: proc(
    x, y, width, height: i32,
    layer: Layer_Kind,
    render_fn: Surface_Render_Fn,
) -> ^Surface {
    if state.surface_count >= MAX_SURFACES do return nil

    s := &state.surfaces[state.surface_count]
    s.id = Surface_Id(state.surface_count)
    s.active = true
    s.x = x
    s.y = y
    s.layer = layer
    s.render_fn = render_fn
    init_surface(s, width, height)

    state.surface_count += 1
    return s
}

frame :: proc(dt: f32) {
    state.canvas_w = gl.DrawingBufferWidth()
    state.canvas_h = gl.DrawingBufferHeight()

    // --- Pass 1: render dirty surfaces into their FBOs ---
    for i in 0..<state.surface_count {
        s := &state.surfaces[i]
        if !s.active || !s.visible do continue
        if !s.dirty do continue

        gl.BindFramebuffer(gl.FRAMEBUFFER, s.fbo)
        gl.Viewport(0, 0, s.width, s.height)
        gl.ClearColor(0, 0, 0, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        s.render_fn(s, dt)
        s.dirty = false
    }

    // --- Pass 2: composite all surfaces to screen ---
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
    gl.Viewport(0, 0, state.canvas_w, state.canvas_h)
    gl.ClearColor(0.05, 0.05, 0.05, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.UseProgram(state.composite_program)

    for layer in Layer_Kind.Background ..= Layer_Kind.Overlay {
        for i in 0..<state.surface_count {
            s := &state.surfaces[i]
            if !s.active || !s.visible do continue
            if s.layer != layer do continue

            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, s.color_texture)
            gl.Uniform1i(state.u_texture, 0)
            gl.Uniform1f(state.u_opacity, s.opacity)

            // Compute transform: unit quad (0..1) → NDC
            sx := 2.0 * f32(s.width)  / f32(state.canvas_w)
            sy := 2.0 * f32(s.height) / f32(state.canvas_h)
            tx := 2.0 * f32(s.x) / f32(state.canvas_w) - 1.0
            ty := 1.0 - 2.0 * f32(s.y) / f32(state.canvas_h) - sy

            transform := [16]f32{
                sx,  0,   0, 0,
                0,   sy,  0, 0,
                0,   0,   1, 0,
                tx,  ty,  0, 1,
            }
            gl.UniformMatrix4fv(state.u_transform, transform)

            renderer.draw_quad()
        }
    }

    gl.Disable(gl.BLEND)
}
```

### Transform Matrix

Maps unit quad (0..1) to NDC (-1..1) based on surface pixel position:

- `(0,0)` → `(tx, ty)` = top-left of surface
- `(1,1)` → `(tx + sx, ty + sy)` = bottom-right of surface

The `ty` formula flips Y because pixels go top-down but NDC goes bottom-up:
- `1.0` → start at NDC top
- `- 2.0 * y / canvas_h` → move down by y pixels
- `- sy` → quad extends downward from its origin

---

## Step 3: Compositor Shaders

### `src/shaders/compositor.vert.glsl`

```glsl
#version 300 es

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texcoord;

uniform mat4 u_transform;
out vec2 v_texcoord;

void main() {
    v_texcoord = a_texcoord;
    gl_Position = u_transform * vec4(a_position, 0.0, 1.0);
}
```

### `src/shaders/compositor.frag.glsl`

```glsl
#version 300 es
precision mediump float;

uniform sampler2D u_texture;
uniform float u_opacity;

in vec2 v_texcoord;
out vec4 fragColor;

void main() {
    vec4 color = texture(u_texture, v_texcoord);
    fragColor = vec4(color.rgb, color.a * u_opacity);
}
```

### `src/shaders/lib.odin`

```odin
package shaders

TRAINGLE_VERT_SHADER :: #load("./traingle.vert.glsl")
TRAINGLE_FRAG_SHADER :: #load("./traingle.frag.glsl")
COMPOSITOR_VERT_SHADER :: #load("./compositor.vert.glsl")
COMPOSITOR_FRAG_SHADER :: #load("./compositor.frag.glsl")
```

---

## Step 4: Wire It Up in Main

```odin
package ArMonarch

import "base:runtime"
import "core:fmt"
import gl "vendor:wasm/WebGL"

import "shaders"
import "renderer"
import "compositor"

ctx: Context

wallpaper_render :: proc(surface: ^compositor.Surface, dt: f32) {
    gl.ClearColor(0.5, 0.7, 1.0, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
}

main :: proc() {
    gl.CreateCurrentContextById("canvas", {.disablePremultipliedAlpha})
    renderer.init_quad()

    composite_program, ok := gl.CreateProgramFromStrings(
        {string(shaders.COMPOSITOR_VERT_SHADER)},
        {string(shaders.COMPOSITOR_FRAG_SHADER)},
    )
    if !ok {
        fmt.eprintln("Error: failed to create compositor program")
        return
    }

    compositor.init(composite_program)

    w := gl.DrawingBufferWidth()
    h := gl.DrawingBufferHeight()
    compositor.create_surface(0, 0, w, h, .Background, wallpaper_render)
}

@(export)
update :: proc(dt: f32) -> bool {
    ctx.acc_time += dt
    ctx.fps += 1
    if ctx.acc_time > 1 {
        update_fps_counter(ctx.fps)
        ctx.acc_time = 0
        ctx.fps = 0
    }
    compositor.frame(dt)
    return true
}
```

### What happens each frame:

1. `compositor.frame(dt)` is called
2. **Pass 1:** Wallpaper surface is dirty (first frame), compositor binds its FBO and calls `wallpaper_render`. Clears with light blue → FBO texture now contains solid light blue. `dirty` set to false.
3. **Pass 2:** Compositor binds default framebuffer (screen), clears with dark color, draws textured quad using wallpaper's texture. Transform matrix makes it fullscreen.

**Result:** Same light blue background, but through the FBO → texture → quad pipeline.

---

## Summary of Files

| File | Action | Purpose |
|------|--------|---------|
| `src/renderer/renderer.odin` | Create | Unit quad VAO, `draw_quad()` |
| `src/compositor/surface.odin` | Create | Surface struct, FBO creation |
| `src/compositor/compositor.odin` | Create | Compositor state, `frame()` loop |
| `src/shaders/compositor.vert.glsl` | Create | Textured quad vertex shader |
| `src/shaders/compositor.frag.glsl` | Create | Texture sampling fragment shader |
| `src/shaders/lib.odin` | Modify | Add `#load` for compositor shaders |
| `src/main.odin` | Rewrite | Wire up renderer + compositor |

**Verify:** `just build-debug && just serve` → light blue background through compositor pipeline. No GL errors in console.
