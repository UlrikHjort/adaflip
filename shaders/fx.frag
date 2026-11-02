// AdaFlip: a combat racer in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// Premultiplied: opacity 0 adds light (fire), more covers what is behind (smoke)
#version 450 core

in vec3 vColor;
in float vAlpha;
in vec2 vUV;
in vec3 vPos;
uniform vec3 uCamPos;
uniform vec3 uFogCol;
uniform float uFogDensity;
out vec4 fragColor;

void main()
{
    float r = length(vUV * 2.0 - 1.0);
    float a = smoothstep(1.0, 0.0, r);
    float fog = exp(-length(vPos - uCamPos) * uFogDensity);
    if (vAlpha <= 0.001) {
        fragColor = vec4(vColor * a * a * fog, 0.0);
    } else {
        float cover = vAlpha * a;
        fragColor = vec4(mix(uFogCol, vColor, fog) * cover, cover);
    }
}
