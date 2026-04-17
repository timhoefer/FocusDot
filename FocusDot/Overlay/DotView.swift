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
        // Physics in BounceAnimator is the single source of truth for stretch/wobble.
        let activePull = animator.pull

        let baseColor = preferences.dotColor.color
        let dotSize = preferences.dotSize
        let blob = BlobShape(pull: activePull, grabWidth: interaction.deformation.grabWidth)

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

            // Grain texture
            if let noise = noiseImage {
                blob.fill(ImagePaint(image: Image(decorative: noise, scale: 2)))
                    .blendMode(.overlay)
                    .opacity(0.08)
            }
        }
        .frame(width: dotSize, height: dotSize)
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
        .scaleEffect(interaction.deformation.squish)
        .opacity(preferences.dotOpacity)
        .offset(animator.offset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dotSize)
        .animation(.easeInOut(duration: 0.2), value: preferences.dotOpacity)
        .frame(width: 200, height: 200)
    }

}
