#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uMix;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  fragColor = vec4(uv.x * uMix, uv.y, 0.5, 1.0);
}
