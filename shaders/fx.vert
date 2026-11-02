// AdaFlip: a combat racer in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// Sparks, flames, smoke, shadows: quads already facing the camera
#version 450 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;   // unused
layout(location = 2) in vec3 aColor;
layout(location = 3) in vec3 aMat;      // opacity (0: adds light), u, v

uniform mat4 uViewProj;

out vec3 vColor;
out float vAlpha;
out vec2 vUV;
out vec3 vPos;

void main()
{
    vColor = aColor;
    vAlpha = aMat.x;
    vUV = aMat.yz;
    vPos = aPos;
    gl_Position = uViewProj * vec4(aPos, 1.0);
}
