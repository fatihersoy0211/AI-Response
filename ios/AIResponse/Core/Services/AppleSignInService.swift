import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - Nonce utilities for Sign in with Apple

enum AppleSignInNonce {
    /// Cryptographically random nonce string used to prevent replay attacks.
    static func generate(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            fatalError("SecRandomCopyBytes failed: \(status)")
        }
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// SHA256 hex digest — sent to Apple as `request.nonce`.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// AppleCredentialValidity and credential state checking live in AppViewModel.swift
// to avoid cross-file resolution issues within the same module.
