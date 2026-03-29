# ArMonarch — WebGL Desktop Environment Architecture

## Context

ArMonarch is an Odin/WebGL/WASM project that currently renders a single rectangle to a canvas. The goal is to evolve it into a web-based desktop environment with a Wayland-inspired compositor that manages multiple WebGL programs as windows on a single canvas — with background layers, floating windows, a desktop with clickable files, and overlay UI.

---

## Package Structure

```
src/
  main.odin                  -- Entry point: init, update loop, wiring all subsystems
  types.odin                 -- Shared types, constants, forward declarations
  bridge.odin                -- Foreign import declarations for JS functions

  compositor/
    compositor.odin           -- Core compositor state, frame composition loop
    surface.odin              -- Surface struct, FBO lifecycle, render-to-texture
    layer.odin                -- Layer enum (Background..Overlay), layer stacks, z-ordering

  wm/
    wm.odin                   -- Window manager: create/destroy/focus/move/resize windows
    window.odin               -- Window struct, state, decorations geometry
    desktop.odin              -- Desktop layer: wallpaper surface, icon layout

  input/
    input.odin                -- Event capture from DOM, routing, hit-testing
    pointer.odin              -- Mouse state, drag tracking
    keyboard.odin             -- Key state, modifier tracking

  vfs/
    vfs.odin                  -- Virtual filesystem: in-memory file/directory tree
    file.odin                 -- File struct, file kinds (Regular, Directory, Application)

  renderer/
    renderer.odin             -- Shader cache, quad batcher
    quad.odin                 -- Unit quad VAO, transform matrix computation
    text.odin                 -- Bitmap font atlas renderer, text measurement

  ui/
    ui.odin                   -- Clay initialization, render command -> WebGL execution
    decorations.odin          -- Window titlebar, close/min/max buttons via Clay
    taskbar.odin              -- Bottom panel showing open windows
    file_browser.odin         -- Desktop icon grid, file viewer window
    context_menu.odin         -- Right-click menus

  shaders/
    lib.odin                  -- All #load directives
    compositor/
      vert.glsl               -- Textured quad vertex shader
      frag.glsl               -- Texture sampling + opacity fragment shader
    programs/                 -- Built-in "client" program shaders
      triangle/vert.glsl, frag.glsl
      gradient/vert.glsl, frag.glsl

  clay/                       -- Existing Clay bindings (unchanged)
  js/
    runtime.js                -- Existing Odin WASM runtime (unchanged)
    lib.js                    -- Extended with new bridge functions
```

### Dependency Graph (no cycles)

```
main → compositor, wm, input, ui, vfs, renderer
compositor → renderer
wm → compositor, vfs
input → compositor, wm
ui → clay, compositor, wm, vfs, renderer
renderer → shaders
vfs → (none)
```

---

## Core Systems

### 1. Compositor (`src/compositor/`)

The compositor owns all surfaces — off-screen FBO+texture pairs that programs render into. It composites them as textured quads onto the default framebuffer in layer/z-order.

**Surface:**

```odin
Surface :: struct {
    id:            Surface_Id,
    active:        bool,
    x, y:          i32,          // Canvas pixel position (top-left origin)
    width, height: i32,
    layer:         Layer_Kind,
    z_index:       i32,          // Within its layer
    fbo:           gl.Framebuffer,
    color_texture: gl.Texture,
    visible:       bool,
    opacity:       f32,
    dirty:         bool,
    render_fn:     Surface_Render_Fn,  // proc(^Surface, dt)
    user_data:     rawptr,
}
```

Each surface's FBO is created once (recreated on resize). Client render functions bind the FBO, draw their content, and the compositor reads the resulting texture.

**Layer protocol** (inspired by `wlr-layer-shell`):

```odin
Layer_Kind :: enum u8 {
    Background,   // Wallpaper (one fullscreen surface)
    Bottom,       // Taskbar, panels below windows
    Desktop,      // Desktop icon grid
    Top,          // Application windows (floating WM operates here)
    Overlay,      // Notifications, context menus, lock screen
}
```

**Composite loop** (each frame):

1. Bind default framebuffer, clear
2. Enable alpha blending (`SRC_ALPHA`, `ONE_MINUS_SRC_ALPHA`)
3. For each layer `Background → Overlay`, for each surface bottom → top:
   - Bind the surface's `color_texture`
   - Compute a transform matrix mapping `(x, y, w, h)` pixels → NDC
   - Draw a unit quad with the compositor shader
