# Window Manager & Application Flow

How the WM and Applications interact within the compositor architecture.

---

## The WM is the middleman between the user and applications

The compositor only sees surfaces. Applications only see their FBO and GPU resources. The WM sits between them and manages the "window" concept — it's the one that creates, positions, decorates, and destroys application surfaces.

---

## Launching an Application

```
User double-clicks "Triangle" icon on desktop
  → Desktop handler calls: wm.open_window(applications.triangle_init)
```

Inside `wm.open_window`:

```
1. WM picks position/size for the new window (e.g. centered, 400x300)
2. WM calls compositor.create_surface(x, y, width, height, .Window)
   → compositor creates FBO + texture, returns ^Surface
3. WM calls triangle_init(surface)
   → app creates its GPU resources, returns ^Application
4. WM stores the Application on the surface:
   surface.application = app
5. WM sets up the render function on the surface:
   surface.render = proc that calls app.render(surface, app, dt)
6. WM creates a Window struct tracking this surface:
   Window {
       surface_id = surface.id,
       title = app.name,
       focused = true,
       ...
   }
7. WM attaches Decoration metadata to the surface:
   surface.decoration = &Decoration {
       titlebar_height = 30,
       title = app.name,
       focused = true,
       close_rect = ...,
       ...
   }
8. WM pushes this window to top of focus stack
```

Now the compositor has a surface with an application and decoration. It doesn't know or care that these came from the WM.

---

## Each Frame

```
update(dt):
  1. Input system has captured DOM events

  2. WM reads input state:
     - Mouse moved? Check if we're dragging a window → update surface position
     - Mouse pressed? Hit-test:

       For each window (top z → bottom z):
         ┌─────────────────────────────┐
         │ Decoration (titlebar)       │ ← WM hit-tests this region
         │  [x] [−] [□]  "Triangle"   │    using decoration.close_rect, etc.
         ├─────────────────────────────┤
         │                             │
         │  Client content area        │ ← If click lands here, WM transforms
         │  (app draws here)           │    coords to surface-local and could
         │                             │    forward to the app if it needs input
         │                             │
         └─────────────────────────────┘

       Hit in titlebar → WM starts drag, sets window.dragging = true
       Hit on close button → WM destroys the window (see below)
       Hit in content area → WM focuses this window, delivers event to app
       Hit on nothing → desktop click

  3. Compositor renders dirty surfaces:
     - Binds surface.framebuffer (the FBO)
     - Calls surface.render(surface, dt)
       → which calls app.render(surface, app, dt)
       → app uses its own program/vao/buffers to draw into the FBO
     - Unbinds FBO

  4. Compositor composites to screen:
     For each surface by layer/z-order:
       - surface.decoration != nil?
         → Draw titlebar rect (decoration.bg_color)
         → Draw close/min/max buttons
         → Draw border
       - Bind surface.texture
       - Draw textured quad at surface position
```

---

## Closing an Application

```
User clicks the close button
  → WM hit-tests, finds it's the close_rect of Window #3
```

Inside `wm.close_window`:

```
1. WM gets the surface from the window's surface_id
2. WM calls surface.application.destroy(surface.application)
   → app deletes its GPU resources (program, vao, buffers)
   → app frees its data (if any)
   → app frees itself
3. surface.application = nil
4. WM removes decoration: surface.decoration = nil
5. WM calls compositor.destroy_surface(surface)
   → compositor deletes the FBO and texture
6. WM removes the Window from its list and focus stack
7. WM focuses the next window in the stack
```

---

## Focus and Stacking

```
User clicks on Window B (currently behind Window A):

1. WM hit-tests → click lands on Window B's content area
2. WM unfocuses Window A:
   - window_a.focused = false
   - window_a's decoration.focused = false (changes titlebar color)
3. WM focuses Window B:
   - window_b.focused = true
   - window_b's decoration.focused = true
   - Raise Window B's surface z_index above Window A
4. Next composite pass: Window B renders on top, with focused decoration colors
```

---

## Dragging

```
User mousedown on Window B's titlebar:

1. WM hit-test → titlebar region
2. WM sets window_b.dragging = true
3. WM records drag_offset = mouse_pos - surface_pos

User mousemove (while dragging):

4. WM reads new mouse position
5. WM updates the surface position:
   surface.x = mouse_x - drag_offset_x
   surface.y = mouse_y - drag_offset_y
6. Compositor composites at new position (no FBO re-render needed, just moves the quad)

User mouseup:

7. WM sets window_b.dragging = false
```

---

## Ownership Summary

| | Compositor | WM | Application |
|---|---|---|---|
| **Creates** | Surfaces (FBO + texture) | Windows (wrapping surfaces) | GPU resources (program, vao, buffers) |
| **Stores** | Surface list, layer/z-order | Window list, focus stack | Its state on `surface.application` |
| **Draws** | Surface textures → screen, decoration geometry | Nothing directly | Into its surface's FBO |
| **Handles input** | Nothing | All routing, hit-testing, drag/resize | Receives forwarded content-area events |
| **Destroys** | FBO, texture | Window struct, calls app.destroy | Its own GPU resources |

The key insight: **the WM orchestrates the lifecycle but doesn't render anything itself**. It tells the compositor what to draw (via decoration metadata and surface positioning) and tells applications when to start and stop.
