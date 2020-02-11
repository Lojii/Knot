///
///  DataCompression
///
///  A libcompression wrapper as an extension for the `Data` type
///  (GZIP, ZLIB, LZFSE, LZMA, LZ4, deflate, RFC-1950, RFC-1951, RFC-1952)
///
///  Created by Markus Wanke, 2016/12/05
///


///
///                Apache License, Version 2.0
///
///  Copyright 2016, Markus Wanke
///
///  Licensed under the Apache License, Version 2.0 (the "License");
///  you may not use this file except in compliance with the License.
///  You may obtain a copy of the License at
///
///  http://www.apache.org/licenses/LICENSE-2.0
///
///  Unless required by applicable law or agreed to in writing, software
///  distributed under the License is distributed on an "AS IS" BASIS,
///  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///  See the License for the specific language governing permissions and
///  limitations under the License.
///


import Foundation
import Compression

public extension Data
{
    /// Compresses the data.
    /// - parameter withAlgorithm: Compression algorithm to use. See the `CompressionAlgorithm` type
    /// - returns: compressed data
    func compress(withAlgorithm algo: CompressionAlgorithm) -> Data?
    {
        return self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_ENCODE, algorithm: algo.lowLevelType)
            return perform(config, source: sourcePtr, sourceSize: count)
        }
    }
    
    /// Decompresses the data.
    /// - parameter withAlgorithm: Compression algorithm to use. See the `CompressionAlgorithm` type
    /// - returns: decompressed data
    func decompress(withAlgorithm algo: CompressionAlgorithm) -> Data?
    {
        return self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: algo.lowLevelType)
            return perform(config, source: sourcePtr, sourceSize: count)
        }
    }
    
    /// Please consider the [libcompression documentation](https://developer.apple.com/reference/compression/1665429-data_compression)
    /// for further details. Short info:
    /// zlib  : Aka deflate. Fast with a good compression rate. Proved itself over time and is supported everywhere.
    /// lzfse : Apples custom Lempel-Ziv style compression algorithm. Claims to compress as good as zlib but 2 to 3 times faster.
    /// lzma  : Horribly slow. Compression as well as decompression. Compresses better than zlib though.
    /// lz4   : Fast, but compression rate is very bad. Apples lz4 implementation often to not compress at all.
    enum CompressionAlgorithm
    {
        case zlib
        case lzfse
        case lzma
        case lz4
    }
    
    /// Compresses the data using the zlib deflate algorithm.
    /// - returns: raw deflated data according to [RFC-1951](https://tools.ietf.org/html/rfc1951).
    /// - note: Fixed at compression level 5 (best trade off between speed and time)
    func deflate() -> Data?
    {
        return self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_ENCODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: sourcePtr, sourceSize: count)
        }
    }
    
    /// Decompresses the data using the zlib deflate algorithm. Self is expected to be a raw deflate
    /// stream according to [RFC-1951](https://tools.ietf.org/html/rfc1951).
    /// - returns: uncompressed data
    func inflate() -> Data?
    {
        return self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: sourcePtr, sourceSize: count)
        }
    }
    
    /// Compresses the data using the deflate algorithm and makes it comply to the zlib format.
    /// - returns: deflated data in zlib format [RFC-1950](https://tools.ietf.org/html/rfc1950)
    /// - note: Fixed at compression level 5 (best trade off between speed and time)
    func zip() -> Data?
    {
        let header = Data([0x78, 0x5e])
        
        let deflated = self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_ENCODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: sourcePtr, sourceSize: count, preload: header)
        }
        
        guard var result = deflated else { return nil }
        
        var adler = self.adler32().checksum.bigEndian
        result.append(Data(bytes: &adler, count: MemoryLayout<UInt32>.size))
        
        return result
    }
    
    /// Decompresses the data using the zlib deflate algorithm. Self is expected to be a zlib deflate
    /// stream according to [RFC-1950](https://tools.ietf.org/html/rfc1950).
    /// - returns: uncompressed data
    func unzip(skipCheckSumValidation: Bool = true) -> Data?
    {
        // 2 byte header + 4 byte adler32 checksum
        let overhead = 6
        guard count > overhead else { return nil }
        
        let header: UInt16 = withUnsafeBytes { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            return ptr.pointee.bigEndian
        }
        
        // check for the deflate stream bit
        guard header >> 8 & 0b1111 == 0b1000 else { return nil }
        // check the header checksum
        guard header % 31 == 0 else { return nil }
        
        let cresult: Data? = withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Data? in
            let source = ptr.advanced(by: 2)
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: source, sourceSize: count - overhead)
        }
        
        guard let inflated = cresult else { return nil }
        
        if skipCheckSumValidation { return inflated }
        
        let cksum: UInt32 = withUnsafeBytes { (bytePtr: UnsafePointer<UInt8>) -> UInt32 in
            let last = bytePtr.advanced(by: count - 4)
            return last.withMemoryRebound(to: UInt32.self, capacity: 1) { (intPtr) -> UInt32 in
                return intPtr.pointee.bigEndian
            }
        }
        
        return cksum == inflated.adler32().checksum ? inflated : nil
    }
    
    /// Compresses the data using the deflate algorithm and makes it comply to the gzip stream format.
    /// - returns: deflated data in gzip format [RFC-1952](https://tools.ietf.org/html/rfc1952)
    /// - note: Fixed at compression level 5 (best trade off between speed and time)
    func gzip() -> Data?
    {
        var header = Data([0x1f, 0x8b, 0x08, 0x00]) // magic, magic, deflate, noflags
        
        var unixtime = UInt32(Date().timeIntervalSince1970).littleEndian
        header.append(Data(bytes: &unixtime, count: MemoryLayout<UInt32>.size))
        
        header.append(contentsOf: [0x00, 0x03])  // normal compression level, unix file type
        
        let deflated = self.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            let config = (operation: COMPRESSION_STREAM_ENCODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: sourcePtr, sourceSize: count, preload: header)
        }
        
        guard var result = deflated else { return nil }
        
        // append checksum
        var crc32: UInt32 = self.crc32().checksum.littleEndian
        result.append(Data(bytes: &crc32, count: MemoryLayout<UInt32>.size))
        
        // append size of original data
        var isize: UInt32 = UInt32(truncatingIfNeeded: count).littleEndian
        result.append(Data(bytes: &isize, count: MemoryLayout<UInt32>.size))
        
        return result
    }
    
    /// Decompresses the data using the gzip deflate algorithm. Self is expected to be a gzip deflate
    /// stream according to [RFC-1952](https://tools.ietf.org/html/rfc1952).
    /// - returns: uncompressed data
    func gunzip() -> Data?
    {
        // 10 byte header + data +  8 byte footer. See https://tools.ietf.org/html/rfc1952#section-2
        let overhead = 10 + 8
        guard count >= overhead else { return nil }
        
        
        typealias GZipHeader = (id1: UInt8, id2: UInt8, cm: UInt8, flg: UInt8, xfl: UInt8, os: UInt8)
        let hdr: GZipHeader = withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> GZipHeader in
            // +---+---+---+---+---+---+---+---+---+---+
            // |ID1|ID2|CM |FLG|     MTIME     |XFL|OS |
            // +---+---+---+---+---+---+---+---+---+---+
            return (id1: ptr[0], id2: ptr[1], cm: ptr[2], flg: ptr[3], xfl: ptr[8], os: ptr[9])
        }
        
        typealias GZipFooter = (crc32: UInt32, isize: UInt32)
        let ftr: GZipFooter = withUnsafeBytes { (bptr: UnsafePointer<UInt8>) -> GZipFooter in
            // +---+---+---+---+---+---+---+---+
            // |     CRC32     |     ISIZE     |
            // +---+---+---+---+---+---+---+---+
            return bptr.advanced(by: count - 8).withMemoryRebound(to: UInt32.self, capacity: 2) { ptr in
                return (ptr[0].littleEndian, ptr[1].littleEndian)
            }
        }
        
        // Wrong gzip magic or unsupported compression method
        guard hdr.id1 == 0x1f && hdr.id2 == 0x8b && hdr.cm == 0x08 else { return nil }
        
        let has_crc16: Bool = hdr.flg & 0b00010 != 0
        let has_extra: Bool = hdr.flg & 0b00100 != 0
        let has_fname: Bool = hdr.flg & 0b01000 != 0
        let has_cmmnt: Bool = hdr.flg & 0b10000 != 0
        
        let cresult: Data? = withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Data? in
            var pos = 10 ; let limit = count - 8
            
            if has_extra {
                pos += ptr.advanced(by: pos).withMemoryRebound(to: UInt16.self, capacity: 1) {
                    return Int($0.pointee.littleEndian) + 2 // +2 for xlen
                }
            }
            if has_fname {
                while pos < limit && ptr[pos] != 0x0 { pos += 1 }
                pos += 1 // skip null byte as well
            }
            if has_cmmnt {
                while pos < limit && ptr[pos] != 0x0 { pos += 1 }
                pos += 1 // skip null byte as well
            }
            if has_crc16 {
                pos += 2 // ignoring header crc16
            }
            
            guard pos < limit else { return nil }
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
            return perform(config, source: ptr.advanced(by: pos), sourceSize: limit - pos)
        }
        
        guard let inflated = cresult                                   else { return nil }
        guard ftr.isize == UInt32(truncatingIfNeeded: inflated.count)  else { return nil }
        guard ftr.crc32 == inflated.crc32().checksum                   else { return nil }
        return inflated
    }
    
    /// Calculate the Adler32 checksum of the data.
    /// - returns: Adler32 checksum type. Can still be further advanced.
    func adler32() -> Adler32
    {
        var res = Adler32()
        res.advance(withChunk: self)
        return res
    }
    
    /// Calculate the Crc32 checksum of the data.
    /// - returns: Crc32 checksum type. Can still be further advanced.
    func crc32() -> Crc32
    {
        var res = Crc32()
        res.advance(withChunk: self)
        return res
    }
}




