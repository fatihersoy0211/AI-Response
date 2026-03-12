import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var currentNonce: String?

    @State private var showForgotPassword = false
    @State private var showEmailVerification = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.ColorToken.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.x24) {

                        // ── Header ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                            Text("AI-Meeting Assist")
                                .font(DS.Typography.title1)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Text("Secure sign in for your meeting workspace")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        }

                        // ── Apple Sign In ────────────────────────────────
                        // A fresh nonce is generated on each tap; SHA256 is sent to Apple
                        // so the backend can verify the JWT nonce claim (replay-attack prevention).
                        SignInWithAppleButton(.signIn) { request in
                            let nonce = AppleSignInNonce.generate()
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AppleSignInNonce.sha256(nonce)
                        } onCompletion: { result in
                            Task {
                                await appViewModel.handleAppleSignIn(result: result, nonce: currentNonce)
                                currentNonce = nil
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        // ⚠️ Do NOT apply clipShape/cornerRadius — it breaks tap events on the native button

                        // ── Divider ─────────────────────────────────────
                        HStack {
                            Rectangle().fill(DS.ColorToken.border).frame(height: 1)
                            Text("or continue with email")
                                .font(DS.Typography.micro)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .fixedSize()
                            Rectangle().fill(DS.ColorToken.border).frame(height: 1)
                        }

                        // ── Mode tabs ────────────────────────────────────
                        HStack(spacing: DS.Spacing.x8) {
                            authPill(.signIn, title: "Sign In")
                            authPill(.signUp, title: "Sign Up")
                        }

                        // ── Fields ───────────────────────────────────────
                        VStack(spacing: DS.Spacing.x12) {
                            if mode == .signUp {
                                LoginInputField(title: "Full Name", text: $name)
                            }
                            LoginInputField(title: "Email", text: $email, keyboard: .emailAddress)
                                .textInputAutocapitalization(.never)
                            LoginSecureField(title: "Password", text: $password)

                            // Password requirements (sign-up only)
                            if mode == .signUp {
                                HStack(spacing: DS.Spacing.x8) {
                                    requirementBadge("8+ characters", met: password.count >= 8)
                                    requirementBadge("Letter", met: password.contains(where: { $0.isLetter }))
                                    requirementBadge("Number", met: password.contains(where: { $0.isNumber }))
                                }
                            }
                        }
                        .padding(DS.Spacing.x16)
                        .background(DS.ColorToken.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.ColorToken.border, lineWidth: 1)
                        )
                        .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: 0, y: 4)

                        // ── Error ────────────────────────────────────────
                        if let error = appViewModel.errorMessage {
                            HStack(spacing: DS.Spacing.x8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DS.ColorToken.error)
                                Text(error)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.ColorToken.error)
                            }
                        }

                        // ── Primary button ───────────────────────────────
                        DSButton(
                            title: primaryTitle,
                            kind: .primary,
                            isLoading: appViewModel.isLoading,
                            isDisabled: isPrimaryDisabled
                        ) {
                            Task {
                                switch mode {
                                case .signIn:
                                    await appViewModel.login(email: email, password: password)
                                case .signUp:
                                    await appViewModel.register(name: name, email: email, password: password)
                                    if appViewModel.pendingVerificationEmail != nil {
                                        showEmailVerification = true
                                    }
                                }
                            }
                        }

                        // ── Forgot Password (sign-in only) ────────────────
                        if mode == .signIn {
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    appViewModel.errorMessage = nil
                                    showForgotPassword = true
                                }
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.ColorToken.primary)
                            }
                        }
                    }
                    .padding(DS.Spacing.x24)
                }
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet()
        }
        .sheet(isPresented: $showEmailVerification, onDismiss: {
            // If the sheet is dismissed without verifying, clear the pending state
            // so the user can try again.
        }) {
            EmailVerificationSheet(
                email: appViewModel.pendingVerificationEmail ?? email
            )
        }
        .onChange(of: appViewModel.pendingVerificationEmail) { _, newValue in
            if newValue != nil { showEmailVerification = true }
        }
    }

    // MARK: - Helpers

    private func requirementBadge(_ label: String, met: Bool) -> some View {
        HStack(spacing: DS.Spacing.x4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(met ? DS.ColorToken.success : DS.ColorToken.textTertiary)
            Text(label)
                .font(DS.Typography.micro)
                .foregroundStyle(met ? DS.ColorToken.success : DS.ColorToken.textTertiary)
        }
    }

    private func authPill(_ authMode: AuthMode, title: String) -> some View {
        Button(title) {
            mode = authMode
            appViewModel.errorMessage = nil
        }
        .font(DS.Typography.caption)
        .foregroundStyle(mode == authMode ? .white : DS.ColorToken.textSecondary)
        .padding(.horizontal, DS.Spacing.x12)
        .padding(.vertical, DS.Spacing.x8)
        .background(mode == authMode ? DS.ColorToken.primary : DS.ColorToken.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.ColorToken.border, lineWidth: mode == authMode ? 0 : 1))
    }

    private var primaryTitle: String { mode == .signIn ? "Sign In" : "Create Account" }

    private var isPrimaryDisabled: Bool {
        switch mode {
        case .signIn:
            return email.isEmpty || password.isEmpty
        case .signUp:
            return name.isEmpty || email.isEmpty
                || password.count < 8
                || !password.contains(where: { $0.isLetter })
                || !password.contains(where: { $0.isNumber })
        }
    }
}

