// OurApp/Core/Shell/GamesTab/Wobble.swift
import SwiftUI

/// The springboard wobble. Reduce Motion swaps the rotation for a static
/// dashed border so edit mode stays visible without movement.
struct Wobble: ViewModifier {
    let active: Bool
    let reduceMotion: Bool
    @State private var leaning = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active && !reduceMotion ? (leaning ? 1.8 : -1.8) : 0))
            .overlay {
                if active && reduceMotion {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.7),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .onChange(of: active) { _, isOn in
                guard isOn, !reduceMotion else { leaning = false; return }
                withAnimation(.easeInOut(duration: 0.13)
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...0.12))) {
                    leaning = true
                }
            }
    }
}
