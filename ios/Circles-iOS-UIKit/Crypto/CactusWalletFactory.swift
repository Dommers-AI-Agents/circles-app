import Foundation
import Security

/// One-tap Cactus wallet creation, entirely on-device — FavCircles' servers
/// never see the secret phrase. The pipeline below is byte-identical to
/// `cactus keys show` (vector-tested against chia-blockchain's library code,
/// then proven with a real on-chain spend before release):
///
///   entropy → BIP39 mnemonic → seed → EIP-2333 m/12381/8444/2/0
///   → synthetic pubkey → standard puzzle hash → bech32m "cac1…"
struct CactusWallet {
    let mnemonic: String   // 24 words — the wallet itself; user-owned secret
    let address: String    // first wallet receive address (cac1…)
}

enum CactusWalletFactory {

    /// Create a brand-new wallet from system entropy. Returns nil only if the
    /// secure RNG fails (never silently falls back to weak entropy).
    static func generate() -> CactusWallet? {
        var entropy = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy) == errSecSuccess,
              let mnemonic = Bip39.mnemonic(fromEntropy: entropy) else { return nil }
        return derive(mnemonic: mnemonic)
    }

    /// Recompute the first wallet address for an existing mnemonic (used to
    /// re-verify a stored phrase still matches the linked address).
    static func derive(mnemonic: String) -> CactusWallet? {
        guard Bip39.isValid(mnemonic: mnemonic) else { return nil }
        let seed = Bip39.seed(fromMnemonic: mnemonic)
        let walletKey = CactusKeys.walletSecretKey(seed: seed, index: 0)
        let publicKey = CactusKeys.publicKey48(secretKey: walletKey)
        guard let syntheticKey = CactusKeys.syntheticPublicKey48(publicKey48: publicKey) else {
            return nil
        }
        let puzzleHash = StandardPuzzleHash.puzzleHash(syntheticPublicKey48: syntheticKey)
        return CactusWallet(mnemonic: mnemonic, address: Bech32m.encode(puzzleHash: puzzleHash))
    }
}
