// AdaFlip: a combat racer in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// Every surface of the world, painted by its material number
#version 450 core

in vec3 vPos;
in vec3 vNormal;
in vec3 vColor;
flat in float vMat;
in vec2 vUV;
in vec3 vLocal;

uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
uniform vec3 uSkyAmb;
uniform vec3 uGroundAmb;
uniform vec3 uFogCol;
uniform float uFogDensity;
uniform vec3 uTint;        // the car's paint, or a glow's strength
uniform vec3 uRoadCol;
uniform vec3 uStripe;      // the lit lines of this track
uniform vec3 uGround1;
uniform vec3 uGround2;
uniform float uNight;      // 0 day .. 1 night
uniform float uTime;

out vec4 fragColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
    return s;
}

void main()
{
    vec3 n = normalize(vNormal);
    if (!gl_FrontFacing) n = -n;
    vec3 v = normalize(uCamPos - vPos);
    float m = vMat;
    bool indoor = m >= 99.5;
    if (indoor) m -= 100.0;
    int mat = int(m + 0.5);

    vec3 albedo = vColor;
    vec3 emit = vec3(0.0);
    float spec = 0.08;
    float rough = 24.0;

    if (mat == 1) {                       // the road
        float half_w = vColor.r;
        float g = fbm(vUV * vec2(1.3, 1.3));
        albedo = uRoadCol * (0.8 + 0.4 * g);
        float a = abs(vUV.y);
        // edge lines, and dashes down the middle
        if (abs(a - (half_w - 0.6)) < 0.18) albedo = vec3(0.75, 0.72, 0.6);
        if (a < 0.14 && fract(vUV.x / 9.0) < 0.5) albedo = vec3(0.8, 0.7, 0.2);
        // a lit line along the edges at night
        if (abs(a - (half_w - 0.15)) < 0.08) emit = uStripe * 0.6;
        spec = 0.12; rough = 40.0;
    } else if (mat == 2) {                // wall panels
        vec2 cell = floor(vec2(vUV.x / 4.0, vUV.y / 2.5));
        vec2 f = fract(vec2(vUV.x / 4.0, vUV.y / 2.5));
        float h = hash(cell);
        albedo = vColor * (0.82 + 0.25 * h);
        float seam = min(min(f.x, 1.0 - f.x) * 4.0, min(f.y, 1.0 - f.y) * 2.5);
        albedo *= mix(0.55, 1.0, smoothstep(0.0, 0.06, seam));
        spec = 0.15; rough = 30.0;
    } else if (mat == 3) {                // lit by itself
        emit = vColor * uTint;
        albedo = vec3(0.0);
    } else if (mat == 4) {                // the ground
        float g = fbm(vPos.xz * 0.02) * 0.7 + fbm(vPos.xz * 0.25) * 0.3;
        albedo = mix(uGround1, uGround2, smoothstep(0.3, 0.7, g));
        albedo *= 0.85 + 0.3 * noise(vPos.xz * 1.7);
    } else if (mat == 5) {                // buildings: windows
        vec2 c = floor(vec2(vUV.x / 3.0, vUV.y / 3.5));
        vec2 f = fract(vec2(vUV.x / 3.0, vUV.y / 3.5));
        bool win = f.x > 0.18 && f.x < 0.82 && f.y > 0.25 && f.y < 0.8;
        albedo = vColor;
        if (win) {
            float lit = step(0.55, hash(c + vColor.rg * 17.0));
            albedo = vec3(0.05, 0.07, 0.1);
            spec = 0.6; rough = 80.0;
            emit = lit * uNight * vec3(1.6, 1.25, 0.8) * (0.5 + hash(c * 1.3));
        }
    } else if (mat == 6) {                // concrete
        albedo = vColor * (0.8 + 0.35 * fbm(vec2(vUV.x, vUV.y) * 0.8));
    } else if (mat == 7) {                // tyres
        float t = fract(vUV.x * 3.8197);
        albedo = vec3(0.035) * (t < 0.5 ? 1.0 : 1.7);
        spec = 0.03;
    } else if (mat == 8) {                // paint
        albedo = vColor * uTint;
        spec = 0.5; rough = 90.0;
    } else if (mat == 9) {                // arrows round a bend
        float s = fract(vUV.x * 3.0 + abs(vUV.y - 0.5) * vColor.r);
        float on = step(0.5, s);
        emit = mix(vec3(0.05), uStripe * 2.5, on);
        albedo = vec3(0.02);
    } else if (mat == 11) {               // rock
        float strata = sin(vPos.y * 0.9 + fbm(vPos.xz * 0.05) * 6.0) * 0.5 + 0.5;
        albedo = vColor * (0.7 + 0.35 * strata) * (0.85 + 0.3 * noise(vPos.xz * 0.3 + vPos.y));
    } else if (mat == 12) {               // checks
        vec2 c = floor(vUV);
        albedo = mod(c.x + c.y, 2.0) < 0.5 ? vec3(0.9) : vec3(0.03);
    } else if (mat == 13) {               // metal
        spec = 0.6; rough = 60.0;
    } else if (mat == 14) {               // glass
        albedo = vec3(0.02, 0.03, 0.05);
        spec = 1.0; rough = 120.0;
    }

    // Light: the sun (not under a roof), the sky and the ground's bounce
    float sun = indoor ? 0.0 : max(dot(n, uSunDir), 0.0);
    vec3 amb = mix(uGroundAmb, uSkyAmb, n.y * 0.5 + 0.5) * (indoor ? 0.45 : 1.0);
    if (indoor) amb += uStripe * 0.12;
    vec3 h = normalize(uSunDir + v);
    float sp = indoor ? 0.0 : pow(max(dot(n, h), 0.0), rough) * spec * (rough + 8.0) / 8.0;
    float fres = pow(1.0 - max(dot(n, v), 0.0), 5.0);
    vec3 col = albedo * (uSunCol * sun + amb) + uSunCol * sp * sun
             + (spec > 0.3 ? fres * spec * mix(uGroundAmb, uSkyAmb, 0.8) * 1.5 : vec3(0.0))
             + emit;

    // Fog, the further the thicker
    float d = length(vPos - uCamPos);
    float fog = 1.0 - exp(-d * uFogDensity);
    col = mix(col, uFogCol, clamp(fog, 0.0, 1.0));
    fragColor = vec4(col, 1.0);
}
