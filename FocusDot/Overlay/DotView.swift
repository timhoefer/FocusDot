import SwiftUI

struct DotView: View {
    @ObservedObject var preferences: PreferencesManager
    @ObservedObject var animator: BounceAnimator

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: preferences.dotSize, height: preferences.dotSize)
            .opacity(preferences.dotOpacity)
            .offset(animator.offset)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: preferences.dotSize)
            .animation(.easeInOut(duration: 0.2), value: preferences.dotOpacity)
    }
}
