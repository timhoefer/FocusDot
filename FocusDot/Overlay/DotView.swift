import SwiftUI

private func makeNoiseImage(size: Int = 64) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
        let noise = UInt8.random(in: 0...255)
        pixels[i * 4] = noise; pixels[i * 4 + 1] = noise; pixels[i * 4 + 2] = noise; pixels[i * 4 + 3] = 255
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let img = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    return img
}
private let noiseImage: CGImage? = makeNoiseImage()

struct DotView: View {
    @ObservedObject var preferences: PreferencesManager
    @ObservedObject var animator: BounceAnimator
    @ObservedObject var interaction: InteractionManager

    var body: some View {
        let interactionPull = interaction.deformation.pull
        let activePull: CGSize = interaction.deformation.isGrabbed || interaction.deformation.jigglePhase > 0
            ? interactionPull
            : CGSize(
                width: animator.pull.width + interactionPull.width,
                height: animator.pull.height + interactionPull.height
            )

        let baseColor = preferences.dotColor.color
        let dotSize = preferences.dotSize
        let blob = BlobShape(pull: activePull, grabWidth: interaction.deformation.grabWidth)

        let pullMag = sqrt(activePull.width * activePull.width + activePull.height * activePull.height)

        // Fixed light source — highlight always at top-left of the dot frame
        let lightX: CGFloat = 0.35
        let lightY: CGFloat = 0.3

        ZStack {
            blob.fill(baseColor)

            // 3D lighting — shifts with deformation toward the light-facing side
            blob.fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.3),
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.06), location: 0.85),
                        .init(color: .black.opacity(0.12), location: 1.0),
                    ]),
                    center: UnitPoint(x: lightX, y: lightY),
                    startRadius: 0,
                    endRadius: dotSize * 0.55
                )
            )

            // Specular highlight — follows the light center
            blob.fill(
                RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.3), .white.opacity(0.0)]),
                    center: UnitPoint(x: lightX + 0.02, y: lightY + 0.02),
                    startRadius: 0,
                    endRadius: dotSize * 0.13
                )
            )


            // Depression effect — lighting depends on where on the ball you press.
            // Concavity inverts the surface normal: bright areas darken, dark areas lighten.
            if let pressPoint = interaction.deformation.pressPoint, interaction.deformation.pressDepth > 0 {
                let depth = interaction.deformation.pressDepth
                let pr = interaction.deformation.pressRadius
                let pressRadius = dotSize * pr
                let shift = pr * 0.35

                // How lit is this area? 0 = dark (bottom-right), 1 = bright (top-left)
                // Light is at (0.35, 0.3) in unit coords
                let dx = pressPoint.x - 0.35
                let dy = pressPoint.y - 0.3
                let distFromLight = sqrt(dx * dx + dy * dy)
                let brightness = max(0, 1.0 - distFromLight * 1.8)  // 1 at light, 0 far away

                // Shadow/highlight direction always follows light vector from press point
                let lightDirX: CGFloat = pressPoint.x - 0.35
                let lightDirY: CGFloat = pressPoint.y - 0.3
                let lightDist = max(sqrt(lightDirX * lightDirX + lightDirY * lightDirY), 0.01)
                let normX = lightDirX / lightDist
                let normY = lightDirY / lightDist

                // Bright areas: light fills the bowl — strong highlight, minimal shadow
                // Dark areas: bowl is in shadow — strong shadow, faint highlight on far wall
                let shadowStrength = 0.25 - brightness * 0.23
                let highlightStrength = 0.06 + brightness * 0.30

                // Shadow — on the side facing the light (rim blocks light from reaching inner wall)
                blob.fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black.opacity(shadowStrength * depth), location: 0.0),
                            .init(color: .black.opacity(shadowStrength * 0.3 * depth), location: 0.55),
                            .init(color: .clear, location: 0.85),
                        ]),
                        center: UnitPoint(
                            x: pressPoint.x - normX * shift,
                            y: pressPoint.y - normY * shift
                        ),
                        startRadius: 0,
                        endRadius: pressRadius
                    )
                )

                // Highlight — on the far side (inner wall faces the light)
                blob.fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(highlightStrength * depth), location: 0.0),
                            .init(color: .white.opacity(highlightStrength * 0.3 * depth), location: 0.55),
                            .init(color: .clear, location: 0.85),
                        ]),
                        center: UnitPoint(
                            x: pressPoint.x + normX * shift,
                            y: pressPoint.y + normY * shift
                        ),
                        startRadius: 0,
                        endRadius: pressRadius
                    )
                )

            }

            // Grain texture
            if let noise = noiseImage {
                blob.fill(ImagePaint(image: Image(decorative: noise, scale: 2)))
                    .blendMode(.overlay)
                    .opacity(0.08)
            }

            // Material translucency — thin regions carve alpha so the background subtly shows through.
            if pullMag > 0.5 {
                let pullIntensity = min(pullMag / 14.0, 1.0)
                let dirX = activePull.width / pullMag
                let dirY = activePull.height / pullMag
                let tipOffset: CGFloat = 0.38 * pullIntensity
                blob.fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black.opacity(0.35 * pullIntensity), location: 0.0),
                            .init(color: .black.opacity(0.12 * pullIntensity), location: 0.5),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: UnitPoint(x: 0.5 + dirX * tipOffset, y: 0.5 + dirY * tipOffset),
                        startRadius: 0,
                        endRadius: dotSize * (0.25 + 0.2 * pullIntensity)
                    )
                )
                .blendMode(.destinationOut)
            }

            if let pressPoint = interaction.deformation.pressPoint, interaction.deformation.pressDepth > 0 {
                let depth = interaction.deformation.pressDepth
                let pressRadius = dotSize * interaction.deformation.pressRadius
                blob.fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black.opacity(0.30 * depth), location: 0.0),
                            .init(color: .black.opacity(0.10 * depth), location: 0.55),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: pressPoint,
                        startRadius: 0,
                        endRadius: pressRadius * 0.9
                    )
                )
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .frame(width: dotSize, height: dotSize)
        .scaleEffect(interaction.deformation.squish)
        .background(
            Group {
                if preferences.backdrop != .none {
                    Circle()
                        .fill(preferences.backdrop == .dark
                              ? Color.black.opacity(0.25)
                              : Color.white.opacity(0.25))
                        .frame(width: dotSize * 1.3, height: dotSize * 1.3)
                }
            }
        )
        .opacity(preferences.dotOpacity)
        .offset(
            CGSize(
                width: animator.offset.width + interaction.deformation.nudge.width,
                height: animator.offset.height + interaction.deformation.nudge.height
            )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dotSize)
        .animation(.easeInOut(duration: 0.2), value: preferences.dotOpacity)
        .frame(width: 200, height: 200)
    }

}
