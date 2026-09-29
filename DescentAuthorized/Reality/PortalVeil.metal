#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

static float veilHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}
static float veilNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(veilHash(i), veilHash(i + float2(1, 0)), u.x),
               mix(veilHash(i + float2(0, 1)), veilHash(i + 1.0), u.x), u.y);
}
static float veilMist(float2 p) {
    float result = 0.0, weight = 0.5;
    for (int i = 0; i < 4; ++i) {
        result += weight * veilNoise(p);
        p = float2(1.6*p.x - 1.2*p.y, 1.2*p.x + 1.6*p.y) + 9.1;
        weight *= 0.5;
    }
    return result;
}

[[visible]] void descentVeil(realitykit::surface_parameters params) {
    // Zero speed is a stable still frame for Reduce Motion.
    float time = params.uniforms().time() * params.uniforms().custom_parameter().x * 0.12;
    float2 uv = params.geometry().uv0();
    float2 p = (uv - 0.5) * float2(2.0, 2.8);
    float2 warp = float2(veilMist(p*1.6 + float2(time, -time*.4)),
                         veilMist(p*1.8 + float2(-time*.35, time*.6)));
    float cloud = veilMist(p*2.2 + warp*2.4 + float2(0, -time));
    float ribbon = pow(1.0 - abs(sin(p.y*4.0 + warp.x*5.0 + time)), 5.0);
    float depth = exp(-dot(p*float2(1.0,.65), p*float2(1.0,.65))*1.1);
    float edge = smoothstep(0.0, .14, min(min(uv.x, 1.0-uv.x), min(uv.y, 1.0-uv.y)));
    float3 charcoal = float3(.009, .012, .018);
    float3 indigo = float3(.105, .080, .155);
    float3 patina = float3(.095, .175, .170);
    float3 color = charcoal + mix(indigo, patina, cloud) * (cloud*.9 + ribbon*.20) * depth * edge;
    // A restrained antique-gold glint, never a rainbow/starfield.
    color += float3(.18,.125,.055) * pow(cloud, 7.0) * depth * edge;
    params.surface().set_emissive_color(half3(color));
}
