import SwiftUI

/// A rubber ball that deforms into a barbell/gourd when pulled.
/// `grabWidth` controls how wide the pulled area is (0 = edge pinch, 1 = wide chunk).
struct BlobShape: Shape {
    var pull: CGSize
    var grabWidth: CGFloat = 0.5

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.width, pull.height) }
        set { pull = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2

        let pullMag = sqrt(pull.width * pull.width + pull.height * pull.height)
        let pullAngle: CGFloat = pullMag > 0.1 ? atan2(pull.height, pull.width) : 0
        let cosP = cos(pullAngle)
        let sinP = sin(pullAngle)
        let stretch = pullMag / r
        let t = min(stretch / 1.2, 1.0)

        func tw(_ ax: CGFloat, _ perp: CGFloat) -> CGPoint {
            CGPoint(x: cx + ax * cosP - perp * sinP,
                    y: cy + ax * sinP + perp * cosP)
        }

        let k: CGFloat = 0.5522847498
        let gw = grabWidth  // 0 = thin edge grab, 1 = wide center grab

        let bodyR = r * (1.0 - t * 0.12)
        // Tip tracks cursor closely — starts at ~90% of pull distance, tapers to ~70% at high stretch
        let tipExtend = pullMag * (0.9 - t * 0.2)
        let frontX = bodyR + tipExtend

        // CP1: at bodyR height (no ledge), forward position
        let cp1Ax = bodyR * k + t * (frontX * 0.55 - bodyR * k)
        let cp1Perp = bodyR

        // Front ball width scales with grabWidth:
        // Edge grab (gw≈0.15): thin front, narrow handles → pinched pull
        // Center grab (gw≈0.9): wide front, big handles → chunky pull
        let frontBallTarget = bodyR * (0.3 + gw * 0.9)  // 0.3r to 1.2r based on grab
        let frontBallW = bodyR * k + t * (frontBallTarget - bodyR * k)

        // 4 anchors
        let back  = tw(-bodyR, 0)
        let bot   = tw(0, -bodyR)
        let front = tw(frontX, 0)
        let top   = tw(0, bodyR)

        var path = Path()
        path.move(to: top)

        // 1: top → back
        path.addCurve(to: back,
                       control1: tw(-bodyR * k, bodyR),
                       control2: tw(-bodyR, bodyR * k))

        // 2: back → bottom
        path.addCurve(to: bot,
                       control1: tw(-bodyR, -bodyR * k),
                       control2: tw(-bodyR * k, -bodyR))

        // 3: bottom → front
        path.addCurve(to: front,
                       control1: tw(cp1Ax, -cp1Perp),
                       control2: tw(frontX, -frontBallW))

        // 4: front → top
        path.addCurve(to: top,
                       control1: tw(frontX, frontBallW),
                       control2: tw(cp1Ax, cp1Perp))

        path.closeSubpath()
        return path
    }
}