/// Struct based type representing a Crc32 checksum.
public struct Crc32: CustomStringConvertible
{
    private static let zLibCrc32: ZLibCrc32FuncPtr? = loadCrc32fromZLib()
    
    public init() {}
    
    // C convention function pointer type matching the signature of `libz::crc32`
    private typealias ZLibCrc32FuncPtr = @convention(c) (
        _ cks:  UInt32,
        _ buf:  UnsafePointer<UInt8>,
        _ len:  UInt32
    ) -> UInt32
    
    /// Raw checksum. Updated after a every call to `advance(withChunk:)`
    public var checksum: UInt32 = 0
    
    /// Advance the current checksum with a chunk of data. Designed t be called multiple times.
    /// - parameter chunk: data to advance the checksum
    public mutating func advance(withChunk chunk: Data)
    {
        if let fastCrc32 = Crc32.zLibCrc32 {
            checksum = chunk.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) -> UInt32 in
                return fastCrc32(checksum, ptr, UInt32(chunk.count))
            })
        }
        else {
            checksum = slowCrc32(start: checksum, data: chunk)
        }
    }
    
    /// Formatted checksum.
    public var description: String
    {
        return String(format: "%08x", checksum)
    }
    
    /// Load `crc32()` from '/usr/lib/libz.dylib' if libz is installed.
    /// - returns: A function pointer to crc32() of zlib or nil if zlib can't be found
    private static func loadCrc32fromZLib() -> ZLibCrc32FuncPtr?
    {
        guard let libz = dlopen("/usr/lib/libz.dylib", RTLD_NOW) else { return nil }
        guard let fptr = dlsym(libz, "crc32") else { return nil }
        return unsafeBitCast(fptr, to: ZLibCrc32FuncPtr.self)
    }
    
    /// Rudimentary fallback implementation of the crc32 checksum. This is only a backup used
    /// when zlib can't be found under '/usr/lib/libz.dylib'.
    /// - returns: crc32 checksum (4 byte)
    private func slowCrc32(start: UInt32, data: Data) -> UInt32
    {
        return ~data.reduce(~start) { (crc: UInt32, next: UInt8) -> UInt32 in
            let tableOffset = (crc ^ UInt32(next)) & 0xff
            return lookUpTable[Int(tableOffset)] ^ crc >> 8
        }
    }
    
    /// Lookup table for faster crc32 calculation.
    /// table source: http://web.mit.edu/freebsd/head/sys/libkern/crc32.c
    private let lookUpTable: [UInt32] = [
        0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
        0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
        0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
        0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
        0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
        0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
        0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
        0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
        0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
        0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
        0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
        0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
        0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
        0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
        0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
        0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
        0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
        0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
        0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
        0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
        0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
        0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
        0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
        0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
        0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
        0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
        0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
        0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
        0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
        0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
        0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
        0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
    ]
}





