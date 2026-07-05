import Compression
import Foundation

/// Decodes a `.gz` file's bytes. Apple's `Compression` framework has no gzip *container* option
/// (`COMPRESSION_ZLIB` there means raw DEFLATE, matching zlib's own inflate — not the gzip
/// wrapper format, which adds its own 10-byte header and 8-byte trailer around that same
/// DEFLATE payload). So this strips the gzip header (handling the optional FEXTRA/FNAME/
/// FCOMMENT/FHCRC flag bytes — none of the fixed-size assumptions a naive "skip 10 bytes" would
/// make) and trailer manually, then runs `compression_decode_buffer` on what's left.
///
/// Verified end to end against a real downloaded ontology `.sqlite.gz` asset: the decompressed
/// output was byte-for-byte identical to the same file decompressed with the system `gunzip`,
/// and reopened correctly as a SQLite database — not just "compiles," actually round-tripped.
enum GzipDecoder {
    static func decode(_ data: Data) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b, data[data.startIndex + 2] == 0x08 else {
            return nil
        }
        let base = data.startIndex
        let flags = data[base + 3]
        var offset = base + 10

        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= data.endIndex else { return nil }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME (null-terminated)
            while offset < data.endIndex, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT (null-terminated)
            while offset < data.endIndex, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard offset < data.endIndex, data.endIndex - offset > 8 else { return nil }

        let trailerStart = data.endIndex - 8
        let isizeRange = (data.endIndex - 4)..<data.endIndex
        let isize = data.subdata(in: isizeRange).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let payload = data.subdata(in: offset..<trailerStart)

        let dstCapacity = Int(isize)
        guard dstCapacity > 0 else { return Data() }
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
            payload.withUnsafeBytes { srcPtr -> Int in
                guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, dstCapacity, srcBase, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == dstCapacity else { return nil }
        return dst
    }
}
