package compositor

import "core:fmt"
import gl "vendor:wasm/WebGL"

Surface_Id :: distinct u32

Layer_Kind :: enum u8 {
	Background,
	Bottom,
	Window,
	Top,
	Overlay,
}

Surface :: struct {
	// general
	id:            Surface_Id,
	x, y:          i32,
	width, height: i32,
	layer:         Layer_Kind,
	dirty:         bool,
	// WebGL related
	framebuffer:   gl.Framebuffer,
	texture:       gl.Texture,
	// application
	application:   ^Application,
}

create_surface :: proc(
	x: i32 = 0,
	y: i32 = 0,
	width: i32 = 100,
	height: i32 = 100,
	layer: Layer_Kind = .Window,
) -> (
	surface: ^Surface,
	success: bool,
) {
	if len(COMPOSITOR.surfaces) >= 4 {
		fmt.eprintln("Error: surfaces limit reached")
		return nil, false
	}
	surface = new(Surface)
	__create_surface__(surface, x, y, width, height, layer)
	append(&COMPOSITOR.surfaces, surface)
	return surface, true
}

__create_surface__ :: proc(surface: ^Surface, x, y: i32, width, height: i32, layer: Layer_Kind) {
	surface.x = x
	surface.y = y
	surface.width = width
	surface.height = height
	surface.layer = layer
	surface.dirty = true

	// create texture
	surface.texture = gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, surface.texture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, 0, nil)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, cast(i32)gl.LINEAR)
	// gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, cast(i32)gl.LINEAR)
	// gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, cast(i32)gl.CLAMP_TO_EDGE)
	// gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, cast(i32)gl.CLAMP_TO_EDGE)

	// create frameBuffer
	surface.framebuffer = gl.CreateFramebuffer()
	gl.BindFramebuffer(gl.FRAMEBUFFER, surface.framebuffer)
	gl.FramebufferTexture2D(
		gl.FRAMEBUFFER,
		gl.COLOR_ATTACHMENT0,
		gl.TEXTURE_2D,
		surface.texture,
		0,
	)

	// unbind
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

delete_surface :: proc(surface: ^Surface) {
	// clear texture and framebuffer
	gl.DeleteTexture(surface.texture)
	gl.DeleteFramebuffer(surface.framebuffer)

	// clear the application
	if surface.application != nil {
		application := surface.application
		application.destroy(application)
		free(application)
	}
}
