# Shapes

```odin
package shapes

import "core:fmt"
import "core:math/linalg/glsl"
import gl "vendor:/wasm/WebGL"

// constants used through out this file
NORMALIZED :: false

DrawRectangle :: proc(x, y: f32, width, height: f32, color: glsl.vec4) -> (success: bool) {
	program, ok := ctx.programs["traingle"]
	if ok != true {
		fmt.eprintln("Error: failed to load program `traingle`")
		return false
	}
	// select the program to use
	gl.UseProgram(program)

	// get the attribute location
	positionAttributeLocation := gl.GetAttribLocation(program, "a_position")

	// set uniforms for shaders
	rgba := gl.GetUniformLocation(program, "u_rgba")
	gl.Uniform4f(rgba, color.r, color.g, color.b, color.a)
	time := gl.GetUniformLocation(program, "time")
	gl.Uniform1f(time, ctx.total_time)

	// create and bind VAO first so it captures all buffer bindings
	vao := gl.CreateVertexArray()
	defer gl.DeleteVertexArray(vao)
	gl.BindVertexArray(vao)

	// vertex buffer
	vertexs := [8]f32 {
		x,
		y, // vertex 0: bottom-left
		x,
		y + height, // vertex 1: top-left
		x + width,
		y, // vertex 2: bottom-right
		x + width,
		y + height, // vertex 3: top-right
	}
	vertexBuffer := gl.CreateBuffer()
	defer gl.DeleteBuffer(vertexBuffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, vertexBuffer)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertexs) * size_of(f32),
		transmute(rawptr)&vertexs,
		gl.STATIC_DRAW,
	)

	// index buffer: two triangles sharing vertices 1 and 2
	indexBuffer := gl.CreateBuffer()
	defer gl.DeleteBuffer(indexBuffer)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer)
	indices := [6]u16 {
		0,
		1,
		2, // triangle 1
		1,
		2,
		3, // triangle 2
	}
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(u16),
		transmute(rawptr)&indices,
		gl.STATIC_DRAW,
	)

	// enable and configure all attribute locations
	gl.EnableVertexAttribArray(positionAttributeLocation)
	gl.VertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, NORMALIZED, 0, 0)

	// draw the rectangle
	gl.DrawElements(gl.TRIANGLES, len(indices), gl.UNSIGNED_SHORT, nil)

	return true
}
```
