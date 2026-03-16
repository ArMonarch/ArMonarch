package ArMonarch

import "core:fmt"
import gl "vendor:wasm/WebGL"

foreign import lib "functions"
foreign lib {
	get_platform_name :: proc "contextless" () ---
	update_fps_counter :: proc "contextless" (fps: u32) ---
}

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
	gl.ClearColor(0.5, 0.7, 1.0, 0.9)
	gl.Clear(transmute(u32)gl.COLOR_BUFFER_BIT)
}

@(export)
update :: proc(dt: f32) -> (keep_going: bool) {
	ctx.acc_time += dt
	ctx.fps += 1
	if ctx.acc_time > 1 {
		update_fps_counter(ctx.fps)
		ctx.acc_time = 0.0
		ctx.fps = 0
	}
	return true
}
