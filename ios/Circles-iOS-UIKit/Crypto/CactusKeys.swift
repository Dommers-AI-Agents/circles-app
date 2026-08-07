import Foundation
import CommonCrypto

/// Key derivation for Cactus (Chia-family) wallets, on top of blst's audited
/// EIP-2333 implementation (exposed via the bridging header).
///
/// Pipeline (byte-identical to `cactus keys show`, verified against
/// cactus-blockchain source and chia-blockchain library ground truth):
///   seed → EIP-2333 master SK → hardened path m/12381/8444/2/0 → wallet SK
///   → G1 public key → synthetic public key (taproot-style offset by
///   sha256(pk ‖ DEFAULT_HIDDEN_PUZZLE_HASH), SIGNED clvm int semantics)
enum CactusKeys {

    /// m/12381/8444/2/<index> — 12381 = BLS spec, 8444 = "Cactus blockchain
    /// number" (kept from Chia; confirmed in cactus/wallet/derive_keys.py).
    static let walletPath: [UInt32] = [12381, 8444, 2]

    /// DEFAULT_HIDDEN_PUZZLE_HASH — the "(=)" unspendable hidden puzzle of
    /// p2_delegated_puzzle_or_hidden_puzzle (extracted from chia-blockchain).
    static let defaultHiddenPuzzleHash: [UInt8] = [
        0x71, 0x1d, 0x6c, 0x4e, 0x32, 0xc9, 0x2e, 0x53, 0x17, 0x9b, 0x19, 0x94,
        0x84, 0xcf, 0x8c, 0x89, 0x75, 0x42, 0xbc, 0x57, 0xf2, 0xb2, 0x25, 0x82,
        0x79, 0x9f, 0x9d, 0x65, 0x7e, 0xec, 0x46, 0x99
    ]

    /// 2^256 mod r for BLS12-381's group order r. Needed because chia derives
    /// the synthetic offset from a SIGNED 256-bit hash (clvm int_from_bytes):
    /// when the hash's top bit is set the value is hash − 2^256, so the offset
    /// point is G·hash − G·(2^256 mod r).
    static let twoTo256ModR: [UInt8] = [
        0x18, 0x24, 0xb1, 0x59, 0xac, 0xc5, 0x05, 0x6f, 0x99, 0x8c, 0x4f, 0xef,
        0xec, 0xbc, 0x4f, 0xf5, 0x58, 0x84, 0xb7, 0xfa, 0x00, 0x03, 0x48, 0x02,
        0x00, 0x00, 0x00, 0x01, 0xff, 0xff, 0xff, 0xfe
    ]

    /// Seed → wallet secret key at m/12381/8444/2/<index> (hardened, the
    /// derivation `cactus keys show` prints as the first wallet address).
    ///
    /// Chia-family derivation is EIP-2333's *structure* with IRTF BLS draft
    /// *v3* HKDF_mod_r semantics (salt hashed before first use) — that's
    /// blst_keygen_v3, and it differs from blst's final-spec EIP-2333
    /// functions (verified against library ground truth). So: master =
    /// keygen_v3(seed); each child = Lamport parent-key expansion (standard
    /// EIP-2333) finished with keygen_v3(lamport_pk).
    static func walletSecretKey(seed: [UInt8], index: UInt32) -> blst_scalar {
        var sk = blst_scalar()
        blst_keygen_v3(&sk, seed, seed.count, nil, 0)
        for step in walletPath + [index] {
            sk = deriveChild(parent: sk, index: step)
        }
        return sk
    }

