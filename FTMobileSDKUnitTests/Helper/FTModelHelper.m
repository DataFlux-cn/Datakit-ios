//
//  FTModelHelper.m
//  FTMobileSDKUnitTests
//
//  Created by hulilei on 2022/4/14.
//  Copyright © 2022 DataFlux-cn. All rights reserved.
//

#import "FTModelHelper.h"
#import <FTConstants.h>
#import <FTDateUtil.h>
#import <FTEnumConstant.h>
#import <FTMobileConfig.h>
@implementation FTModelHelper
+ (FTRecordModel *)createLogModel{
    return  [FTModelHelper createLogModel:[FTDateUtil currentTimeGMT]];
}
+ (FTRecordModel *)createLogModel:(NSString *)message{
    NSDictionary *filedDict = @{FT_KEY_MESSAGE:message,
    };
    NSDictionary *tagDict = @{FT_KEY_STATUS:FTStatusStringMap[FTStatusInfo]};

    FTRecordModel *model = [[FTRecordModel alloc]initWithSource:FT_LOGGER_SOURCE op:FT_DATA_TYPE_LOGGING tags:tagDict field:filedDict tm:[FTDateUtil currentTimeNanosecond]];
    return model;
}
@end
