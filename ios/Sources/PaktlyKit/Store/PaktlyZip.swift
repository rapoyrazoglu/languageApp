import Foundation
import Compression

/// Minimal PKZIP reader for pack archives. Supports the only two compression
/// methods we ship — STORE (0) and DEFLATE (8) — and refuses everything else
/// (encrypted, ZIP64, multi-disk). The backend already validates uploaded
/// packs, so we trust well-formedness; this reader is the consumer-side
/// counterpart and re-applies zip-slip defence on every entry name.
enum PaktlyZipError: Error, Sendable, Equatable {
    case malformed(String)
    case unsupportedMethod(UInt16)
    case zipSlip(path: String)
    case truncated
}

struct PaktlyZipEntry: Sendable, Equatable {
    let name: String
    let isDirectory: Bool
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let method: UInt16
    let crc32: UInt32
    let localHeaderOffset: UInt32
}

struct PaktlyZip: Sendable {
    private let data: Data
    let entries: [PaktlyZipEntry]

    init(data: Data) throws {
        self.data = data
        let eocd = try Self.findEOCD(in: data)
        var cursor = Int(eocd.cdOffset)
        var collected: [PaktlyZipEntry] = []
        collected.reserveCapacity(Int(eocd.entryCount))
        for _ in 0..<Int(eocd.entryCount) {
            let entry = try Self.readCentralEntry(in: data, at: &cursor)
            collected.append(entry)
        }
        self.entries = collected
    }

    /// Decompress one entry into memory. The backend bounds pack archive size
    /// well below RAM limits so we don't bother streaming.
    func read(_ entry: PaktlyZipEntry) throws -> Data {
        let (dataStart, declaredCompressedSize) = try locateEntryData(entry)
        let compressedSize = Int(declaredCompressedSize == 0 ? entry.compressedSize : declaredCompressedSize)
        guard dataStart + compressedSize <= data.count else { throw PaktlyZipError.truncated }
        let compressed = data.subdata(in: dataStart..<(dataStart + compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw PaktlyZipError.unsupportedMethod(entry.method)
        }
    }

    /// Extract every non-directory entry into `dest`, creating subdirectories
    /// as needed. Each entry name is sanitized so a malicious archive can't
    /// escape `dest` (zip-slip).
    func extract(to dest: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let normalisedDest = dest.standardizedFileURL.path

        for entry in entries {
            try Self.assertSafeName(entry.name)
            let outURL = dest.appendingPathComponent(entry.name)
            // Belt-and-braces: even after assertSafeName, verify the resolved
            // path stays under `dest`.
            let resolved = outURL.standardizedFileURL.path
            guard resolved == normalisedDest || resolved.hasPrefix(normalisedDest + "/") else {
                throw PaktlyZipError.zipSlip(path: entry.name)
            }
            if entry.isDirectory {
                try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try read(entry)
            try bytes.write(to: outURL)
        }
    }

    // MARK: - Parsing internals

    private static let eocdSignature: UInt32 = 0x06054b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let localSignature: UInt32 = 0x04034b50

    private struct EOCD { let entryCount: UInt16; let cdOffset: UInt32 }

    private static func findEOCD(in data: Data) throws -> EOCD {
        // EOCD is 22 bytes minimum, plus a comment up to 65535 bytes.
        let minSize = 22
        guard data.count >= minSize else { throw PaktlyZipError.malformed("file shorter than EOCD") }
        let scanStart = max(0, data.count - minSize - 65535)
        var i = data.count - minSize
        while i >= scanStart {
            if read32(data, i) == eocdSignature {
                let entryCount = read16(data, i + 10)
                let cdSize = read32(data, i + 12)
                let cdOffset = read32(data, i + 16)
                guard Int(cdOffset) + Int(cdSize) <= data.count else {
                    throw PaktlyZipError.malformed("central directory out of bounds")
                }
                return EOCD(entryCount: entryCount, cdOffset: cdOffset)
            }
            i -= 1
        }
        throw PaktlyZipError.malformed("EOCD record not found")
    }

    private static func readCentralEntry(in data: Data, at cursor: inout Int) throws -> PaktlyZipEntry {
        guard cursor + 46 <= data.count else { throw PaktlyZipError.truncated }
        guard read32(data, cursor) == centralSignature else {
            throw PaktlyZipError.malformed("missing central directory signature at \(cursor)")
        }
        let flags = read16(data, cursor + 8)
        if flags & 0x0001 != 0 { throw PaktlyZipError.malformed("encrypted entry") }
        let method = read16(data, cursor + 10)
        let crc = read32(data, cursor + 16)
        let compressedSize = read32(data, cursor + 20)
        let uncompressedSize = read32(data, cursor + 24)
        if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF {
            throw PaktlyZipError.malformed("ZIP64 not supported")
        }
        let nameLen = Int(read16(data, cursor + 28))
        let extraLen = Int(read16(data, cursor + 30))
        let commentLen = Int(read16(data, cursor + 32))
        let localOffset = read32(data, cursor + 42)
        guard cursor + 46 + nameLen <= data.count else { throw PaktlyZipError.truncated }
        let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLen))
        guard let name = String(data: nameData, encoding: .utf8) else {
            throw PaktlyZipError.malformed("non-utf8 entry name")
        }
        cursor += 46 + nameLen + extraLen + commentLen
        return PaktlyZipEntry(
            name: name,
            isDirectory: name.hasSuffix("/"),
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            method: method,
            crc32: crc,
            localHeaderOffset: localOffset
        )
    }

