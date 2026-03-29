# ArMonarch — WebGL Desktop Environment Architecture (v2)

## Context

ArMonarch is an Odin/WebGL/WASM project building a web-based desktop environment. The architecture follows Wayland's model: a compositor manages surfaces (pixel buffers), a window manager adds window semantics on top, and input flows through the WM for routing — just like a Wayland compositor.

---

## Package Structure

```
src/
  main.odin                  -- Entry point: init, update loop, wiring subsystems
  types.odin                 -- Shared types, constants, forward declarations
  bridge.odin                -- Foreign import declarations for JS functions

  compositor/
    compositor.odin           -- Surface management, composite loop (FBO textures → screen)
    surface.odin              -- Surface struct, FBO lifecycle, render-to-texture

  wm/
    wm.odin                   -- Window manager: create/destroy/focus/move/resize windows
    window.odin               -- Window struct, decoration metadata, state
    desktop.odin              -- Desktop layer: wallpaper surface, desktop entries

  input/
    input.odin                -- DOM event capture, pointer/keyboard state

  renderer/
    renderer.odin             -- Shader cache, shared unit quad VAO, transform matrices

  ui/
    ui.odin                   -- Clay initialization, render command → WebGL execution
    taskbar.odin              -- Bottom panel showing open windows

  colors/
    colors.odin               -- Color constants (exists)

  shaders/
    lib.odin                  -- All #load directives (exists)
    compositor.vert.glsl      -- Textured quad vertex shader (exists, needs texture support)
    compositor.frag.glsl      -- Texture sampling + opacity fragment shader (exists, needs texture support)
    traingle.vert.glsl        -- Triangle vertex shader (exists)
    traingle.frag.glsl        -- Triangle fragment shader (exists)

  applications/
    application.odin          -- Application struct, lifecycle types
    triangle.odin             -- Triangle demo application
    gradient.odin             -- Gradient shader application
    wallpaper.odin            -- Animated wallpaper application

  clay/                       -- Clay bindings (exists, unchanged)
  artwall/
    builder.odin              -- Wallpaper builder (exists, stub)

  js/
    runtime.js                -- Odin WASM runtime (exists, unchanged)
    lib.js                    -- Bridge functions (exists)
```

### Dependency Graph (no cycles)

```
main → compositor, wm, input, ui, applications
compositor → renderer, shaders
wm → compositor (creates surfaces, provides decoration metadata)
input → (none — captures DOM events, exposes state)
wm uses input (reads input state, does hit-testing/routing)
applications → compositor (receives surface), shaders (GPU resources)
ui → clay, renderer
renderer → shaders
```

---

## Core Systems

### 1. Compositor (`src/compositor/`) — like `wl_compositor`

The compositor owns all surfaces and composites them onto the screen. It knows nothing about windows — only surfaces with position, size, layer, and z-order.

**Surface:**

```odin
Surface :: struct {
    id:            Surface_Id,
    x, y:          i32,          // Canvas pixel position (top-left origin)
    width, height: i32,
    layer:         Layer_Kind,
    z_index:       i32,          // Within its layer
    dirty:         bool,
    visible:       bool,
    opacity:       f32,
    // WebGL resources
    framebuffer:   gl.Framebuffer,
    texture:       gl.Texture,
    render:        Render_Function,  // proc(^Surface, dt: f32)
    // Application running on this surface (owns GPU resources)
    application:   ^Application,
    // Optional decoration metadata (set by WM for window surfaces)
    decoration:    ^Decoration,
}
```

**Layer protocol** (inspired by `wlr-layer-shell`):

```odin
Layer_Kind :: enum u8 {
    Background,   // Wallpaper
    Bottom,       // Taskbar, panels
    Window,       // Application windows (WM operates here)
    Top,          // Popups, tooltips above windows
    Overlay,      // Notifications, lock screen
}
```

**Decoration metadata** (provided by WM, drawn by compositor):

```odin
Decoration :: struct {
    titlebar_height: i32,       // Pixels above the client surface
    border_width:    i32,       // Pixels around the client surface
    title:           [128]byte,
    title_len:       u8,
    bg_color:        glsl.vec4, // Titlebar background
    border_color:    glsl.vec4,
    focused:         bool,      // Affects decoration appearance
    // Button regions (relative to decoration top-left)
    close_rect:      Rect,
    minimize_rect:   Rect,
    maximize_rect:   Rect,
}
```

**Composite loop** (each frame):

1. Bind default framebuffer, clear with background color
2. Enable alpha blending (`SRC_ALPHA`, `ONE_MINUS_SRC_ALPHA`)
3. For each layer `Background → Overlay`, for each surface sorted by z_index:
   - Skip if `!visible`
   - If surface has `decoration != nil`:
     - Draw decoration geometry (titlebar rect, border, buttons) using decoration metadata
   - Bind the surface's `texture`
   - Compute transform matrix mapping `(x, y, w, h)` pixels → NDC
   - Draw unit quad with compositor shader (texture sampling + opacity)