4. Disable blending

### 2. Window Manager (`src/wm/`)

Operates on surfaces in the `Top` layer. Adds window semantics: title, decorations, focus, dragging/resizing. Floating only.

**Window:**

```odin
Window :: struct {
    id:              Window_Id,
    content_surface: Surface_Id,
    x, y, width, height: i32,       // Including decorations
    content_x, content_y: i32,      // Inset by titlebar/border
    content_width, content_height: i32,
    titlebar_height: i32,           // ~30px
    border_width:    i32,           // ~1px
    state:           Window_State,  // Normal, Maximized, Minimized
    title:           [128]byte,
    focused:         bool,
    dragging, resizing: bool,
    render_fn:       proc(^Surface, f32),
}
```

**Focus:** Last-focused window is on top. Clicking a window raises and focuses it. Focus stack tracks order.

**Hit-testing:** Given mouse coords, iterate windows top → bottom. Check if point is in titlebar (drag), close/min/max buttons, content area, or resize edges.

### 3. Input System (`src/input/`)

Registers DOM event listeners on the canvas via `core:sys/wasm/js`:

- `Mouse_Down`, `Mouse_Up`, `Mouse_Move`, `Wheel`
- `Key_Down`, `Key_Up`
- `Click`, `Double_Click`, `Context_Menu`

**Routing flow:**

1. DOM event → Odin callback
2. Update pointer/keyboard state
3. Hit-test against WM
4. Route to appropriate handler:
   - **Titlebar** → begin drag
   - **Content** → transform to surface-local coords, deliver to program
   - **Close button** → destroy window
   - **Desktop** (no window hit) → desktop click handler
   - **Context menu** on right-click

> Canvas needs `tabindex="0"` in HTML for keyboard focus.

### 4. Virtual Filesystem (`src/vfs/`)

In-memory tree structure for desktop files. No real filesystem — everything is hardcoded or created at runtime.

```odin
File :: struct {
    id:       File_Id,
    kind:     File_Kind,   // Regular, Directory, Application
    name:     [64]byte,
    parent:   File_Id,
    children: [32]File_Id,
    icon_id:  u16,
    // For Application: launch proc that creates a window
    app_launch_fn: proc(rawptr),
    // For Regular: text content
    content:  [1024]byte,
}
```

**Default desktop structure:**

```
/Desktop/
  README.txt      (Regular — opens text viewer window)
  Projects/       (Directory — opens file browser window)
  Terminal        (Application — opens a program window)
```

### 5. UI via Clay (`src/ui/`)

Clay handles all 2D UI: window decorations, taskbar, desktop icons, context menus.

**Integration:**

1. Init Clay with a memory arena at startup
2. Each frame, call `clay.SetPointerState()` with current mouse pos
3. Build Clay layouts for visible UI elements
4. `clay.EndLayout()` → iterate `RenderCommand` array → translate to WebGL draw calls:
   - **Rectangle** → draw colored/rounded rect
   - **Text** → render via bitmap font atlas
   - **Border** → draw border lines
   - **ScissorStart/End** → `gl.Scissor`
   - **Custom** → custom WebGL drawing (e.g., surface preview thumbnails)

**Text rendering:** Bitmap font atlas. Pre-baked font texture loaded at startup. `MeasureTextFunction` returns dimensions from a metrics table. Text rendered as textured quads from the atlas.

### 6. Program Types (Mixed)

Surfaces support two kinds of content:

**a) Odin render procedures:** Full WebGL access. The proc receives `^Surface` and `dt`, draws whatever it wants into the bound FBO. All compiled into the same WASM binary.

**b) Shader programs:** Fragment-shader-only programs (Shadertoy-style). The compositor provides a standard vertex shader (fullscreen quad) and passes uniforms: `u_time`, `u_resolution`, `u_mouse`. The user just writes a fragment shader. Registered as:

```odin
Shader_Program :: struct {
    frag_source: string,
    program:     gl.Program,
    u_time:      i32,
    u_resolution: i32,
    u_mouse:     i32,
}
```

### 7. Renderer Utilities (`src/renderer/`)