// MARK: - Auth Mode

private enum AuthMode { case signIn, signUp }

// MARK: - Forgot Password Sheet

private struct ForgotPasswordSheet: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: ForgotStep = .enterEmail
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var mismatchError = false

    enum ForgotStep { case enterEmail, enterCode }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                    switch step {
                    case .enterEmail: enterEmailView
                    case .enterCode:  enterCodeView
                    }
                }
                .padding(DS.Spacing.x24)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var enterEmailView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x16) {
            Text("Enter your account email address and we will send a 6-digit reset code.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textSecondary)

            bareField(title: "Email", text: $email, keyboard: .emailAddress)

            errorRow

            DSButton(
                title: "Send Reset Code",
                kind: .primary,
                isLoading: appViewModel.isLoading,
                isDisabled: email.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                appViewModel.errorMessage = nil
                Task {
                    await appViewModel.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))
                    if appViewModel.errorMessage == nil { step = .enterCode }
                }
            }
        }
    }

    private var enterCodeView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x16) {
            Text("Enter the 6-digit code sent to **\(email)** and choose a new password.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textSecondary)

            bareField(title: "6-Digit Code", text: $code, keyboard: .numberPad)
            LoginSecureField(title: "New Password", text: $newPassword)
            LoginSecureField(title: "Confirm Password", text: $confirmPassword)

            // Requirements
            HStack(spacing: DS.Spacing.x8) {
                reqBadge("8+ chars", met: newPassword.count >= 8)
                reqBadge("Letter",   met: newPassword.contains(where: { $0.isLetter }))
                reqBadge("Number",   met: newPassword.contains(where: { $0.isNumber }))
            }

            if mismatchError {
                Text("Passwords do not match.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.error)
            }
            errorRow

            DSButton(
                title: "Reset Password",
                kind: .primary,
                isLoading: appViewModel.isLoading,
                isDisabled: code.count != 6 || newPassword.count < 8 || newPassword != confirmPassword
            ) {
                mismatchError = false
                appViewModel.errorMessage = nil
                guard newPassword == confirmPassword else { mismatchError = true; return }
                Task {
                    await appViewModel.verifyReset(
                        email: email.trimmingCharacters(in: .whitespaces),
                        code: code,
                        newPassword: newPassword
                    )
                    if appViewModel.errorMessage == nil { dismiss() }
                }
            }

            Button("Resend Code") {
                Task { await appViewModel.forgotPassword(email: email.trimmingCharacters(in: .whitespaces)) }
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.ColorToken.primary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var errorRow: some View {
        Group {
            if let error = appViewModel.errorMessage {
                HStack(spacing: DS.Spacing.x8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.ColorToken.error)
                    Text(error).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.error)
                }
            }
        }
    }

    private func reqBadge(_ label: String, met: Bool) -> some View {
        HStack(spacing: DS.Spacing.x4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(met ? DS.ColorToken.success : DS.ColorToken.textTertiary)
            Text(label).font(DS.Typography.micro)
                .foregroundStyle(met ? DS.ColorToken.success : DS.ColorToken.textTertiary)
        }
    }

    private func bareField(title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, DS.Spacing.x12)
                .padding(.vertical, DS.Spacing.x12)
                .background(DS.ColorToken.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Email Verification Sheet

struct EmailVerificationSheet: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    let email: String

    @State private var code = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                    VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                        Text("Check your email")
                            .font(DS.Typography.title2)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Text("A 6-digit verification code was sent to **\(email)**. Enter it below to activate your account.")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                        Text("Verification Code")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.x12)
                            .padding(.vertical, DS.Spacing.x16)
                            .background(DS.ColorToken.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(
                                        code.count == 6 ? DS.ColorToken.primary : DS.ColorToken.border,
                                        lineWidth: code.count == 6 ? 2 : 1
                                    )
                            )
                            .onChange(of: code) { _, new in
                                code = String(new.filter { $0.isNumber }.prefix(6))
                            }
                    }

                    if let error = appViewModel.errorMessage {
                        HStack(spacing: DS.Spacing.x8) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.ColorToken.error)
                            Text(error).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.error)
                        }
                    }

                    DSButton(
                        title: "Verify Email",
                        kind: .primary,
                        isLoading: appViewModel.isLoading,
                        isDisabled: code.count != 6
                    ) {
                        Task { await appViewModel.verifyEmail(email: email, code: code) }
                    }

                    Button("Resend Code") {
                        appViewModel.errorMessage = nil
                        Task { await appViewModel.forgotPassword(email: email) }
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(DS.Spacing.x24)
            }
            .background(DS.ColorToken.canvas)
            .navigationTitle("Verify Email")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }
}

// MARK: - Local field components

private struct LoginInputField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary)
            TextField(title, text: $text)
                .keyboardType(keyboard)
                .padding(.horizontal, DS.Spacing.x12)
                .padding(.vertical, DS.Spacing.x12)
                .background(DS.ColorToken.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
        }
    }
}

private struct LoginSecureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary)
            SecureField(title, text: $text)
                .padding(.horizontal, DS.Spacing.x12)
                .padding(.vertical, DS.Spacing.x12)
                .background(DS.ColorToken.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
        }
    }
}
