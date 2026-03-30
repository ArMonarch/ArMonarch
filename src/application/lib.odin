package application

import gl "vendor:wasm/WebGL"

App_Render_Fn :: #type proc(app: ^Application, dt: f32)
App_Destroy_Fn :: #type proc(app: ^Application)

Application :: struct {
	name:       string,
	// gpu resources
	program:    gl.Program,
	vao:        gl.VertexArrayObject,
	vertex_buf: gl.Buffer,
	index_buf:  gl.Buffer,
	// uniform locations
	u_time:     f32,
	// application lifetime
	render:     App_Render_Fn,
	destroy:    App_Destroy_Fn,
}
