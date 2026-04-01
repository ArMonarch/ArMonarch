#version 300 es

in vec2 a_position;
out vec2 v_uv;

void main() {
  v_uv = a_position;
  vec2 positions = a_position * 2.0 - 1.0;
  gl_Position = vec4(positions, 0.0, 1.0);
}
