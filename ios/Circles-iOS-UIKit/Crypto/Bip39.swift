import Foundation
import CommonCrypto

/// BIP39 mnemonic handling for Cactus wallet creation. Standard everywhere:
/// 256-bit entropy → 24 words (8-bit checksum), seed via PBKDF2-HMAC-SHA512
/// with salt "mnemonic" and 2048 iterations — verified against the published
/// BIP39 test vectors and chia-blockchain's implementation.
enum Bip39 {

    /// 32 bytes of entropy → 24-word mnemonic.
    static func mnemonic(fromEntropy entropy: [UInt8]) -> String? {
        guard entropy.count == 32 else { return nil }
        var checksum = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(entropy, CC_LONG(entropy.count), &checksum)

        // 256 entropy bits + 8 checksum bits = 264 bits = 24 × 11-bit indices.
        let bits = entropy + [checksum[0]]
        var words: [String] = []
        for wordIndex in 0..<24 {
            var value = 0
            for bit in (wordIndex * 11)..<((wordIndex + 1) * 11) {
                value = (value << 1) | Int((bits[bit / 8] >> (7 - UInt8(bit % 8))) & 1)
            }
            words.append(Bip39WordList.english[value])
        }
        return words.joined(separator: " ")
    }

    /// Checksum-validating decode; returns nil for anything malformed.
    static func isValid(mnemonic: String) -> Bool {
        let words = mnemonic.lowercased().split(separator: " ").map(String.init)
        guard words.count == 24 else { return false }
        var indices: [Int] = []
        for word in words {
            guard let index = Bip39WordList.english.firstIndex(of: word) else { return false }
            indices.append(index)
        }
        var bits = [UInt8](repeating: 0, count: 33)
        for (wordIndex, value) in indices.enumerated() {
            for offset in 0..<11 {
                let bit = wordIndex * 11 + offset
                if (value >> (10 - offset)) & 1 == 1 {
                    bits[bit / 8] |= 1 << (7 - UInt8(bit % 8))
                }
            }
        }
        let entropy = Array(bits[0..<32])
        var checksum = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(entropy, CC_LONG(entropy.count), &checksum)
        return checksum[0] == bits[32]
    }

    /// Mnemonic → 64-byte seed (PBKDF2-HMAC-SHA512, salt "mnemonic", 2048 rounds).
    static func seed(fromMnemonic mnemonic: String, passphrase: String = "") -> [UInt8] {
        let password = mnemonic.decomposedStringWithCompatibilityMapping
        let salt = Array(("mnemonic" + passphrase.decomposedStringWithCompatibilityMapping).utf8)
        var seed = [UInt8](repeating: 0, count: 64)
        _ = password.withCString { passwordPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordPtr, strlen(passwordPtr),
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                2048,
                &seed, seed.count)
        }
        return seed
    }
}
