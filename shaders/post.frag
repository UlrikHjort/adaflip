// AdaFlip: a combat racer in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// The picture to the screen: glow round bright things, tone mapping,
// a darker edge, and a flash when hit
#version 450 core

in vec2 vUV;
uniform sampler2D uScene;
uniform float uFlash;
uniform float uSpeed;     // 0 .. 1, for the blur at the edges
out vec4 fragColor;

vec3 aces(vec3 x)
{
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main()
{
    vec3 c = texture(uScene, vUV).rgb;
    // speed: the edges smear towards the middle
    vec2 dir = vUV - 0.5;
    float edge = smoothstep(0.15, 0.7, length(dir)) * uSpeed;
    if (edge > 0.01) {
        vec3 acc = c;
        for (int i = 1; i <= 6; i++)
            acc += texture(uScene, vUV - dir * edge * 0.025 * float(i)).rgb;
        c = acc / 7.0;
    }
    vec3 glow = vec3(0.0);
    glow += max(textureLod(uScene, vUV, 2.0).rgb - 1.4, 0.0) * 0.35;
    glow += max(textureLod(uScene, vUV, 4.0).rgb - 1.3, 0.0) * 0.4;
    glow += max(textureLod(uScene, vUV, 6.0).rgb - 1.2, 0.0) * 0.5;
    c += glow;
    c = aces(c * 0.8);
    float vig = 1.0 - 0.35 * pow(length(dir) * 1.3, 2.5);
    c *= vig;
    c = mix(c, vec3(1.0, 0.85, 0.6), uFlash);
    fragColor = vec4(pow(c, vec3(1.0 / 2.2)), 1.0);
}
