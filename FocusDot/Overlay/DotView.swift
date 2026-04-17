import SwiftUI
import simd

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

        let params = BallShadingParams.resolve(animator.shadingState)
        // Top-left, slightly above the screen plane. SwiftUI y is down, so y < 0 is "up".
        let light = simd_normalize(SIMD3<Float>(-0.4, -0.3, 0.85))
        let center = CGPoint(x: dotSize / 2, y: dotSize / 2)

        ZStack {
            blob.fill(baseColor)
                .colorEffect(Shader.ballShade(center: center, params: params, light: light))

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
