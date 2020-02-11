//
//  AFormatter.m
//  Hex
//
//  Created by Andrew O'Mahony on 6/9/12.
//  Copyright (c) 2012 Myself. All rights reserved.
//

#import "AFormatter.h"

@implementation AFormatter
@synthesize currentDisplaySize, data;
@synthesize numberOfCharactersPerLine;

- (id)init
{
    if (self = [super init])
    {
        currentDisplaySize = FORMATTER_DISPLAY_SIZE_BYTE;
        stride = 16;
    }
    return (self);
}

- (NSInteger)displaySize
{
    if (currentDisplaySize == FORMATTER_DISPLAY_SIZE_BYTE)
        return (1);
    else if (currentDisplaySize == FORMATTER_DISPLAY_SIZE_WORD)
        return (2);
    else if (currentDisplaySize == FORMATTER_DISPLAY_SIZE_DWORD)
        return (4);
    else if (currentDisplaySize == FORMATTER_DISPLAY_SIZE_QWORD)
        return (8);
    return (0);
}

- (NSArray*)displaySizeStrings
{
    return ([NSArray arrayWithObjects:@"1 byte", @"2 bytes", @"4 bytes", @"8 bytes", nil]);
}

- (NSString*)getLineFromOffset:(NSInteger)offset
{
    NSInteger displayByteSize = [self displaySize];
    unsigned char* displayByteBuffer = (unsigned char*)malloc (displayByteSize);
    
    NSInteger currentSpaceCounter = 0;
    NSInteger maxSpaceCounter = displayByteSize;
    
    NSInteger numLineBytes = MIN ([data length] - offset, stride);    
    NSInteger numDisplayWords = numLineBytes / displayByteSize;
    NSInteger numPaddingBytes = numLineBytes % displayByteSize;
    NSInteger numXBytes = (stride - numLineBytes) % stride;
    
    NSInteger spacePadding = displayByteSize;
    
    NSMutableString* string = [NSMutableString new];
    
//    [string appendFormat:@"0x%.8X: ", offset];
    
    for (NSInteger i = 0; i < numDisplayWords; i ++)
    {
        [data getBytes:displayByteBuffer range:NSMakeRange (offset + (i * displayByteSize), displayByteSize)];
    
        if (displayByteSize == 1)
            [string appendFormat:@"%.2X", *displayByteBuffer];
        else if (displayByteSize == 2)
            [string appendFormat:@"%.4X", *(unsigned short*)displayByteBuffer];
        else if (displayByteSize == 4)
            [string appendFormat:@"%.8X", *(unsigned int*)displayByteBuffer];
        else if (displayByteSize == 8)
            [string appendFormat:@"%.16llX", *(long long*)displayByteBuffer];
        
        [string appendFormat:@" "];
    }
    
    NSInteger paddingOffset = (offset + (numDisplayWords * displayByteSize));
    for (NSInteger i = 0; i < numPaddingBytes; i ++)
    {
        [data getBytes:displayByteBuffer range:NSMakeRange (paddingOffset + i, 1)];
    
        [string appendFormat:@"%.2X", *displayByteBuffer];
        currentSpaceCounter ++;
        if (currentSpaceCounter == maxSpaceCounter)
        {
            for (NSInteger j = 0; j < spacePadding; j ++)
                [string appendString:@" "];
            currentSpaceCounter = 0;
        }
    }
    
    for (NSInteger i = 0; i < numXBytes; i ++)
    {
        [string appendString:@"  "];
        currentSpaceCounter ++;
        if (currentSpaceCounter == maxSpaceCounter)
        {
            [string appendString:@" "];
            currentSpaceCounter = 0;
        }
    }
    
    unsigned char lineByteArray [numLineBytes];
    [data getBytes:lineByteArray range:NSMakeRange (offset, numLineBytes)];
    
    [string appendFormat:@" "];
    for (NSInteger i = 0; i < stride; i ++)
    {
        if (isprint (lineByteArray [i]) && (i < numLineBytes))
            [string appendFormat:@"%c", lineByteArray [i]];
        else
            [string appendString:@"."];
    }
    
    [string appendString:@"\n"];
    NSString* ret = [NSString stringWithString:string];
    free (displayByteBuffer);
    
    return (ret);
}

- (NSString*)formattedString
{
    NSMutableString* string = [[NSMutableString alloc] init];
    
    @autoreleasepool
    {
        for (NSInteger i = 0; i < [data length]; i += stride)
        {    
            [string appendString:[self getLineFromOffset:i]];
        }
    }
    
    NSString* ret = [NSString stringWithString:string];
    return (ret);
}

- (void)setData:(NSData*)d
{
    if (data != d)
    {
        data = d;
        
        addressStringLength = 12;
    }
}

- (NSData*)formatDataBasedOnDisplay:(NSData*)d
{
    NSMutableData* tempData = [NSMutableData new];
    
    NSInteger i = 0;
    NSInteger length = [d length];
    NSInteger wordLength = [self displaySize];
    NSInteger increment = wordLength;
    NSInteger offset;
    
    @autoreleasepool
    {
        while (i < length)
        {
            increment = ((i + wordLength) > length) ? (length - i) : wordLength;
            offset = i + increment - 1;
            
            do
            {
                if (offset < length)
                    [tempData appendData:[d subdataWithRange:NSMakeRange (offset, 1)]];
                offset --;
            } while (offset >= i);
            
            i += increment;
        }
    }
    NSData* ret = [NSData dataWithData:tempData];
    return (ret);
}

