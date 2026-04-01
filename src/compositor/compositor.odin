package compositor

import "../colors"
import "../shaders"
import "core:fmt"
import gl "vendor:wasm/WebGL"

// global compositor
COMPOSITOR: Compositor

Compositor :: struct {
	surfaces:     [dynamic]^Surface,
	// gpu resources
	program:      gl.Program,
	vao:          gl.VertexArrayObject,
	vertexBuffer: gl.Buffer,
	indexBuffer:  gl.Buffer,
	// uniform location for the program
	u_time:       f32,
}

build_compositor :: proc() {
	COMPOSITOR.surfaces = make([dynamic]^Surface, len = 0, cap = 4)
	COMPOSITOR.u_time = 0

	program, ok := gl.CreateProgramFromStrings(
		{transmute(string)shaders.Compositor_Vert_Shader},
		{transmute(string)shaders.Compositor_Frag_Shader},
	)

	if ok != true {
		fmt.eprintln("Error: failed to create compositor program")
		return
	}
	COMPOSITOR.program = program

	// select the program to use
	gl.UseProgram(COMPOSITOR.program)

	// get the attribute location
	positionAttributeLocation := gl.GetAttribLocation(program, "a_position")

	// set uniforms for shaders
	u_time := gl.GetUniformLocation(program, "u_time")
	gl.Uniform1f(u_time, COMPOSITOR.u_time)

	// create and bind VAO first so it captures all buffer bindings
	COMPOSITOR.vao = gl.CreateVertexArray()
	gl.BindVertexArray(COMPOSITOR.vao)

	// vertex buffer
	vertexs := [8]f32 {
		0,
		0, // vertex 0: bottom-left
		0,
		1, // vertex 1: top-left
		1,
		0, // vertex 2: bottom-right
		1,
		1, // vertex 3: top-right
	}
	COMPOSITOR.vertexBuffer = gl.CreateBuffer()
	gl.BindBuffer(gl.ARRAY_BUFFER, COMPOSITOR.vertexBuffer)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertexs) * size_of(f32),
		transmute(rawptr)&vertexs,
		gl.STATIC_DRAW,
	)

	// index buffer: two triangles sharing vertices 1 and 2
	indices := [6]u16 {
		0,
		1,
		2, // triangle 1
		1,
		2,
		3, // triangle 2
	}
	COMPOSITOR.indexBuffer = gl.CreateBuffer()
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, COMPOSITOR.indexBuffer)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(u16),
		transmute(rawptr)&indices,
		gl.STATIC_DRAW,
	)

	// enable and configure all attribute locations
	gl.EnableVertexAttribArray(positionAttributeLocation)
	gl.VertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, false, 0, 0)
}

render_frame :: proc(dt: f32) {
	COMPOSITOR.u_time += dt

	// PASS 1: render each surface framebuffer to its texture
	for surface in COMPOSITOR.surfaces {
		if !surface.dirty do continue
		gl.BindFramebuffer(gl.FRAMEBUFFER, surface.framebuffer)
		gl.Viewport(0, 0, surface.width, surface.height)

		gl.ClearColor(expand_values(colors.Shimmering_Red.rgba))
		gl.Clear(cast(u32)gl.COLOR_BUFFER_BIT)

		if surface.application == nil do continue
		surface.application.render(surface.application, dt)
	}

	// PASS 2: composite all the surfaces in the default canvas framebuffer
	// reset the framebuffer
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.UseProgram(COMPOSITOR.program)
	gl.BindVertexArray(COMPOSITOR.vao)
	canvas_width := gl.DrawingBufferWidth()
	canvas_height := gl.DrawingBufferHeight()
	gl.Viewport(0, 0, canvas_width, canvas_height)

	for surface in COMPOSITOR.surfaces {
		gl.BindTexture(gl.TEXTURE_2D, surface.texture)
		gl.ActiveTexture(gl.TEXTURE0)

		// set uniform transform
		u_transform := gl.GetUniformLocation(COMPOSITOR.program, "u_transform")
		sx := 2 * f32(surface.width) / f32(canvas_width)
		sy := 2 * f32(surface.height) / f32(canvas_height)
		tx := 2 * f32(surface.x) / f32(canvas_width) - 1
		ty := 1 - 2 * f32(surface.y) / f32(canvas_height) - sy
		transform := matrix[4, 4]f32{
			sx, 0, 0, tx,
			0, sy, 0, ty,
			0, 0, 1, 0,
			0, 0, 0, 1,
		}
		gl.UniformMatrix4fv(u_transform, transform)
		gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
	}
}

destroy_compositor :: proc() {
	for surface in COMPOSITOR.surfaces {
		delete_surface(surface)
		free(surface)
	}
	delete(COMPOSITOR.surfaces)

	// clear gpu resources
	gl.DeleteBuffer(COMPOSITOR.vertexBuffer)
	gl.DeleteBuffer(COMPOSITOR.indexBuffer)
	gl.DeleteVertexArray(COMPOSITOR.vao)
	gl.DeleteProgram(COMPOSITOR.program)
}
