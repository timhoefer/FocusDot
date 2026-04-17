import SwiftUI
import simd

/// Snapshot of physics state needed to drive the per-pixel ellipsoid shader.
struct BallShadingState: Equatable {
    var pullAxis: CGVector = .init(dx: 1, dy: 0)
    var x: CGFloat = 0          // physics deformation: >0 compression, <0 stretch
    var R0: CGFloat = 20

    static let neutral = BallShadingState()
}

/// Resolved ellipsoid semi-axes + lighting weights for one frame.
struct BallShadingParams {
    var a: Float        // along pull axis
    var b: Float        // perpendicular to pull axis (in screen plane)
    var c: Float        // out-of-screen depth
    var sc: Float       // compression amount, [0, 1]
    var ss: Float       // stretch amount, [0, 1]
    var axis: SIMD2<Float>

    static func resolve(_ s: BallShadingState) -> BallShadingParams {
        let R0 = max(Float(s.R0), 1)
        let xN = Float(s.x) / R0   // normalized deformation

        // Asymmetric semi-axis growth/shrink, clamped so the ellipsoid stays well-conditioned.
        let stretchAmt: Float
        let compressAmt: Float
        let a: Float
        if xN < 0 {                                   // stretch
            stretchAmt  = min(-xN, 1)
            compressAmt = 0
            a = R0 * (1 + 0.5 * min(stretchAmt, 0.6))
        } else if xN > 0 {                            // compression
            stretchAmt  = 0
            compressAmt = min(xN, 1)
            a = R0 * max(0.4, 1 - 0.4 * min(compressAmt, 0.8))
        } else {
            stretchAmt = 0; compressAmt = 0; a = R0
        }
        // Volume-ish preservation in the screen plane: b shrinks/grows opposite to a.
        let b = R0 * sqrt(R0 / a)
        let c = min(a, b)

        // Default axis when undeformed — math is rotation-invariant when a == b, but the
        // shader still needs a finite unit vector.
        var ax = SIMD2<Float>(Float(s.pullAxis.dx), Float(s.pullAxis.dy))
        let len = sqrt(ax.x * ax.x + ax.y * ax.y)
        if len > 1e-4 { ax /= len } else { ax = SIMD2<Float>(1, 0) }

        return BallShadingParams(a: a, b: b, c: c, sc: compressAmt, ss: stretchAmt, axis: ax)
    }
}

@available(macOS 14.0, *)
extension Shader {
    /// Ellipsoid normal-reconstruction shader. `center` is the blob's center in the
    /// view's local coordinate space (points). `light` should be pre-normalized.
    static func ballShade(center: CGPoint,
                          params: BallShadingParams,
                          light: SIMD3<Float>) -> Shader {
        ShaderLibrary.bundle(.main).ballShade(
            .float2(Float(center.x), Float(center.y)),
            .float2(params.axis.x, params.axis.y),
            .float(params.a),
            .float(params.b),
            .float(params.c),
            .float(params.sc),
            .float(params.ss),
            .float3(light.x, light.y, light.z)
        )
    }
}
