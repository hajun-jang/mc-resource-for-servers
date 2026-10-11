#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:matrix.glsl>
#include <minecraft:oit.glsl>

uniform sampler2D Sampler0;

#ifdef GLINT
uniform sampler2D GlintSampler;
#endif

#ifndef OIT_ALPHA_ONLY
layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
#endif
layout(location = 2) in vec4 vertexColor;
#ifndef OIT_ALPHA_ONLY
layout(location = 3) in vec4 lightMapColor;
layout(location = 4) in vec4 overlayColor;
#endif
layout(location = 5) in vec2 texCoord0;
#ifdef GLINT
layout(location = 6) in vec2 texCoordGlint;
#endif

layout(location = 8) in vec4 texProj0;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

const vec3[] COLORS = vec3[](
    vec3(0.022087, 0.098399, 0.110818),
    vec3(0.011892, 0.095924, 0.089485),
    vec3(0.027636, 0.101689, 0.100326),
    vec3(0.046564, 0.109883, 0.114838),
    vec3(0.064901, 0.117696, 0.097189),
    vec3(0.063761, 0.086895, 0.123646),
    vec3(0.084817, 0.111994, 0.166380),
    vec3(0.097489, 0.154120, 0.091064),
    vec3(0.106152, 0.131144, 0.195191),
    vec3(0.097721, 0.110188, 0.187229),
    vec3(0.133516, 0.138278, 0.148582),
    vec3(0.070006, 0.243332, 0.235792),
    vec3(0.196766, 0.142899, 0.214696),
    vec3(0.047281, 0.315338, 0.321970),
    vec3(0.204675, 0.390010, 0.302066),
    vec3(0.080955, 0.314821, 0.661491)
);

const mat4 SCALE_TRANSLATE = mat4(
    0.5, 0.0, 0.0, 0.25,
    0.0, 0.5, 0.0, 0.25,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0
);

mat4 end_portal_layer(float layer) {
    mat4 translate = mat4(
        1.0, 0.0, 0.0, 17.0 / layer,
        0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (GameTime * 1.5),
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    );

    mat2 rotate = mat2_rotate_z(radians((layer * layer * 4321.0 + layer * 9.0) * 2.0));
    mat2 scale = mat2((4.5 - layer / 4.0) * 2.0);

    return mat4(scale * rotate) * translate * SCALE_TRANSLATE;
}

vec3 getPortalTexture(vec2 uv) {
    vec2 puv1 = floor(uv * (ScreenSize / 8.0)); 
    float h1 = fract(sin(dot(puv1, vec2(12.9898, 78.233))) * 43758.5453);
    float val1 = pow(h1, 110.0) * 2.0;

    vec2 puv2 = floor(uv * (ScreenSize / 14.0)); 
    float h2 = fract(sin(dot(puv2, vec2(39.346, 11.135))) * 43758.5453);
    float val2 = pow(h2, 200.0) * 3.0;

    vec2 puv3 = floor(uv * (ScreenSize / 20.0)); 
    float h3 = fract(sin(dot(puv3, vec2(73.156, 52.235))) * 43758.5453);
    float val3 = pow(h3, 450.0) * 4.0;

    return vec3(clamp(val1 + val2 + val3, 0.0, 1.0));
}

#ifndef OIT_ALPHA_ONLY
vec4 calculateFinalColor(vec4 color, bool isCosmic) {
    color.rgb = mix(overlayColor.rgb, color.rgb, overlayColor.a);
    if (!isCosmic) {
        color *= lightMapColor;
    }

    #ifdef GLINT
    vec4 glintColor = GlintAlpha * texture(GlintSampler, texCoordGlint);
    // Matches BlendFuntion.GLINT
    color.rgb += glintColor.rgb * glintColor.rgb;
    #endif

    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif

    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}
#endif

void main() {
    vec4 texColor = texture(Sampler0, texCoord0);
    vec4 color = texColor;
    #ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
    #endif

    ivec3 pixelRGB = ivec3(round(texColor.rgb * 255.0));
    ivec3 finalRGB = ivec3(round((texColor * vertexColor * ColorModulator).rgb * 255.0));

    bool matchPixel = abs(pixelRGB.r - 123) <= 3 && abs(pixelRGB.g - 45) <= 3 && abs(pixelRGB.b - 67) <= 3;
    bool matchFinal = abs(finalRGB.r - 123) <= 3 && abs(finalRGB.g - 45) <= 3 && abs(finalRGB.b - 67) <= 3;
    bool isCosmic = matchPixel || matchFinal;

    if (isCosmic) {
        vec3 cosmicColor = vec3(0.05) * COLORS[0];
        for (int i = 0; i < 15; i++) {
            vec4 tProj = texProj0 * end_portal_layer(float(i + 1));
            vec2 uv = tProj.xy / tProj.w;
            cosmicColor += getPortalTexture(uv) * COLORS[i + 1];
        }
        color = vec4(cosmicColor, 1.0);
    } else {
        color *= vertexColor * ColorModulator;
    }

    #ifdef GLINT
    color.a = max(color.a, GlintAlpha);
    #endif

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color, isCosmic);
    #endif
}
