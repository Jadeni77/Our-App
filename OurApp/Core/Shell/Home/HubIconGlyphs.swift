import SwiftUI

/// Picks the glyph for an icon and lifts it off the body with a soft shadow.
struct HubIconGlyph: View {
    let icon: HubIcon
    let side: CGFloat

    var body: some View {
        Group {
            switch icon {
            case .specialDates:  CalendarHeartGlyph(side: side, accent: icon.ramp.deep)
            case .dailyQuestion: PairedBubblesGlyph(side: side, accent: icon.ramp.deep)
            case .memories:      PhotoStackGlyph(side: side, accent: icon.ramp.deep)
            }
        }
        .shadow(color: .black.opacity(0.20), radius: side * 0.03, y: side * 0.015)
    }
}

/// A calendar whose date is a heart — the day that matters, not a number.
private struct CalendarHeartGlyph: View {
    let side: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            HStack(spacing: side * 0.20) {
                ring
                ring
            }
            .offset(y: -side * 0.28)

            RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
                .fill(.white)
                .frame(width: side * 0.52, height: side * 0.44)
                .offset(y: side * 0.04)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(accent.opacity(0.35))
                        .frame(width: side * 0.52, height: side * 0.03)
                        .offset(y: side * 0.11)
                }

            HeartShape()
                .fill(accent)
                .frame(width: side * 0.21, height: side * 0.19)
                .offset(y: side * 0.10)
        }
    }

    private var ring: some View {
        Capsule()
            .fill(.white)
            .frame(width: side * 0.055, height: side * 0.13)
    }
}

/// Two bubbles — theirs behind, ours in front carrying the question.
private struct PairedBubblesGlyph: View {
    let side: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            // Theirs: mirrored so its tail points the other way. Two bubbles
            // leaning away from each other read as a conversation; two facing
            // the same way read as one person talking twice.
            BubbleShape()
                .fill(.white.opacity(0.55))
                .frame(width: side * 0.44, height: side * 0.32)
                .scaleEffect(x: -1, y: 1)
                .offset(x: side * 0.11, y: -side * 0.17)

            // Ours, carrying the question.
            BubbleShape()
                .fill(.white)
                .frame(width: side * 0.54, height: side * 0.40)
                .offset(x: -side * 0.06, y: side * 0.10)

            question
                .offset(x: -side * 0.06, y: side * 0.04)
        }
    }

    private var question: some View {
        VStack(spacing: side * 0.03) {
            QuestionMarkShape()
                .stroke(accent, style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
                .frame(width: side * 0.13, height: side * 0.13)
            Circle()
                .fill(accent)
                .frame(width: side * 0.05, height: side * 0.05)
        }
    }
}

/// Two photos, fanned, the front one holding a picture.
private struct PhotoStackGlyph: View {
    let side: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
                .fill(.white.opacity(0.55))
                .frame(width: side * 0.44, height: side * 0.34)
                .rotationEffect(.degrees(-9))
                .offset(x: -side * 0.07, y: -side * 0.02)

            picture
                .rotationEffect(.degrees(6))
                .offset(x: side * 0.05, y: side * 0.04)

            SparkleShape()
                .fill(.white)
                .frame(width: side * 0.11, height: side * 0.11)
                .offset(x: side * 0.21, y: -side * 0.22)
        }
    }

    /// The front photo: a sun over hills, inset inside a white border so it
    /// reads as a print rather than a coloured rectangle.
    private var picture: some View {
        let width = side * 0.46, height = side * 0.36
        let inset = side * 0.030
        let innerWidth = width - inset * 2, innerHeight = height - inset * 2
        return ZStack {
            Color.white

            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: innerWidth * 0.17, height: innerWidth * 0.17)
                    .offset(x: -innerWidth * 0.26, y: -innerHeight * 0.24)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: innerHeight))
                    path.addLine(to: CGPoint(x: innerWidth * 0.34, y: innerHeight * 0.40))
                    path.addLine(to: CGPoint(x: innerWidth * 0.56, y: innerHeight * 0.70))
                    path.addLine(to: CGPoint(x: innerWidth * 0.74, y: innerHeight * 0.46))
                    path.addLine(to: CGPoint(x: innerWidth, y: innerHeight))
                    path.closeSubpath()
                }
                .fill(accent.opacity(0.75))
            }
            .frame(width: innerWidth, height: innerHeight)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.05, style: .continuous))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.08, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            ForEach(Array(HubIcon.allCases.enumerated()), id: \.offset) { _, icon in
                HubIconView(icon: icon).frame(width: 110, height: 110)
            }
        }
        HStack(spacing: 16) {
            ForEach(Array(HubIcon.allCases.enumerated()), id: \.offset) { _, icon in
                HubIconView(icon: icon).frame(width: 78, height: 78)
            }
        }
    }
    .padding(30)
    .background(Theme.duskGradient)
}
