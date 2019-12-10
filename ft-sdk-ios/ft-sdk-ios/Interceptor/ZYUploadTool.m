//
//  ZYUploadTool.m
//  ft-sdk-ios
//
//  Created by 胡蕾蕾 on 2019/12/3.
//  Copyright © 2019 hll. All rights reserved.
//

#import "ZYUploadTool.h"
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import "ZYBaseInfoHander.h"
#import "ZYTrackerEventDBTool.h"
#import "ZYLog.h"
#import "RecordModel.h"
#import "FTMobileConfig.h"
@interface ZYUploadTool()
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, assign) BOOL isUploading;
@property (nonatomic, strong) FTMobileConfig *config;

@end
@implementation ZYUploadTool
-(instancetype)initWithConfig:(FTMobileConfig *)config{
     self = [super init];
       if (self) {
           self.config = config;
       }
       return self;
}
-(void)upload{
    if (!self.isUploading) {
        //当前数据库所有数据
        self.isUploading = YES;
        [self flushQueue];
    }
}
- (void)flushQueue{
   
    @try {
        while ([[ZYTrackerEventDBTool sharedManger] getDatasCount]>0){
            ZYDebug(@"DB DATAS COUNT = %ld",[[ZYTrackerEventDBTool sharedManger] getDatasCount]);
         NSArray *updata = [[ZYTrackerEventDBTool sharedManger] getFirstTenData];
        
         RecordModel *model = [updata lastObject];
         BOOL scuess = [self apiRequestWithEventsAry:updata andError:nil];
            if (!scuess) {//请求失败
                ZYDebug(@"上传事件失败");
                break;
            }
                ZYDebug(@"上传事件成功");
            BOOL delect = [[ZYTrackerEventDBTool sharedManger] deleteItemWithTm:model.tm];
            ZYDebug(@"delect == %d",delect);
        }
        self.isUploading = NO;
    }
    @catch (NSException *exception) {
         ZYDebug(@"flushQueue exception %@",exception);
    }
}
- (BOOL)apiRequestWithEventsAry:(NSArray *)events andError:(NSError *)error {
    __block BOOL success =NO;
    __block int  retry = 0;
    NSString *requestData = [self getRequestDataWithEventArray:events];
   
        NSString *date =[ZYBaseInfoHander currentGMT];
        NSURL *url = [NSURL URLWithString:@"http://10.100.64.106:19557/v1/write/metrics"];
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
            //设置请求地址
        //添加header
        NSMutableURLRequest *mutableRequest = [request mutableCopy];    //拷贝request
         
       
        mutableRequest.HTTPMethod = @"POST";
         //添加header
        [mutableRequest addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [mutableRequest addValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
        [mutableRequest addValue:@"charset=utf-8" forHTTPHeaderField:@"Content-Type"];

            //设置请求参数
        [mutableRequest setValue:self.config.sdkUUID forHTTPHeaderField:@"X-Datakit-UUID"];
        [mutableRequest setValue:date forHTTPHeaderField:@"Date"];
        [mutableRequest setValue:@"forethought datakit" forHTTPHeaderField:@"User-Agent"];
        [mutableRequest setValue:@"zh-CN" forHTTPHeaderField:@"Accept-Language"];
        mutableRequest.HTTPBody = [requestData dataUsingEncoding:NSUTF8StringEncoding];
        if (self.config.enableRequestSigning) {
            NSString *authorization = [NSString stringWithFormat:@"DWAY %@:%@",self.config.akId,[ZYBaseInfoHander getSSOSignWithAkSecret:self.config.akSecret datetime:date data:requestData]];
            [mutableRequest addValue:authorization forHTTPHeaderField:@"Authorization"];
        }
        request = [mutableRequest copy];        //拷贝回去
        
        ZYDebug(@"allHTTPHeaderFields == %@ mutableRequest.HTTPBody = %@", request.allHTTPHeaderFields,requestData);

 
            //设置请求session
            NSURLSession *session = [NSURLSession sharedSession];
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);

            //设置网络请求的返回接收器
            NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        ZYDebug(@"%@error1 = %@",error);
                        retry++;
                    }else{
                        NSError *errors;
                        NSMutableDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&errors];
                        if (errors){
                            ZYDebug(@"%@error2 = %@",error);
                            retry++;
                        }else {
                            ZYDebug(@"%@responseObject = %@",responseObject);
                            success = YES;
                        }
                    }
                     dispatch_group_leave(group);
                });
                   
            }];
        //开始请求
            [dataTask resume];
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    return success;
}

