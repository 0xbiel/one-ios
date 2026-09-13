import SwiftUI

struct OnboardingView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSaving = false

    private var pageIndex: Int { min(max(store.onboardingStep, 0), 2) }
    private var page: OneOnboardingPage {
        switch pageIndex {
        case 0:
            OneOnboardingPage(
                eyebrow: "A calmer day",
                title: "Welcome to your home.",
                body: "ONE helps your care circle notice daily rhythms with clarity and consent.",
                symbol: "house.and.flag.fill",
                tint: OneTheme.accentCyan
            )
        case 1:
            OneOnboardingPage(
                eyebrow: "Your choices",
                title: "Choose what ONE may use.",
                body: "You can change these choices later in Account.",
                symbol: "slider.horizontal.3",
                tint: OneTheme.accentBlue
            )
        case 2:
            OneOnboardingPage(
                eyebrow: "No pressure",
                title: "Set up at your pace.",
                body: "Camera pairing and inviting family are optional. You can do them later from the care circle.",
                symbol: "lock.shield.fill",
                tint: OneTheme.mint
            )
        default:
            OneOnboardingPage(
                eyebrow: "Ready when you are",
                title: "You’re ready.",
                body: "Your choices are saved. ONE will keep observations understandable and non-diagnostic.",
                symbol: "checkmark.seal.fill",
                tint: OneTheme.accentCyan
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    OneOnboardingHero(page: page)
                        .padding(.top, 24)
                        .padding(.bottom, 34)
                        .id(pageIndex)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(page.eyebrow.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(page.tint)

                        Text(page.title)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .tracking(-0.7)
                            .foregroundStyle(OneTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)

                        Text(page.body)
                            .font(.title3)
                            .foregroundStyle(OneTheme.secondaryInk)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    if pageIndex == 1 {
                        consentChoices.padding(.top, 28)
                    } else if pageIndex == 2 {
                        privacyCallout.padding(.top, 28)
                    }

                    if let authError = store.authError {
                        Label(authError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.top, 20)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: pageIndex)
            }

            onboardingFooter
        }
        .background(OneBackground())
        .accessibilityElement(children: .contain)
    }

    private var onboardingHeader: some View {
        HStack(spacing: 10) {
            Label("ONE", systemImage: "waveform.circle.fill")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(OneTheme.accentBlue)

            Spacer()

            Text("SETUP \(pageIndex + 1) OF 3")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(OneTheme.surface, in: Capsule())
                .overlay { Capsule().stroke(OneTheme.secondaryInk.opacity(0.16), lineWidth: 0.75) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ONE, setup step \(pageIndex + 1) of 3")
    }

    private var consentChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose what can help")
                .font(.headline)
                .foregroundStyle(OneTheme.ink)

            ForEach(Array(store.onboardingConsents.keys.sorted()), id: \.self) { purpose in
                Toggle(isOn: consentBinding(for: purpose)) {
                    HStack(spacing: 12) {
                        Image(systemName: purposeSymbol(for: purpose))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.accentBlue)
                            .frame(width: 36, height: 36)
                            .background(OneTheme.accentBlue.opacity(0.10), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(purpose)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OneTheme.ink)
                            Text(purposeDescription(for: purpose))
                                .font(.caption)
                                .foregroundStyle(OneTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(OneTheme.accentBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OneTheme.secondaryInk.opacity(0.14), lineWidth: 0.75) }
                .accessibilityHint("You can change this choice later in Account.")
            }
        }
    }

    private var privacyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(OneTheme.cyan)
                .frame(width: 38, height: 38)
                .background(OneTheme.cyan.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Private by default")
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                Text("No camera or family access is enabled automatically. You stay in control of what is shared.")
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OneTheme.cyan.opacity(0.22), lineWidth: 0.75) }
        .accessibilityElement(children: .combine)
    }

    private var onboardingFooter: some View {
        VStack(spacing: 20) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.20))
                        .frame(width: index == pageIndex ? 24 : 7, height: 7)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pageIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(pageIndex + 1) of 3")

            Button(action: advance) {
                HStack {
                    Text(isSaving ? "Saving…" : (pageIndex < 2 ? "Continue" : "Finish setup"))
                    Spacer()
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
            }
            .buttonStyle(OnePrimaryButtonStyle())
            .disabled(isSaving)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(.regularMaterial)
    }

    private func advance() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let saved = pageIndex == 1 ? await store.recordOnboardingConsents() : true
            guard saved else { return }

            if pageIndex < 2 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    store.onboardingStep += 1
                }
            } else {
                store.completeOnboarding()
            }
        }
    }

    private func consentBinding(for purpose: String) -> Binding<Bool> {
        Binding(
            get: { store.onboardingConsents[purpose] ?? false },
            set: { store.onboardingConsents[purpose] = $0 }
        )
    }

    private func purposeSymbol(for purpose: String) -> String {
        switch purpose {
        case "Daily check-in support": "waveform"
        case "Room and camera data": "camera.viewfinder"
        case "Medication reminders": "cross.case.fill"
        case "Family sharing": "person.2.fill"
        default: "checkmark.circle"
        }
    }

    private func purposeDescription(for purpose: String) -> String {
        switch purpose {
        case "Daily check-in support": "A calm conversation and voice input for today’s check-in."
        case "Room and camera data": "Local room context for approximate movement and object memory."
        case "Medication reminders": "Human-entered reminders that help the care circle stay organized."
        case "Family sharing": "Share selected updates with the people you choose."
        default: "A purpose-specific choice you can revisit later."
        }
    }
}

private struct OneOnboardingPage {
    let eyebrow: String
    let title: String
    let body: String
    let symbol: String
    let tint: Color
}

private struct OneOnboardingHero: View {
    let page: OneOnboardingPage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [page.tint.opacity(0.16), OneTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))

            OneOnboardingRouteArtwork(tint: page.tint)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))

            Circle()
                .fill(page.tint.opacity(0.13))
                .frame(width: 148, height: 148)
            Circle()
                .stroke(page.tint.opacity(0.24), lineWidth: 1)
                .frame(width: 188, height: 188)

            Image(systemName: page.symbol)
                .font(.system(size: 62, weight: .medium))
                .foregroundStyle(page.tint)

            VStack {
                HStack {
                    Label("CALM SUPPORT", systemImage: "sparkles")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(page.tint)
                    Spacer()
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 224)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ONE onboarding illustration: \(page.title)")
    }
}

private struct OneOnboardingRouteArtwork: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.04, y: size.height * 0.76))
            route.addCurve(
                to: CGPoint(x: size.width * 0.42, y: size.height * 0.40),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.76),
                control2: CGPoint(x: size.width * 0.22, y: size.height * 0.36)
            )
            route.addCurve(
                to: CGPoint(x: size.width * 0.98, y: size.height * 0.20),
                control1: CGPoint(x: size.width * 0.62, y: size.height * 0.48),
                control2: CGPoint(x: size.width * 0.78, y: size.height * 0.16)
            )
            context.stroke(route, with: .color(tint.opacity(0.20)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            var echo = Path()
            echo.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.98))
            echo.addCurve(
                to: CGPoint(x: size.width * 0.88, y: size.height * 0.58),
                control1: CGPoint(x: size.width * 0.40, y: size.height * 0.92),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.68)
            )
            context.stroke(echo, with: .color(tint.opacity(0.10)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 7]))
        }
        .allowsHitTesting(false)
    }
}
