import SwiftUI

struct LoginView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var pairingCode = ""
    @State private var emailCode = LoginView.debugShowsEmailConfirmation ? "482701" : ""
    @State private var emailChallenge = LoginView.debugShowsEmailConfirmation
    @State private var isSubmitting = false
    @State private var mode = 0
    @State private var name = ""
    @State private var email = LoginView.debugShowsEmailConfirmation ? "you@example.com" : ""
    @State private var homeName = ""
    @State private var careSetting = "home"
    @State private var supportFocus = "mci"
    @State private var consent = false
    @State private var signInMethod: SignInMethod = .email
    @State private var validationMessage: String?
    @State private var stage: AuthStage = LoginView.debugShowsAuthForm ? .form : .welcome

    private enum Field: String, Hashable { case name, email, homeName, pairingCode, emailCode }
    private enum AuthStage { case welcome, form }
    private static var debugShowsEmailConfirmation: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-one-show-email-confirmation")
#else
        false
#endif
    }
    private static var debugShowsAuthForm: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(where: { $0 == "-one-show-auth-form" || $0 == "-one-show-email-confirmation" })
#else
        false
#endif
    }
    private enum SignInMethod: String, CaseIterable, Identifiable {
        case email, pairing

        var id: String { rawValue }
        var title: String {
            switch self {
            case .email: "Email code"
            case .pairing: "Pairing code"
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case 1: "Create a care space"
        case 2: "Join a care space"
        default: "Sign in"
        }
    }

    private var modeDescription: String {
        switch mode {
        case 1: "For a home or residence."
        case 2: "Enter the one-time invitation from a caregiver."
        default: "Use your email or a pairing code."
        }
    }

    private var actionTitle: String {
        if mode == 2 { return "Join care space" }
        if mode == 0 && signInMethod == .pairing { return "Open my home" }
        if emailChallenge { return "Verify with code" }
        return mode == 1 ? "Create care space" : "Email me a code"
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmailFlow: Bool { mode == 1 || (mode == 0 && signInMethod == .email) }

    private var canSubmit: Bool {
        if mode == 2 {
            return isSixDigitCode(pairingCode)
        }
        if mode == 0 && signInMethod == .pairing {
            return isSixDigitCode(pairingCode)
        }

        let hasEmail = !trimmedEmail.isEmpty
        let hasCode = isSixDigitCode(emailCode)
        if mode == 1 {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && hasEmail
                && consent
                && (!emailChallenge || hasCode)
        }
        return hasEmail && (!emailChallenge || hasCode)
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 40, 1), 520)

            ZStack {
                OneBackground()

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            authHeader
                            if stage == .welcome {
                                welcomeContent
                            } else {
                                formContent
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 22)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedField) { _, field in
                        guard let field else { return }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 160_000_000)
                            guard !Task.isCancelled, focusedField == field else { return }
                            withAnimation(reduceMotionAnimation) {
                                scrollProxy.scrollTo(field, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if stage == .form {
                    authFooter(contentWidth: contentWidth)
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
        }
        .task { await store.checkBackend() }
        .onChange(of: mode) { _, _ in
            emailChallenge = false
            emailCode = ""
            pairingCode = ""
            signInMethod = .email
            store.emailChallenge = nil
            store.authError = nil
            validationMessage = nil
        }
        .onChange(of: signInMethod) { _, _ in
            emailChallenge = false
            emailCode = ""
            pairingCode = ""
            store.emailChallenge = nil
            store.authError = nil
            validationMessage = nil
        }
        .animation(reduceMotionAnimation, value: stage)
        .animation(reduceMotionAnimation, value: emailChallenge)
    }

    private var reduceMotionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A calmer way to stay connected.")
                .font(.system(size: 38, weight: .semibold, design: .default))
                .tracking(-1.25)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 12) {
                Button {
                    openForm(mode: 0)
                } label: {
                    HStack {
                        Text("Sign in")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(OnePrimaryButtonStyle())
                .accessibilityIdentifier("auth-start-sign-in")

                Button {
                    openForm(mode: 1)
                } label: {
                    HStack {
                        Text("Create a home")
                        Spacer()
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(OneSecondaryButtonStyle())
                .accessibilityIdentifier("auth-start-create")

                Button {
                    openForm(mode: 2)
                } label: {
                    HStack {
                        Text("Join with invite")
                        Spacer()
                        Image(systemName: "person.2")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.secondaryInk)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth-start-join")
            }
            .padding(.top, 36)

            Label("Share only with the people and purposes you choose.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
        }
        .padding(.top, 74)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if emailChallenge {
                confirmationContent
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(modeTitle)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .tracking(-1.1)
                        .foregroundStyle(OneTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(modeDescription)
                        .font(.body)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                }
                .padding(.top, 24)

                if mode == 0 {
                    signInMethodPicker
                        .padding(.top, 24)
                }

                detailsSection
                    .padding(.top, 22)

                errorMessage
            }
        }
    }

    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiquidGlassSurface(radius: 18) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(OneTheme.accentBlue)
                    .frame(width: 62, height: 62)
                    .background(OneTheme.accentBlue.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text("CHECK YOUR EMAIL")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OneTheme.cyan)
                .padding(.top, 30)

            Text("Enter your code.")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .tracking(-1.1)
                .foregroundStyle(OneTheme.ink)
                .padding(.top, 7)

            emailVerificationCodeField
                .padding(.top, 28)

            Text("We sent a six-digit code to \(trimmedEmail). It expires shortly.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Button(action: resendEmailCode) {
                Text(isSubmitting ? "Sending…" : "Send a new code")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.accentBlue)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityIdentifier("auth-resend-code")
            .padding(.top, 6)

            errorMessage
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let message = validationMessage ?? store.authError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(OneTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(OneTheme.amber.opacity(0.18), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .padding(.top, 14)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var authHeader: some View {
        HStack {
            OneBrandMark(compact: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ONE")
    }

    private var signInMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIGN-IN METHOD")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(OneTheme.secondaryInk)

            LiquidGlassSurface(radius: 16) {
                HStack(spacing: 4) {
                    authOption("Email code", selected: signInMethod == .email, identifier: "auth-method-email") {
                        signInMethod = .email
                    }
                    authOption("Pairing code", selected: signInMethod == .pairing, identifier: "auth-method-pairing") {
                        signInMethod = .pairing
                    }
                }
                .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func authOption(_ title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? OneTheme.ink : OneTheme.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? OneTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == 2 ? "INVITATION DETAILS" : emailChallenge ? "VERIFICATION" : "YOUR DETAILS")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(OneTheme.secondaryInk)

            VStack(spacing: 12) {
                    if mode == 1 {
                        authField("Your name", systemImage: "person", text: $name, field: .name)
                            .textContentType(.name)
                        authField("Email", systemImage: "envelope", text: $email, field: .email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        authField("Care space name (optional)", systemImage: "house", text: $homeName, field: .homeName)
                            .textContentType(.organizationName)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Care setting")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OneTheme.secondaryInk)
                            Picker("Care setting", selection: $careSetting) {
                                Text("Private home").tag("home")
                                Text("Residence").tag("residence")
                            }
                            .pickerStyle(.segmented)
                            Text(careSetting == "residence" ? "A staffed or shared care setting." : "A private home and its care circle.")
                                .font(.caption)
                                .foregroundStyle(OneTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Support focus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OneTheme.secondaryInk)
                            Picker("Support focus", selection: $supportFocus) {
                                Text("MCI support").tag("mci")
                                Text("General").tag("general")
                            }
                            .pickerStyle(.segmented)
                            Text(supportFocus == "mci" ? "Check-ins for memory support; no diagnosis or clinical care." : "Everyday routines and check-ins.")
                                .font(.caption)
                                .foregroundStyle(OneTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if mode == 0 {
                        if signInMethod == .email {
                            authField("Email", systemImage: "envelope", text: $email, field: .email)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                            authInlineMessage
                        } else {
                            pairingCodeField
                            authInlineMessage
                        }
                    } else {
                        authField("Invitation code", systemImage: "number", text: $pairingCode, field: .pairingCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.numberPad)
                            .onChange(of: pairingCode) { _, value in
                                pairingCode = sanitizedCode(value)
                            }
                            .accessibilityLabel("Invitation code")
                        authInlineMessage
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
                            .onChange(of: emailCode) { _, value in
                                emailCode = sanitizedCode(value)
                            }
                            .accessibilityLabel("Email verification code")
                    }

                    if mode == 1 {
                        Toggle(isOn: $consent) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("I consent to ONE storing the care-space account data needed for this service.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(OneTheme.ink)
                                Text("You can review these choices during setup and later in Account.")
                                    .font(.caption)
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                        }
                        .tint(OneTheme.accentBlue)
                        .padding(.top, 4)
                        .onChange(of: consent) { _, _ in
                            validationMessage = nil
                            store.authError = nil
                        }
                    }
            }
        }
    }

    private var emailVerificationCodeField: some View {
        sixDigitCodeField(
            text: $emailCode,
            field: .emailCode,
            accessibilityLabel: "Email verification code",
            identifier: "auth-field-emailCode"
        )
    }

    private var pairingCodeField: some View {
        sixDigitCodeField(
            text: $pairingCode,
            field: .pairingCode,
            accessibilityLabel: "Six-digit pairing code",
            identifier: "auth-field-pairingCode"
        )
    }

    private func sixDigitCodeField(
        text: Binding<String>,
        field: Field,
        accessibilityLabel: String,
        identifier: String
    ) -> some View {
        LiquidGlassSurface(radius: 18) {
            ZStack {
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        verificationDigit(at: index, code: text.wrappedValue, field: field)
                            .padding(.trailing, index == 2 ? 12 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = field }

                TextField("", text: text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: field)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                    .onChange(of: text.wrappedValue) { _, value in
                        text.wrappedValue = sanitizedCode(value)
                        validationMessage = nil
                        store.authError = nil
                    }
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(text.wrappedValue.isEmpty ? "Empty" : "\(text.wrappedValue.count) of 6 digits entered")
                    .accessibilityIdentifier(identifier)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .frame(width: 250)
        .frame(minHeight: 66)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(focusedField == field ? OneTheme.accentBlue.opacity(0.62) : .white.opacity(0.28), lineWidth: focusedField == field ? 1.2 : 0.6)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .id(field)
    }

    private func verificationDigit(at index: Int, code: String, field: Field) -> some View {
        let digits = Array(code)
        let digit = index < digits.count ? String(digits[index]) : ""
        let activeIndex = min(code.count, 5)
        let isActive = focusedField == field && index == activeIndex

        return VStack(spacing: 6) {
            Text(digit.isEmpty ? "0" : digit)
                .font(.system(size: 25, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(digit.isEmpty ? OneTheme.secondaryInk.opacity(0.28) : OneTheme.ink)
                .frame(height: 32)

            Capsule()
                .fill(isActive ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(digit.isEmpty ? 0.22 : 0.55))
                .frame(width: 27, height: isActive ? 2.5 : 1.5)
        }
        .frame(width: 30, height: 52)
    }

    @ViewBuilder
    private var authInlineMessage: some View {
        if mode == 0 && signInMethod == .pairing {
            Text("Use the six-digit code from your ONE setup.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if mode == 0 && signInMethod == .email {
            Text("Sign in with a short-lived email code.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if mode == 2 {
            Text("Invitation codes are single-use.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func authFooter(contentWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Image(systemName: "arrow.left")
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(OneSecondaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth-back")
                .accessibilityLabel(emailChallenge ? "Change email" : "Back")

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
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(OnePrimaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityHint("Sign in securely to your ONE care space")
            }
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 12)
    }

    private func authField(_ title: String, systemImage: String, text: Binding<String>, field: Field) -> some View {
        LiquidGlassSurface(radius: 14) {
            ZStack(alignment: .leading) {
                TextField(title, text: text)
                    .textFieldStyle(.plain)
                    .padding(.leading, 48)
                    .padding(.trailing, 15)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .focused($focusedField, equals: field)
                    .submitLabel(field == .emailCode || field == .pairingCode ? .go : .next)
                    .onSubmit { focusNext(after: field) }
                    .onChange(of: text.wrappedValue) { _, _ in
                        validationMessage = nil
                        store.authError = nil
                    }

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.secondaryInk)
                    .frame(width: 20)
                    .padding(.leading, 15)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusedField == field ? OneTheme.accentBlue : .white.opacity(0.32), lineWidth: focusedField == field ? 1.35 : 0.65)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("auth-field-\(field.rawValue)")
        .id(field)
    }

    private func focusNext(after field: Field) {
        switch field {
        case .name: focusedField = mode == 1 ? .email : nil
        case .email:
            focusedField = emailChallenge ? .emailCode : (mode == 1 ? .homeName : nil)
        case .homeName: focusedField = nil
        case .pairingCode: submit()
        case .emailCode: submit()
        }
    }

    private func openForm(mode selectedMode: Int) {
        mode = selectedMode
        stage = .form
        focusedField = nil
    }

    private func goBack() {
        focusedField = nil
        validationMessage = nil
        store.authError = nil
        if emailChallenge {
            emailChallenge = false
            emailCode = ""
            store.emailChallenge = nil
        } else {
            stage = .welcome
        }
    }

    private func resendEmailCode() {
        guard !isSubmitting, !trimmedEmail.isEmpty else { return }
        isSubmitting = true
        validationMessage = nil
        store.authError = nil

        Task { @MainActor in
            _ = await store.requestEmailCode(
                email: email,
                purpose: mode == 1 ? "create" : "login",
                displayName: mode == 1 ? name : nil,
                homeName: homeName.isEmpty ? "ONE Home" : homeName,
                careSetting: mode == 1 ? careSetting : "home",
                supportFocus: mode == 1 ? supportFocus : "general"
            )
            applyDevelopmentCodeIfAvailable()
            isSubmitting = false
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        guard canSubmit else {
            validationMessage = formValidationMessage
            focusFirstInvalidField()
            return
        }
        focusedField = nil
        isSubmitting = true
        validationMessage = nil
        store.authError = nil

        Task { @MainActor in
            if mode == 0 && signInMethod == .pairing {
                await store.login(pairingCode: pairingCode)
            } else if mode == 2 {
                await store.acceptFamilyInvite(code: pairingCode, displayName: name.isEmpty ? nil : name, email: email.isEmpty ? nil : email)
            } else if emailChallenge {
                await store.login(email: email, code: emailCode)
            } else {
                if await store.requestEmailCode(email: email, purpose: mode == 1 ? "create" : "login", displayName: mode == 1 ? name : nil, homeName: homeName.isEmpty ? "ONE Home" : homeName, careSetting: mode == 1 ? careSetting : "home", supportFocus: mode == 1 ? supportFocus : "general") != nil {
                    emailChallenge = true
                    applyDevelopmentCodeIfAvailable()
                    if emailCode.isEmpty { focusedField = .emailCode }
                }
            }
            isSubmitting = false
        }
    }

    private var formValidationMessage: String {
        if mode == 2 || (mode == 0 && signInMethod == .pairing) {
            return "Enter the complete six-digit code to continue."
        }
        if mode == 1 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your name to create the care space."
        }
        if trimmedEmail.isEmpty {
            return "Enter your email address to continue."
        }
        if mode == 1 && !consent {
            return "Confirm the account data consent to continue."
        }
        return "Enter the complete six-digit verification code."
    }

    private func focusFirstInvalidField() {
        if mode == 2 || (mode == 0 && signInMethod == .pairing) {
            focusedField = .pairingCode
        } else if mode == 1 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedField = .name
        } else if trimmedEmail.isEmpty {
            focusedField = .email
        } else if emailChallenge && !isSixDigitCode(emailCode) {
            focusedField = .emailCode
        }
    }

    private func isSixDigitCode(_ value: String) -> Bool {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.count == 6 && code.allSatisfy(\.isNumber)
    }

    private func sanitizedCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(6))
    }

    private func applyDevelopmentCodeIfAvailable() {
#if DEBUG
        guard let challenge = store.emailChallenge,
              challenge.delivery == "development_outbox",
              let devCode = challenge.devCode,
              isSixDigitCode(devCode) else { return }
        emailCode = sanitizedCode(devCode)
        focusedField = nil
#endif
    }
}
