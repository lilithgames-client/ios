//
//  UIDevice+UIDevice_iPhone6Hax.m
//  IRCCloud
//
//  Created by Sam Steele on 9/22/14.
//  Copyright (c) 2014 IRCCloud, Ltd. All rights reserved.
//

#import "UIDevice+UIDevice_iPhone6Hax.h"

@implementation UIDevice (UIDevice_iPhone6Hax)
-(BOOL)isBigPhone {
    return [self userInterfaceIdiom] == UIUserInterfaceIdiomPhone && [[UIScreen mainScreen] nativeScale] == 3.0f;
}
@end