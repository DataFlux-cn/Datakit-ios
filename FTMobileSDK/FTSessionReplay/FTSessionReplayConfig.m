//
//  FTSessionReplayConfig.m
//  FTMobileSDK
//
//  Created by hulilei on 2024/7/4.
//  Copyright © 2024 DataFlux-cn. All rights reserved.
//

#import "FTSessionReplayConfig.h"

@implementation FTSessionReplayConfig
-(instancetype)init{
    self = [super init];
    if(self){
        _sampleRate = 100;
        _privacy = FTSRPrivacyMask;
    }
    return self;
}
@end
