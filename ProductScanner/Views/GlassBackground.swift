import SwiftUI

/// Approximates the newest Apple "Liquid Glass" look with a translucent
/// material, a soft light-catching stroke, and a grounding shadow — built on
/// plain SwiftUI materials so it works from iOS 16 up on every device,
/// rather than requiring the iOS 26 `glassEffect()` API.
struct GlassBackgroundModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

extension View {
    func glassBackground<S: InsettableShape>(in shape: S) -> some View {
        modifier(GlassBackgroundModifier(shape: shape))
    }
}
