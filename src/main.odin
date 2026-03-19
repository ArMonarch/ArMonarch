package ArMonarch

import "core:fmt"
import gl "vendor:wasm/WebGL"

import "shaders"

foreign import lib "functions"
foreign lib {
	get_platform_name :: proc "contextless" () ---
	update_fps_counter :: proc "contextless" (fps: u32) ---
}

vert_shader_src := string(shaders.TRAINGLE_VERT_SHADER)
frag_shader_src := string(shaders.TRAINGLE_FRAG_SHADER)

// WebGL Context used through out the program
Context :: struct {
	id:       string,
	acc_time: f32,
	fps:      u32,
}
ctx: Context

main :: proc() {
	ctx.id = "canvas"
	gl_context_attribute: gl.ContextAttributes = {gl.ContextAttribute.disablePremultipliedAlpha}
	gl.CreateCurrentContextById(ctx.id, gl_context_attribute)

	major, minor: i32
	gl.GetWebGLVersion(&major, &minor)
	fmt.printfln("Initialized With WebGl Version: v%d.%d", major, minor)

	gl.Viewport(0, 0, gl.DrawingBufferWidth(), gl.DrawingBufferHeight())
	gl.ClearColor(0.5, 0.7, 1.0, 1.0)
	gl.Clear(transmute(u32)(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT))

}

@(export)
update :: proc(dt: f32) -> (keep_going: bool) {
	// update the fps counter
	ctx.acc_time += dt
	ctx.fps += 1
	if ctx.acc_time > 1 {
		update_fps_counter(ctx.fps)
		ctx.acc_time = 0.0
		ctx.fps = 0
	}

	// match the canvas width and height to clientWidth and clientHeight
	gl.Viewport(0, 0, gl.DrawingBufferWidth(), gl.DrawingBufferHeight())
	gl.ClearColor(0.5, 0.7, 1.0, 1.0)
	gl.Clear(transmute(u32)(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT))

	draw_rectangle(dt)

	return true
}

draw_rectangle :: proc(dt: f32) {
	program, ok := gl.CreateProgramFromStrings(
		[]string{vert_shader_src},
		[]string{frag_shader_src},
	)
	defer gl.DeleteProgram(program)
	gl.UseProgram(program)

	if ok != true {
		fmt.println("Failed to create program")
	}

	positionAttributeLocation := gl.GetAttribLocation(program, "a_position")
	positionBuffer := gl.CreateBuffer()
	defer gl.DeleteBuffer(positionBuffer)

	gl.BindBuffer(gl.ARRAY_BUFFER, positionBuffer)
	positions := [?]f32{-0.8, 0.8, -0.8, -0.8, 0.8, 0.8, 0.8, 0.8, 0.8, -0.8, -0.8, -0.8}
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(positions) * size_of(f32),
		transmute(rawptr)&positions,
		gl.STATIC_DRAW,
	)

	vao := gl.CreateVertexArray()
	defer gl.DeleteVertexArray(vao)


	colors := gl.GetUniformLocation(program, "colors")
	gl.Uniform4f(colors, 30, 80, 133, 1)

	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(positionAttributeLocation)
	gl.VertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, false, 0, 0)
	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}
