# Surface Rendering Flow

Two-step process: surfaces render into their own FBOs, then the compositor draws those textures to the canvas.

## Step 1: Render INTO the Surface's FBO

Each surface's `render` function binds its FBO, draws content, then unbinds:

```odin
artwall_render :: proc(surface: ^compositor.Surface, time: f32) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, surface.framebuffer)
    gl.Viewport(0, 0, surface.width, surface.height)

    // draw content here (using the surface's own shader/VAO)
    gl.ClearColor(0.2, 0.0, 0.4, 1.0)
    gl.Clear(cast(u32)gl.COLOR_BUFFER_BIT)
    // ... any other drawing into this FBO ...

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)  // unbind back to canvas
}
```

Key points:
- Bind the surface's FBO before drawing
- Set viewport to the surface's dimensions
- Unbind FBO (bind 0) when done so subsequent draws go to the canvas

## Step 2: Compositor Composites Surface Textures to Canvas

The compositor loops through all surfaces, first letting them render, then drawing each surface's texture as a quad on the canvas:

```odin
frame :: proc(time: f32) {
    // 1. Let each surface render into its own FBO
    for surface in COMPOSITOR.surfaces {
        if surface.render != nil {
            surface.render(surface, time)
        }
    }

    // 2. Composite: draw each surface's texture to the canvas
    canvas_w := cast(f32)gl.DrawingBufferWidth()
    canvas_h := cast(f32)gl.DrawingBufferHeight()
    gl.Viewport(0, 0, cast(i32)canvas_w, cast(i32)canvas_h)

    gl.UseProgram(COMPOSITOR.program)
    gl.BindVertexArray(COMPOSITOR.vao)

    for surface in COMPOSITOR.surfaces {
        gl.BindTexture(gl.TEXTURE_2D, surface.texture)
        // set u_transform per surface to map (x, y, w, h) -> NDC
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
    }
}
```

## Compositor Shaders

The compositor shader samples from the surface's texture instead of outputting a solid color.

### compositor.vert.glsl

```glsl
#version 300 es

in vec2 a_position;
out vec2 v_texcoord;
uniform mat4 u_transform;

void main() {
    v_texcoord = a_position;
    gl_Position = u_transform * vec4(a_position, 0., 1.);
}
```

### compositor.frag.glsl

```glsl
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D u_texture;
out vec4 out_color;

void main() {
    out_color = texture(u_texture, v_texcoord);
}
```

## Transform Matrix

Maps surface pixel coordinates `(x, y, w, h)` to NDC (-1 to 1):

```
sx = 2*w/canvas_w,  sy = 2*h/canvas_h
tx = 2*x/canvas_w - 1,  ty = 1 - 2*y/canvas_h - sy
```

For a fullscreen background surface (x=0, y=0, w=canvas_w, h=canvas_h), this maps to the full NDC range.

## Wiring It Up

Pass the render function when creating a surface:

```odin
wall_surface, success := compositor.create_surface(
    0, 0, canvas_width, canvas_height,
    .Background,
    artwall.artwall_render,
)
```

## Flow Summary

```
Each frame:
  surface.render() → binds FBO → draws content → unbinds FBO
  compositor → binds surface texture → draws textured quad to canvas
```
