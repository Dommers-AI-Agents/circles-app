import Foundation
import CommonCrypto

/// Tree hash of Chia/Cactus's standard wallet puzzle
/// (p2_delegated_puzzle_or_hidden_puzzle) curried with a synthetic public key
/// — i.e. `puzzle_hash_for_synthetic_pk`, the 32 bytes a receive address
/// encodes. Ported line-for-line from chia-blockchain's curry_and_treehash.py;
/// clvm tree hashing is sha256 with 0x01 (atom) / 0x02 (pair) prefixes.
enum StandardPuzzleHash {

    /// Tree hash of `(q . MOD)` for the standard puzzle — QUOTED_MOD_HASH,
    /// extracted from chia-blockchain (the MOD hash itself is
    /// e9aaa49f45bad5c889b86ee3341550c155cfdd10c3a6757de618d20612fffd52).
    static let quotedModHash: [UInt8] = [
        0x98, 0x90, 0xa9, 0xbd, 0x13, 0x30, 0xfc, 0x3c, 0x4f, 0x4a, 0xf0, 0xde,
        0x86, 0x42, 0xdc, 0x31, 0xb1, 0xd5, 0x25, 0xe2, 0xb1, 0x8e, 0x0f, 0xde,
        0x4e, 0xae, 0x07, 0x9a, 0xfb, 0x1b, 0x60, 0xa4
    ]

    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(bytes, CC_LONG(bytes.count), &digest)
        return digest
    }

    private static func shatreeAtom(_ atom: [UInt8]) -> [UInt8] { sha256([0x01] + atom) }
    private static func shatreePair(_ left: [UInt8], _ right: [UInt8]) -> [UInt8] {
        sha256([0x02] + left + right)
    }

    /// curry_and_treehash(QUOTED_MOD_HASH, shatree_atom(synthetic_pk)).
    /// The curry pattern is `(a (q . MOD) E)` with one curried argument:
    /// E = (c (q . pk) (1 . 0)).
    static func puzzleHash(syntheticPublicKey48: [UInt8]) -> [UInt8] {
        let qHash = shatreeAtom([0x01])      // quote keyword
        let aHash = shatreeAtom([0x02])      // apply keyword
        let cHash = shatreeAtom([0x04])      // cons keyword
        let nullHash = shatreeAtom([])       // nil
        let oneHash = shatreeAtom([0x01])    // terminal `1` of the env chain

        let curriedValues = shatreePair(
            cHash,
            shatreePair(
                shatreePair(qHash, shatreeAtom(syntheticPublicKey48)),
                shatreePair(oneHash, nullHash)))

        return shatreePair(
            aHash,
            shatreePair(quotedModHash, shatreePair(curriedValues, nullHash)))
    }
}
