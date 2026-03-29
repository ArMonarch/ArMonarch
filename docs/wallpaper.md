# Wallpaper as a Self-Contained Program

The wallpaper is a self-contained program with its own WebGL resources.

## State & Init

### `src/wallpaper/wallpaper.odin`

```odin
package wallpaper

import gl "vendor:wasm/WebGL"
import "../shaders"

State :: struct {
    program:      gl.Program,
    vao:          gl.VertexArray,
    vbo:          gl.Buffer,
    ebo:          gl.Buffer,
    u_time:       i32,
    u_resolution: i32,
}

state: State

init :: proc() {
    program, ok := gl.CreateProgramFromStrings(
        {string(shaders.WALLPAPER_VERT_SHADER)},
        {string(shaders.WALLPAPER_FRAG_SHADER)},
    )
    if !ok {
        return
    }
    state.program = program

    state.u_time       = gl.GetUniformLocation(program, "u_time")
    state.u_resolution = gl.GetUniformLocation(program, "u_resolution")

    state.vao = gl.CreateVertexArray()
    gl.BindVertexArray(state.vao)

    // Fullscreen quad in NDC (-1..1)
    vertices := [8]f32{
        -1.0, -1.0,  // bottom-left
         1.0, -1.0,  // bottom-right
        -1.0,  1.0,  // top-left
         1.0,  1.0,  // top-right
    }

    state.vbo = gl.CreateBuffer()
    gl.BindBuffer(gl.ARRAY_BUFFER, state.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)

    indices := [6]u16{0, 1, 2, 2, 1, 3}

    state.ebo = gl.CreateBuffer()
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, state.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)

    gl.BindVertexArray(gl.VertexArray(0))
}
```

**Key difference from compositor's unit quad:** Vertices go from -1 to 1 (full NDC), not 0 to 1. Fills its entire FBO — no transform matrix needed. No texcoords since the fragment shader generates pixels procedurally.

## Render Function

The compositor calls this. The FBO is already bound when it runs.

```odin
import "../compositor"

render :: proc(surface: ^compositor.Surface, dt: f32) {
    gl.UseProgram(state.program)

    gl.Uniform1f(state.u_time, dt)
    gl.Uniform2f(state.u_resolution, f32(surface.width), f32(surface.height))

    gl.BindVertexArray(state.vao)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
    gl.BindVertexArray(gl.VertexArray(0))
}
```

## Shaders (Shadertoy-style)

### `src/shaders/wallpaper.vert.glsl`

```glsl
#version 300 es

layout(location = 0) in vec2 a_position;

void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
}
```

Vertices are already in NDC, just pass them through.

### `src/shaders/wallpaper.frag.glsl`

```glsl
#version 300 es
precision mediump float;

uniform float u_time;
uniform vec2 u_resolution;

out vec4 fragColor;

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;

    // Example: animated gradient
    vec3 color = vec3(
        0.5 + 0.5 * sin(u_time + uv.x * 3.0),
        0.5 + 0.5 * sin(u_time + uv.y * 3.0 + 2.0),
        0.5 + 0.5 * sin(u_time + uv.x * 3.0 + 4.0)
    );

    fragColor = vec4(color, 1.0);
}
```

Swap this shader for any effect — noise, fractals, waves, a static color, an image.

### `src/shaders/lib.odin` — add the loads

```odin
WALLPAPER_VERT_SHADER :: #load("./wallpaper.vert.glsl")
WALLPAPER_FRAG_SHADER :: #load("./wallpaper.frag.glsl")
```

## Wire It Up

```odin
import "wallpaper"
import "compositor"

main :: proc() {
    // ... WebGL context, renderer init, compositor init ...

    wallpaper.init()

    w := gl.DrawingBufferWidth()
    h := gl.DrawingBufferHeight()
    wp := compositor.create_surface(0, 0, w, h, .Background, wallpaper.render)
}
```

## Animated Wallpapers

The wallpaper needs accumulated time, not just dt. Two options:

### Option A — Track time in the wallpaper package (simpler)

```odin
State :: struct {
    // ... existing fields ...
    total_time: f32,
}

render :: proc(surface: ^compositor.Surface, dt: f32) {
    state.total_time += dt
    surface.dirty = true  // re-render next frame (animated)

    gl.UseProgram(state.program)
    gl.Uniform1f(state.u_time, state.total_time)
    // ...
}
```

### Option B — Pass total time through the surface struct (add a time field)

Option A is simpler for now.

## Pattern for Future Programs

Every "program" (wallpaper, terminal, text viewer, etc.) follows this shape:

```
my_program/
├── State struct     (owns program, VAO, VBO, uniforms, any app state)
├── init()           (creates GPU resources once)
└── render(surface, dt)  (draws into the surface's FBO)
```

The compositor doesn't know or care what's inside — it just calls `render_fn` and composites the resulting texture.
