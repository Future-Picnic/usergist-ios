import Foundation
import CommonCrypto

/// Thin SHA-256 helper used to derive a safe directory name from the
/// caller's write key (so storage is namespaced without leaking secrets).
enum Hashing {
    /// Hex-encoded SHA-256 of `input`.
    static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Short (first 16 hex chars) SHA-256 — enough entropy to disambiguate
    /// write keys on a device without bloating paths.
    static func shortSha256(_ input: String) -> String {
        String(sha256Hex(input).prefix(16))
    }
}