4. Disable blending

The compositor shader needs texture coordinates and a sampler uniform — the current shader only does solid color and must be updated.

### 2. Window Manager (`src/wm/`) — like a Wayland WM

The WM adds window semantics on top of compositor surfaces. It is the only system that knows what a "window" is.

**Window:**

```odin
Window :: struct {
    id:              Window_Id,
    surface_id:      Surface_Id,     // The compositor surface this window wraps
    state:           Window_State,   // Normal, Maximized, Minimized
    title:           [128]byte,
    title_len:       u8,
    focused:         bool,
    // Drag/resize state
    dragging:        bool,
    drag_offset_x:   i32,
    drag_offset_y:   i32,
    resizing:        bool,
    resize_edge:     Resize_Edge,
}

Window_State :: enum u8 { Normal, Maximized, Minimized }
Resize_Edge :: enum u8 { None, Top, Bottom, Left, Right, TopLeft, TopRight, BottomLeft, BottomRight }
```

**Responsibilities:**
- **Create window**: asks compositor to create a surface on the `Window` layer, attaches `Decoration` metadata to it
- **Destroy window**: removes decoration, asks compositor to destroy surface
- **Focus**: maintains a focus stack; focused window has highest z_index in Window layer
- **Drag**: on titlebar mousedown, begin drag; on mousemove, update surface position via compositor
- **Resize**: on edge mousedown, begin resize; on mousemove, resize surface and recreate FBO
- **Close/Min/Max buttons**: hit-test button rects in decoration metadata

**Input routing** (WM owns this, like Wayland):

1. Read raw pointer/keyboard state from input system
2. On pointer events, hit-test:
   - Check Overlay surfaces first (top layer), then Top, Window, Bottom, Background
   - Within Window layer, check surfaces top z → bottom z
   - For each window surface: check decoration regions (titlebar, buttons, resize edges), then client content area
3. Route accordingly:
   - **Decoration titlebar** → begin drag, focus window
   - **Decoration button** → close/minimize/maximize
   - **Decoration edge** → begin resize
   - **Client content area** → transform to surface-local coordinates, deliver to client
   - **No window hit** → desktop click handler
4. Keyboard events go to the focused window's client

### 3. Input System (`src/input/`) — like `wl_seat`

Captures DOM events and maintains raw state. Does NOT route — that's the WM's job.

Registers listeners on the canvas via `core:sys/wasm/js`:

- `mousedown`, `mouseup`, `mousemove`, `wheel`
- `keydown`, `keyup`
- `contextmenu`

**State:**

```odin
Input_State :: struct {
    // Pointer
    mouse_x, mouse_y:   i32,
    mouse_dx, mouse_dy:  i32,    // Delta since last frame
    buttons:             u8,      // Bitmask: left=1, right=2, middle=4
    buttons_pressed:     u8,      // Just pressed this frame
    buttons_released:    u8,      // Just released this frame
    scroll_dx, scroll_dy: f32,
    // Keyboard
    keys:                [256]bool,
    keys_pressed:        [256]bool,
    keys_released:       [256]bool,
    modifiers:           Modifiers,  // shift, ctrl, alt, meta
}
```

Each frame, the WM reads this state and processes it. At frame end, clear per-frame deltas (`buttons_pressed`, `keys_pressed`, etc.).

> Canvas needs `tabindex="0"` in HTML for keyboard focus.

### 4. Desktop Entries (minimal)

No VFS. Just a flat array of entries for desktop icons.

```odin
Entry_Kind :: enum u8 { File, Directory, Application }

Desktop_Entry :: struct {
    name:    [64]byte,
    name_len: u8,
    kind:    Entry_Kind,
    icon_id: u16,
    action:  proc(),   // Called on double-click
}
```

**Default entries:**

```
README.txt      (File — opens text viewer window)
Projects/       (Directory — opens file browser window)
Terminal        (Application — opens a program window)
```

### 5. Renderer Utilities (`src/renderer/`)

**Shader cache:** All shader programs created once at init, stored by name/id. Never recreated per frame.

**Shared unit quad:**

```odin
// Vertices: [0,0], [1,0], [0,1], [1,1] with UVs matching
// Indices: [0,1,2], [1,2,3]
// Single VAO used by compositor and all programs
```

**Transform matrix:** Maps `(x, y, w, h)` in pixel coords to NDC:

```
sx = 2*w/canvas_w,  sy = 2*h/canvas_h
tx = 2*x/canvas_w - 1,  ty = 1 - 2*y/canvas_h - sy
→ scale+translate matrix
```

### 6. UI via Clay (`src/ui/`)

Clay handles complex 2D UI: taskbar, desktop icon grid.

