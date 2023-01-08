# BrotliKit

An Objective-C and Swift library for Brotli compression and decompression.

## Installation

Via Cocoapods:

```
pod 'BrotliKit'
```

## Usage

### `NSData` category

```objc
// compression
[myData compressBrotli];

// decompression
[myData decompressBrotli];
```

### Compressor class

Simple usage

```objc
// compression
[LMBrotliCompressor compressedDataWithData:myData];

// decompression
[LMBrotliCompressor decompressedDataWithData:myData];
```

Compression quality

```objc
// compression
[LMBrotliCompressor compressedDataWithData:myData quality:11];
```

Decompressing partial inputs

```objc
// decompression
BOOL isPartialInput;
[LMBrotliCompressor decompressedDataWithData:myData isPartialInput:&isPartialInput];
```

### Core Foundation API

```c
CF_EXPORT CFDataRef LMCreateBrotliCompressedData(const void* bytes, CFIndex length, int16_t quality);
CF_EXPORT CFDataRef LMCreateBrotliDecompressedData(const void* bytes, CFIndex length, bool* isPartialInput);
```

## License

MIT License. The original [Brotli repository](https://github.com/google/brotli) is also under the MIT license.
