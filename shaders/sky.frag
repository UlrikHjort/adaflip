// AdaFlip: a combat racer in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// The sky: a gradient, the sun, clouds by day and stars by night
#version 450 core

in vec2 vNdc;
uniform mat4 uInvViewProj;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform float uNight;
uniform float uTime;
out vec4 fragColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void main()
{
    vec4 a = uInvViewProj * vec4(vNdc, -1.0, 1.0);
    vec4 b = uInvViewProj * vec4(vNdc, 1.0, 1.0);
    vec3 d = normalize(b.xyz / b.w - a.xyz / a.w);
    float h = clamp(d.y, -1.0, 1.0);
    vec3 col = mix(uHorizon, uZenith, pow(clamp(h, 0.0, 1.0), 0.55));
    if (h < 0.0) col = uHorizon * 0.8;
    float s = max(dot(d, uSunDir), 0.0);
    col += uSunCol * (pow(s, 900.0) * 6.0 + pow(s, 12.0) * 0.12);
    if (h > 0.0) {
        vec2 p = d.xz / (d.y + 0.15) * 2.0 + vec2(uTime * 0.01, 0.0);
        float c = noise(p) * 0.6 + noise(p * 2.7) * 0.3 + noise(p * 6.1) * 0.1;
        c = smoothstep(0.55, 0.85, c) * (1.0 - uNight * 0.7);
        col = mix(col, mix(uHorizon * 1.2, vec3(1.0), 0.5) * (1.0 - 0.8 * uNight), c * 0.7 * smoothstep(0.0, 0.2, h));
        // stars
        vec2 sp = floor(d.xz / (d.y + 1.0) * 400.0);
        float st = step(0.997, hash(sp)) * uNight * smoothstep(0.05, 0.3, h);
        col += vec3(st) * 1.5;
    }
    fragColor = vec4(col, 1.0);
}