**Integration:**

1. Init Clay with a memory arena at startup
2. Each frame, call `clay.SetPointerState()` with current mouse pos
3. Build Clay layouts for visible UI elements
4. `clay.EndLayout()` → iterate `RenderCommand` array → translate to WebGL draw calls:
   - **Rectangle** → draw colored/rounded rect
   - **Text** → render via bitmap font atlas (deferred to later phase)
   - **Border** → draw border lines
   - **ScissorStart/End** → `gl.Scissor`
   - **Custom** → custom WebGL drawing

### 7. Applications (`src/applications/`)

An application is anything that draws into a surface's FBO. The `Application` struct lives on the surface and holds the common GPU resources every app needs. Applications follow a simple lifecycle: init once, render each frame, destroy on close.

**Application struct** (attached to `surface.application`):

```odin
App_Render_Fn  :: #type proc(surface: ^Surface, app: ^Application, dt: f32)
App_Destroy_Fn :: #type proc(app: ^Application)

Application :: struct {
    name:         [64]byte,
    name_len:     u8,
    // Common GPU resources
    program:      gl.Program,
    vao:          gl.VertexArrayObject,
    vertex_buf:   gl.Buffer,
    index_buf:    gl.Buffer,
    // Uniform locations (common)
    u_time:       i32,
    u_resolution: i32,
    // App state
    total_time:   f32,
    // Lifecycle
    render:       App_Render_Fn,
    destroy:      App_Destroy_Fn,
    // Escape hatch for apps that need extra state beyond common fields
    data:         rawptr,
}
```

**Why this design:**
- Most apps need the same GPU resources: a shader program, a VAO, vertex/index buffers, and a few uniforms
- These live directly on `Application` — no casting, no per-app state structs for simple cases
- Complex apps that need extra buffers, textures, or state use `data: rawptr`
- The compositor doesn't care about any of this — it just calls `surface.render`

**Lifecycle:**

```
1. WM (or desktop) decides to launch an application
2. Compositor creates a surface (FBO + texture)
3. App init function allocates Application, creates GPU resources ONCE
4. surface.application = app
5. surface.render calls app.render(surface, app, dt)
6. Each frame: compositor binds FBO → calls surface.render → app draws using its own GPU state
7. On close: app.destroy(app) → deletes GPU resources, frees data, frees app
```

**Example — triangle application:**

```odin
// src/applications/triangle.odin
package applications

triangle_init :: proc(surface: ^compositor.Surface) -> ^Application {
    app := new(Application)
    app.name = "Triangle"

    // Create shader program ONCE
    app.program, _ = gl.CreateProgramFromStrings(
        {transmute(string)shaders.TRIANGLE_VERT},
        {transmute(string)shaders.TRIANGLE_FRAG},
    )
    app.u_time = gl.GetUniformLocation(app.program, "u_time")

    // Create VAO and buffers ONCE
    app.vao = gl.CreateVertexArray()
    gl.BindVertexArray(app.vao)

    app.vertex_buf = gl.CreateBuffer()
    // ... set up vertices ...

    app.index_buf = gl.CreateBuffer()
    // ... set up indices ...

    app.render = triangle_render
    app.destroy = triangle_destroy
    return app
}

triangle_render :: proc(surface: ^compositor.Surface, app: ^Application, dt: f32) {
    app.total_time += dt
    // FBO already bound by compositor
    gl.UseProgram(app.program)
    gl.BindVertexArray(app.vao)
    gl.Uniform1f(app.u_time, app.total_time)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
}

triangle_destroy :: proc(app: ^Application) {
    gl.DeleteProgram(app.program)
    gl.DeleteVertexArray(app.vao)
    gl.DeleteBuffer(app.vertex_buf)
    gl.DeleteBuffer(app.index_buf)
    free(app)
}
```

**Example — app with extra state (uses `data`):**

```odin
// An app that needs multiple textures beyond the common fields
Particle_Data :: struct {
    particle_buf:   gl.Buffer,
    particle_count: i32,
    sprite_texture: gl.Texture,
}

particle_init :: proc(surface: ^compositor.Surface) -> ^Application {
    app := new(Application)
    // ... set up common GPU resources ...

    extra := new(Particle_Data)
    extra.particle_buf = gl.CreateBuffer()
    extra.sprite_texture = gl.CreateTexture()
    app.data = extra

    app.render = particle_render
    app.destroy = particle_destroy
    return app
}

particle_destroy :: proc(app: ^Application) {
    extra := cast(^Particle_Data)app.data
    gl.DeleteBuffer(extra.particle_buf)
    gl.DeleteTexture(extra.sprite_texture)
    free(extra)
    // ... free common resources ...
    free(app)
}
```

