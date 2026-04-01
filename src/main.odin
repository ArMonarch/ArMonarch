package ArMonarch

import "apps"
import "base:runtime"
import "compositor"
import "core:fmt"
import gl "vendor:wasm/WebGL"

foreign import lib "functions"
foreign lib {
	get_platform_name :: proc "contextless" () ---
	update_fps_counter :: proc "contextless" (fps: u32) ---
}

// WebGL Context used through out the program
Context :: struct {
	id:         string,
	acc_time:   f32,
	total_time: f32,
	fps:        u32,
}
ctx: Context

main :: proc() {
	ctx.id = "canvas"

	gl_context_attribute: gl.ContextAttributes = {.disablePremultipliedAlpha}
	gl.CreateCurrentContextById(ctx.id, gl_context_attribute)

	major, minor: i32
	gl.GetWebGLVersion(&major, &minor)
	fmt.printfln("Initialized With WebGl Version: v%d.%d", major, minor)

	canvas_width, canvas_height := gl.DrawingBufferWidth(), gl.DrawingBufferHeight()
	gl.Viewport(0, 0, canvas_width, canvas_height)

	// initialize the compositor
	compositor.build_compositor()

	// initialize artwall
	surface, success := compositor.create_surface(0, 0, canvas_width, canvas_height, .Background)
	if success := apps.build_artwall(surface); success != true {
		fmt.eprintfln("Error: failed to build ArtWall application")
	}
}

@(export)
update :: proc(dt: f32) -> (keep_going: bool = false) {
	// update the fps counter
	ctx.acc_time += dt
	ctx.fps += 1
	if ctx.acc_time >= 1 {
		update_fps_counter(ctx.fps)
		ctx.acc_time = 0.0
		ctx.fps = 0
	}
	ctx.total_time += dt

	compositor.render_frame(dt)
	return true
}

@(export, fini)
finish :: proc "contextless" () {
	context = runtime.default_context()
	compositor.destroy_compositor()
}
