#version 300 es

in vec2 a_position;
out vec2 v_texcoord;
uniform mat4 u_transform;

void main() {
  gl_Position = u_transform * vec4(a_position, 0., 1.);
}