**Shader-only applications (Shadertoy-style):** A helper creates an Application from just a fragment shader string. Common fields hold the program + standard uniforms (`u_time`, `u_resolution`). The renderer provides the vertex shader (fullscreen quad). No `data` needed. Used for animated wallpapers and demos.

---

## Frame Pipeline

```
update(dt):
  1. Input: DOM events already captured via callbacks
  2. WM: read input state, process drag/resize, update surface positions,
         update decoration metadata
  3. Render: for each dirty surface, bind its FBO, call render_fn(surface, dt)
  4. Composite: bind default framebuffer, clear
     - For each layer (Background → Overlay):
       - For each surface sorted by z_index (bottom → top):
         a. If surface.decoration != nil: draw decoration geometry
         b. Bind surface.texture
         c. Draw textured quad at (x, y, w, h) with opacity
     - Alpha blending enabled throughout
  5. FPS accounting
  6. return true
```

---

## JS Bridge (`src/js/lib.js`)

Current functions (keep):
- `get_platform_name()` — debug logging
- `update_fps_counter(fps)` — FPS display
- Canvas resize observer

Add as needed (not upfront):
- `set_cursor_style(style)` — for resize/drag cursors
- `get_device_pixel_ratio()` — HiDPI handling

---

## Implementation Phases

### Phase 1 — Fix Compositor

The compositor currently creates FBOs but never composites textures to screen. The composite shader only outputs solid color.

- Update compositor shaders to sample a texture (add `sampler2D` uniform, texture coordinates)
- Add the actual composite pass in `frame()`: bind default framebuffer → for each surface, bind its texture → draw textured quad
- Move shared quad geometry to renderer utilities (shader cache, unit quad VAO, transform matrix)
- Refactor `main.odin`: assign a render function to the background surface that draws content into its FBO
- **Verify:** background surface renders through FBO → texture → screen pipeline

### Phase 2 — Multi-Surface & Layers

- Sort surfaces by layer then z_index in composite loop
- Alpha blending between surfaces
- Create test surfaces on different layers (background + a floating rect)
- Surface visibility toggle
- **Verify:** multiple surfaces render in correct layer order with transparency

### Phase 3 — Input System

- Create `input/` package
- Register DOM listeners on canvas via `core:sys/wasm/js`
- Store pointer and keyboard state in `Input_State`
- Clear per-frame deltas each frame
- Add `tabindex="0"` to canvas in HTML
- **Verify:** pointer state updates correctly (log mouse position on click)

### Phase 4 — Window Manager

- Create `wm/` package with Window struct
- WM creates windows by requesting surfaces from compositor on `Window` layer
- Attach `Decoration` metadata to window surfaces
- Compositor draws decorations during composite pass
- WM reads input state, hit-tests windows, routes events
- Titlebar drag, focus switching, close button
- Focus stack (focused window on top)
- **Verify:** two draggable windows with SSD decorations and focus switching

### Phase 5 — Clay UI Integration

- Init Clay, render commands → WebGL
- Taskbar surface on Bottom layer (shows open windows)
- Desktop icon grid on Background layer
- **Verify:** taskbar shows window list, desktop has clickable icons

### Phase 6 — Desktop & Apps

- Desktop entries (flat list) with double-click actions
- Shader program support (Shadertoy-style fragment shaders)
- Animated wallpaper shader
- **Verify:** desktop icons launch app windows, wallpaper animates

### Phase 7 — Polish (deferred)

- Window resize from edges
- Minimize/maximize
- Context menus
- Bitmap font text rendering
- Cursor style changes via JS bridge

---

## Key Files to Modify

| File | Changes |
|------|---------|
| `src/main.odin` | Wire compositor, WM, input; assign render_fn to surfaces |
| `src/compositor/compositor.odin` | Add composite pass (texture → screen), decoration drawing |
| `src/shaders/compositor.vert.glsl` | Add texture coordinates, transform uniform |
| `src/shaders/compositor.frag.glsl` | Add texture sampler, opacity uniform |
| `src/js/lib.js` | Add bridge functions as needed |
| `index.html` | Add `tabindex="0"` to canvas |

## Key Files to Create

| File | Purpose |
|------|---------|
| `src/renderer/renderer.odin` | Shader cache, unit quad VAO, transform matrices |
| `src/input/input.odin` | DOM event capture, Input_State |
| `src/wm/wm.odin` | Window manager, window creation, focus, drag |
| `src/wm/window.odin` | Window struct, Decoration struct |
| `src/ui/ui.odin` | Clay init, render command → WebGL |
| `src/ui/taskbar.odin` | Taskbar layout and rendering |

---

## Verification

After each phase:

1. `just build-debug` — compiles without errors
2. `just serve` — open `localhost:4000` in browser
3. Visual check: surfaces render correctly, input responds, windows drag
4. Browser console: no GL errors, no JS exceptions
5. FPS stays at 60 (no per-frame shader recompilation or resource creation)
