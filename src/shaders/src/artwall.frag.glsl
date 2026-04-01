#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 color;
uniform float u_time;
uniform vec4 u_rgba;

void main() {
  vec2 uv = v_uv;
  float t = u_time * 0.4;

  // layered sine distortion field
  float d = 0.0;
  d += sin(uv.x * 6.0 + t * 1.3) * 0.5;
  d += sin(uv.y * 8.0 - t * 0.9) * 0.4;
  d += sin((uv.x + uv.y) * 5.0 + t * 0.7) * 0.3;
  d += sin(length(uv - 0.5) * 12.0 - t * 1.6) * 0.5;

  // color channels driven by distortion with phase offsets
  float r = sin(d * 3.0 + t * 0.3) * 0.5 + 0.5;
  float g = sin(d * 3.0 + t * 0.5 + 2.1) * 0.5 + 0.5;
  float b = sin(d * 3.0 + t * 0.7 + 4.2) * 0.5 + 0.5;

  // tint toward u_rgba
  vec3 base = vec3(r, g, b);
  vec3 tinted = mix(base, u_rgba.rgb, 0.35);

  // vignette
  float vig = 1.0 - smoothstep(0.3, 0.9, length(uv - 0.5));
  tinted *= 0.7 + 0.3 * vig;

  color = vec4(tinted, u_rgba.a);
}
