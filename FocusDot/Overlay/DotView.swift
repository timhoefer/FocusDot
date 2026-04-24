import SwiftUI
import AppKit

/// Desaturate + darken a SwiftUI color so it reads as "seen in low light".
private func subdued(_ color: Color) -> Color {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h),
                 saturation: Double(s) * 0.55,
                 brightness: Double(b) * 0.50,
                 opacity: Double(a))
}

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
    @ObservedObject var wallpaperSampler: WallpaperSampler

    var body: some View {
        if preferences.isRepositionMode {
            RepositionPlaceholder(
                dotSize: preferences.dotSize,
                color: preferences.dotColor.color,
                onConfirm: { preferences.confirmReposition() }
            )
        } else {
            ballBody
        }
    }

    @ViewBuilder
    private var ballBody: some View {
        let interactionPull = interaction.deformation.pull
        let activePull: CGSize = interaction.deformation.isGrabbed || interaction.deformation.jigglePhase > 0
            ? interactionPull
            : CGSize(
                width: animator.pull.width + interactionPull.width,
                height: animator.pull.height + interactionPull.height
            )

        let isDark = preferences.isEffectivelyDark
        let baseColor = isDark ? subdued(preferences.dotColor.color) : preferences.dotColor.color
        let dotSize = preferences.dotSize
        let blob = BlobShape(pull: activePull, grabWidth: interaction.deformation.grabWidth)

        let pullMag = sqrt(activePull.width * activePull.width + activePull.height * activePull.height)

        // Fixed light source — highlight always at top-left of the dot frame
        let lightX: CGFloat = 0.35
        let lightY: CGFloat = 0.3

        // Highlight nudges in the direction of pull — fakes the lit surface "leaning"
        // with the deformation. Specular sharpens slightly when the skin is taut.
        let shiftFactor: CGFloat = 0.22
        let dynLightX = lightX + (activePull.width  / max(dotSize, 1)) * shiftFactor
        let dynLightY = lightY + (activePull.height / max(dotSize, 1)) * shiftFactor
        let specBoost: CGFloat = min(pullMag / dotSize, 1.0) * 0.10

        ZStack {
            blob.fill(baseColor)

            // Key light — top-left, the dominant directional light. Diffuse + shadow falloff.
            blob.fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.3),
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.06), location: 0.85),
                        .init(color: .black.opacity(0.12), location: 1.0),
                    ]),
                    center: UnitPoint(x: dynLightX, y: dynLightY),
                    startRadius: 0,
                    endRadius: dotSize * 0.55
                )
            )

            // Fill light — softer, broader, from directly above. Slightly cool to feel sky-like.
            blob.fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.16), location: 0.0),
                        .init(color: Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.06), location: 0.45),
                        .init(color: .clear, location: 0.85),
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.05),
                    startRadius: 0,
                    endRadius: dotSize * 0.75
                )
            )

            // Key specular — small, bright, follows the key light.
            blob.fill(
                RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.3 + specBoost), .white.opacity(0.0)]),
                    center: UnitPoint(x: dynLightX + 0.02, y: dynLightY + 0.02),
                    startRadius: 0,
                    endRadius: dotSize * 0.13
                )
            )

            // Fill specular — small soft sheen near the top, hints at the second light.
            blob.fill(
                RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.18), .white.opacity(0.0)]),
                    center: UnitPoint(x: 0.5, y: 0.10),
                    startRadius: 0,
                    endRadius: dotSize * 0.10
                )
            )

            // Bounce light from the desktop, picked up on the shadow-side rim.
            if #available(macOS 14, *), preferences.isAmbientShadingEnabled {
                blob.fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: wallpaperSampler.ambientColor.opacity(0.55), location: 0.0),
                            .init(color: wallpaperSampler.ambientColor.opacity(0.30), location: 0.4),
                            .init(color: .clear, location: 0.95),
                        ]),
                        center: UnitPoint(x: 1 - lightX + 0.20, y: 1 - lightY + 0.20),
                        startRadius: 0,
                        endRadius: dotSize * 0.9
                    )
                )
                .animation(.easeInOut(duration: 0.25), value: wallpaperSampler.ambientColor)
            }

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
        // Dim the whole composite in dark mode so white speculars don't pop against the muted base.
        .colorMultiply(isDark ? Color(white: 0.65) : .white)
        .frame(width: dotSize, height: dotSize)
        .scaleEffect(interaction.deformation.squish * animator.visibilityScale)
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

/// Placeholder shown during reposition mode: a dotted outline where the dot will land,
/// plus a confirm button. Drag handling stays in InteractionManager (drag anywhere on
/// the dot circle moves it).
private struct RepositionPlaceholder: View {
    let dotSize: CGFloat
    let color: Color
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    color.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                )
                .background(Circle().fill(color.opacity(0.08)))
                .frame(width: dotSize, height: dotSize)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: max(8, dotSize * 0.35), weight: .semibold))
                .foregroundStyle(color.opacity(0.85))

            Button(action: onConfirm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .offset(x: dotSize / 2 + 18, y: 0)
        }
        .frame(width: 200, height: 200)
    }
}
