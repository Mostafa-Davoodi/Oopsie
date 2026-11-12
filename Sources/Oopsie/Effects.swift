import SwiftUI

// MARK: - Buttons

struct BigButton: View {
    let title: String
    let emoji: String
    let colors: [Color]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 17))
                    .rotationEffect(.degrees(hovering ? -14 : 0))
                    .scaleEffect(hovering ? 1.18 : 1)
                Text(title)
            }
        }
        .buttonStyle(ChunkyButtonStyle(colors: colors, lifted: hovering))
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hovering = h }
        }
    }
}

struct ChunkyButtonStyle: ButtonStyle {
    let colors: [Color]
    var lifted = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: (colors.last ?? .black).opacity(pressed ? 0.25 : 0.45),
                    radius: pressed ? 2 : (lifted ? 12 : 8),
                    y: pressed ? 1 : (lifted ? 6 : 4))
            .scaleEffect(pressed ? 0.93 : (lifted ? 1.04 : 1))
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: pressed)
            .contentShape(Capsule())
    }
}

// MARK: - Shake

struct Shake: GeometryEffect {
    var progress: CGFloat
    var travel: CGFloat = 9
    var shakes: CGFloat = 6

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = travel * sin(progress * .pi * shakes)
        let angle = 0.02 * sin(progress * .pi * shakes * 1.3)
        let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .rotated(by: angle)
            .translatedBy(x: -size.width / 2 + x, y: -size.height / 2)
        return ProjectionTransform(t)
    }
}

// MARK: - Boom

struct Particle: Identifiable {
    enum Kind { case shard(Color), emoji(String) }

    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let spin: Double
    let size: CGFloat
    let kind: Kind

    static func burst(count: Int = 38) -> [Particle] {
        let colors = Palette.boom + Palette.grape + [Palette.busy, Palette.alive, .white]
        let debris = ["🐧", "📦", "💾", "⚙️", "🔩", "📄", "🧨"]
        return (0..<count).map { i in
            let kind: Kind = i % 5 == 0
                ? .emoji(debris.randomElement()!)
                : .shard(colors.randomElement()!)
            return Particle(
                angle: Double.random(in: 0..<(2 * .pi)),
                distance: .random(in: 90...260),
                spin: .random(in: -540...540),
                size: .random(in: 5...12),
                kind: kind
            )
        }
    }
}

private struct Fly: ViewModifier, Animatable {
    var progress: CGFloat
    let particle: Particle

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let d = particle.distance * progress
        let gravity = 140 * progress * progress
        return content
            .rotationEffect(.degrees(particle.spin * Double(progress)))
            .scaleEffect(1 - 0.45 * progress)
            .offset(x: CGFloat(cos(particle.angle)) * d,
                    y: CGFloat(sin(particle.angle)) * d + gravity)
            .opacity(Double(1 - progress))
    }
}

/// Shockwave + flying debris + flash. Plays once on appear.
struct BoomView: View {
    @State private var particles = Particle.burst()
    @State private var progress: CGFloat = 0
    @State private var flash = 0.55
    @State private var ring: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .opacity(flash)
                .allowsHitTesting(false)

            Circle()
                .strokeBorder(
                    AngularGradient(colors: Palette.boom + Palette.grape + [Palette.boom[0]], center: .center),
                    lineWidth: 14 * (1 - ring) + 1
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.3 + ring * 8)
                .opacity(Double(1 - ring))

            ForEach(particles) { p in
                particleView(p).modifier(Fly(progress: progress, particle: p))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            withAnimation(.easeOut(duration: 0.7)) { ring = 1 }
            withAnimation(.easeOut(duration: 1.25)) { progress = 1 }
        }
    }

    @ViewBuilder
    private func particleView(_ p: Particle) -> some View {
        switch p.kind {
        case .shard(let color):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: p.size, height: p.size * 0.55)
        case .emoji(let e):
            Text(e).font(.system(size: p.size * 2.1))
        }
    }
}
