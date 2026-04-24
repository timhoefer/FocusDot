import SwiftUI

/// Radial swatch picker that wraps around the dot.
struct ColorPickerOverlay: View {
    let isOpen: Bool
    let dotSize: CGFloat
    let currentColor: DotColor
    let onPick: (DotColor) -> Void

    private let swatchSize: CGFloat = 26
    private let swatchStroke: CGFloat = 1.5

    /// Distance from dot center to swatch center.
    private var ringRadius: CGFloat {
        max(50, dotSize * 1.6 + 28)
    }

    var body: some View {
        ZStack {
            ForEach(Array(DotColor.allCases.enumerated()), id: \.element) { index, color in
                let count = DotColor.allCases.count
                // Start at top (-π/2) and go clockwise.
                let angle = -.pi / 2 + 2 * .pi * Double(index) / Double(count)
                let dx = CGFloat(cos(angle)) * ringRadius
                let dy = CGFloat(sin(angle)) * ringRadius
                let isSelected = color == currentColor

                Button(action: { onPick(color) }) {
                    Circle()
                        .fill(color.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(
                            Circle().stroke(
                                isSelected ? Color.white : Color.white.opacity(0.55),
                                lineWidth: isSelected ? 2.5 : swatchStroke
                            )
                        )
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .offset(x: dx, y: dy)
                // Stagger the entrance so it reads as a "blooming" reveal.
                .scaleEffect(isOpen ? 1.0 : 0.1)
                .opacity(isOpen ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.7)
                        .delay(isOpen ? Double(index) * 0.02 : 0),
                    value: isOpen
                )
            }
        }
        .frame(width: 200, height: 200)
        .allowsHitTesting(isOpen)
    }
}
