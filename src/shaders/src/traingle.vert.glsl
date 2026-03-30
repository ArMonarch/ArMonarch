#version 300 es
 
// an attribute is an input (in) to a vertex shader.
// It will receive data from a buffer
in vec2 a_position;
 
// all shaders have a main function
void main() {
  // gl_Position is a special variable a vertex shader
  // is responsible for setting
  vec2 positions = a_position * 2.0 - 1.0;
  gl_Position = vec4(positions, 0.0, 1.0);
}
