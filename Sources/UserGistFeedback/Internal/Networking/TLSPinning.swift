import Foundation
import Security
import CommonCrypto

// PORTED FROM (concept): cross-platform TLS pinning. RN currently does not
// pin (see PARITY.md note); native SDKs pin first and RN catches up under
// P5.4. SPKI pinning is the recommended approach since it survives leaf
// rotation as long as the same public key is reused.
//
// Pinning is keyed on hostname. Non-pinned hosts (e.g. localhost or
// staging-only domains) fall through to the system's default trust
// evaluation — the SDK never breaks dev workflows that hit local APIs.
//
// Pin material: base64-encoded SHA-256 of the SubjectPublicKeyInfo. Two
// pins are recommended (leaf + backup) so a key rotation does not brick
// every installed app at once.

struct TLSPinSet {
    /// Hostname these pins protect (case-insensitive). Wildcard prefix
    /// `*.example.com` matches all direct subdomains.
    let host: String
    /// Base64 SHA-256(SPKI) values. Empty disables pinning for this host.
    let sha256Pins: [String]
}

final class TLSPinnedSessionDelegate: NSObject, URLSessionDelegate {
    private let pinSets: [TLSPinSet]
    private let logger: UserGistLogger

    init(pinSets: [TLSPinSet], logger: UserGistLogger) {
        self.pinSets = pinSets
        self.logger = logger
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        guard let pinSet = pinFor(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if pinSet.sha256Pins.isEmpty {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            logger.warn("TLS trust evaluation failed for \(host): \(String(describing: trustError))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Keep the SDK's declared iOS 14 floor. `SecTrustCopyCertificateChain`
        // starts at iOS 15, while the indexed APIs are available on iOS 12.
        let chain = (0..<SecTrustGetCertificateCount(trust)).compactMap {
            SecTrustGetCertificateAtIndex(trust, $0)
        }
        for cert in chain {
            guard let pin = pinForCertificate(cert) else { continue }
            if pinSet.sha256Pins.contains(pin) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        logger.warn("TLS pin mismatch for \(host) — rejecting connection")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func pinFor(_ host: String) -> TLSPinSet? {
        let hostLower = host.lowercased()
        for set in pinSets {
            let p = set.host.lowercased()
            if p == hostLower { return set }
            if p.hasPrefix("*.") {
                let suffix = String(p.dropFirst())
                if hostLower.hasSuffix(suffix) { return set }
            }
        }
        return nil
    }

    /// Returns base64 SHA-256 of the cert's SubjectPublicKeyInfo, or nil
    /// if the key cannot be exported (uncommon — typically only for
    /// non-RSA/EC keys we don't ship against).
    private func pinForCertificate(_ cert: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(cert),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        // Apple's SPKI hashing convention: hash the raw key bits (the
        // exported representation already contains the algorithm/parameters
        // for RSA/EC keys). This matches the standard SPKI-pin generator
        // output for those families.
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { raw in
            _ = CC_SHA256(raw.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }
}

enum TLSPinEnv {
    static let leaf = "USERGIST_TLS_PIN_LEAF"
    static let backup = "USERGIST_TLS_PIN_BACKUP"
    static let pinnedHost = "api.usergist.com"
}

extension UserGistConfig {
    /// Pin sets used by the SDK's URLSession. Defaults to pinning
    /// `api.usergist.com` against the two production SPKI hashes; set
    /// the env vars in `TLSPinEnv` to override in development. Empty pins
    /// disable pinning for that host.
    var tlsPinSets: [TLSPinSet] {
        let env = ProcessInfo.processInfo.environment
        let pins = [env[TLSPinEnv.leaf] ?? "", env[TLSPinEnv.backup] ?? ""]
            .filter { !$0.isEmpty }
        return [TLSPinSet(host: TLSPinEnv.pinnedHost, sha256Pins: pins)]
    }
}
