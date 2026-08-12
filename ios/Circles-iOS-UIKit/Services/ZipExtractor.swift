import Foundation
import Compression

/// Minimal ZIP reader for import files — Mapstr and Google Takeout both
/// deliver their exports zipped, and making users extract archives in the
/// Files app before importing is a silent flow-killer. Parses the central
/// directory and handles stored + deflated entries via the Compression
/// framework; no third-party dependency.
///
/// Deliberately not a general unzipper: no zip64, no encryption, no
/// streaming (export archives are small standard zips; anything exotic just
/// yields no entries and the caller reports an unreadable file).
enum ZipExtractor {

    struct Entry {
        let filename: String
        let data: Data
    }

    static func extract(_ archive: Data) -> [Entry] {
        guard archive.count > 22 else { return [] }

        func u16(_ offset: Int) -> Int { Int(archive[offset]) | Int(archive[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }

        // End-of-central-directory record: scan backwards for PK\x05\x06
        // (up to 64KB of trailing comment is legal)
        var eocdOffset = -1
        let scanFloor = max(0, archive.count - 66_000)
        var i = archive.count - 22
        while i >= scanFloor {
            if archive[i] == 0x50, archive[i + 1] == 0x4B,
               archive[i + 2] == 0x05, archive[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { return [] }

        let entryCount = u16(eocdOffset + 10)
        var cursor = u32(eocdOffset + 16)
        var entries: [Entry] = []

        for _ in 0..<entryCount {
            guard cursor + 46 <= archive.count,
                  archive[cursor] == 0x50, archive[cursor + 1] == 0x4B,
                  archive[cursor + 2] == 0x01, archive[cursor + 3] == 0x02 else { break }

            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let uncompressedSize = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localHeaderOffset = u32(cursor + 42)
            let nameData = archive.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let fullName = String(data: nameData, encoding: .utf8) ?? ""
            cursor += 46 + nameLength + extraLength + commentLength

            // Skip directories, empty entries, and macOS resource-fork noise
            let baseName = (fullName as NSString).lastPathComponent
            guard !fullName.hasSuffix("/"), compressedSize > 0,
                  !baseName.hasPrefix("._"), !fullName.hasPrefix("__MACOSX") else { continue }

            // Data sits after the LOCAL header (whose name/extra lengths can
            // differ from the central record's)
            guard localHeaderOffset + 30 <= archive.count else { continue }
            let localNameLength = u16(localHeaderOffset + 26)
            let localExtraLength = u16(localHeaderOffset + 28)
            let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= archive.count else { continue }
            let compressed = archive.subdata(in: dataStart..<(dataStart + compressedSize))

            let fileData: Data?
            switch method {
            case 0: fileData = compressed // stored
            case 8: fileData = inflate(compressed, expectedSize: uncompressedSize)
            default: fileData = nil // unsupported compression
            }
            if let fileData = fileData {
                entries.append(Entry(filename: baseName, data: fileData))
            }
        }
        return entries
    }

    /// Raw DEFLATE (zip method 8) — Compression's COMPRESSION_ZLIB is
    /// headerless deflate, which is exactly what zip entries contain.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0, expectedSize < 200_000_000 else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { outBuffer -> Int in
            data.withUnsafeBytes { inBuffer -> Int in
                guard let outPtr = outBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let inPtr = inBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    outPtr, expectedSize,
                    inPtr, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { return nil }
        return output
    }
}
