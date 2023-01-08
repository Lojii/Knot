//
//  YYImageExampleUtils.h
//  YYKitExample
//
//  Created by ibireme on 15/7/20.
//  Copyright (c) 2015 ibireme. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "YYImage.h"

@interface YYImageExampleHelper : NSObject

/// Tap to play/pause
+ (void)addTapControlToAnimatedImageView:(YYAnimatedImageView *)view;

/// Slide to forward/rewind
+ (void)addPanControlToAnimatedImageView:(YYAnimatedImageView *)view;

@end

