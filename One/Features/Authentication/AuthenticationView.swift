import SwiftUI

struct LoginView: View {
    @Bindable var store: AppStore

    @FocusState private var focusedField: Field?
    @State private var pairingCode = ""
    @State private var emailCode = ""
    @State private var emailChallenge = false
    @State private var isSubmitting = false
    @State private var mode = 0
    @State private var name = ""
    @State private var email = ""
    @State private var homeName = ""
    @State private var consent = false

    private enum Field: Hashable { case name, email, homeName, pairingCode, emailCode }

    private var modeTitle: String {
        switch mode {
        case 1: "Create a household."
        case 2: "Join a household."
        default: "Sign in to your home."
        }
    }

    private var modeDescription: String {
        switch mode {
        case 1: "Start with an account for the people you trust."
        case 2: "Enter the one-time invitation from a caregiver."
        default: "Use the email tied to your household. We’ll send a one-time code."
        }
    }

    private var actionTitle: String {
        if mode == 2 { return "Join household" }
        if emailChallenge { return "Verify with code" }
        return mode == 1 ? "Create household" : "Email me a code"
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmailFlow: Bool { mode == 0 || mode == 1 }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        if mode == 2 {
            return pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
        }

        let hasEmail = !trimmedEmail.isEmpty
        let hasCode = !emailCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if mode == 1 {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && hasEmail
                && consent
                && (!emailChallenge || hasCode)
        }
        return hasEmail && (!emailChallenge || hasCode)
    }

    var body: some View {
        ZStack {
            OneBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    authHeader
                    authHero
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode == 2 ? "HOUSEHOLD ACCESS" : "WELCOME TO ONE")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(OneTheme.cyan)
                        Text(modeTitle)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .tracking(-0.8)
                            .foregroundStyle(OneTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(modeDescription)
                            .font(.title3)
                            .foregroundStyle(OneTheme.secondaryInk)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 5)
                    }
                    .padding(.top, 24)

                    modePicker
                        .padding(.top, 22)
                    detailsSection
                        .padding(.top, 14)

