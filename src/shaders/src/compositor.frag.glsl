#version 300 es
precision highp float;

in vec2 v_texcoord;
out vec4 out_color;
uniform float u_time;
uniform sampler2D u_texture;

void main() {
  out_color = texture(u_texture, v_texcoord);
}
