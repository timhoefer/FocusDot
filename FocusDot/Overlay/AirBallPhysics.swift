import Foundation
import CoreGraphics
import QuartzCore

/// 1-DOF lumped air-balloon model.
/// `x > 0` = compression, `x < 0` = stretch, both along the active pull axis.
/// All lengths are in scene points (same units as `dotSize`).
final class AirBallPhysics {

    struct Params {
        var R0: CGFloat       = 20      // rest radius
        var mass: CGFloat     = 1.0
        var gamma: CGFloat    = 1.2     // 1.0 isothermal, 1.4 adiabatic
        var P0: CGFloat       = 1.0     // initial internal pressure (== ambient → ΔP starts at 0)
        var Pamb: CGFloat     = 1.0
        var alpha: CGFloat    = 0.6     // stretch → radial-growth gain
        var beta: CGFloat     = 0.05    // pressure participation under stretch (≪1)
        // shell stiffness — compression is gentle, stretch hardens steeply
        var k1c: CGFloat      = 8       // linear, compression
        var k3c: CGFloat      = 0.02    // cubic,  compression
        var k1s: CGFloat      = 25      // linear, stretch
        var k3s: CGFloat      = 0.6     // cubic,  stretch (dominant)
        var damping: CGFloat  = 6
        // safety
        var vMax: CGFloat     = 4000
        var vEps: CGFloat     = 1e-3
    }

    var p = Params()

    private(set) var x: CGFloat = 0
    private(set) var xdot: CGFloat = 0

    /// External force from the user (drag) projected onto the pull axis.
    var externalForce: CGFloat = 0

    func reset() { x = 0; xdot = 0 }

    /// Inject a velocity change. Negative = stretch impulse, positive = compression impulse.
    func applyImpulse(_ deltaXdot: CGFloat) {
        xdot += deltaXdot
        if xdot >  p.vMax { xdot =  p.vMax }
        if xdot < -p.vMax { xdot = -p.vMax }
    }

    /// Advance one step. `dt` is sub-stepped internally for stability.
    func step(dt: CFTimeInterval) {
        let h = max(1.0 / 240.0, min(dt, 1.0 / 30.0))   // clamp dt
        let sub = 2                                     // 2 sub-steps @60Hz → 120Hz physics
        let dts = CGFloat(h) / CGFloat(sub)
        for _ in 0..<sub { integrate(dts) }
    }

    private func integrate(_ dt: CGFloat) {
        let R0 = p.R0
        let V0 = (4.0 / 3.0) * .pi * R0 * R0 * R0
        let Vmin = 0.05 * V0
        let Vmax = 8.0  * V0

        var V: CGFloat
        var Aeff: CGFloat
        var Fshell: CGFloat

        if x >= 0 {                                     // compression
            let h = min(x, 2 * R0)
            let Vcap = .pi * h * h * (R0 - h / 3)
            V    = max(Vmin, V0 - Vcap)
            Aeff = .pi * max(0, 2 * R0 * h - h * h)
            Fshell = p.k1c * x + p.k3c * x * x * x
        } else {                                        // stretch
            let s = -x / R0
            let g = 1 + p.alpha * s
            V    = min(Vmax, V0 * g * g * g)
            Aeff = p.beta * .pi * R0 * R0
            Fshell = p.k1s * x + p.k3s * x * x * x      // x<0 → negative
        }

        let Pint = p.P0 * pow(V0 / max(V, p.vEps), p.gamma)
        let dP   = Pint - p.Pamb
        let sgn: CGFloat = x >= 0 ? 1 : -1
        let Fpress = sgn * dP * Aeff                    // opposes deformation
        let Fdamp  = -p.damping * xdot

        let F = -(Fpress + Fshell) + Fdamp + externalForce

        xdot += (F / p.mass) * dt
        if xdot >  p.vMax { xdot =  p.vMax }
        if xdot < -p.vMax { xdot = -p.vMax }
        x += xdot * dt

        // hard clamps so we never explode
        let xMaxComp =  1.6 * R0
        let xMaxStr  = -3.0 * R0
        if x > xMaxComp { x = xMaxComp; if xdot > 0 { xdot = 0 } }
        if x < xMaxStr  { x = xMaxStr;  if xdot < 0 { xdot = 0 } }
    }
}
