//
//  FTMobileAgent.m
//  FTMobileAgent
//
//  Created by 胡蕾蕾 on 2019/11/28.
//  Copyright © 2019 hll. All rights reserved.
//

#import "FTMobileAgent.h"
#import <UIKit/UIKit.h>
#import "ZYLog.h"
#import "FTTrackerEventDBTool.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import "FTUploadTool.h"
#import "FTRecordModel.h"
#import "FTBaseInfoHander.h"
#import <objc/runtime.h>
#import "FTLocationManager.h"
#import "FTNetMonitorFlow.h"
#import "FTTrackBean.h"
#import "FTMonitorManager.h"
@interface FTMobileAgent ()
@property (nonatomic, assign) BOOL isForeground;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong) CTTelephonyNetworkInfo *telephonyInfo;
@property (nonatomic, strong) dispatch_queue_t serialQueue;
@property (nonatomic, strong) dispatch_queue_t immediateLabel;
@property (nonatomic, copy) NSString *net;
@property (nonatomic, strong) FTUploadTool *upTool;
@property (nonatomic, strong) FTMobileConfig *config;
@property (nonatomic, assign) int preFlowTime;
@property (readwrite, nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) NSDictionary *monitorTagDict;
@end
@implementation FTMobileAgent

static FTMobileAgent *sharedInstance = nil;
static dispatch_once_t onceToken;
static char FTAutoTrack;
static void ZYReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    if (info != NULL && [(__bridge NSObject*)info isKindOfClass:[FTMobileAgent class]]) {
        @autoreleasepool {
            FTMobileAgent *zy = (__bridge FTMobileAgent *)info;
            [zy reachabilityChanged:flags];
        }
    }
}
+ (void)startLocation:(nullable void (^)(NSInteger errorCode,NSString * _Nullable errorMessage))callBack{
    if ([[FTLocationManager sharedInstance].location.country isEqualToString:@"N/A"]) {
    [[FTLocationManager sharedInstance] startUpdatingLocation];
    __block BOOL isUpdate = NO;
    [FTLocationManager sharedInstance].updateLocationBlock = ^(FTLocationInfo * _Nonnull locInfo, NSError * _Nullable error) {
        if (error) {
            NSString *message =error.domain;
            if(error.code == 104){
                message = [error.userInfo objectForKey:NSLocalizedDescriptionKey];
            }
            (callBack&&isUpdate==NO)?callBack(UnknownException,message):nil;
            ZYDebug(@"Location Error : %@",error);
        }else{
            ZYDebug(@"Location Success");
            (callBack&&isUpdate==NO)?callBack(0,nil):nil;
        }
        isUpdate = YES;
    };
    }else{
        ZYDebug(@"Location Success");
        callBack?callBack(0,nil):nil;
    }
}
#pragma mark --------- 初始化 config 设置 ----------
+ (void)startWithConfigOptions:(FTMobileConfig *)configOptions{
    NSAssert ((strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0),@"SDK 必须在主线程里进行初始化，否则会引发无法预料的问题（比如丢失 lunch 事件）。");
    if (configOptions.enableRequestSigning) {
        NSAssert((configOptions.akSecret.length!=0 && configOptions.akId.length != 0), @"设置需要进行请求签名 必须要填akId与akSecret");
    }
    if (configOptions.autoTrackEventType != FTAutoTrackTypeNone && configOptions.enableAutoTrack) {
        NSAssert((NSClassFromString(@"FTAutoTrack")), @"开启自动采集需导入FTAutoTrackSDK");
    }
    NSAssert((configOptions.metricsUrl.length!=0 ), @"请设置FT-GateWay metrics 写入地址");
    if (configOptions.product.length>0) {
        NSAssert(([FTBaseInfoHander verifyProductStr:[NSString stringWithFormat:@"flow_mobile_activity_%@",configOptions.product]]), @"product命名只能包含英文字母、数字、中划线和下划线，最长 20 个字符，区分大小写");
    }
    if (sharedInstance) {
        [[FTMobileAgent sharedInstance] resetConfig:configOptions];
    }
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FTMobileAgent alloc] initWithConfig:configOptions];
    });
}
// 单例
+ (instancetype)sharedInstance {
    NSAssert(sharedInstance, @"请先使用 startWithConfigOptions: 初始化 SDK");
    return sharedInstance;
}
- (instancetype)initWithConfig:(FTMobileConfig *)config{
    if ([super init]) {
        //基础类型的记录
        if (config) {
            self.config = config;
        }
        [[FTMonitorManager sharedInstance] setMonitorType:self.config.monitorInfoType];
        [[FTMonitorManager sharedInstance] setFlushInterval:self.config.flushInterval];
        NSString *label = [NSString stringWithFormat:@"io.zy.%p", self];
        self.serialQueue = dispatch_queue_create([label UTF8String], DISPATCH_QUEUE_SERIAL);
        NSString *immediateLabel = [NSString stringWithFormat:@"io.immediateLabel.%p", self];
        self.immediateLabel = dispatch_queue_create([immediateLabel UTF8String], DISPATCH_QUEUE_SERIAL);
        [self setupAppNetworkListeners];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadFlush) name:@"FTUploadNotification" object:nil];
        if (self.config.enableAutoTrack) {
            [self startAutoTrack];
        }
        self.upTool = [[FTUploadTool alloc]initWithConfig:self.config];
    }
    return self;
}
-(void)startAutoTrack{
    NSString *invokeMethod = @"startWithConfig:";
    Class track =  NSClassFromString(@"FTAutoTrack");
    if (track) {
        id  autoTrack = [[NSClassFromString(@"FTAutoTrack") alloc]init];
        SEL startMethod = NSSelectorFromString(invokeMethod);
        IMP imp = [autoTrack methodForSelector:startMethod];
        void (*func)(id, SEL,id) = (void (*)(id,SEL,id))imp;
        func(autoTrack,startMethod,self.config);
        objc_setAssociatedObject(self, &FTAutoTrack, autoTrack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
-(void)resetConfig:(FTMobileConfig *)config{
    config.sdkTrackVersion = self.config.sdkTrackVersion;
    id autotrack = objc_getAssociatedObject(self, &FTAutoTrack);
    self.config = config;
    if (!autotrack) {
        if (self.config.enableAutoTrack) {
            [self startAutoTrack];
        }
    }
    [[FTMonitorManager sharedInstance] setMonitorType:config.monitorInfoType];
    self.upTool.config = config;
}
#pragma mark ========== publick method ==========
- (void)trackBackground:(NSString *)measurement field:(NSDictionary *)field{
    [self trackBackground:measurement tags:nil field:field];
}
- (void)trackBackground:(NSString *)measurement tags:(nullable NSDictionary*)tags field:(NSDictionary *)field{
    @try {
        NSParameterAssert(measurement);
        NSParameterAssert(field);
        if (measurement == nil || [FTBaseInfoHander removeFrontBackBlank:measurement].length == 0  || field == nil || [field allKeys].count == 0) {
            ZYDebug(@"文件名 事件名不能为空");
            return;
        }
        NSMutableDictionary *opdata =  [NSMutableDictionary dictionaryWithDictionary:@{
            @"measurement":measurement,
            @"field":field
        }];
        NSMutableDictionary *tag = [NSMutableDictionary new];
        if (tags) {
            [tag addEntriesFromDictionary:tags];
        }
        
        [opdata addEntriesFromDictionary:@{@"tags":tag}];
        [self insertDBWithOpdata:opdata op:@"cstm"];
        
    }
    @catch (NSException *exception) {
        ZYDebug(@"track measurement tags field exception %@",exception);
    }
}

-(void)trackImmediate:(NSString *)measurement field:(NSDictionary *)field callBack:(void (^)(NSInteger statusCode, id _Nullable responseObject))callBackStatus{
    [self trackImmediate:measurement tags:nil field:field callBack:^(NSInteger statusCode, id _Nullable responseObject) {
        callBackStatus? callBackStatus(statusCode,responseObject):nil;
    }];
}
- (void)trackImmediate:(NSString *)measurement tags:(NSDictionary *)tags field:(NSDictionary *)field callBack:(void (^)(NSInteger, id _Nullable))callBackStatus{
    @try {
        NSParameterAssert(measurement);
        NSParameterAssert(field);
        if (measurement == nil || [FTBaseInfoHander removeFrontBackBlank:measurement].length == 0 || field == nil || [field allKeys].count == 0) {
            ZYDebug(@"文件名 事件名不能为空");
            callBackStatus?callBackStatus(InvalidParamsException,nil):nil;
            return;
        }
        FTRecordModel *model = [FTRecordModel new];
        NSMutableDictionary *tag = [NSMutableDictionary new];
        NSMutableDictionary *fieldDict = [field mutableCopy];
        if (tags) {
            [tag addEntriesFromDictionary:tags];
        }
        NSDictionary *addDict = [[FTMonitorManager sharedInstance] getMonitorTagFiledDict];
        if ([addDict objectForKey:@"tag"]) {
            [tag addEntriesFromDictionary:[addDict objectForKey:@"tag"]];
        }
        if ([addDict objectForKey:@"field"]) {
            [fieldDict addEntriesFromDictionary:[addDict objectForKey:@"field"]];
        }
        NSMutableDictionary *opdata =  [NSMutableDictionary dictionaryWithDictionary:@{
            @"measurement":measurement,
            @"field":fieldDict,
            @"tags":tag,
        }];
        
        NSDictionary *data =@{
            @"op":@"cstm",
            @"opdata":opdata,
        };
        model.data =[FTBaseInfoHander ft_convertToJsonData:data];
        
        model.tm = [FTBaseInfoHander ft_getCurrentTimestamp];
        ZYDebug(@"trackImmediateData == %@",data);
        [self trackUpload:@[model] callBack:callBackStatus];
    }
    @catch (NSException *exception) {
        ZYDebug(@"track measurement tags field exception %@",exception);
    }
}
- (void)trackImmediateList:(NSArray <FTTrackBean *>*)trackList callBack:(void (^)(NSInteger statusCode, _Nullable id responseObject))callBackStatus{
    NSParameterAssert(trackList);
    __block NSMutableArray *list = [NSMutableArray new];
    [trackList enumerateObjectsUsingBlock:^(FTTrackBean * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.measurement.length>0 && obj.field.allKeys.count>0) {
            FTRecordModel *model = [FTRecordModel new];
            NSMutableDictionary *tag = [NSMutableDictionary new];
            NSMutableDictionary *field = [obj.field mutableCopy];
            if (obj.tags) {
                [tag addEntriesFromDictionary:obj.tags];
            }
            NSDictionary *addDict = [[FTMonitorManager sharedInstance] getMonitorTagFiledDict];
            if ([addDict objectForKey:@"tag"]) {
                [tag addEntriesFromDictionary:[addDict objectForKey:@"tag"]];
            }
            if ([addDict objectForKey:@"field"]) {
                [field addEntriesFromDictionary:[addDict objectForKey:@"field"]];
            }
            NSDictionary *data =@{
                @"op":@"cstm",
                @"opdata":@{@"measurement":obj.measurement,
                            @"field":field,
                            @"tags":tag,
                },
            };
            model.data =[FTBaseInfoHander ft_convertToJsonData:data];
            if(obj.timeMillis && obj.timeMillis>1000000000000){
                model.tm = obj.timeMillis*1000;
            }else{
                model.tm = [FTBaseInfoHander ft_getCurrentTimestamp];
            }
            [list addObject:model];
        }else{
            ZYLog(@"传入的第 %d 个数据格式有误",idx);
        }
    }];
    if (list.count>0) {
        [self trackUpload:list callBack:callBackStatus];
    }else{
        ZYLog(@"传入的数据格式有误");
        callBackStatus?callBackStatus(InvalidParamsException,nil):nil;
    }
    
}
-(void)trackUpload:(NSArray<FTRecordModel *> *)list callBack:(void (^)(NSInteger statusCode, _Nullable id responseObject))callBack{
    if ([self.net isEqualToString:@"-1"]) {
        callBack? callBack(NetWorkException,nil):nil;
    }else{
    dispatch_async(self.immediateLabel, ^{
        [self.upTool trackImmediateList:list callBack:^(NSInteger statusCode, NSData * _Nonnull response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                callBack? callBack(statusCode,[[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]):nil;
            });
        }];
    });
    }
}
-(void)flowTrack:(NSString *)product traceId:(NSString *)traceId name:(NSString *)name parent:(NSString *)parent duration:(long)duration{
    [self flowTrack:product traceId:traceId name:name parent:parent tags:nil duration:duration field:nil];
}

- (void)flowTrack:(NSString *)product traceId:(NSString *)traceId name:(nonnull NSString *)name parent:(nullable NSString *)parent tags:(nullable NSDictionary *)tags duration:(long)duration field:(nullable NSDictionary *)field{
    @try {
        NSParameterAssert(product);
        NSParameterAssert(traceId);
        NSParameterAssert(name);
        if ([FTBaseInfoHander removeFrontBackBlank:product].length == 0 ||  [FTBaseInfoHander removeFrontBackBlank:traceId].length== 0||[FTBaseInfoHander removeFrontBackBlank:name].length==0) {
            ZYDebug(@"产品名、跟踪ID、name、parent 不能为空");
            return;
        }
        NSString *productStr = [NSString stringWithFormat:@"flow_%@",product];
        if (![FTBaseInfoHander verifyProductStr:productStr]) {
            return;
        }
        NSMutableDictionary *fieldDict = @{@"$duration":[NSNumber numberWithLong:duration]}.mutableCopy;
        NSMutableDictionary *tag =@{@"$traceId":traceId,
                                    @"$name":name,
        }.mutableCopy;
        if (parent.length>0) {
            [tag setObject:parent forKey:@"$parent"];
        }
        if (field.allKeys.count>0) {
            [fieldDict addEntriesFromDictionary:field];
        }
        if (tags) {
            [tag addEntriesFromDictionary:tags];
        }
        NSDictionary *opdata = @{@"measurement":[NSString stringWithFormat:@"$%@",productStr],
                                 @"tags":tag,
                                 @"field":fieldDict,
        };

        [self insertDBWithOpdata:opdata op:@"flowcstm"];
        
    } @catch (NSException *exception) {
        ZYDebug(@"flowTrack product traceId name exception %@",exception);
    }
}

- (void)bindUserWithName:(NSString *)name Id:(NSString *)Id exts:(NSDictionary *)exts{
    NSParameterAssert(name);
    NSParameterAssert(Id);
    [[FTTrackerEventDBTool sharedManger] insertUserDataWithName:name Id:Id exts:exts];
}
-(void)setMonitorFlushInterval:(NSInteger)interval{
    _config.flushInterval = interval;
    [[FTMonitorManager sharedInstance] setFlushInterval:interval];
}
-(void)startMonitorFlush{
    [[FTMonitorManager sharedInstance] startFlush];
}
-(void)setConnectBluetoothCBUUID:(nullable NSArray<CBUUID *> *)serviceUUIDs{
    [[FTMonitorManager sharedInstance] setConnectBluetoothCBUUID:serviceUUIDs];
}
- (void)logout{
    NSUserDefaults *defatluts = [NSUserDefaults standardUserDefaults];
    [defatluts removeObjectForKey:FT_SESSIONID];
    [defatluts synchronize];
    ZYDebug(@"User logout");
}
- (void)resetInstance{
    [[FTMonitorManager sharedInstance] resetInstance];
    [[FTLocationManager sharedInstance] resetInstance];
    self.config = nil;
    objc_setAssociatedObject(self, &FTAutoTrack, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_removeAssociatedObjects(self);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.upTool = nil;
    onceToken = 0;
    sharedInstance =nil;
}
#pragma mark ========== private method==========
#pragma mark --------- 数据拼接 存储数据库 ----------
//处理 监控项 动态获取的tag和field 的添加
- (void)insertDBWithOpdata:(NSDictionary *)dict op:(NSString *)op{
    FTRecordModel *model = [FTRecordModel new];
    NSMutableDictionary *opdata = [dict mutableCopy];
    NSMutableDictionary *tag = [NSMutableDictionary new];
    NSMutableDictionary *field = [NSMutableDictionary new];
    if ([opdata.allKeys containsObject:@"tags"]) {
        [tag addEntriesFromDictionary:opdata[@"tags"]];
    }
    [field addEntriesFromDictionary:opdata[@"field"]];
    // 流程图不添加 监控项 和 设备信息
    if (![op isEqualToString:@"flowcstm"] && ![op isEqualToString:@"view"]) {
        
        NSDictionary *addDict = [[FTMonitorManager sharedInstance] getMonitorTagFiledDict];
        
        if ([addDict objectForKey:@"tag"]) {
            [tag addEntriesFromDictionary:[addDict objectForKey:@"tag"]];
        }
        if ([addDict objectForKey:@"field"]) {
            [field addEntriesFromDictionary:[addDict objectForKey:@"field"]];
        }
        [opdata setValue:tag forKey:@"tags"];
        [opdata setValue:field forKey:@"field"];
    }
    NSDictionary *data =@{@"op":op,
                          @"opdata":opdata,
    };
    ZYDebug(@"insert DB data == %@",data);
    model.data =[FTBaseInfoHander ft_convertToJsonData:data];
    [[FTTrackerEventDBTool sharedManger] insertItemWithItemData:model];
}

#pragma mark --------- 网络与App的生命周期 ---------
- (void)setupAppNetworkListeners{
    BOOL reachabilityOk = NO;
    if ((_reachability = SCNetworkReachabilityCreateWithName(NULL, "www.baidu.com")) != NULL) {
        SCNetworkReachabilityContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
        if (SCNetworkReachabilitySetCallback(_reachability, ZYReachabilityCallback, &context)) {
            if (SCNetworkReachabilitySetDispatchQueue(_reachability, self.serialQueue)) {
                reachabilityOk = YES;
            } else {
                SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
            }
        }
    }
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    // 应用生命周期通知
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillTerminate:)
                               name:UIApplicationWillTerminateNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActive:)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackground:)
                               name:UIApplicationDidEnterBackgroundNotification
                             object:nil];
    
}
- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags {
    if (flags & kSCNetworkReachabilityFlagsReachable) {
        if (flags & kSCNetworkReachabilityFlagsIsWWAN) {
            self.net = @"0";//2G/3G/4G
            [self uploadFlush];
        } else {
            self.net = @"4";//WIFI
            [self uploadFlush];
        }
    } else {
        self.net = @"-1";//未知
    }
    ZYDebug(@"联网状态: %@", [@"-1" isEqualToString:self.net]?@"未知":[@"0" isEqualToString:self.net]?@"移动网络":@"WIFI");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    ZYDebug(@"applicationWillTerminate ");
}
- (void)applicationWillResignActive:(NSNotification *)notification {
    @try {
        self.isForeground = NO;
    }
    @catch (NSException *exception) {
        ZYDebug(@"applicationWillResignActive exception %@",exception);
    }
}
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    @try {
        self.isForeground = YES;
        [self uploadFlush];
    }
    @catch (NSException *exception) {
        ZYDebug(@"applicationDidBecomeActive exception %@",exception);
    }
}
- (void)applicationDidEnterBackground:(NSNotification *)notification {
    ZYDebug(@"applicationDidEnterBackground ");
}

#pragma mark --------- 上报策略 ----------
- (void)uploadFlush{
    
    dispatch_async(self.serialQueue, ^{
        if (![self.net isEqualToString:@"-1"]) {
            [self.upTool upload];
        }
    });
}
@end