    private func locateEntryData(_ entry: PaktlyZipEntry) throws -> (start: Int, compressedSize: UInt32) {
        let headerOffset = Int(entry.localHeaderOffset)
        guard headerOffset + 30 <= data.count else { throw PaktlyZipError.truncated }
        guard Self.read32(data, headerOffset) == Self.localSignature else {
            throw PaktlyZipError.malformed("missing local file header")
        }
        // The local header re-states the filename + extra field lengths —
        // these can differ from the central directory's lengths (extra fields
        // commonly do), so always re-read here.
        let nameLen = Int(Self.read16(data, headerOffset + 26))
        let extraLen = Int(Self.read16(data, headerOffset + 28))
        let dataStart = headerOffset + 30 + nameLen + extraLen
        guard dataStart <= data.count else { throw PaktlyZipError.truncated }
        return (dataStart, entry.compressedSize)
    }

    // MARK: - Path safety

    private static func assertSafeName(_ name: String) throws {
        if name.isEmpty || name.first == "/" || name.contains("\\") {
            throw PaktlyZipError.zipSlip(path: name)
        }
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            if component == ".." {
                throw PaktlyZipError.zipSlip(path: name)
            }
        }
    }

    // MARK: - Byte reads (little-endian)

    static func read16(_ d: Data, _ at: Int) -> UInt16 {
        UInt16(d[at]) | (UInt16(d[at + 1]) << 8)
    }
    static func read32(_ d: Data, _ at: Int) -> UInt32 {
        UInt32(d[at])
            | (UInt32(d[at + 1]) << 8)
            | (UInt32(d[at + 2]) << 16)
            | (UInt32(d[at + 3]) << 24)
    }
}

// MARK: - DEFLATE inflate via Compression.framework

private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
    // Apple's COMPRESSION_ZLIB encodes raw DEFLATE (no zlib frame header), which
    // is exactly what PKZIP method 8 stores.
    if expectedSize == 0 { return Data() }
    return try input.withUnsafeBytes { srcPtr in
        guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw PaktlyZipError.malformed("empty deflate input")
        }
        let cap = max(expectedSize, 1)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let written = compression_decode_buffer(dst, cap, src, srcPtr.count, nil, COMPRESSION_ZLIB)
        guard written > 0 else {
            throw PaktlyZipError.malformed("inflate failed")
        }
        return Data(bytes: dst, count: written)
    }
}
