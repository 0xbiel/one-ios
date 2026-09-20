import SwiftUI

struct OnboardingView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSaving = false
    @State private var selectedChoice: Bool?
    @State private var answeredPurposes: Set<String> = []
    @State private var validationMessage: String?

    private let pages = [
        OneOnboardingPage(
            eyebrow: "A clear view, with consent",
            title: "Support a calmer daily check-in.",
            body: "Use room and camera context in a private home or residence to help the care circle notice familiar routines and compare with the person’s own baseline.",
            purpose: "Room and camera data",
            symbol: "camera.viewfinder",
            tint: OneTheme.accentCyan
        ),
        OneOnboardingPage(
            eyebrow: "Natural conversations",
            title: "Make answers feel easy.",
            body: "Use the microphone for a gentle conversation when someone chooses to press and hold to talk, including daily MCI support without turning observations into a diagnosis.",
            purpose: "Daily check-in support",
            symbol: "waveform",
            tint: OneTheme.accentBlue
        ),
        OneOnboardingPage(
            eyebrow: "Share care, intentionally",
            title: "Keep trusted people close.",
            body: "Share selected context with trusted family, caregivers, or residence staff, with clear roles and purpose-specific access.",
            purpose: "Family sharing",
            symbol: "person.2.fill",
            tint: OneTheme.mint
        )
    ]

    private var pageIndex: Int {
        min(max(store.onboardingStep, 0), pages.count - 1)
    }

    private var page: OneOnboardingPage { pages[pageIndex] }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 40, 1), 520)

            VStack(spacing: 0) {
                onboardingHeader
                    .frame(width: contentWidth)
                    .frame(maxWidth: .infinity)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        OneOnboardingHero(page: page)
                            .padding(.top, 30)
                            .padding(.bottom, 22)
                            .id(pageIndex)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(page.eyebrow.uppercased())
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(page.tint)

                            Text(page.title)
                                .font(.system(size: 30, weight: .semibold, design: .default))
                                .tracking(-0.9)
                                .foregroundStyle(OneTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 7)

                            Text(page.body)
                                .font(.body)
                                .foregroundStyle(OneTheme.secondaryInk)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 9)
                        }

                        consentChoice
                            .padding(.top, 22)

                        if let message = validationMessage ?? store.authError {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(OneTheme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.top, 16)
                                .accessibilityAddTraits(.isStaticText)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    // Keep the final choice/error content scrollable above the
                    // fixed navigation footer on compact devices.
                    .padding(.bottom, 112)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: pageIndex)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                onboardingFooter(contentWidth: contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(
                        OneTheme.canvas
                            .opacity(0.98)
                            .ignoresSafeArea(edges: [.horizontal, .bottom])
                    )
            }
        }
        .background(OneBackground())
        .accessibilityElement(children: .contain)
        .onAppear {
            loadChoiceForCurrentPage()
        }
        .onChange(of: pageIndex) { _, _ in
            loadChoiceForCurrentPage()
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 10) {
            OneBrandMark(compact: true)

            Spacer()

            Text("SETUP \(pageIndex + 1) OF \(pages.count)")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ONE, setup step \(pageIndex + 1) of \(pages.count)")
    }

    private var consentChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose for this home")
                .font(.headline)
                .foregroundStyle(OneTheme.ink)

            Text("This choice only controls this purpose. Nothing starts until you choose.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            choiceButton(
                granted: true,
                title: "Allow",
                body: "Enable this purpose for your care circle."
            )
            choiceButton(
                granted: false,
                title: "Not now",
                body: "Keep this data source off for now."
            )
        }
        .padding(16)
        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.selection, trigger: selectedChoice)
    }

    private func choiceButton(granted: Bool, title: String, body: String) -> some View {
        let isSelected = selectedChoice == granted
        return Button {
            selectedChoice = granted
            store.onboardingConsents[page.purpose] = granted
            validationMessage = nil
            store.authError = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? page.tint : OneTheme.secondaryInk)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.ink)
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? page.tint.opacity(0.10) : OneTheme.controlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? page.tint.opacity(0.42) : OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(OnboardingChoiceButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selectedChoice)
        .accessibilityIdentifier(granted ? "onboarding-allow" : "onboarding-not-now")
        .accessibilityLabel("\(title). \(body)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func onboardingFooter(contentWidth: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.20))
                        .frame(width: index == pageIndex ? 24 : 7, height: 7)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pageIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(pageIndex + 1) of \(pages.count)")

            HStack(spacing: 12) {
                if pageIndex > 0 {
                    Button(action: goBack) {
                        Image(systemName: "arrow.left")
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(OneSecondaryButtonStyle())
                    .accessibilityIdentifier("onboarding-back")
                    .accessibilityLabel("Back")
                }

                Button(action: advance) {
                    HStack {
                        Text(isSaving ? "Saving…" : (pageIndex == pages.count - 1 ? "Finish setup" : "Continue"))
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: pageIndex == pages.count - 1 ? "checkmark" : "arrow.right")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(OnePrimaryButtonStyle())
                .disabled(isSaving || selectedChoice == nil)
                .accessibilityIdentifier("onboarding-continue")
            }
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 12)
    }

    private func advance() {
        guard !isSaving else { return }
        guard let selectedChoice else {
            validationMessage = "Choose Allow or Not now before continuing."
            return
        }
        let currentPage = page
        isSaving = true
        validationMessage = nil

        Task { @MainActor in
            let saved = await store.recordOnboardingConsent(for: currentPage.purpose, granted: selectedChoice)
            guard saved else {
                isSaving = false
                return
            }

            answeredPurposes.insert(currentPage.purpose)
            if pageIndex < pages.count - 1 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    store.onboardingStep += 1
                    self.selectedChoice = nil
                    validationMessage = nil
                }
            } else {
                guard store.completeOnboarding() else {
                    isSaving = false
                    return
                }
            }
            isSaving = false
        }
    }

    private func goBack() {
        guard !isSaving, pageIndex > 0 else { return }
        let previousPage = pages[pageIndex - 1]
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            store.onboardingStep -= 1
            selectedChoice = answeredPurposes.contains(previousPage.purpose) ? store.onboardingConsents[previousPage.purpose] : nil
        }
    }

    private func loadChoiceForCurrentPage() {
        selectedChoice = answeredPurposes.contains(page.purpose) ? store.onboardingConsents[page.purpose] : nil
        validationMessage = nil
    }
}

private struct OnboardingChoiceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct OneOnboardingPage {
    let eyebrow: String
    let title: String
    let body: String
    let purpose: String
    let symbol: String
    let tint: Color
}

private struct OneOnboardingHero: View {
    let page: OneOnboardingPage

    var body: some View {
        HStack {
            Image(systemName: page.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(page.tint)
                .frame(width: 68, height: 68)
                .background(page.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ONE onboarding illustration: \(page.title)")
    }
}
