import AuthenticationServices
import CryptoKit
import UIKit

/// Result of a successful Sign in with Apple.
struct AppleCredential {
    let userID: String
    let idToken: String
    let rawNonce: String
    let fullName: String?
    let email: String?
}

enum AppleSignInError: Error { case invalidResponse }

/// Drives the native Sign in with Apple flow and returns the identity token +
/// the raw nonce, which is exactly what Supabase's `signInWithIdToken` needs.
/// The Apple part works with just the "Sign in with Apple" capability enabled;
/// completing the round-trip into Supabase also needs the Apple provider
/// configured in the dashboard.
@MainActor
final class AppleSignInCoordinator: NSObject, ObservableObject {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var currentNonce: String?

    func signIn() async throws -> AppleCredential {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)   // Apple gets the HASHED nonce

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: Nonce helpers

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for byte in randoms where remaining > 0 {
                if byte < UInt8(charset.count) {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { continuation = nil }
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            continuation?.resume(throwing: AppleSignInError.invalidResponse)
            return
        }
        let name = [cred.fullName?.givenName, cred.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        continuation?.resume(returning: AppleCredential(
            userID: cred.user,
            idToken: idToken,
            rawNonce: nonce,
            fullName: name.isEmpty ? nil : name,
            email: cred.email))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
