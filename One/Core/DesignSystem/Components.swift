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

struct LiquidGlassSurface<Content: View>: View {
    let radius: CGFloat
    let content: Content

    init(radius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
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

/// Shared by the map legend, projected markers, and selection details.
enum MapMarkerStyle: String, CaseIterable, Identifiable {
    case simulated, simulatedUnknown, simulatedRecent, simulatedStale, recognized, unknownNow, unknownRecent, cameraOnline, cameraOffline, cameraUnknown, cameraSimulated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simulated: "Person"
        case .simulatedUnknown: "Unknown person"
        case .simulatedRecent: "Recent observation"
        case .simulatedStale: "Earlier observation"
        case .recognized: "Recognized"
        case .unknownNow: "Unknown now"
        case .unknownRecent: "Unknown recent"
        case .cameraOnline: "Camera online"
        case .cameraOffline: "Camera offline"
        case .cameraUnknown: "Camera status unknown"
        case .cameraSimulated: "Camera active"
        }
    }

    var symbol: String {
        switch self {
        case .simulated: "person.fill"
        case .simulatedUnknown: "person.fill.questionmark"
        case .simulatedRecent, .simulatedStale: "clock.fill"
        case .recognized: "person.crop.circle.badge.checkmark"
        case .unknownNow: "person.fill.questionmark"
        case .unknownRecent: "clock.fill"
        case .cameraOnline, .cameraSimulated: "camera.fill"
        case .cameraUnknown: "camera.badge.ellipsis"
        case .cameraOffline: "video.slash.fill"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .simulated, .simulatedUnknown: .systemPurple
        case .simulatedRecent, .simulatedStale: .systemGray
        case .recognized: .systemGreen
        case .unknownNow, .unknownRecent: .systemOrange
        case .cameraOnline: .systemBlue
        case .cameraOffline: .systemRed
        case .cameraUnknown: .systemGray
        case .cameraSimulated: .systemPurple
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var detail: String {
        switch self {
        case .simulated: "Named scripted position; no camera capture or recognition."
        case .simulatedUnknown: "Anonymous scripted position; no camera capture or recognition."
        case .simulatedRecent: "Recent scripted position, not a current sighting."
        case .simulatedStale: "Earlier scripted position; current location is unknown."
        case .recognized: "Face profile matched. Faded markers were seen recently."
        case .unknownNow: "Seen within about 12 seconds."
        case .unknownRecent: "Last seen within about 2 minutes."
        case .cameraOnline: "Device connected; floor coverage is not established."
        case .cameraUnknown: "Camera status or placement is unconfirmed."
        case .cameraSimulated: "Scripted availability; no real camera capture."
        case .cameraOffline: "Camera unavailable."
        }
    }

    static func camera(_ registration: CameraRegistrationDescriptor, objects: [RoomObject], cameras: [PairedCamera]) -> Self {
        guard registration.status == .positioned,
              let id = registration.cameraID,
              let camera = cameras.first(where: { $0.id == id }) else { return .cameraUnknown }
        if camera.simulationStatus == "simulated_online" { return .cameraSimulated }
        if camera.simulationStatus == "simulated_offline" || camera.status.lowercased() == "offline" { return .cameraOffline }
        guard camera.status.lowercased() == "online" else { return .cameraUnknown }
        let people = objects.filter {
            $0.cameraID == registration.cameraID && $0.identityStatus != "simulated" && MapPresenceAppearance.presence($0) != nil
        }
        if people.contains(where: { $0.identityStatus == "matched" }) { return .recognized }
        if people.contains(where: { MapPresenceAppearance.presence($0)?.isRecent == false }) { return .unknownNow }
        if !people.isEmpty { return .unknownRecent }
        return .cameraOnline
    }
}

struct MapPresenceAppearance {
    let style: MapMarkerStyle
    let isRecent: Bool

    var opacity: Double { isRecent ? 0.38 : 0.96 }

    static func presence(_ object: RoomObject, now: Date = Date()) -> Self? {
        guard ["person", "people", "human"].contains(object.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                || ["person", "people", "human"].contains(object.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
              let observedAt = object.observedAt else { return nil }
        let age = now.timeIntervalSince(observedAt)
        guard age >= -5 else { return nil }
        if object.identityStatus == "simulated" {
            if object.presenceState == .stale || age > 120 { return Self(style: .simulatedStale, isRecent: true) }
            if object.presenceState == .recent || age > 12 { return Self(style: .simulatedRecent, isRecent: true) }
            let named = !(object.identityName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return Self(style: named ? .simulated : .simulatedUnknown, isRecent: false)
        }
        guard object.presenceState != .stale, age <= 120 else { return nil }
        let current = object.presenceState != .recent && age <= 12
        return Self(style: object.identityStatus == "matched" ? .recognized : (current ? .unknownNow : .unknownRecent), isRecent: !current)
    }
}

struct OneStatusBadge: View {
    let title: String
    let symbol: String
    var tint: Color = OneTheme.accentBlue
    var faded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .opacity(faded ? 0.38 : 1)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(faded ? 0.05 : 0.10), in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(faded ? 0.14 : 0.22), lineWidth: 0.75) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct MapLegendBadge: View {
    let style: MapMarkerStyle

    var body: some View {
        OneStatusBadge(title: style.title, symbol: style.symbol, tint: style.color, faded: style == .unknownRecent)
            .accessibilityHint(style.detail)
    }
}
