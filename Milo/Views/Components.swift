import SwiftUI

// MARK: - Chip

struct Chip: View {
    enum Kind { case warn, ok, soft }
    var text: String
    var icon: String? = nil
    var kind: Kind

    private var colors: (bg: Color, fg: Color) {
        switch kind {
        case .warn: return (Theme.alertSoft, Theme.alert)
        case .ok:   return (Theme.okChipBg, Theme.brand)
        case .soft: return (Theme.accentSoft, Theme.accentDeep)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Text(icon) }
            Text(text)
        }
        .font(.milo(11, .heavy))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(colors.bg)
        .foregroundStyle(colors.fg)
        .clipShape(Capsule())
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    var progress: Double           // 0...1+ (clamped for the arc)
    var lineWidth: CGFloat
    var gradient: LinearGradient = Theme.ringGradient
    var over: Bool = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(over ? Theme.overGradient : gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
        }
    }
}

// MARK: - Horizontal budget bar (home dog cards)

struct BudgetBar: View {
    var progress: Double
    var over: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(over ? Theme.overGradient : Theme.barGradient)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Member avatar stack

struct MemberStack: View {
    var members: [Member]
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -9) {
            ForEach(members) { m in
                Text(m.initials)
                    .font(.milo(size * 0.4, .heavy))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(m.palette.gradient)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
        }
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.milo(16, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Primary CTA button

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.milo(16, .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Theme.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .shadow(color: Theme.brandDeep.opacity(enabled ? 0.35 : 0),
                    radius: 14, y: 10)
        }
        .disabled(!enabled)
        .buttonStyle(PressStyle())
    }
}

/// Subtle press-scale used across tappable surfaces (matches the mockup's :active).
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Toast

struct ToastView: View {
    var text: String
    var body: some View {
        HStack(spacing: 11) {
            Text("✓")
                .font(.milo(16, .heavy))
                .foregroundStyle(Theme.brandDeep)
                .frame(width: 30, height: 30)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(.milo(13, .heavy))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.brandDeep)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Circular back button

struct BackButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.milo(17, .heavy))
                .foregroundStyle(Theme.brandDeep)
                .frame(width: 38, height: 38)
                .background(Theme.card)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}