// 更新网络指示器
- (void)updateNetworkActivityIndicator:(BOOL)on {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = on;
    });
}
- (NSString *)getRequestDataWithEventArray:(NSArray *)events{
    NSMutableString *requestDatas = [NSMutableString new];
   
    [events enumerateObjectsUsingBlock:^(RecordModel *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *item = [ZYBaseInfoHander dictionaryWithJsonString:obj.data];
        NSString *event = [item valueForKey:@"op"];
        NSString *cpn = [item valueForKey:@"cpn"];
        NSString *rpn = [item valueForKey:@"rpn"];
        if (rpn.length==0) {
            rpn = @"null";
        }
        NSDictionary *opdata = item[@"opdata"];
        if (idx==0) {
                  [requestDatas appendString:[self getBasicData]];
               
        }else{
                  [requestDatas appendFormat:@"\n%@",[self getBasicData]];
               }
        if (opdata) {
            [opdata enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                [requestDatas appendFormat:@"%@=%@,",key,obj];
            }];
        }
        if(cpn){
            [requestDatas appendFormat:@"current_page_name=%@,",cpn];
        }
        if (rpn) {
            [requestDatas appendFormat:@"root_page_name=%@",rpn];
        }
        [requestDatas appendFormat:@" event=\"%@\"",event];
        [requestDatas appendFormat:@" %ld",obj.tm*1000*1000];
    
    }];
  
    return requestDatas;
}
- (NSString *)getBasicData{
    if (_tag != nil) {
        return _tag;
    }
    CFUUIDRef puuid = CFUUIDCreate ( nil ) ;
    CFStringRef uuidString = CFUUIDCreateString ( nil , puuid ) ;
    NSString* uuid = (NSString*)CFBridgingRelease(CFStringCreateCopy(NULL, uuidString));
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    CFShow((__bridge CFTypeRef)(infoDictionary));
    NSString *app_Name = [infoDictionary objectForKey:@"CFBundleDisplayName"];
    NSString *identifier = [infoDictionary objectForKey:@"CFBundleIdentifier"];
    NSString *app_Version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];

    NSString *preferredLanguage = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    NSString *version = [UIDevice currentDevice].systemVersion;
    NSMutableString *tag = [NSMutableString string];
    [tag appendString:@"mobile_tracker,"];
    [tag appendFormat:@"device_uuid=%@,",uuid];
    [tag appendFormat:@"application_identifier=%@,",identifier];
    [tag appendFormat:@"application_name=%@,",app_Name];
    [tag appendFormat:@"sdk_version=%@,",app_Version];
    [tag appendString:@"os=iOS,"];
    [tag appendFormat:@"os_version=%@,",version];
    [tag appendString:@"imei=null,"];
    [tag appendString:@"device_band=APPLE,"];
    [tag appendFormat:@"locale=%@,",preferredLanguage];
    [tag appendFormat:@"device_model=%@,",[ZYBaseInfoHander getDeviceType]];
    [tag appendFormat:@"display=%@,",[ZYBaseInfoHander resolution]];
    [tag appendFormat:@"carrier=%@,",[ZYBaseInfoHander getTelephonyInfo]];
    _tag = [tag stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
    return _tag;
}

@end