**Shader cache:** All shader programs created once at init, stored by name/id. Never recreated per frame (fixes current perf issue).

**Quad geometry:** Shared unit quad VAO (vertices `[0,0]`, `[1,0]`, `[0,1]`, `[0,1]`, `[1,0]`, `[1,1]`) used by the compositor and shader programs.

**Transform matrix:** Maps `(x, y, w, h)` in pixel coords to NDC:

```
sx = 2*w/canvas_w,  sy = 2*h/canvas_h
tx = 2*x/canvas_w - 1,  ty = 1 - 2*y/canvas_h - sy
→ scale+translate matrix
```

### 8. JS Bridge Extensions (`src/js/lib.js`)

New functions to add:

- `set_cursor_style(style)` — change cursor for resize/drag
- `get_device_pixel_ratio()` — HiDPI handling
- `load_image_texture(url, callback)` — async image loading → GL texture
- `get_timestamp()` — for VFS file metadata

---

## Frame Pipeline

```
update(dt) → bool:
  1. Input: DOM events already processed via callbacks. Update Clay pointer state.
  2. WM update: process pending drag/resize, update window positions.
  3. Surface render: for each dirty surface, bind its FBO, call render_fn(surface, dt).
     - For windows: render Clay decorations first, then client content in inset area.
  4. Composite: draw all surface textures to screen in layer order.
  5. FPS accounting.
  6. return true
```

---

## Memory Strategy

All fixed-size pools (no dynamic allocation after init):

- `MAX_SURFACES :: 64`
- `MAX_WINDOWS :: 32`
- `MAX_FILES :: 256`
- Strings as `[N]byte` with length field
- Clay arena allocated once at startup

---

## Implementation Phases

### Phase 1 — Compositor Foundation

- Create `renderer/` package: shader cache, unit quad VAO, matrix utils
- Create `compositor/` package: Surface struct, FBO lifecycle, single-surface compositing
- Refactor `main.odin`: move rectangle drawing into a surface `render_fn`
- **Verify:** same rectangle renders, but through FBO → texture → quad pipeline

### Phase 2 — Layers & Multi-Surface

- Implement layer system and layer stacks
- Create background surface (solid color wallpaper)
- Create multiple content surfaces on different layers
- **Verify:** surfaces render in correct layer order with alpha blending

### Phase 3 — Input

- Create `input/` package, register DOM listeners via `core:sys/wasm/js`
- Implement hit-testing (which surface was clicked)
- **Verify:** clicking surfaces logs correct surface ID

### Phase 4 — Window Manager

- Create `wm/` package: Window struct, create/focus/move/resize
- Simple colored-rect decorations (no Clay yet)
- Window dragging and focus switching
- **Verify:** two draggable windows with focus indication

### Phase 5 — Clay UI

- Create `ui/` package: Clay init, render command → WebGL
- Bitmap font atlas loading and text rendering
- Replace simple decorations with Clay-rendered titlebar/buttons
- Add taskbar surface
- **Verify:** windows have proper decorations, taskbar shows window list

### Phase 6 — Desktop & VFS

- Create `vfs/` package with in-memory filesystem
- Desktop surface with Clay icon grid
- Double-click opens files/apps as windows
- Basic text file viewer program
- **Verify:** desktop icons open windows

### Phase 7 — Polish

- Window resize from edges, maximize/minimize
- Context menus (right-click desktop, titlebar)
- Shader program support (Shadertoy-style)
- Animated wallpaper shader
- Cursor style changes, image loading via JS bridge

---

## Key Files to Modify

| File | Changes |
|------|---------|
| `src/main.odin` | Refactor to wire compositor, wm, input, ui subsystems |
| `src/js/lib.js` | Add bridge functions (cursor, image load, DPR) |
| `src/shaders/lib.odin` | Add `#load` for compositor and new program shaders |
| `index.html` | Add `tabindex="0"` to canvas, optionally remove FPS div |

## Key Files to Create

All new packages listed in the package structure above.

---

## Verification

After each phase:

1. `just build-debug` — compiles without errors
2. `just serve` — open `localhost:4000` in browser
3. Visual check: surfaces render correctly, input responds, windows drag
4. Browser console: no GL errors, no JS exceptions
5. FPS counter stays at 60 (no per-frame shader recompilation)
