import SwiftUI

enum Palette {
    static let grape = [Color(red: 0.66, green: 0.47, blue: 1.0), Color(red: 0.46, green: 0.29, blue: 0.94)]
    static let boom = [Color(red: 1.0, green: 0.50, blue: 0.36), Color(red: 0.94, green: 0.20, blue: 0.40)]
    static let ink = Color(red: 0.090, green: 0.075, blue: 0.122)
    static let alive = Color(red: 0.36, green: 0.86, blue: 0.52)
    static let busy = Color(red: 1.0, green: 0.74, blue: 0.30)
}

struct PopoverView: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        VStack(spacing: 0) {
            Header()
            ZStack { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Footer()
        }
        .frame(width: 580, height: 480)
    }

    private var swap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle:
            IdleView().transition(swap)
        case .spawning:
            SpawningView().transition(swap)
        case .running, .shellExited:
            RunningView().transition(swap)
        case .destroyed:
            DestroyedView().id(store.boomID).transition(.opacity)
        case .failed(let message):
            FailedView(message: message).transition(swap)
        case .missingCLI:
            MissingCLIView().transition(swap)
        }
    }
}

// MARK: - Header & footer

private struct Header: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("💥")
                .font(.system(size: 26))
                .rotationEffect(.degrees(store.isBreaking ? 20 : -8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Oopsie")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                StatusChip()
            }
            Spacer()
            CounterPill()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct StatusChip: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(color: color, pulsing: store.phase == .running || store.phase == .spawning)
            if store.phase == .running || store.phase == .shellExited, let born = store.bornAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    label("ubuntu · alive \(Self.uptime(from: born, to: context.date))")
                }
            } else {
                label(text)
            }
        }
    }

    private func label(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var color: Color {
        switch store.phase {
        case .running, .shellExited: return Palette.alive
        case .spawning: return Palette.busy
        case .failed, .missingCLI: return Palette.boom[1]
        default: return .secondary.opacity(0.5)
        }
    }

    private var text: String {
        switch store.phase {
        case .spawning: return "booting…"
        case .destroyed: return "freshly obliterated"
        case .failed: return "having a moment"
        case .missingCLI: return "needs a little setup"
        default: return "no machine"
        }
    }

    static func uptime(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct CounterPill: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        HStack(spacing: 6) {
            Text("🪦").font(.system(size: 13))
            Text("\(store.destroyedCount)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: Double(store.destroyedCount)))
                .monospacedDigit()
            Text(store.destroyedCount == 1 ? "Linux destroyed" : "Linuxes destroyed")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .phaseAnimator([1.0, 1.22, 1.0], trigger: store.destroyedCount) { view, scale in
            view.scaleEffect(scale)
        } animation: { _ in
            .spring(response: 0.22, dampingFraction: 0.45)
        }
        .help("Lifetime Linux body count")
    }
}

private struct Footer: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        HStack {
            (Text("Rank: ").foregroundColor(Color.secondary.opacity(0.6))
                + Text(store.rank).foregroundColor(.secondary))
            Spacer()
            Button("Quit Oopsie") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(store.isAlive ? "Quitting destroys your Linux too" : "Bye!")
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

// MARK: - Idle

private struct IdleView: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            FloatingPenguin()
            Text(store.idleLine)
                .font(.system(size: 23, weight: .bold, design: .rounded))
            Text("One click for a fresh Ubuntu box. Break it, bin it, repeat.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            BigButton(title: "Spawn Linux", emoji: "🐧", colors: Palette.grape) { store.spawn() }
                .padding(.top, 8)
            ShortcutHint("⌘ ↩")
            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }
}

private struct FloatingPenguin: View {
    @State private var bob = false
    @State private var spin = 0.0
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Text("🐧")
                .font(.system(size: 66))
                .rotationEffect(.degrees(spin + (hovering ? -10 : 0)))
                .offset(y: bob ? -7 : 3)
                .onTapGesture {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { spin += 360 }
                }
                .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hovering = h } }
            Ellipse()
                .fill(.black.opacity(bob ? 0.10 : 0.18))
                .frame(width: bob ? 38 : 48, height: 7)
                .blur(radius: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        }
    }
}

// MARK: - Spawning