/// Struct based type representing a Adler32 checksum.
public struct Adler32: CustomStringConvertible
{
    private static let zLibAdler32: ZLibAdler32FuncPtr? = loadAdler32fromZLib()
    
    public init() {}
    
    // C convention function pointer type matching the signature of `libz::adler32`
    private typealias ZLibAdler32FuncPtr = @convention(c) (
        _ cks:  UInt32,
        _ buf:  UnsafePointer<UInt8>,
        _ len:  UInt32
    ) -> UInt32
    
    /// Raw checksum. Updated after a every call to `advance(withChunk:)`
    public var checksum: UInt32 = 1
    
    /// Advance the current checksum with a chunk of data. Designed t be called multiple times.
    /// - parameter chunk: data to advance the checksum
    public mutating func advance(withChunk chunk: Data)
    {
        if let fastAdler32 = Adler32.zLibAdler32 {
            checksum = chunk.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) -> UInt32 in
                return fastAdler32(checksum, ptr, UInt32(chunk.count))
            })
        }
        else {
            checksum = slowAdler32(start: checksum, data: chunk)
        }
    }
    
    /// Formatted checksum.
    public var description: String
    {
        return String(format: "%08x", checksum)
    }
    
    /// Load `adler32()` from '/usr/lib/libz.dylib' if libz is installed.
    /// - returns: A function pointer to adler32() of zlib or nil if zlib can't be found
    private static func loadAdler32fromZLib() -> ZLibAdler32FuncPtr?
    {
        guard let libz = dlopen("/usr/lib/libz.dylib", RTLD_NOW) else { return nil }
        guard let fptr = dlsym(libz, "adler32") else { return nil }
        return unsafeBitCast(fptr, to: ZLibAdler32FuncPtr.self)
    }
    
    /// Rudimentary fallback implementation of the adler32 checksum. This is only a backup used
    /// when zlib can't be found under '/usr/lib/libz.dylib'.
    /// - returns: adler32 checksum (4 byte)
    private func slowAdler32(start: UInt32, data: Data) -> UInt32
    {
        var s1: UInt32 = start & 0xffff
        var s2: UInt32 = (start >> 16) & 0xffff
        let prime: UInt32 = 65521
        
        for byte in data {
            s1 += UInt32(byte)
            if s1 >= prime { s1 = s1 % prime }
            s2 += s1
            if s2 >= prime { s2 = s2 % prime }
        }
        return (s2 << 16) | s1
    }
}



