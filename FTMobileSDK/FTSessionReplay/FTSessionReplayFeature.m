//
//  FTSessionReplayFeature.m
//  FTMobileSDK
//
//  Created by hulilei on 2024/7/4.
//  Copyright © 2024 DataFlux-cn. All rights reserved.
//

#import "FTSessionReplayFeature.h"
#import "FTSegmentRequest.h"
#import "FTPerformancePresetOverride.h"
#import "FTThreadDispatchManager.h"
#import "FTRecorder.h"
#import "FTConstants.h"
#import "FTViewAttributes.h"
#import "FTBaseInfoHandler.h"
#import "FTSessionReplayTouches.h"
#import "FTWindowObserver.h"
#import "FTSessionReplayConfig.h"
#import "FTTLV.h"
#import "FTResourceProcessor.h"
#import "FTResourceWriter.h"
#import "FTSnapshotProcessor.h"
@interface FTSessionReplayFeature()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSDictionary *lastRUMContext;
@property (nonatomic, assign) BOOL isSampled;
@property (nonatomic, strong) FTRecorder *windowRecorder;
@property (nonatomic, assign) FTSRPrivacy privacy;
@property (nonatomic, assign) int sampleRate;
@property (nonatomic, strong) FTSessionReplayTouches *touches;
@property (nonatomic, strong) FTWindowObserver *windowObserver;
@property (nonatomic, strong) dispatch_queue_t processorsQueue;
@end
@implementation FTSessionReplayFeature
-(instancetype)initWithConfig:(FTSessionReplayConfig *)config{
    self = [super init];
    if(self){
        _name = @"session-replay";
        _privacy = config.privacy;
        _processorsQueue = dispatch_queue_create("com.guance.session-replay.processors", 0);
        _sampleRate = config.sampleRate;
        _requestBuilder = [[FTSegmentRequest alloc]init];
        FTPerformancePresetOverride *performancePresetOverride = [[FTPerformancePresetOverride alloc]initWithMeanFileAge:2 minUploadDelay:0.6];
        performancePresetOverride.maxFileSize = FT_MAX_DATA_LENGTH;
        performancePresetOverride.maxObjectSize = FT_MAX_DATA_LENGTH;
        performancePresetOverride.initialUploadDelay = 1;
        performancePresetOverride.uploadDelayChangeRate = 0.75;
        _performanceOverride = performancePresetOverride;
        _windowObserver = [[FTWindowObserver alloc]init];
        _touches = [[FTSessionReplayTouches alloc]initWithWindowObserver:_windowObserver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextChange:) name:FTRumContextDidChangeNotification object:nil];
    }
    return self;
}

-(void)startWithWriter:(id<FTWriter>)writer resourceWriter:(id<FTWriter>)resourceWriter resourceDataStore:(id<FTDataStore>)dataStore{
    FTResourceWriter *resource = [[FTResourceWriter alloc]initWithWriter:resourceWriter dataStore:dataStore];
    FTResourceProcessor *resourceProcessor = [[FTResourceProcessor alloc]initWithQueue:self.processorsQueue resourceWriter:resource];
    FTSnapshotProcessor *srProcessor = [[FTSnapshotProcessor alloc]initWithQueue:self.processorsQueue writer:writer];
    FTRecorder *windowRecorder = [[FTRecorder alloc]initWithWindowObserver:self.windowObserver snapshotProcessor:srProcessor resourceProcessor:resourceProcessor];
    self.windowRecorder = windowRecorder;
    [self start];
}
-(void)start{
    [FTThreadDispatchManager performBlockDispatchMainAsync:^{
        if(self.timer){
            return;
        }
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf captureNextRecord];
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }];
}
- (void)stop{
    [FTThreadDispatchManager performBlockDispatchMainAsync:^{
        if(self.timer){
            [self.timer invalidate];
            self.timer = nil;
        }
    }];
}
- (void)contextChange:(NSNotification *)notification{
    NSDictionary *context = notification.userInfo;
    if(self.lastRUMContext){
        if(![context isEqualToDictionary:self.lastRUMContext]&& ![context[FT_RUM_KEY_SESSION_ID] isEqualToString:self.lastRUMContext[FT_RUM_KEY_SESSION_ID]]){
            BOOL isSampled = [FTBaseInfoHandler randomSampling:self.sampleRate];
            if (isSampled) {
                [self start];
            } else {
                [self stop];
            }
            _isSampled = isSampled;
        }
    }
    self.lastRUMContext = context;
}

- (void)captureNextRecord{
    NSString *viewID = self.lastRUMContext[FT_KEY_VIEW_ID];
    if (!viewID) {
        return;
    }
    FTSRContext *context = [[FTSRContext alloc]init];
    context.privacy = [[FTSRTextObfuscatingFactory alloc]initWithPrivacy:self.privacy];
    context.sessionID = self.lastRUMContext[FT_RUM_KEY_SESSION_ID];
    context.viewID = self.lastRUMContext[FT_KEY_VIEW_ID];
    context.applicationID = self.lastRUMContext[FT_APP_ID];
    context.date = [NSDate date];
    [self.windowRecorder taskSnapShot:context touches:[self.touches takeTouches]];
}
-(void)dealloc{
    [self stop];
}
@end
