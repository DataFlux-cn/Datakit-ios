//
//  FTUIPickerViewRecorder.h
//  FTMobileSDK
//
//  Created by hulilei on 2023/8/30.
//  Copyright © 2023 DataFlux-cn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FTSRWireframesBuilder.h"

@class FTViewAttributes;
NS_ASSUME_NONNULL_BEGIN
@interface FTUIPickerViewBuilder : NSObject<FTSRWireframesBuilder>
@property (nonatomic, assign) int wireframeID;
@property (nonatomic, strong) FTViewAttributes *attributes;
@property (nonatomic, assign) CGRect wireframeRect;
@end
@interface FTUIPickerViewRecorder : NSObject<FTSRWireframesRecorder>

@end

NS_ASSUME_NONNULL_END
