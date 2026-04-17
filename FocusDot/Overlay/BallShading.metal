#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Ellipsoid normal-reconstruction shader for a 2D blob.
// Driven by physics state: pull axis (unit vector), semi-axes a/b/c,
// compression amount sc ∈ [0,1], stretch amount ss ∈ [0,1], and a fixed
// screen-space light direction.
[[ stitchable ]] half4 ballShade(
    float2 pos,         // pixel position in view-local coords
    half4  base,        // current pixel color (the filled blob color)
    float2 center,
    float2 axis,        // unit vector aligned with the pull direction
    float  a,
    float  b,
    float  c,
    float  sc,
    float  ss,
    float3 light)       // expected pre-normalized
{
    // Position in ellipsoid-local frame (rotated so x is along pull axis).
    float2 p = pos - center;
    float xL =  p.x * axis.x + p.y * axis.y;
    float yL = -p.x * axis.y + p.y * axis.x;

    float nx = xL / a;
    float ny = yL / b;
    float r2 = nx * nx + ny * ny;
    if (r2 >= 1.0) return base;

    float nz_l = sqrt(1.0 - r2);

    // Ellipsoid normal: gradient of (x/a)^2 + (y/b)^2 + (z/c)^2 - 1.
    float3 N_l = float3(xL / (a * a), yL / (b * b), nz_l / c);
    N_l = normalize(N_l);

    // Rotate normal back to screen space.
    float3 N = float3(
        N_l.x * axis.x - N_l.y * axis.y,
        N_l.x * axis.y + N_l.y * axis.x,
        N_l.z
    );

    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(light + V);

    float diff = max(0.0, dot(N, light));
    float shin = 28.0 + 30.0 * ss;                      // sharper highlight under stretch
    float spec = pow(max(0.0, dot(N, H)), shin);

    float ks      = 0.45 * (1.0 + 0.3 * ss) * max(0.5, 1.0 - 0.6 * sc);
    float kd      = 0.75;
    float ambient = 0.30;

    half3 lit = half3(base.rgb) * half(ambient + kd * diff)
              + half3(ks * spec);

    // Soft silhouette — fade out the last ~18% of nz_l to kill the hard ellipse edge.
    float rim = smoothstep(0.0, 0.18, nz_l);

    // Compression contact darkening: small AO disk on the +axis pole.
    if (sc > 0.001) {
        float2 cP = float2(a * sc * axis.x, a * sc * axis.y);
        float d   = length(p - cP) / (0.4 * a);
        float ao  = 1.0 - 0.25 * sc * exp(-d * d);
        lit *= half(ao);
    }

    lit *= half(rim);
    return half4(lit, base.a * half(rim));
}
