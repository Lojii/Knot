//
//  AFormatter.h
//  Hex
//
//  Created by Andrew O'Mahony on 6/9/12.
//  Copyright (c) 2012 Myself. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum
{
    FORMATTER_DISPLAY_SIZE_NULL = 0,
    FORMATTER_DISPLAY_SIZE_BYTE,
    FORMATTER_DISPLAY_SIZE_WORD,
    FORMATTER_DISPLAY_SIZE_DWORD,
    FORMATTER_DISPLAY_SIZE_QWORD
    
}formatterDisplaySize;

typedef enum
{
    FORMATTER_SEARCH_MODE_NULL = 0,
    FORMATTER_SEARCH_MODE_BINARY,
    FORMATTER_SEARCH_MODE_TEXT
    
}formatterSearchMode;

typedef enum
{
    FORMATTER_SELECTION_MODE_NULL = 0,
    FORMATTER_SELECTION_MODE_BINARY,
    FORMATTER_SELECTION_MODE_TEXT
    
}formatterSelectionMode;

@interface AFormatter : NSObject
{
    formatterDisplaySize currentDisplaySize;
    NSData* data;
    
    NSInteger numberOfCharactersPerLine;
    NSInteger stride;
    
    NSInteger addressStringLength; //Includes the trailing space
}

@property (nonatomic, assign) formatterDisplaySize currentDisplaySize;
@property (nonatomic, retain) NSData* data;
@property (readonly) NSString* formattedString;
@property (readonly) NSInteger displaySize;

@property (nonatomic, assign) NSInteger numberOfCharactersPerLine;

@property (readonly) NSArray* displaySizeStrings;

- (NSArray*)getFormattedRangesOfAddressRange:(NSRange)range searchMode:(formatterSearchMode)searchMode;

- (NSInteger)getFormattedOffsetOfAbsoluteAddress:(NSInteger)address searchMode:(formatterSearchMode)searchMode;

- (NSInteger)getAbsoluteAddressForFormattedOffset:(NSInteger)offset searchMode:(formatterSearchMode)searchMode roundToByte:(BOOL)r;

- (NSInteger)getDisplaySizeForAddress:(NSInteger)address;

- (NSInteger)getFormattedAddressLineOffset:(NSInteger)address;

- (NSData*)formatDataBasedOnDisplay:(NSData*)data;

- (BOOL)isSelectableCharacterIndex:(NSInteger)index;

- (formatterSelectionMode)selectionModeForCharacterIndex:(NSInteger)index;

@end
