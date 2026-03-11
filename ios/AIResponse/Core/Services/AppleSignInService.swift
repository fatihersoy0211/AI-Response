import AuthenticationServices
import Foundation

// AppleSignInService is retained for future use.
// The primary Apple auth flow is handled via SignInWithAppleButton's onCompletion
// in LoginView → AppViewModel.handleAppleSignIn(result:).
// AppleCredential and AppleSignInError are defined in Models.swift.