- (NSInteger)getFormattedAddressLineOffset:(NSInteger)address
{
    return ((address / stride) * numberOfCharactersPerLine);
}

- (NSInteger)getFormattedOffsetOfByte:(NSInteger)address
{
    NSInteger addressOffset = (address % stride);
    
    return ([self getFormattedAddressLineOffset:address] + 
            addressStringLength + 
            ((addressOffset / [self displaySize]) * ([self displaySize] * 3)) +
            (([self displaySize] - 1 - (addressOffset % [self displaySize])) * 2)
            );
}

- (NSArray*)getFormattedRangesOfAddressRange:(NSRange)range
                                  searchMode:(formatterSearchMode)searchMode
{
    NSInteger address = range.location;
    NSInteger length = range.length;
    
    NSMutableArray* ret = [NSMutableArray array];
    
    NSInteger offset = [self getFormattedAddressLineOffset:address];
    
    NSInteger addressOffset = (address % stride);
    
    if (searchMode == FORMATTER_SEARCH_MODE_BINARY)
    {
        for (NSInteger i = range.location; i < range.location + range.length; i ++)
        {
            [ret addObject:[NSValue valueWithRange:NSMakeRange ([self getFormattedOffsetOfByte:i], 2)]];
        }
    }
    else if (searchMode == FORMATTER_SEARCH_MODE_TEXT)
    {
        offset += numberOfCharactersPerLine - (stride - addressOffset) - 1;
                
        NSRange currentRange;
        
        currentRange.location = offset;
        currentRange.length = 0;
        
        while (length > 0)
        {
            currentRange.length ++;
            length --;
            
            addressOffset ++;
            if ((addressOffset % stride) == 0)
            {
                [ret addObject:[NSValue valueWithRange:currentRange]];
                currentRange.location += currentRange.length + numberOfCharactersPerLine - stride;
                currentRange.length = 0;
            }
        }
        
        if (currentRange.length > 0)
            [ret addObject:[NSValue valueWithRange:currentRange]];
    }
    
    return ([NSArray arrayWithArray:ret]);    
}

- (NSInteger)getFormattedOffsetOfAbsoluteAddress:(NSInteger)address
                                      searchMode:(formatterSearchMode)searchMode
{
    NSInteger offset = [self getFormattedAddressLineOffset:address];
    
    if (searchMode == FORMATTER_SEARCH_MODE_BINARY)
    {
        NSInteger addressOffset = (address % stride);
        offset += addressStringLength + 
                  (addressOffset / [self displaySize]) * ([self displaySize] * 3) + 
                  ((addressOffset % [self displaySize]) * ([self displaySize]));
    }
    else if (searchMode == FORMATTER_SEARCH_MODE_TEXT)
    {
        offset += numberOfCharactersPerLine - (stride - (address % stride)) - 1;
    }
    
    return (offset);
}

- (NSInteger)getAbsoluteAddressForFormattedOffset:(NSInteger)offset
                                       searchMode:(formatterSearchMode)searchMode
                                      roundToByte:(BOOL)r
{
    NSInteger ret = stride * (offset / numberOfCharactersPerLine);
    
    if (searchMode == FORMATTER_SEARCH_MODE_BINARY)
    {
        NSInteger lineOffset = ((offset % numberOfCharactersPerLine) - addressStringLength);
        NSInteger wordOffset = (lineOffset / ([self displaySize] * 3));
        NSInteger byteOffset = (lineOffset % ([self displaySize] * 3));
        
        if (((byteOffset % 2) != 0) &&
            !r)
            return (-1);
        
        byteOffset /= 2;
        
        ret += (wordOffset * [self displaySize]) + ([self displaySize] - byteOffset - 1);
    }
    else if (searchMode == FORMATTER_SEARCH_MODE_TEXT)
    {
        ret += offset - (numberOfCharactersPerLine - stride - 1);
    }
    
    return (ret);
}

- (BOOL)isSelectableCharacterIndex:(NSInteger)index
{
    NSInteger addressOffset = (index % numberOfCharactersPerLine);
    if (addressOffset < addressStringLength ||
        addressOffset >= (numberOfCharactersPerLine - 1 - stride))
        return (NO);
    
    return (![[NSCharacterSet whitespaceCharacterSet] characterIsMember:[self.formattedString characterAtIndex:index]]);
}

- (formatterSelectionMode)selectionModeForCharacterIndex:(NSInteger)index
{
    NSInteger addressOffset = (index % numberOfCharactersPerLine);
    
    if (addressOffset < addressStringLength)
        return (FORMATTER_SELECTION_MODE_NULL);
    else if (addressOffset >= addressStringLength &&
             addressOffset < numberOfCharactersPerLine - stride - 1)
        return (FORMATTER_SELECTION_MODE_BINARY);
    else
        return (FORMATTER_SELECTION_MODE_TEXT);
}

- (NSInteger)getDisplaySizeForAddress:(NSInteger)address
{
    if (address % self.displaySize)
        return (1);
    return (self.displaySize);
}

- (void)dealloc{
    self.data = nil;
}

@end
