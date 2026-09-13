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
            .overlay(.black.opacity(0.04), in: .rect(cornerRadius: radius))
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

struct OneBackground: View {
    var body: some View {
        ZStack {
            OneTheme.canvas
            Circle().fill(OneTheme.accentCyan.opacity(0.18)).frame(width: 280).blur(radius: 30).offset(x: 130, y: -310)
            Circle().fill(OneTheme.accentBlue.opacity(0.08)).frame(width: 220).blur(radius: 40).offset(x: -160, y: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