    /// EIP-2333 IKM_to_lamport_SK + parent_SK_to_lamport_PK, finished with
    /// chia's v3 HKDF_mod_r. HKDF is SHA256-based (RFC 5869).
    private static func deriveChild(parent: blst_scalar, index: UInt32) -> blst_scalar {
        var parentCopy = parent
        var ikm = [UInt8](repeating: 0, count: 32)
        blst_bendian_from_scalar(&ikm, &parentCopy)
        let salt = [UInt8(index >> 24 & 0xff), UInt8(index >> 16 & 0xff),
                    UInt8(index >> 8 & 0xff), UInt8(index & 0xff)]

        // lamport_0 from the parent key, lamport_1 from its bitwise complement;
        // the lamport public key hashes each 32-byte chunk, then the lot.
        var digestInput: [UInt8] = []
        for keyMaterial in [ikm, ikm.map { ~$0 }] {
            let okm = hkdfSha256(salt: salt, ikm: keyMaterial, length: 255 * 32)
            for chunk in 0..<255 {
                digestInput += sha256(Array(okm[(chunk * 32)..<((chunk + 1) * 32)]))
            }
        }
        let lamportPk = sha256(digestInput)

        var child = blst_scalar()
        blst_keygen_v3(&child, lamportPk, lamportPk.count, nil, 0)
        return child
    }

    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(bytes, CC_LONG(bytes.count), &digest)
        return digest
    }

    /// RFC 5869 HKDF-SHA256 (extract with `salt`, expand with empty info).
    private static func hkdfSha256(salt: [UInt8], ikm: [UInt8], length: Int) -> [UInt8] {
        var prk = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), salt, salt.count, ikm, ikm.count, &prk)
        var okm: [UInt8] = []
        var block: [UInt8] = []
        var counter = 1  // RFC 5869 caps at 255 blocks; Int avoids a trap at the boundary
        while okm.count < length {
            let message = block + [UInt8(counter)]
            block = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), prk, prk.count, message, message.count, &block)
            okm += block
            counter += 1
        }
        return Array(okm[0..<length])
    }

    /// Compressed 48-byte G1 public key for a secret key.
    static func publicKey48(secretKey: blst_scalar) -> [UInt8] {
        var sk = secretKey
        var point = blst_p1()
        blst_sk_to_pk_in_g1(&point, &sk)
        var compressed = [UInt8](repeating: 0, count: 48)
        blst_p1_compress(&compressed, &point)
        return compressed
    }

    /// calculate_synthetic_public_key(pk, DEFAULT_HIDDEN_PUZZLE_HASH):
    /// synthetic = pk + G·offset, offset = signed(sha256(pk ‖ hph)) mod r.
    static func syntheticPublicKey48(publicKey48: [UInt8]) -> [UInt8]? {
        guard publicKey48.count == 48 else { return nil }

        var blob = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        var message = publicKey48 + defaultHiddenPuzzleHash
        CC_SHA256(&message, CC_LONG(message.count), &blob)

        // G · unsigned(blob) — blst_p1_mult takes a little-endian scalar and
        // multiplies mod r, so no explicit reduction is needed.
        var offsetPoint = blst_p1()
        blst_p1_mult(&offsetPoint, blst_p1_generator(), Array(blob.reversed()), 256)

        // Signed clvm semantics: top bit set means the value was negative by
        // 2^256 — subtract G·(2^256 mod r).
        if blob[0] & 0x80 != 0 {
            var correction = blst_p1()
            blst_p1_mult(&correction, blst_p1_generator(), Array(twoTo256ModR.reversed()), 256)
            blst_p1_cneg(&correction, true)
            var uncorrected = offsetPoint
            blst_p1_add_or_double(&offsetPoint, &uncorrected, &correction)
        }

        var pkAffine = blst_p1_affine()
        guard blst_p1_uncompress(&pkAffine, publicKey48) == BLST_SUCCESS else { return nil }
        var pkPoint = blst_p1()
        blst_p1_from_affine(&pkPoint, &pkAffine)

        var synthetic = blst_p1()
        blst_p1_add_or_double(&synthetic, &pkPoint, &offsetPoint)
        var compressed = [UInt8](repeating: 0, count: 48)
        blst_p1_compress(&compressed, &synthetic)
        return compressed
    }
}
