# WebGPU vs OpenGL vs Vulkan — Power Comparison & Migration Notes

## Power Comparison

| | OpenGL/WebGL | WebGPU | Vulkan |
|---|---|---|---|
| **Abstraction level** | High (driver does a lot) | Medium (you control most things) | Low (you control everything) |
| **Compute shaders** | WebGL: No, GL: Yes (4.3+) | Yes | Yes |
| **Multi-threading** | No | Command encoding yes, submission no | Full multi-threaded |
| **Pipeline control** | Minimal | Significant | Total |
| **Memory control** | None | Usage hints | Manual allocation, memory types, heaps |
| **Render passes** | Implicit | Explicit | Explicit + subpasses, dependencies |
| **Synchronization** | Automatic | Automatic | Manual (semaphores, fences, barriers) |
| **Shader stages** | Vertex/Fragment | Vertex/Fragment/Compute | Vertex/Fragment/Compute/Geometry/Tessellation/Mesh/Ray |
| **Ray tracing** | No | No (proposed extension) | Yes (via extensions) |
| **Bindless resources** | No | No | Yes |

WebGPU sits between OpenGL and Vulkan — you get most of Vulkan's explicit control without the pain of manual synchronization and memory management. Think of it as "Vulkan made practical."

**wgpu** (the Rust crate) is an *implementation* of WebGPU, not a separate API. On native platforms it translates to Vulkan/D3D12/Metal. In the browser it maps directly to the WebGPU API.

## Major Issues When Migrating from WebGL to WebGPU

### 1. No Geometry/Tessellation Shaders

WebGPU only supports vertex, fragment, and compute stages. Not an issue for the current ArMonarch project, but limits future flexibility.

### 2. WGSL Limitations

- No `#include` or preprocessor — you'll need to concatenate shader strings yourself or use Odin's `#load` creatively.
- Less mature tooling and fewer examples compared to GLSL.
- Some GLSL built-ins have different names:
  - `texture()` → `textureSample()`
  - `gl_FragCoord` → `@builtin(position)`
  - `in`/`out` → `@location(N)` annotations

### 3. Verbose Initialization

What's currently ~10 lines of WebGL context setup becomes:

```
Instance → request Adapter → request Device → configure Surface
→ create ShaderModule → create PipelineLayout → create RenderPipeline
→ create BindGroupLayout → create BindGroup
```

All before you draw a single pixel.

### 4. Async Adapter/Device Creation

In browser WebGPU, `requestAdapter()` and `requestDevice()` are async. Odin's WASM bindings may handle this differently than WebGL's synchronous `CreateCurrentContextById`. Check how `vendor:wgpu`'s `wgpu_js.odin` handles this.

### 5. Texture Format Negotiation

WebGL just gives you RGBA8. WebGPU requires you to query the surface's preferred format (`getSurfacePreferredFormat`) and match it. Mismatches = validation errors.

### 6. Buffer Alignment Rules

- Uniform buffers must be 16-byte aligned.
- `BufferBinding` offsets must be 256-byte aligned.
- These will cause subtle bugs if Odin structs aren't padded correctly.

### 7. Canvas Configuration (Browser-Specific)

WebGL auto-manages the canvas framebuffer. In WebGPU you must explicitly call `surface.configure()` and handle `getCurrentTexture()` each frame. On resize, you must reconfigure.

### 8. Limited Debugging Resources

Fewer Odin + WebGPU + WASM examples exist compared to WebGL. You'll often be translating from Rust wgpu tutorials or the WebGPU spec directly.

## ArMonarch-Specific Migration Friction Points

- **Rewriting 6 GLSL shaders to WGSL** (straightforward but tedious).
- **Replacing the compositor's FBO pipeline** with render pass descriptors and texture views.
- **Async initialization** on the WASM target.
- **Learning the bind group system** to replace `gl.GetUniformLocation` / `gl.Uniform*` calls.

## GLSL to WGSL Quick Reference

```glsl
// GLSL
in vec2 v_uv;
uniform float u_time;
out vec4 fragColor;
```

```wgsl
// WGSL equivalent
@group(0) @binding(0) var<uniform> u_time: f32;

@fragment
fn main(@location(0) v_uv: vec2f) -> @location(0) vec4f {
    // ...
}
```

## Browser Support (as of April 2026)

- **Chrome/Edge/Brave:** Full support
- **Firefox:** Full support from v141+ (current: 147.0.3)
- **Safari:** Partial/experimental
