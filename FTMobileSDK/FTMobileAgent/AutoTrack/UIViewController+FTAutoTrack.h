//
//  UIViewController+FT_RootVC.h
//  FTAutoTrack
//
//  Created by 胡蕾蕾 on 2019/12/2.
//  Copyright © 2019 hll. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FTAutoTrackProperty.h"
NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (FTAutoTrack)<FTAutoTrackViewControllerProperty>
-(BOOL)isBlackListContainsViewController;
-(void)dataflux_viewWillAppear:(BOOL)animated;
-(void)dataflux_viewDidAppear:(BOOL)animated;
-(void)dataflux_viewDidDisappear:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
