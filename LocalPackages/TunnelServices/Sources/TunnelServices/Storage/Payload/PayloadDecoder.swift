import Foundation
import NIOCore

/// Streaming payload decoder.
/// Reads raw payload → decompresses → writes decoded payload + extracts search text.
public enum PayloadDecoder {

    /// Stream decode: raw file → decoded file. Used for background async decode.
    public static func decode(
        rawPath: String,
        decodedPath: String,
        encoding: String,
        chunkSize: Int = 64 * 1024,
        textMaxSize: Int = 100 * 1024
    ) throws -> DecodeResult {
        let reader = try PayloadReader(filePath: rawPath, chunkSize: chunkSize)
        defer { reader.close() }

        let dir = (decodedPath as NSString).deletingLastPathComponent
        let fileName = (decodedPath as NSString).lastPathComponent
        let writer = try PayloadWriter(directory: dir, fileName: fileName)

        let stream = try makeDecompressStream(encoding: encoding)
        let textAccumulator = TextAccumulator(maxSize: textMaxSize)
        var decodedSize: Int64 = 0

        for chunk in reader.chunks() {
            let decoded = try stream.decompress(chunk)
            try writer.append(decoded)
            decodedSize += Int64(decoded.count)
            textAccumulator.append(decoded)
        }

        try stream.finalize()
        try writer.close()

        return DecodeResult(
            decodedSize: decodedSize,
            searchText: textAccumulator.text,
            detectedType: detectContentType(textAccumulator.text),
            payloadRef: fileName
        )
    }

    /// Synchronous in-memory decode. Used for breakpoint/script intercept path.
    public static func decodeSynchronously(data: Data, encoding: String) throws -> Data {
        let stream = try makeDecompressStream(encoding: encoding)
        let decoded = try stream.decompress(data)
        try stream.finalize()
        return decoded
    }

    private static func detectContentType(_ text: String?) -> String {
        guard let text = text, !text.isEmpty else { return "binary" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "application/json" }
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<") { return "text/xml" }
        return "text/plain"
    }
}
