# Vertex Buffer Object (VBO) & Vertex Array Object (VAO)

## Vertex Buffer Object (VBO)

A VBO is a GPU-side memory buffer that stores vertex data (positions, colors, normals, UVs, etc.).

### Why it matters

- **Without VBO** — vertex data is sent from CPU to GPU every frame. Slow.
- **With VBO** — data is uploaded to GPU memory once, then reused across draw calls. Fast.

### How it works in WebGL

```js
// 1. Create buffer
const vbo = gl.createBuffer();

// 2. Bind it as the active buffer
gl.bindBuffer(gl.ARRAY_BUFFER, vbo);

// 3. Upload data to GPU memory (done once)
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);

// 4. Tell the shader how to read it
gl.vertexAttribPointer(location, size, gl.FLOAT, false, stride, offset);
gl.enableVertexAttribArray(location);

// 5. Draw — GPU reads directly from its own memory
gl.drawArrays(gl.TRIANGLES, 0, vertexCount);
```

### Key points

- **Performance** — eliminates per-frame CPU-to-GPU data transfer
- **`gl.STATIC_DRAW`** — hint that data won't change (best for static geometry)
- **`gl.DYNAMIC_DRAW`** — hint that data will change frequently (animations, particles)
- **Multiple VBOs** — you can have separate buffers for positions, colors, normals, or interleave them in one buffer

---

## Vertex Array Object (VAO)

A VAO stores the *configuration* of how vertex data is read from VBOs. It's a state container, not data storage.

### The problem it solves

Without VAO, you must repeat the attribute setup before every draw call:

```js
gl.bindBuffer(gl.ARRAY_BUFFER, positionVBO);
gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
gl.enableVertexAttribArray(0);

gl.bindBuffer(gl.ARRAY_BUFFER, colorVBO);
gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
gl.enableVertexAttribArray(1);

gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
```

With multiple objects, this gets repetitive and error-prone.

### With VAO

```js
// Setup (once)
const vao = gl.createVertexArray();
gl.bindVertexArray(vao);
  gl.bindBuffer(gl.ARRAY_BUFFER, positionVBO);
  gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(0);

  gl.bindBuffer(gl.ARRAY_BUFFER, colorVBO);
  gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(1);

  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
gl.bindVertexArray(null);

// Draw (every frame) — one call restores all state
gl.bindVertexArray(vao);
gl.drawElements(gl.TRIANGLES, count, gl.UNSIGNED_SHORT, 0);
```

### What a VAO remembers

- Which VBO is bound to each attribute
- `vertexAttribPointer` configuration (size, type, stride, offset)
- Which attributes are enabled/disabled
- The bound Element Buffer Object (EBO/IBO)

### Key points

- **VBO** = the data (vertices, colors, normals)
- **VAO** = the layout (how to read that data)
- Switching between objects becomes a single `bindVertexArray()` call instead of reconfiguring everything
- **WebGL2** has native VAO support. WebGL1 needs the `OES_vertex_array_object` extension.
