import Foundation

/// Bech32m encoding (BIP-350) of 32-byte puzzle hashes into Cactus addresses
/// (HRP "cac"). Matches chia/util/bech32m.py.
enum Bech32m {

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    private static let bech32mConst: UInt32 = 0x2bc830a3

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 {
                checksum ^= generator[i]
            }
        }
        return checksum
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let scalars = Array(hrp.unicodeScalars)
        return scalars.map { UInt8($0.value >> 5) } + [0] + scalars.map { UInt8($0.value & 31) }
    }

    /// Regroup 8-bit bytes into 5-bit groups, padding the tail (BIP-173).
    private static func convertBits(_ data: [UInt8], from: Int, to: Int) -> [UInt8] {
        var accumulator = 0, bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << to) - 1
        for byte in data {
            accumulator = (accumulator << from) | Int(byte)
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if bits > 0 { result.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        return result
    }

    /// 32-byte puzzle hash → "cac1…" address.
    static func encode(puzzleHash: [UInt8], hrp: String = "cac") -> String {
        let data = convertBits(puzzleHash, from: 8, to: 5)
        let checksumInput = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymodValue = polymod(checksumInput) ^ bech32mConst
        let checksum = (0..<6).map { UInt8((polymodValue >> (5 * (5 - UInt32($0)))) & 31) }
        return hrp + "1" + String((data + checksum).map { charset[Int($0)] })
    }
}