                    if let authError = store.authError {
                        Label(authError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(OneTheme.amber.opacity(0.18), lineWidth: 0.75) }
                            .padding(.top, 14)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    Text("ONE keeps household access purpose-specific. Camera pairing and live viewing stay separate from your account.")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            authFooter
        }
        .task { await store.checkBackend() }
        .onChange(of: mode) { _, _ in
            emailChallenge = false
            emailCode = ""
            pairingCode = ""
            store.emailChallenge = nil
            store.authError = nil
        }
    }

    private var authHeader: some View {
        HStack(spacing: 10) {
            Label("ONE", systemImage: "waveform.circle.fill")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(OneTheme.accentBlue)

            Spacer()

            Text(connectionLabel)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(OneTheme.surface, in: Capsule())
                .overlay { Capsule().stroke(OneTheme.secondaryInk.opacity(0.16), lineWidth: 0.75) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ONE, \(connectionLabel.lowercased())")
    }

    private var connectionLabel: String {
        switch store.backendState {
        case .connected: "API READY"
        case .checking: "CONNECTING"
        case .unavailable: "OFFLINE"
        case .demo: "PREVIEW"
        }
    }

    private var authHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: [OneTheme.inverseSurface, OneTheme.accentBlue.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))

            OneAuthRouteArtwork(tint: OneTheme.accentCyan)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            Circle()
                .fill(OneTheme.accentCyan.opacity(0.14))
                .frame(width: 148, height: 148)
            Circle()
                .stroke(OneTheme.accentCyan.opacity(0.26), lineWidth: 1)
                .frame(width: 188, height: 188)

            Image(systemName: mode == 1 ? "house.and.flag.fill" : mode == 2 ? "person.2.fill" : "lock.shield.fill")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(OneTheme.accentCyan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading) {
                HStack {
                    Label("CONSENTED HOUSEHOLD", systemImage: "lock.shield.fill")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.86))
                    Spacer()
                }
                Spacer()
                Text("A calmer way to stay connected.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 218)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ONE secure household access")
    }

    private var modePicker: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ACCOUNT ACTION")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(OneTheme.secondaryInk)
                Picker("Account action", selection: $mode) {
                    Text("Sign in").tag(0)
                    Text("Create").tag(1)
                    Text("Join").tag(2)
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == 2 ? "INVITATION DETAILS" : emailChallenge ? "VERIFICATION" : "YOUR DETAILS")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(OneTheme.secondaryInk)

            SurfaceCard(radius: 24) {
                VStack(spacing: 12) {
                    if mode == 1 {
                        authField("Your name", systemImage: "person", text: $name, field: .name)
                            .textContentType(.name)
                        authField("Email", systemImage: "envelope", text: $email, field: .email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        authField("Household name (optional)", systemImage: "house", text: $homeName, field: .homeName)
                            .textContentType(.organizationName)
                    } else if mode == 0 {
                        authField("Email", systemImage: "envelope", text: $email, field: .email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                    } else {
                        authField("Invitation code", systemImage: "number", text: $pairingCode, field: .pairingCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Invitation code")
                        authField("Invited email (optional)", systemImage: "envelope", text: $email, field: .email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        authField("Your name (optional)", systemImage: "person", text: $name, field: .name)
                            .textContentType(.name)
                    }

                    if isEmailFlow && emailChallenge {
                        authField("Verification code", systemImage: "number", text: $emailCode, field: .emailCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .accessibilityLabel("Email verification code")

                        verificationNote
                    }

                    if mode == 1 {
                        Toggle(isOn: $consent) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("I consent to ONE storing the household account data needed for this service.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(OneTheme.ink)
                                Text("You can review these choices during setup and later in Account.")
                                    .font(.caption)
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                        }
                        .tint(OneTheme.accentBlue)
                        .padding(.top, 4)
                    }
                }
                .padding(14)
            }
        }
    }

    private var verificationNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Code requested", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneTheme.mint)
            if let challenge = store.emailChallenge, challenge.delivery == "development_outbox", let devCode = challenge.devCode {
                Text("Local development code: \(devCode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OneTheme.secondaryInk)
            } else {
                Text("Check the email address tied to this household for the six-digit code.")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(OneTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var authFooter: some View {
        VStack(spacing: 8) {
            Button(action: submit) {
                HStack {
                    Text(isSubmitting ? "Working…" : actionTitle)
                    Spacer()
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
            }
            .buttonStyle(OnePrimaryButtonStyle())
            .disabled(!canSubmit)
            .accessibilityHint("Account access is protected by a short-lived backend session")

            Text(emailChallenge ? "Enter the code sent to your email." : mode == 2 ? "Invitation codes are single-use." : "No password required. ONE uses a short-lived email code.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(OneTheme.secondaryInk.opacity(0.12)).frame(height: 0.5) }
    }

    private func authField(_ title: String, systemImage: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneTheme.secondaryInk)
                .frame(width: 20)
            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .submitLabel(field == .emailCode || field == .pairingCode ? .go : .next)
                .onSubmit { focusNext(after: field) }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 54)
        .background(OneTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OneTheme.secondaryInk.opacity(0.16), lineWidth: 0.75) }
    }

    private func focusNext(after field: Field) {
        switch field {
        case .name: focusedField = mode == 1 ? .email : nil
        case .email: focusedField = mode == 1 ? .homeName : nil
        case .homeName, .pairingCode: focusedField = nil
        case .emailCode: submit()
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true

        Task { @MainActor in
            if mode == 2 {
                await store.acceptFamilyInvite(code: pairingCode, displayName: name.isEmpty ? nil : name, email: email.isEmpty ? nil : email)
            } else if emailChallenge {
                await store.login(email: email, code: emailCode)
            } else {
                if await store.requestEmailCode(email: email, purpose: mode == 1 ? "create" : "login", displayName: mode == 1 ? name : nil, homeName: homeName.isEmpty ? "ONE Home" : homeName) != nil {
                    emailChallenge = true
                }
            }
            isSubmitting = false
        }
    }
}

private struct OneAuthRouteArtwork: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.04, y: size.height * 0.80))
            route.addCurve(
                to: CGPoint(x: size.width * 0.44, y: size.height * 0.40),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.77),
                control2: CGPoint(x: size.width * 0.24, y: size.height * 0.34)
            )
            route.addCurve(
                to: CGPoint(x: size.width * 0.98, y: size.height * 0.18),
                control1: CGPoint(x: size.width * 0.62, y: size.height * 0.52),
                control2: CGPoint(x: size.width * 0.80, y: size.height * 0.14)
            )
            context.stroke(route, with: .color(tint.opacity(0.26)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            var echo = Path()
            echo.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.98))
            echo.addCurve(
                to: CGPoint(x: size.width * 0.90, y: size.height * 0.58),
                control1: CGPoint(x: size.width * 0.36, y: size.height * 0.92),
                control2: CGPoint(x: size.width * 0.60, y: size.height * 0.68)
            )
            context.stroke(echo, with: .color(tint.opacity(0.14)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 7]))
        }
        .allowsHitTesting(false)
    }
}
