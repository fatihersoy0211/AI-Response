import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var forgotEmail = ""
    @State private var showForgot = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.ColorToken.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                        // ── Header ────────────────────────────────────
                        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                            Text("AI-Meeting Assist")
                                .font(DS.Typography.title1)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Text("Secure sign in for your meeting workspace")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                        }

                        // ── Apple Sign In (standard, unmodified) ──────
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await appViewModel.handleAppleSignIn(result: result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        // ⚠️ Do NOT apply clipShape/cornerRadius — it breaks tap events

                        // ── Divider ───────────────────────────────────
                        HStack {
                            Rectangle()
                                .fill(DS.ColorToken.border)
                                .frame(height: 1)
                            Text("or continue with email")
                                .font(DS.Typography.micro)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .fixedSize()
                            Rectangle()
                                .fill(DS.ColorToken.border)
                                .frame(height: 1)
                        }

                        // ── Mode tabs ─────────────────────────────────
                        authSegment

                        // ── Fields ────────────────────────────────────
                        VStack(spacing: DS.Spacing.x12) {
                            if mode == .signUp {
                                DSInputField(title: "Full Name", text: $name)
                            }
                            DSInputField(title: "Work Email", text: $email, keyboard: .emailAddress)
                                .textInputAutocapitalization(.never)
                            if mode != .magicLink {
                                DSSecureInputField(title: "Password", text: $password)
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

                        // ── Error ─────────────────────────────────────
                        if let error = appViewModel.errorMessage {
                            HStack(spacing: DS.Spacing.x8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DS.ColorToken.error)
                                Text(error)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.ColorToken.error)
                            }
                        }

                        // ── Primary action ────────────────────────────
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
                                case .magicLink:
                                    appViewModel.errorMessage = "Magic link is not yet available."
                                }
                            }
                        }

                        if mode != .magicLink {
                            Button("Forgot password?") {
                                showForgot = true
                            }
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.primary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(DS.Spacing.x24)
                }
            }
            .sheet(isPresented: $showForgot) {
                forgotPasswordSheet
            }
        }
    }

    private var authSegment: some View {
        HStack(spacing: DS.Spacing.x8) {
            authPill(.signIn, title: "Sign In")
            authPill(.signUp, title: "Sign Up")
            authPill(.magicLink, title: "Magic Link")
        }
    }

    private func authPill(_ authMode: AuthMode, title: String) -> some View {
        Button(title) { mode = authMode }
            .font(DS.Typography.caption)
            .foregroundStyle(mode == authMode ? .white : DS.ColorToken.textSecondary)
            .padding(.horizontal, DS.Spacing.x12)
            .padding(.vertical, DS.Spacing.x8)
            .background(mode == authMode ? DS.ColorToken.primary : DS.ColorToken.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.ColorToken.border, lineWidth: mode == authMode ? 0 : 1))
    }

    private var primaryTitle: String {
        switch mode {
        case .signIn: return "Sign In"
        case .signUp: return "Create Account"
        case .magicLink: return "Send Magic Link"
        }
    }

    private var isPrimaryDisabled: Bool {
        switch mode {
        case .signIn: return email.isEmpty || password.isEmpty
        case .signUp: return name.isEmpty || email.isEmpty || password.isEmpty
        case .magicLink: return email.isEmpty
        }
    }

    private var forgotPasswordSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.x16) {
                Text("Forgot Password")
                    .font(DS.Typography.title2)
                Text("Enter your email and we will send reset instructions.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                DSInputField(title: "Email", text: $forgotEmail, keyboard: .emailAddress)
                DSButton(title: "Send Reset Link", kind: .primary) {
                    appViewModel.errorMessage = "Password reset is not yet available."
                    showForgot = false
                }
                Spacer()
            }
            .padding(DS.Spacing.x24)
            .background(DS.ColorToken.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showForgot = false }
                }
            }
        }
    }
}

private enum AuthMode {
    case signIn
    case signUp
    case magicLink
}

private struct DSInputField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
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

private struct DSSecureInputField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
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