private struct SpawningView: View {
    @EnvironmentObject private var store: OopsieStore
    @State private var wobble = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text("🐧")
                .font(.system(size: 66))
                .rotationEffect(.degrees(wobble ? 12 : -12), anchor: .bottom)
                .scaleEffect(x: wobble ? 1.06 : 0.96, y: wobble ? 0.94 : 1.04, anchor: .bottom)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true)) { wobble = true }
                }
            Text(store.spawnMessage)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)
                .id(store.spawnMessage)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            BouncingDots()
            Spacer(minLength: 0)
        }
    }
}

private struct BouncingDots: View {
    @State private var up = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(LinearGradient(colors: Palette.grape, startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: 8)
                    .offset(y: up ? -6 : 2)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14), value: up)
            }
        }
        .onAppear { up = true }
    }
}

// MARK: - Running

private struct RunningView: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        VStack(spacing: 12) {
            TerminalCard()
                .modifier(Shake(progress: store.isBreaking ? 1 : 0))
                .scaleEffect(store.isBreaking ? 0.9 : 1)
                .blur(radius: store.isBreaking ? 4 : 0)
                .opacity(store.isBreaking ? 0.4 : 1)

            HStack(spacing: 14) {
                TipTicker()
                Spacer(minLength: 8)
                VStack(spacing: 3) {
                    BigButton(title: "Oopsie!", emoji: "💥", colors: Palette.boom) { store.oopsie() }
                    ShortcutHint("⌘ ⌫")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

private struct TerminalCard: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                WindowDot(color: Palette.boom[1], symbol: "xmark") { store.oopsie() }
                    .help("Oopsie!")
                WindowDot(color: Palette.busy, symbol: nil, action: nil)
                WindowDot(color: Palette.alive, symbol: nil, action: nil)
                Spacer()
                Text("root@\(store.machineName ?? "linux")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            TerminalHost(session: store.terminal)
                .id(store.terminal.generation)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.bottom, 6)
        }
        .background(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .overlay {
            if store.phase == .shellExited {
                ShellExitedOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct WindowDot: View {
    let color: Color
    let symbol: String?
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(action == nil ? 0.35 : 0.9))
            if let symbol, hovering {
                Image(systemName: symbol)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .frame(width: 11, height: 11)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
    }
}

private struct ShellExitedOverlay: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.88)
            VStack(spacing: 10) {
                Text("🐧").font(.system(size: 44))
                Text("You left. The penguin waits.")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your machine is still alive in there.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Button { store.reconnect() } label: {
                    Label("Jump back in", systemImage: "arrow.uturn.left")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.grape[1])
                .padding(.top, 4)
            }
        }
    }
}

private struct TipTicker: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 7)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 7) % Quips.tips.count
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("💡").font(.system(size: 11))
                Text(LocalizedStringKey(Quips.tips[index]))
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
    }
}

// MARK: - Destroyed

private struct DestroyedView: View {
    @EnvironmentObject private var store: OopsieStore
    @State private var showText = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            BoomView()
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("Well, that happened.")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .scaleEffect(showText ? 1 : 0.6)
                    .opacity(showText ? 1 : 0)
                Text(store.boomLine)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 6)
                VStack(spacing: 4) {
                    BigButton(title: "Do It Again", emoji: "🔄", colors: Palette.grape) { store.spawn() }
                    ShortcutHint("⌘ ↩")
                }
                .padding(.top, 14)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 12)
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.28)) { showText = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.65)) { showButton = true }
        }
    }
}

// MARK: - Problems

private struct FailedView: View {
    @EnvironmentObject private var store: OopsieStore
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text("😵‍💫").font(.system(size: 58))
            Text("Oopsie! (the bad kind)")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .textSelection(.enabled)
                .padding(.horizontal, 50)
            BigButton(title: "Try Again", emoji: "🐧", colors: Palette.grape) { store.spawn() }
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }
}

private struct MissingCLIView: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text("📦").font(.system(size: 58))
            Text("Oopsie needs Apple's container tool")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("It's what runs the Linux machines. Install it, then come back to break things.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/apple/container/releases")!) {
                    Label("Get container", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.grape[1])
                Button("I installed it") { store.recheckCLI() }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bits

private struct ShortcutHint: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
    }
}

private struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .fill(color.opacity(0.45))
                    .scaleEffect(animate ? 2.6 : 1)
                    .opacity(animate ? 0 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: 7, height: 7)
        .id(pulsing)
        .onAppear {
            animate = false
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { animate = true }
        }
    }
}
