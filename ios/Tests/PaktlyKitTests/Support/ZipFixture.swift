import Foundation

/// Build a valid PKZIP archive (STORE method, no compression) entirely in
/// memory for tests. We can't rely on the on-disk reference pack here — tests
/// need to control bytes precisely (e.g. inject a malicious entry name to
/// exercise zip-slip defence). The reader exercises both STORE and DEFLATE
/// paths against real release archives in integration tests.
enum ZipFixture {
    struct File {
        let name: String
        let data: Data
        init(_ name: String, _ data: Data) { self.name = name; self.data = data }
        init(_ name: String, _ string: String) { self.init(name, Data(string.utf8)) }
    }

    static func build(_ files: [File]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        for file in files {
            let nameBytes = Data(file.name.utf8)
            let crc = CRC32.hash(file.data)
            let size = UInt32(file.data.count)
            let localOffset = UInt32(output.count)

            // Local file header (signature 0x04034b50)
            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)                       // version needed
            output.appendUInt16(0)                        // flags
            output.appendUInt16(0)                        // method = STORE
            output.appendUInt16(0)                        // mod time
            output.appendUInt16(0)                        // mod date
            output.appendUInt32(crc)
            output.appendUInt32(size)                     // compressed
            output.appendUInt32(size)                     // uncompressed
            output.appendUInt16(UInt16(nameBytes.count))
            output.appendUInt16(0)                        // extra
            output.append(nameBytes)
            output.append(file.data)

            // Central directory entry (signature 0x02014b50)
            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)             // version made by
            centralDirectory.appendUInt16(20)             // version needed
            centralDirectory.appendUInt16(0)              // flags
            centralDirectory.appendUInt16(0)              // method
            centralDirectory.appendUInt16(0)              // mod time
            centralDirectory.appendUInt16(0)              // mod date
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt16(UInt16(nameBytes.count))
            centralDirectory.appendUInt16(0)              // extra
            centralDirectory.appendUInt16(0)              // comment
            centralDirectory.appendUInt16(0)              // disk number
            centralDirectory.appendUInt16(0)              // internal attrs
            centralDirectory.appendUInt32(0)              // external attrs
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(nameBytes)

            entryCount += 1
        }

        let cdOffset = UInt32(output.count)
        let cdSize = UInt32(centralDirectory.count)
        output.append(centralDirectory)

        // EOCD (signature 0x06054b50)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)              // disk number
        output.appendUInt16(0)              // disk where CD starts
        output.appendUInt16(entryCount)     // entries on this disk
        output.appendUInt16(entryCount)     // total entries
        output.appendUInt32(cdSize)
        output.appendUInt32(cdOffset)
        output.appendUInt16(0)              // comment length

        return output
    }
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
    }
    mutating func appendUInt32(_ v: UInt32) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 24) & 0xff))
    }
}

// MARK: - CRC32 (PKZIP polynomial 0xEDB88320)

private enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[idx]
        }
        return crc ^ 0xFFFFFFFF
    }
}