fileprivate extension Data
{
    func withUnsafeBytes<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType
    {
        return try self.withUnsafeBytes({ (rawBufferPointer: UnsafeRawBufferPointer) -> ResultType in
            return try body(rawBufferPointer.bindMemory(to: ContentType.self).baseAddress!)
        })
    }
}

fileprivate extension Data.CompressionAlgorithm
{
    var lowLevelType: compression_algorithm {
        switch self {
            case .zlib    : return COMPRESSION_ZLIB
            case .lzfse   : return COMPRESSION_LZFSE
            case .lz4     : return COMPRESSION_LZ4
            case .lzma    : return COMPRESSION_LZMA
        }
    }
}


fileprivate typealias Config = (operation: compression_stream_operation, algorithm: compression_algorithm)


fileprivate func perform(_ config: Config, source: UnsafePointer<UInt8>, sourceSize: Int, preload: Data = Data()) -> Data?
{
    guard config.operation == COMPRESSION_STREAM_ENCODE || sourceSize > 0 else { return nil }
    
    let streamBase = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { streamBase.deallocate() }
    var stream = streamBase.pointee
    
    let status = compression_stream_init(&stream, config.operation, config.algorithm)
    guard status != COMPRESSION_STATUS_ERROR else { return nil }
    defer { compression_stream_destroy(&stream) }

    var result = preload
    var flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
    let blockLimit = 64 * 1024
    var bufferSize = Swift.max(sourceSize, 64)

    if sourceSize > blockLimit {
        bufferSize = blockLimit
        if config.algorithm == COMPRESSION_LZFSE && config.operation != COMPRESSION_STREAM_ENCODE   {
            // This fixes a bug in Apples lzfse decompressor. it will sometimes fail randomly when the input gets 
            // splitted into multiple chunks and the flag is not 0. Even though it should always work with FINALIZE...
            flags = 0
        }
    }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    stream.dst_ptr  = buffer
    stream.dst_size = bufferSize
    stream.src_ptr  = source
    stream.src_size = sourceSize
    
    while true {
        switch compression_stream_process(&stream, flags) {
            case COMPRESSION_STATUS_OK:
                guard stream.dst_size == 0 else { return nil }
                result.append(buffer, count: stream.dst_ptr - buffer)
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize

                if flags == 0 && stream.src_size == 0 { // part of the lzfse bugfix above
                    flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                }
                
            case COMPRESSION_STATUS_END:
                result.append(buffer, count: stream.dst_ptr - buffer)
                return result
                
            default:
                return nil
        }
    }
}
