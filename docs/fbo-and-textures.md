# Framebuffer Objects & Textures: Drawing a Textured Quad

A complete reference for understanding and using Framebuffer Objects (FBOs) and textures
in WebGL 2 (GLSL ES 3.0), with Odin code examples matching ArMonarch's conventions.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Textures In Depth](#2-textures-in-depth)
3. [Framebuffer Objects In Depth](#3-framebuffer-objects-in-depth)
4. [The Render-to-Texture Pipeline](#4-the-render-to-texture-pipeline)
5. [Step-by-Step: Create an FBO with a Texture](#5-step-by-step-create-an-fbo-with-a-texture)
6. [Step-by-Step: Render Into the FBO](#6-step-by-step-render-into-the-fbo)
7. [Step-by-Step: Draw a Quad with the FBO Texture](#7-step-by-step-draw-a-quad-with-the-fbo-texture)
8. [Complete Working Example](#8-complete-working-example)
9. [The Quad Geometry](#9-the-quad-geometry)
10. [Texture Coordinates & UV Mapping](#10-texture-coordinates--uv-mapping)
11. [The Transform Matrix](#11-the-transform-matrix)
12. [Shaders for Textured Quad Rendering](#12-shaders-for-textured-quad-rendering)
13. [Texture Parameters Explained](#13-texture-parameters-explained)
14. [Multiple Render Targets (MRT)](#14-multiple-render-targets-mrt)
15. [Depth and Stencil Attachments](#15-depth-and-stencil-attachments)
16. [Common Pitfalls & Debugging](#16-common-pitfalls--debugging)
17. [Performance Considerations](#17-performance-considerations)
18. [Quick Reference Cheat Sheet](#18-quick-reference-cheat-sheet)

---

## 1. Core Concepts

### What is a Texture?

A texture is a block of GPU memory that holds image data. Think of it as a 2D array of
pixels (called **texels**) that the GPU can sample from during rendering. In WebGL 2, the
most common type is `TEXTURE_2D` — a rectangular grid of color values.

```
Texture (4x4 pixels):
┌──────┬──────┬──────┬──────┐
│ RGBA │ RGBA │ RGBA │ RGBA │  ← Row 0
├──────┼──────┼──────┼──────┤
│ RGBA │ RGBA │ RGBA │ RGBA │  ← Row 1
├──────┼──────┼──────┼──────┤
│ RGBA │ RGBA │ RGBA │ RGBA │  ← Row 2
├──────┼──────┼──────┼──────┤
│ RGBA │ RGBA │ RGBA │ RGBA │  ← Row 3
└──────┴──────┴──────┴──────┘
```

Each texel has 4 channels: Red, Green, Blue, Alpha (RGBA). Each channel is typically
one byte (0–255), so each texel is 4 bytes.

### What is a Framebuffer Object (FBO)?

A framebuffer is the destination where the GPU writes pixels when you draw something.
By default, there is a **default framebuffer** — this is your screen (or canvas in WebGL).

A **Framebuffer Object** (FBO) is a user-created framebuffer that redirects rendering
to one or more **attachments** instead of the screen. These attachments are typically
textures (but can also be renderbuffers).

```
Default Pipeline:           FBO Pipeline:
Draw Call → Screen          Draw Call → FBO → Texture (in GPU memory)
                                              ↓
                                     Can be used as input
                                     for another draw call
```

### Why Use FBOs?

1. **Render-to-texture**: Draw a scene into a texture, then use that texture on a quad
2. **Off-screen rendering**: Each surface/window renders independently into its own buffer
3. **Post-processing**: Render a scene, then apply effects (blur, glow, color grading)
4. **Compositing**: Layer multiple rendered textures together (exactly what ArMonarch does)

---

## 2. Textures In Depth

### Texture Lifecycle

```
Create → Bind → Allocate Storage → Set Parameters → Use → Delete
```

### Creating and Configuring a Texture

```odin
// 1. Create the texture object (GPU-side handle)
texture := gl.CreateTexture()

// 2. Bind it to the TEXTURE_2D target
//    All subsequent texture operations affect this texture
gl.BindTexture(gl.TEXTURE_2D, texture)

// 3. Allocate storage — defines the texture's dimensions and format
//    This creates an EMPTY texture (data = nil)
gl.TexImage2D(
    gl.TEXTURE_2D,      // target: must match what we bound
    0,                   // mipmap level: 0 = base level (full resolution)
    gl.RGBA,             // internal format: how the GPU stores it
    width, height,       // dimensions in pixels
    0,                   // border: must be 0 in WebGL
    gl.RGBA,             // source format: layout of input data
    gl.UNSIGNED_BYTE,    // source type: data type per channel
    nil,                 // data: nil = allocate empty, or pointer to pixel data
)

// 4. Set sampling parameters (how the GPU reads from this texture)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

// 5. Unbind (good practice, prevents accidental modification)
gl.BindTexture(gl.TEXTURE_2D, gl.Texture(0))
```

### Internal Formats (WebGL 2)

| Format          | Channels | Bits/Pixel | Use Case                     |
|-----------------|----------|------------|------------------------------|
| `gl.RGBA`       | 4        | 32         | General purpose, transparency |
| `gl.RGB`        | 3        | 24         | Opaque images                |
| `gl.RGBA8`      | 4        | 32         | Explicit 8-bit per channel   |
| `gl.RGBA16F`    | 4        | 64         | HDR rendering                |
| `gl.RGBA32F`    | 4        | 128        | High precision compute       |
| `gl.R8`         | 1        | 8          | Grayscale, masks             |
| `gl.RG8`        | 2        | 16         | Normal maps (2-channel)      |
| `gl.DEPTH_COMPONENT16` | 1 | 16        | Depth buffer                 |
| `gl.DEPTH24_STENCIL8`  | 2 | 32        | Combined depth + stencil     |

For FBO render targets, `RGBA` / `RGBA8` is the most common choice.

### Texture Units

The GPU has multiple **texture units** (slots) that shaders can sample from simultaneously.
WebGL 2 guarantees at least 8 units for fragment shaders.

```odin
// Activate texture unit 0
gl.ActiveTexture(gl.TEXTURE0)

// Bind our texture to unit 0
gl.BindTexture(gl.TEXTURE_2D, some_texture)

// Tell the shader's sampler uniform to read from unit 0
gl.Uniform1i(u_texture_location, 0)
```

The flow:
```
Texture Unit 0 ← BindTexture(my_texture)
     ↑
Sampler uniform "u_texture" → reads from unit 0 (because we set Uniform1i to 0)
```

To use multiple textures in one draw call:
```odin
gl.ActiveTexture(gl.TEXTURE0)
gl.BindTexture(gl.TEXTURE_2D, diffuse_texture)
gl.Uniform1i(u_diffuse, 0)

gl.ActiveTexture(gl.TEXTURE1)
gl.BindTexture(gl.TEXTURE_2D, normal_texture)
gl.Uniform1i(u_normal, 1)
```

---

## 3. Framebuffer Objects In Depth

### FBO Architecture

An FBO is a **container** that holds references to attachment points. It does not store
pixels itself — the attachments do.

```
┌─────────────────────────────────┐
│           Framebuffer           │
│                                 │
│  COLOR_ATTACHMENT0 ──→ Texture  │  ← Where color pixels go
│  COLOR_ATTACHMENT1 ──→ Texture  │  ← Second color output (MRT)
│  DEPTH_ATTACHMENT  ──→ RBO/Tex  │  ← Where depth values go
│  STENCIL_ATTACHMENT──→ RBO/Tex  │  ← Where stencil values go
│                                 │
└─────────────────────────────────┘
```

**Attachment types:**
- **Texture**: Can be sampled later in shaders. Use when you need to read the result.
- **Renderbuffer (RBO)**: Cannot be sampled. Faster for write-only buffers (depth/stencil).

### FBO Lifecycle

```
Create → Bind → Attach textures/RBOs → Check completeness → Use → Delete
```

### Creating an FBO

```odin
// 1. Create the FBO handle
fbo := gl.CreateFramebuffer()

// 2. Bind it — all framebuffer operations now target this FBO
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)

// 3. Attach a texture as the color output
gl.FramebufferTexture2D(
    gl.FRAMEBUFFER,          // target
    gl.COLOR_ATTACHMENT0,    // attachment point
    gl.TEXTURE_2D,           // texture target
    color_texture,           // the texture handle
    0,                       // mipmap level (always 0 for render targets)
)

// 4. (Optional) Check completeness
status := gl.CheckFramebufferStatus(gl.FRAMEBUFFER)
if status != gl.FRAMEBUFFER_COMPLETE {
    fmt.eprintln("FBO incomplete! Status:", status)
}

// 5. Unbind — go back to the default framebuffer (screen)
gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
```

### Framebuffer Completeness

An FBO must be **complete** before you can render to it. WebGL checks:

| Requirement                          | Fix                                           |
|--------------------------------------|------------------------------------------------|
| At least one attachment              | Attach a texture or renderbuffer               |
| All attachments have same dimensions | Make all attached textures the same size        |
| Internal formats are color-renderable| Use `RGBA`, `RGBA8`, `RGBA16F`, etc.           |
| Attachment types are valid           | Don't mix incompatible formats                 |

Common status codes:
- `FRAMEBUFFER_COMPLETE` (0x8CD5) — All good
- `FRAMEBUFFER_INCOMPLETE_ATTACHMENT` (0x8CD6) — Bad attachment
- `FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT` (0x8CD7) — No attachments
- `FRAMEBUFFER_INCOMPLETE_DIMENSIONS` (0x8CD9) — Mismatched sizes

### Default Framebuffer vs FBO

| Aspect               | Default Framebuffer      | Custom FBO                    |
|----------------------|--------------------------|-------------------------------|
| ID                   | `0` or `Framebuffer(0)`  | Non-zero handle               |
| Renders to           | Canvas / screen          | Attached textures/RBOs        |
| Created by           | WebGL context init       | `gl.CreateFramebuffer()`      |
| Size                 | Canvas dimensions        | Attachment dimensions         |
| Always complete      | Yes                      | Must be configured properly   |

---

## 4. The Render-to-Texture Pipeline

This is the fundamental pattern: render a scene into a texture via FBO, then draw a
quad textured with that result onto the screen.

```
Phase 1: RENDER TO TEXTURE
┌─────────────────────────────────────────────────┐
│ Bind FBO                                        │
│ Set viewport to FBO texture size                │
│ Clear the FBO                                   │
│ Draw your scene (triangles, shapes, etc.)       │
│ Unbind FBO (bind default framebuffer)           │
└─────────────────────────────────────────────────┘
                      │
                      ▼
         FBO's texture now contains
         the rendered scene as pixels

Phase 2: DRAW TEXTURED QUAD
┌─────────────────────────────────────────────────┐
│ Bind default framebuffer (screen)               │
│ Set viewport to canvas size                     │
│ Use textured-quad shader program                │
│ Bind the FBO's texture to a texture unit        │
│ Set transform matrix for quad positioning       │
│ Draw the quad (6 indices, 2 triangles)          │
└─────────────────────────────────────────────────┘
                      │
                      ▼
         Screen shows the FBO contents
         mapped onto a quad
```

---

## 5. Step-by-Step: Create an FBO with a Texture

Here is the complete setup procedure, annotated line by line.

```odin
create_render_target :: proc(width, height: i32) -> (gl.Framebuffer, gl.Texture) {
    // ── Create the color texture ──────────────────────────────────────
    //
    // This texture will receive the pixel output when we render to the FBO.
    // We allocate it empty (nil data) because the GPU will write into it.

    color_tex := gl.CreateTexture()
    gl.BindTexture(gl.TEXTURE_2D, color_tex)

    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,                   // level 0 = full resolution
        gl.RGBA,             // 4 channels, 8 bits each
        width, height,
        0,                   // border (must be 0)
        gl.RGBA,             // matches internal format
        gl.UNSIGNED_BYTE,    // 1 byte per channel
        nil,                 // no initial data
    )

    // Filtering: LINEAR smooths when the texture is scaled up/down.
    // For pixel-perfect rendering, use NEAREST instead.
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    // Wrapping: CLAMP_TO_EDGE prevents sampling beyond texture borders.
    // Critical for FBO textures — you never want wrap-around on a render target.
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    // ── Create the FBO ────────────────────────────────────────────────
    //
    // The FBO is just a container. We attach our texture to it so that
    // any draw calls while this FBO is bound write into color_tex.

    fbo := gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)

    // Attach texture to COLOR_ATTACHMENT0 (the primary color output).
    // Fragment shader's "out vec4 fragColor" writes to this attachment.
    gl.FramebufferTexture2D(
        gl.FRAMEBUFFER,
        gl.COLOR_ATTACHMENT0,
        gl.TEXTURE_2D,
        color_tex,
        0,                   // mip level
    )

    // ── Cleanup ───────────────────────────────────────────────────────
    //
    // Unbind everything to prevent accidental writes.

    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
    gl.BindTexture(gl.TEXTURE_2D, gl.Texture(0))

    return fbo, color_tex
}
```

### Memory Layout After Setup

```
GPU Memory:
┌─────────────────────┐
│ FBO (handle: fbo)   │
│   └─ COLOR_ATTACHMENT0 ──→ color_tex (width × height × 4 bytes)
└─────────────────────┘

All pixels in color_tex are currently (0, 0, 0, 0) — transparent black.
```

---

## 6. Step-by-Step: Render Into the FBO

Once the FBO and texture are created, here's how to render into them.

```odin
render_to_fbo :: proc(fbo: gl.Framebuffer, width, height: i32) {
    // ── Step 1: Bind the FBO ──────────────────────────────────────────
    //
    // From this point, ALL draw calls write into the FBO's texture,
    // not the screen.
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)

    // ── Step 2: Set the viewport ──────────────────────────────────────
    //
    // The viewport MUST match the FBO texture dimensions.
    // If you forget this, you'll render at the wrong resolution.
    gl.Viewport(0, 0, width, height)

    // ── Step 3: Clear the FBO ─────────────────────────────────────────
    //
    // Clear with transparent black. This matters because the texture
    // will be composited with alpha blending later.
    gl.ClearColor(0.0, 0.0, 0.0, 0.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)

    // ── Step 4: Draw your content ─────────────────────────────────────
    //
    // Use whatever shader program and geometry you want.
    // Everything drawn here ends up in the FBO's color texture.

    gl.UseProgram(my_shader_program)
    gl.BindVertexArray(my_vao)
    // set uniforms...
    gl.DrawElements(gl.TRIANGLES, index_count, gl.UNSIGNED_SHORT, nil)

    // ── Step 5: Unbind FBO ────────────────────────────────────────────
    //
    // Switch back to the default framebuffer (screen) so subsequent
    // draw calls go to the canvas again.
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
}
```

### What Happens Internally

```
Before Clear:               After Clear:              After Draw:
┌────────────────┐         ┌────────────────┐        ┌────────────────┐
│ ░░░░░░░░░░░░░░ │         │                │        │     ▲          │
│ ░░ old data ░░ │  ──→    │  (transparent)  │  ──→   │    ╱ ╲         │
│ ░░░░░░░░░░░░░░ │         │                │        │   ╱___╲        │
│ ░░░░░░░░░░░░░░ │         │                │        │                │
└────────────────┘         └────────────────┘        └────────────────┘
   FBO texture                FBO texture               FBO texture
   (garbage)                  (cleared)                 (has triangle)
```

---

## 7. Step-by-Step: Draw a Quad with the FBO Texture

Now that the FBO texture contains rendered content, draw it onto the screen
as a textured quad.

```odin
draw_textured_quad :: proc(
    texture: gl.Texture,
    program: gl.Program,
    vao: gl.VertexArrayObject,
    u_texture: i32,
    u_transform: i32,
    u_opacity: i32,
    transform: [16]f32,
    opacity: f32,
) {
    // ── Step 1: Ensure we're drawing to the screen ────────────────────
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))

    // ── Step 2: Use the compositor shader ─────────────────────────────
    gl.UseProgram(program)

    // ── Step 3: Bind the FBO texture to texture unit 0 ────────────────
    //
    // The texture now contains whatever was rendered into the FBO.
    // We bind it so the fragment shader can sample from it.
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.Uniform1i(u_texture, 0)   // sampler reads from unit 0

    // ── Step 4: Set uniforms ──────────────────────────────────────────
    gl.UniformMatrix4fv(u_transform, transform)
    gl.Uniform1f(u_opacity, opacity)

    // ── Step 5: Enable alpha blending ─────────────────────────────────
    //
    // Surfaces may have transparent regions. Standard alpha blending:
    // final = src.rgb * src.a + dst.rgb * (1 - src.a)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    // ── Step 6: Draw the quad ─────────────────────────────────────────
    gl.BindVertexArray(vao)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)

    // ── Step 7: Cleanup ───────────────────────────────────────────────
    gl.BindVertexArray(gl.VertexArrayObject(0))
    gl.Disable(gl.BLEND)
}
```

### The Full Data Flow

```
                    GPU Pipeline
                    ─────────────

Vertex Buffer ──→ Vertex Shader ──→ Rasterizer ──→ Fragment Shader ──→ Screen
(quad coords)     (transforms       (fills the      (samples FBO
 + tex coords)     position to       quad with       texture at each
                   screen space)     fragments)      pixel, outputs
                                                     color)
```

---

## 8. Complete Working Example

Putting it all together — a self-contained example that creates an FBO, renders a
solid red rectangle into it, then draws that texture as a quad on screen.

```odin
package example

import gl "vendor:wasm/WebGL"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GPU Resources
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

State :: struct {
    // FBO resources
    fbo:           gl.Framebuffer,
    fbo_texture:   gl.Texture,
    fbo_width:     i32,
    fbo_height:    i32,

    // Quad geometry
    quad_vao:      gl.VertexArrayObject,
    quad_vbo:      gl.Buffer,
    quad_ebo:      gl.Buffer,

    // Shader for drawing the textured quad
    program:       gl.Program,
    u_transform:   i32,
    u_texture:     i32,
    u_opacity:     i32,

    // Shader for drawing content into FBO
    content_program: gl.Program,

    // Canvas dimensions
    canvas_w:      i32,
    canvas_h:      i32,
}

state: State

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Initialization
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

init :: proc() {
    state.canvas_w = gl.DrawingBufferWidth()
    state.canvas_h = gl.DrawingBufferHeight()

    // -- Create unit quad geometry --
    init_quad()

    // -- Create FBO (200x150 pixel render target) --
    state.fbo_width = 200
    state.fbo_height = 150
    state.fbo, state.fbo_texture = create_fbo(state.fbo_width, state.fbo_height)

    // -- Create shader programs --
    // (Assume create_program compiles and links shaders)
    state.program = create_program(COMPOSITE_VERT, COMPOSITE_FRAG)
    state.u_transform = gl.GetUniformLocation(state.program, "u_transform")
    state.u_texture   = gl.GetUniformLocation(state.program, "u_texture")
    state.u_opacity   = gl.GetUniformLocation(state.program, "u_opacity")

    state.content_program = create_program(CONTENT_VERT, CONTENT_FRAG)
}

init_quad :: proc() {
    state.quad_vao = gl.CreateVertexArray()
    gl.BindVertexArray(state.quad_vao)

    //                     x    y    u    v
    vertices := [16]f32{
        0.0, 0.0,  0.0, 0.0,   // bottom-left
        1.0, 0.0,  1.0, 0.0,   // bottom-right
        0.0, 1.0,  0.0, 1.0,   // top-left
        1.0, 1.0,  1.0, 1.0,   // top-right
    }

    state.quad_vbo = gl.CreateBuffer()
    gl.BindBuffer(gl.ARRAY_BUFFER, state.quad_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)

    indices := [6]u16{0, 1, 2, 2, 1, 3}

    state.quad_ebo = gl.CreateBuffer()
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, state.quad_ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

    // Attribute 0: position (x, y)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 4 * size_of(f32), 0)

    // Attribute 1: texcoord (u, v)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 4 * size_of(f32), 2 * size_of(f32))

    gl.BindVertexArray(gl.VertexArrayObject(0))
}

create_fbo :: proc(width, height: i32) -> (gl.Framebuffer, gl.Texture) {
    // Create texture
    tex := gl.CreateTexture()
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    // Create FBO and attach texture
    fbo := gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)

    // Unbind
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
    gl.BindTexture(gl.TEXTURE_2D, gl.Texture(0))

    return fbo, tex
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Per-Frame Rendering
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

render_frame :: proc() {
    // ── Pass 1: Render content into FBO ───────────────────────────────
    gl.BindFramebuffer(gl.FRAMEBUFFER, state.fbo)
    gl.Viewport(0, 0, state.fbo_width, state.fbo_height)
    gl.ClearColor(0.0, 0.0, 0.0, 0.0)   // transparent
    gl.Clear(gl.COLOR_BUFFER_BIT)

    // Draw something into the FBO (e.g., a red rectangle)
    gl.UseProgram(state.content_program)
    // ... set uniforms, draw calls ...

    // ── Pass 2: Draw FBO texture as a quad on screen ──────────────────
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
    gl.Viewport(0, 0, state.canvas_w, state.canvas_h)
    gl.ClearColor(0.1, 0.1, 0.1, 1.0)   // dark background
    gl.Clear(gl.COLOR_BUFFER_BIT)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.UseProgram(state.program)

    // Bind FBO texture
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, state.fbo_texture)
    gl.Uniform1i(state.u_texture, 0)
    gl.Uniform1f(state.u_opacity, 1.0)

    // Position the quad at (50, 50) on screen
    x, y : i32 = 50, 50
    transform := compute_transform(x, y, state.fbo_width, state.fbo_height)
    gl.UniformMatrix4fv(state.u_transform, transform)

    // Draw
    gl.BindVertexArray(state.quad_vao)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)

    gl.Disable(gl.BLEND)
}

compute_transform :: proc(x, y, w, h: i32) -> [16]f32 {
    cw := f32(state.canvas_w)
    ch := f32(state.canvas_h)

    sx := 2.0 * f32(w) / cw
    sy := 2.0 * f32(h) / ch
    tx := 2.0 * f32(x) / cw - 1.0
    ty := 1.0 - 2.0 * f32(y) / ch - sy

    return [16]f32{
        sx,  0,   0, 0,
        0,   sy,  0, 0,
        0,   0,   1, 0,
        tx,  ty,  0, 1,
    }
}
```

---

## 9. The Quad Geometry

A quad is two triangles forming a rectangle. We define 4 vertices and 6 indices.

### Vertex Layout

```
(0,1)───────(1,1)        Each vertex has 4 floats:
  │ ╲         │            - x, y:  position (0 to 1, "unit" space)
  │   ╲       │            - u, v:  texture coordinate
  │     ╲     │
  │       ╲   │           Stride: 4 floats = 16 bytes per vertex
  │         ╲ │           Total:  4 vertices = 64 bytes
(0,0)───────(1,0)
```

### Index Buffer

```
Triangle 1: vertices 0, 1, 2  →  (0,0), (1,0), (0,1)
Triangle 2: vertices 2, 1, 3  →  (0,1), (1,0), (1,1)
```

### Why a Unit Quad (0 to 1)?

Using 0–1 coordinates instead of actual pixel positions keeps the geometry static
and reusable. The vertex shader applies a transform matrix to map `(0..1)` to the
correct screen position. This means:

- **One VAO** serves all quads (surfaces, windows, UI elements)
- Only the **uniform** (transform matrix) changes per quad
- No per-quad vertex buffer updates = better performance

---

## 10. Texture Coordinates & UV Mapping

Texture coordinates (UVs) define how a texture maps onto geometry.

### Coordinate System

```
Texture Space:              Screen Space (NDC):
(0,1)──────(1,1)           (-1,+1)────(+1,+1)
  │          │                │          │
  │  image   │                │  canvas  │
  │          │                │          │
(0,0)──────(1,0)           (-1,-1)────(+1,-1)
```

- `(0,0)` = bottom-left of texture
- `(1,1)` = top-right of texture
- Values outside 0–1 depend on wrap mode (CLAMP_TO_EDGE, REPEAT, etc.)

### How UVs Map to the Quad

Since our unit quad vertices have position and texcoord at the same values:
```
Vertex 0: pos(0,0) texcoord(0,0) → bottom-left  corner samples bottom-left  of texture
Vertex 1: pos(1,0) texcoord(1,0) → bottom-right corner samples bottom-right of texture
Vertex 2: pos(0,1) texcoord(0,1) → top-left     corner samples top-left     of texture
Vertex 3: pos(1,1) texcoord(1,1) → top-right    corner samples top-right    of texture
```

The rasterizer **interpolates** UVs across the triangle surface. A fragment at the
center of the quad gets texcoord `(0.5, 0.5)` — the center of the texture.

### Flipping the Texture

If your texture appears upside down, flip the V coordinate:
```odin
vertices := [16]f32{
//  x    y    u    v
    0.0, 0.0, 0.0, 1.0,  // was 0.0 → now 1.0
    1.0, 0.0, 1.0, 1.0,  // was 0.0 → now 1.0
    0.0, 1.0, 0.0, 0.0,  // was 1.0 → now 0.0
    1.0, 1.0, 1.0, 0.0,  // was 1.0 → now 0.0
}
```

Or flip in the vertex shader:
```glsl
v_texcoord = vec2(a_texcoord.x, 1.0 - a_texcoord.y);
```

---

## 11. The Transform Matrix

The transform matrix maps the unit quad `(0..1)` to its final screen position in
Normalized Device Coordinates `(-1..1)`.

### The Math

Given a surface at pixel position `(x, y)` with size `(w, h)` on a canvas of
size `(cw, ch)`:

```
Scale X:     sx = 2 * w / cw
Scale Y:     sy = 2 * h / ch
Translate X: tx = 2 * x / cw - 1
Translate Y: ty = 1 - 2 * y / ch - sy
```

### Why These Formulas?

**Scale:** NDC range is 2 units wide (-1 to +1). A surface of width `w` on a canvas
of width `cw` occupies `w/cw` of the canvas, which is `2 * w/cw` in NDC units.

**Translate X:** Pixel `x=0` maps to NDC `-1`. Pixel `x=cw` maps to NDC `+1`.
So: `ndc_x = 2 * x / cw - 1`.

**Translate Y:** Pixels go top-down (y=0 = top), NDC goes bottom-up (y=+1 = top).
We need to flip: `ndc_y = 1 - 2 * y / ch`. The extra `- sy` shifts the origin from
the top-left of the quad to account for the quad extending downward.

### Matrix Layout (Column-Major)

WebGL expects column-major matrices. The 4x4 matrix:
```
| sx  0   0   0 |
| 0   sy  0   0 |
| 0   0   1   0 |
| tx  ty  0   1 |
```

Stored as a flat array in **column-major** order:
```odin
transform := [16]f32{
    sx,  0,   0, 0,    // column 0
    0,   sy,  0, 0,    // column 1
    0,   0,   1, 0,    // column 2
    tx,  ty,  0, 1,    // column 3
}
```

### Visual Example

Canvas: 800x600, Surface at (100, 50) with size 200x150:
```
sx = 2 * 200 / 800  = 0.5
sy = 2 * 150 / 600  = 0.5
tx = 2 * 100 / 800 - 1 = -0.75
ty = 1 - 2 * 50 / 600 - 0.5 = 0.333

Vertex (0,0) → (0*0.5 + (-0.75), 0*0.5 + 0.333) = (-0.75, 0.333)
Vertex (1,1) → (1*0.5 + (-0.75), 1*0.5 + 0.333) = (-0.25, 0.833)
```

---

## 12. Shaders for Textured Quad Rendering

### Vertex Shader

```glsl
#version 300 es

layout(location = 0) in vec2 a_position;   // unit quad vertex (0..1)
layout(location = 1) in vec2 a_texcoord;   // texture coordinate (0..1)

uniform mat4 u_transform;                  // maps unit quad → NDC

out vec2 v_texcoord;                       // pass to fragment shader

void main() {
    v_texcoord = a_texcoord;
    gl_Position = u_transform * vec4(a_position, 0.0, 1.0);
}
```

**What each line does:**
- `layout(location = 0)` — must match `VertexAttribPointer` index
- `u_transform * vec4(...)` — applies the scale+translate matrix
- `v_texcoord` — interpolated across fragments by the rasterizer

### Fragment Shader

```glsl
#version 300 es
precision mediump float;

uniform sampler2D u_texture;    // the FBO's color texture
uniform float u_opacity;        // overall transparency

in vec2 v_texcoord;             // interpolated from vertex shader
out vec4 fragColor;             // output to framebuffer

void main() {
    vec4 color = texture(u_texture, v_texcoord);
    fragColor = vec4(color.rgb, color.a * u_opacity);
}
```

**What each line does:**
- `texture(u_texture, v_texcoord)` — samples the texture at the interpolated UV
- `color.a * u_opacity` — allows per-surface transparency
- `fragColor` — written to whichever framebuffer is currently bound

### How `texture()` Sampling Works

When the fragment shader calls `texture(u_texture, v_texcoord)`:

1. GPU looks at the `v_texcoord` value (e.g., `(0.5, 0.5)`)
2. Maps it to a texel position: `(0.5 * width, 0.5 * height)`
3. Based on the filter mode:
   - **NEAREST**: Returns the closest texel (pixelated)
   - **LINEAR**: Blends the 4 nearest texels (smooth)
4. Returns an `RGBA` vec4 with values normalized to 0.0–1.0

---

## 13. Texture Parameters Explained

### Filter Modes

Controls how texels are sampled when the texture is displayed at a different size
than its native resolution.

| Parameter         | Value      | Effect                          | Use Case                     |
|-------------------|------------|---------------------------------|------------------------------|
| `TEXTURE_MIN_FILTER` | `NEAREST`  | Nearest texel, no blending   | Pixel art, crisp edges       |
| `TEXTURE_MIN_FILTER` | `LINEAR`   | Bilinear interpolation       | Photos, smooth scaling       |
| `TEXTURE_MIN_FILTER` | `NEAREST_MIPMAP_LINEAR` | Mipmapped | 3D scenes with distance |
| `TEXTURE_MAG_FILTER` | `NEAREST`  | Nearest texel when magnified | Pixel art upscaling          |
| `TEXTURE_MAG_FILTER` | `LINEAR`   | Smooth when magnified        | General use                  |

**MIN_FILTER** — Used when the texture is **minified** (displayed smaller than its native size).
**MAG_FILTER** — Used when the texture is **magnified** (displayed larger than its native size).

```
Native texture: 256x256

Displayed at 128x128 → MIN_FILTER applies (shrinking)
Displayed at 512x512 → MAG_FILTER applies (stretching)
Displayed at 256x256 → Either (1:1 mapping)
```

### Wrap Modes

Controls what happens when texture coordinates go outside the 0–1 range.

| Parameter       | Value            | Effect                                    |
|-----------------|------------------|-------------------------------------------|
| `TEXTURE_WRAP_S` | `CLAMP_TO_EDGE` | UV clamped to [0,1]; edge pixels stretch  |
| `TEXTURE_WRAP_S` | `REPEAT`         | UV wraps around (tiling)                  |
| `TEXTURE_WRAP_S` | `MIRRORED_REPEAT`| UV mirrors at each integer boundary       |

`WRAP_S` = horizontal (U axis), `WRAP_T` = vertical (V axis).

```
CLAMP_TO_EDGE:     REPEAT:            MIRRORED_REPEAT:
┌──────────┐      ┌──────┬──────┐    ┌──────┬──────┐
│  image   │      │ img  │ img  │    │ img  │ gmi  │
│  eeeeee  │      │ img  │ img  │    │ img  │ gmi  │
│  eeeeee  │      ├──────┼──────┤    ├──────┼──────┤
└──────────┘      │ img  │ img  │    │ gmi  │ img  │
 (edge extends)   └──────┴──────┘    └──────┴──────┘
                   (tiles)            (mirrors)
```

**For FBO textures, always use `CLAMP_TO_EDGE`** — you don't want render target
content wrapping or repeating.

---

## 14. Multiple Render Targets (MRT)

WebGL 2 supports rendering to multiple textures simultaneously from a single
fragment shader. This is useful for deferred rendering or G-buffer passes.

```odin
// Create two textures
color_tex := create_texture(width, height)
normal_tex := create_texture(width, height)

// Attach both to the FBO
fbo := gl.CreateFramebuffer()
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, color_tex, 0)
gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, normal_tex, 0)

// Tell WebGL which attachments to draw to
draw_buffers := [2]u32{gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1}
gl.DrawBuffers(draw_buffers[:])
```

Fragment shader with multiple outputs:
```glsl
#version 300 es
precision mediump float;

layout(location = 0) out vec4 out_color;    // → COLOR_ATTACHMENT0
layout(location = 1) out vec4 out_normal;   // → COLOR_ATTACHMENT1

void main() {
    out_color  = vec4(1.0, 0.0, 0.0, 1.0);  // red
    out_normal = vec4(0.0, 0.0, 1.0, 1.0);  // blue (representing a normal)
}
```

---

## 15. Depth and Stencil Attachments

For 3D rendering or depth-tested 2D rendering, attach a depth buffer to the FBO.

### Using a Renderbuffer (Write-Only, Faster)

```odin
depth_rbo := gl.CreateRenderbuffer()
gl.BindRenderbuffer(gl.RENDERBUFFER, depth_rbo)
gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, width, height)

gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.FramebufferRenderbuffer(
    gl.FRAMEBUFFER,
    gl.DEPTH_ATTACHMENT,
    gl.RENDERBUFFER,
    depth_rbo,
)
```

### Using a Texture (Readable, for Shadow Maps)

```odin
depth_tex := gl.CreateTexture()
gl.BindTexture(gl.TEXTURE_2D, depth_tex)
gl.TexImage2D(
    gl.TEXTURE_2D, 0,
    gl.DEPTH_COMPONENT16,    // depth-only format
    width, height, 0,
    gl.DEPTH_COMPONENT,      // source format
    gl.UNSIGNED_SHORT,       // 16-bit depth
    nil,
)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.FramebufferTexture2D(
    gl.FRAMEBUFFER,
    gl.DEPTH_ATTACHMENT,
    gl.TEXTURE_2D,
    depth_tex,
    0,
)
```

### Combined Depth + Stencil

```odin
gl.TexImage2D(
    gl.TEXTURE_2D, 0,
    gl.DEPTH24_STENCIL8,         // 24-bit depth + 8-bit stencil
    width, height, 0,
    gl.DEPTH_STENCIL,
    gl.UNSIGNED_INT_24_8,
    nil,
)

gl.FramebufferTexture2D(
    gl.FRAMEBUFFER,
    gl.DEPTH_STENCIL_ATTACHMENT, // combined attachment point
    gl.TEXTURE_2D,
    depth_stencil_tex,
    0,
)
```

---

## 16. Common Pitfalls & Debugging

### Pitfall 1: Forgetting to Set the Viewport

**Symptom:** Content renders at wrong size or appears in a corner.

```odin
// WRONG — viewport still set to canvas size
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
// rendering happens at canvas resolution, not FBO resolution

// RIGHT — always set viewport after binding a framebuffer
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.Viewport(0, 0, fbo_width, fbo_height)
```

### Pitfall 2: Feedback Loop (Reading and Writing Same Texture)

**Symptom:** Garbage output, undefined behavior.

```odin
// WRONG — texture is both the FBO attachment AND the sampler input
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)  // writes to tex_a
gl.BindTexture(gl.TEXTURE_2D, tex_a)     // reads from tex_a
// GPU is reading and writing the same memory!

// RIGHT — use a different texture for input
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)  // writes to tex_a
gl.BindTexture(gl.TEXTURE_2D, tex_b)     // reads from tex_b
```

### Pitfall 3: Not Clearing the FBO

**Symptom:** Ghost images from previous frames, accumulating artifacts.

```odin
// Always clear after binding the FBO
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.ClearColor(0.0, 0.0, 0.0, 0.0)
gl.Clear(gl.COLOR_BUFFER_BIT)
```

### Pitfall 4: Wrong Texture Unit

**Symptom:** Black quad (sampling from empty/wrong texture).

```odin
// WRONG — activated unit 0, but told shader to use unit 1
gl.ActiveTexture(gl.TEXTURE0)
gl.BindTexture(gl.TEXTURE_2D, my_texture)
gl.Uniform1i(u_texture, 1)  // mismatch!

// RIGHT — unit number must match
gl.ActiveTexture(gl.TEXTURE0)
gl.BindTexture(gl.TEXTURE_2D, my_texture)
gl.Uniform1i(u_texture, 0)  // matches TEXTURE0
```

### Pitfall 5: Missing Texture Parameters

**Symptom:** Black texture or incomplete FBO.

WebGL requires `MIN_FILTER` to be set for non-mipmapped textures. The default
`MIN_FILTER` is `NEAREST_MIPMAP_LINEAR`, which requires mipmaps. If you haven't
generated mipmaps, sampling returns black.

```odin
// Always set these for FBO textures
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)   // or NEAREST
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)   // or NEAREST
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
```

### Pitfall 6: Premultiplied Alpha

**Symptom:** Dark fringes around transparent edges.

If the WebGL context has premultiplied alpha enabled (default), colors are stored
as `(R*A, G*A, B*A, A)`. The blend function must account for this:

```odin
// Standard alpha (ArMonarch uses disablePremultipliedAlpha):
gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

// Premultiplied alpha:
gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
```

### Pitfall 7: Not Unbinding the FBO

**Symptom:** Subsequent draw calls go to the FBO instead of the screen.

```odin
// After rendering to FBO, always switch back to default
gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
```

### Debugging Checklist

If your textured quad shows a black rectangle:

1. Is the FBO complete? Check `gl.CheckFramebufferStatus(gl.FRAMEBUFFER)`
2. Did you actually render something into the FBO? Clear with a visible color to test
3. Did you set the viewport when rendering to the FBO?
4. Is the correct texture bound to the correct texture unit?
5. Does the uniform sampler index match the active texture unit?
6. Did you set `MIN_FILTER` to `LINEAR` or `NEAREST`?
7. Is blending enabled? (`gl.Enable(gl.BLEND)`)
8. Are your texture coordinates correct? (0–1 range, matching vertex positions)
9. Is the transform matrix producing valid NDC coordinates?
10. Check for GL errors (browser console in WebGL)

---

## 17. Performance Considerations

### Minimize FBO Switches

Each `gl.BindFramebuffer` call is expensive. Batch all FBO renders together:

```odin
// GOOD — render all surfaces, then composite all
for &s in surfaces { render_to_fbo(s) }     // Pass 1
for &s in surfaces { composite_to_screen(s) } // Pass 2

// BAD — alternating between FBO and screen per surface
for &s in surfaces {
    render_to_fbo(s)           // bind FBO
    composite_to_screen(s)     // bind default
}
```

### Use the Dirty Flag

Only re-render an FBO when its content has changed:

```odin
if s.dirty {
    gl.BindFramebuffer(gl.FRAMEBUFFER, s.fbo)
    // ... render ...
    s.dirty = false
}
// The texture persists — composite it every frame regardless
```

### Reuse Geometry

One unit quad VAO for everything. Never create per-surface vertex buffers:

```odin
// ONE quad VAO, created once
init_quad()

// Every surface reuses it with a different transform matrix
for &s in surfaces {
    gl.UniformMatrix4fv(u_transform, s.transform)
    draw_quad()
}
```

### Texture Size

- FBO textures consume `width * height * 4` bytes (RGBA8)
- A 1920x1080 texture = ~8 MB
- 10 surfaces at 1920x1080 = ~80 MB of GPU memory
- Size FBO textures to the actual surface dimensions, not the canvas size

### Power-of-Two Textures

WebGL 2 supports non-power-of-two (NPOT) textures fully. Unlike WebGL 1, you can use
any dimensions with all wrap modes and mipmaps. No need to pad to powers of two.

---

## 18. Quick Reference Cheat Sheet

### Create Texture
```odin
tex := gl.CreateTexture()
gl.BindTexture(gl.TEXTURE_2D, tex)
gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
```

### Create FBO
```odin
fbo := gl.CreateFramebuffer()
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)
```

### Render to FBO
```odin
gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
gl.Viewport(0, 0, fbo_w, fbo_h)
gl.Clear(gl.COLOR_BUFFER_BIT)
// ... draw calls ...
gl.BindFramebuffer(gl.FRAMEBUFFER, gl.Framebuffer(0))
```

### Draw Textured Quad
```odin
gl.ActiveTexture(gl.TEXTURE0)
gl.BindTexture(gl.TEXTURE_2D, fbo_texture)
gl.Uniform1i(u_sampler, 0)
gl.UniformMatrix4fv(u_transform, transform)
gl.BindVertexArray(quad_vao)
gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
```

### Delete Resources
```odin
gl.DeleteFramebuffer(fbo)
gl.DeleteTexture(tex)
gl.DeleteRenderbuffer(rbo)
```

### Essential State
```odin
gl.Enable(gl.BLEND)
gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
```
