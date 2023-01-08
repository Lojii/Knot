//
//  BrotliKitTests.m
//  BrotliKitTests
//
//  Created by Micha Mazaheri on 4/5/18.
//  Copyright © 2018 Paw. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "LMBrotliCompressor.h"

@interface BrotliKitTests : XCTestCase

@end

@implementation BrotliKitTests

#pragma mark - Compress Only

- (void)testCompressEmptyData
{
    XCTAssertNil([LMBrotliCompressor compressedDataWithData:[NSData data]]);
}

- (void)testCompressSmallLengthData
{
    XCTAssertNotNil([LMBrotliCompressor compressedDataWithData:[NSData dataWithBytes:"luckymarmot" length:11]]);
}

- (void)testCompressNormalLengthData
{
    NSData* originalData = [self makeRandomDataWithLength:1024 * 8]; // 8 kB
    XCTAssertNotNil([LMBrotliCompressor compressedDataWithData:originalData]);
}

- (void)testCompressMediumLengthData
{
    NSData* originalData = [self makeRandomDataWithLength:1024 * 64]; // 64 kB
    XCTAssertNotNil([LMBrotliCompressor compressedDataWithData:originalData]);
}

- (void)testCompressMediumLengthConstantData
{
    NSData* originalData = [self makeConstantDataWithLength:1024 * 64]; // 64 kB
    NSData* compressedData = [LMBrotliCompressor compressedDataWithData:originalData];
    XCTAssertNotNil(compressedData);
    XCTAssertTrue(compressedData.length > 8); // not too small
    XCTAssertTrue(compressedData.length < 1024); // not too large (its a constant data)
}

- (void)testCompressLargeLengthData
{
    // make the data not so random to check compression levels
    NSMutableData* originalData = [[self makeRandomDataWithLength:1024 * 1024] mutableCopy]; // 1 MB
    memset(originalData.mutableBytes + (1024 * 64), '_', 1024 * 256);
    memset(originalData.mutableBytes + (1024 * 700), '-', 1024 * 256);
    
    NSData* compressedData = [LMBrotliCompressor compressedDataWithData:originalData];
    XCTAssertNotNil(compressedData);
    XCTAssertTrue(compressedData.length > 1024); // not too small
    XCTAssertTrue(compressedData.length < 1024 * 800); // not too large
}

#pragma mark - Decompress Only

- (void)testDecompressEmptyData
{
    XCTAssertNil([LMBrotliCompressor decompressedDataWithData:[NSData data]]);
}

- (void)testDecompressSmallLengthData
{
    NSData* sourceData = [[NSData alloc] initWithBase64EncodedString:@"G0oBAIyUq+1oGZTkpM6pbNzcpC8kbIHSihXO4d92wL5/T7qoonVJGgQDaWCZu557eWmSjrLRyRZvdAlvxWxam0v84gSqjtPiV9HmsmuNetIqXRMuUVTErzFBfr+fSEZ8QmSGLsRg2o0LVfyl4emO5I0nyipTIaoznmOKOJEcdRq4yZq0FAifBn71uhiSWmpSC1QY9quTx8I4duxtZQM=" options:kNilOptions];
    NSData* uncompressedData = [LMBrotliCompressor decompressedDataWithData:sourceData];
    XCTAssertNotNil(uncompressedData);
    XCTAssertEqualObjects(uncompressedData, [NSData dataWithBytes:"No one wants to die. Even people who want to go to heaven don't want to die to get there. And yet death is the destination we all share. No one has ever escaped it. And that is as it should be, because Death is very likely the single best invention of Life. It is Life's change agent. It clears out the old to make way for the new." length:331]);
}

#pragma mark - Compress And Decompress

- (void)testCompressDecompressMediumLengthData
{
    NSData* originalData = [self makeRandomDataWithLength:1024 * 64]; // 64 kB
    NSData* compressedData = [LMBrotliCompressor compressedDataWithData:originalData];
    NSData* decompressedData = [LMBrotliCompressor decompressedDataWithData:compressedData];
    XCTAssertNotNil(compressedData);
    XCTAssertNotNil(decompressedData);
    XCTAssertEqualObjects(originalData, decompressedData);
}

- (void)testCompressDecompressMediumLengthConstantData
{
    NSData* originalData = [self makeConstantDataWithLength:1024 * 64]; // 64 kB
    NSData* compressedData = [LMBrotliCompressor compressedDataWithData:originalData];
    NSData* decompressedData = [LMBrotliCompressor decompressedDataWithData:compressedData];
    XCTAssertNotNil(compressedData);
    XCTAssertNotNil(decompressedData);
    XCTAssertEqualObjects(originalData, decompressedData);
    XCTAssertTrue(compressedData.length > 8); // not too small
    XCTAssertTrue(compressedData.length < 1024); // not too large (its a constant data)
}

- (void)testCompressDecompressLargeLengthData
{
    // make the data not so random to check compression levels
    NSMutableData* originalData = [[self makeRandomDataWithLength:1024 * 1024] mutableCopy]; // 1 MB
    memset(originalData.mutableBytes + (1024 * 64), '_', 1024 * 256);
    memset(originalData.mutableBytes + (1024 * 700), '-', 1024 * 256);
    
    NSData* compressedData = [LMBrotliCompressor compressedDataWithData:originalData];
    NSData* decompressedData = [LMBrotliCompressor decompressedDataWithData:compressedData];
    XCTAssertNotNil(compressedData);
    XCTAssertNotNil(decompressedData);
    XCTAssertEqualObjects(originalData, decompressedData);
    XCTAssertTrue(compressedData.length > 1024); // not too small
    XCTAssertTrue(compressedData.length < 1024 * 800); // not too large
}

#pragma mark - Performance

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

#pragma mark - Helpers

- (NSData*)makeRandomDataWithLength:(NSUInteger)length
{
    uint8_t* buffer = malloc(length * sizeof(size_t));
    if (0 != SecRandomCopyBytes(kSecRandomDefault, (size_t)length * sizeof(size_t), buffer)) {
        free(buffer);
        buffer = NULL;
        return nil;
    }
    NSData* originalData = [NSData dataWithBytes:buffer length:(size_t)length];
    free(buffer);
    buffer = NULL;
    return originalData;
}

- (NSData*)makeConstantDataWithLength:(NSUInteger)length
{
    uint8_t* buffer = malloc(length * sizeof(size_t));
    memset(buffer, '_', length);
    NSData* originalData = [NSData dataWithBytes:buffer length:(size_t)length];
    free(buffer);
    buffer = NULL;
    return originalData;
}

@end
