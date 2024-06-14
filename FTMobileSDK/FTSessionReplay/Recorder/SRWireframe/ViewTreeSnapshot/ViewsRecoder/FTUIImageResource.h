//
//  FTUIImageResource.h
//  FTMobileSDK
//
//  Created by hulilei on 2024/6/14.
//  Copyright © 2024 DataFlux-cn. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol FTSRResource;
@interface FTUIImageResource : NSObject<FTSRResource>
-(instancetype)initWithImage:(UIImage *)image tintColor:(UIColor *)tintColor;
@end

NS_ASSUME_NONNULL_END
