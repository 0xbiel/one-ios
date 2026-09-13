import SwiftUI

struct SurfaceCard<Content: View>: View {
    let content: Content
    var radius: CGFloat = 24

    init(radius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content.foregroundStyle(OneTheme.ink)
            .background(OneTheme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.04))
                    .allowsHitTesting(false)
            }
    }
}

struct OneBrandMark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image("OneLogo")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                .accessibilityHidden(true)

            Text("ONE")
                .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                .tracking(compact ? 1 : 1.2)
                .foregroundStyle(OneTheme.accentBlue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ONE")
    }
}

struct LiquidGlassControl<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: .capsule) }
        else { content.background(.ultraThinMaterial, in: Capsule()) }
    }
}

struct OnePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(OneTheme.accentBlue.opacity(isEnabled ? 1 : 0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct OneSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? OneTheme.ink : OneTheme.secondaryInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OneTheme.secondaryInk.opacity(0.16), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct OneBackground: View {
    var body: some View {
        OneTheme.canvas
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct SectionTitle: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(OneTheme.cyan)
            Text(title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(OneTheme.ink)
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: ObservationConfidence
    var body: some View {
        Label(confidence.title, systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(confidence == .high ? OneTheme.mint : OneTheme.amber)
            .accessibilityLabel("Confidence: \(confidence.title)")
    }
}
