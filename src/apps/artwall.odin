package application

import "../colors"
import "../compositor"
import "../shaders"
import "core:fmt"
import gl "vendor:wasm/WebGL"

// Artwall Application State Struct
State :: struct {
	animated: bool,
}

// Artwall Application Builder
build_artwall :: proc(surface: ^compositor.Surface) -> (success: bool) {
	// set the surface application value
	if surface.application != nil do return false

	app, err := new(compositor.Application)
	if err != nil do return false

	// initialize artwall application
	program, ok := gl.CreateProgramFromStrings(
		{cast(string)shaders.ArtWall_Vert_Shader},
		{cast(string)shaders.ArtWall_Frag_Shader},
	)
	if ok != true {
		fmt.eprintln("Error: failed to create ArtWall program")
		free(app)
		return
	}

	// select the program to use
	app.program = program
	gl.UseProgram(app.program)

	// get the attribute location
	positionAttributeLocation := gl.GetAttribLocation(program, "a_position")

	// set uniforms for shaders
	u_time := gl.GetUniformLocation(program, "u_time")
	gl.Uniform1f(u_time, app.u_time)
	u_rgba := gl.GetUniformLocation(program, "u_rgba")
	gl.Uniform4f(u_rgba, expand_values(colors.Mystic_Navy.rgba))

	// create and bind VAO first so it captures all buffer bindings
	app.vao = gl.CreateVertexArray()
	gl.BindVertexArray(app.vao)

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
	app.vertex_buf = gl.CreateBuffer()
	gl.BindBuffer(gl.ARRAY_BUFFER, app.vertex_buf)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertexs) * size_of(f32),
		transmute(rawptr)&vertexs,
		gl.STATIC_DRAW,
	)

	// index_buf
	indices := [6]u16{0, 1, 2, 1, 2, 3}
	app.index_buf = gl.CreateBuffer()
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, app.index_buf)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(u16),
		transmute(rawptr)&indices,
		gl.STATIC_DRAW,
	)

	// enable and configure all attribute locations
	gl.EnableVertexAttribArray(positionAttributeLocation)
	gl.VertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, false, 0, 0)

	// set application states and lifetime
	state := new(State)
	state.animated = true
	app.state = state
	app.render = render_artwall
	app.destroy = destroy_artwall

	// set surface.application
	surface.application = app
	return true
}

// Artwall Render Procedure
render_artwall :: proc(app: ^compositor.Application, dt: f32) {
	app.u_time += dt
	// use this application program
	gl.UseProgram(app.program)
	// set uniforms for shaders
	u_time := gl.GetUniformLocation(app.program, "u_time")
	gl.Uniform1f(u_time, app.u_time)

	// bind vao and draw
	gl.BindVertexArray(app.vao)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
}

// Artwall Destroy Procedure
destroy_artwall :: proc(app: ^compositor.Application) {
	if app == nil do return
	// delete buffers
	gl.DeleteBuffer(app.vertex_buf)
	gl.DeleteBuffer(app.index_buf)
	// delete vertex array object
	gl.DeleteVertexArray(app.vao)
	// delete program
	gl.DeleteProgram(app.program)
	if app.state != nil do free(app.state)
	// the surface takes the responsibility for freeing the application
}
