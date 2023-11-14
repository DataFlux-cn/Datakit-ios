//
//  FTURLSessionInterceptor.m
//  FTMobileAgent
//
//  Created by hulilei on 2022/3/17.
//  Copyright © 2022 DataFlux-cn. All rights reserved.
//

#import "FTURLSessionInterceptor.h"
#import "FTSessionTaskHandler.h"
#import "FTResourceContentModel.h"
#import "FTResourceMetricsModel.h"
#import "FTReadWriteHelper.h"
#import "FTInternalLog.h"
@interface FTURLSessionInterceptor ()
@property (nonatomic, strong) FTReadWriteHelper<NSMutableDictionary <id,FTSessionTaskHandler *>*> *traceHandlers;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, weak) id<FTTracerProtocol> tracer;
@property (nonatomic, strong) dispatch_queue_t queue;
@end
@implementation FTURLSessionInterceptor
@synthesize rumResourceHandeler = _rumResourceHandeler;
@synthesize intakeUrlHandler = _intakeUrlHandler;
static FTURLSessionInterceptor *sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)shared{
    dispatch_once(&onceToken, ^{
        sharedInstance = [[super allocWithZone:NULL] init];
    });
    return sharedInstance;
}
-(instancetype)init{
    self = [super init];
    if (self) {
        _traceHandlers = [[FTReadWriteHelper alloc]initWithValue:[NSMutableDictionary new]];
        _queue = dispatch_queue_create("com.network.interceptor", DISPATCH_QUEUE_SERIAL);

    }
    return self;
}
- (void)setTracer:(id<FTTracerProtocol>)tracer{
    _tracer = tracer;
}
- (BOOL)isTraceUrl:(NSURL *)url{
    if(self.intakeUrlHandler){
        return self.intakeUrlHandler(url);
    }
    return YES;
}
/**
 * 内部采集以 task 为 key
 * 外部传传入为 NSString 类型的 key
 */
- (void)setTraceHandler:(FTSessionTaskHandler *)handler forKey:(id)key{
    if (key == nil) {
        return;
    }
    [self.traceHandlers concurrentWrite:^(NSMutableDictionary<id,FTSessionTaskHandler *> * _Nonnull value) {
        [value setValue:handler forKey:key];
    }];
}
// 因为不涉及 trace 数据写入 调用-getTraceHandler方法的仅是 rum 操作 需要确保 rum 调用此方法
- (FTSessionTaskHandler *)getTraceHandler:(id)key{
    if (key == nil) {
        return nil;
    }
    __block FTSessionTaskHandler *handler;
    [self.traceHandlers concurrentRead:^(NSMutableDictionary<id,FTSessionTaskHandler *> * _Nonnull value) {
        handler = [value objectForKey:key];
    }];
    return handler;
}
-(void)removeTraceHandlerWithKey:(id)key{
    if (key == nil) {
        return;
    }
    [self.traceHandlers concurrentWrite:^(NSMutableDictionary<id,FTSessionTaskHandler *> * _Nonnull value) {
        [value removeObjectForKey:key];
    }];
}
#pragma mark --------- URLSessionInterceptorType ----------
-(void)setIntakeUrlHandler:(FTIntakeUrl)intakeUrlHandler{
    _intakeUrlHandler = intakeUrlHandler;
}
-(FTIntakeUrl)intakeUrlHandler{
    return _intakeUrlHandler;
}
-(void)setRumResourceHandeler:(id<FTRumResourceProtocol>)innerResourceHandeler{
    _rumResourceHandeler = innerResourceHandeler;
}
-(id<FTRumResourceProtocol>)rumResourceHandeler{
    if(!_rumResourceHandeler){
        FTInnerLogError(@"SDK configuration RUM error, RUM is not supported");
    }
    return _rumResourceHandeler;
}
- (NSURLRequest *)interceptRequest:(NSURLRequest *)request{
    NSURLRequest *backRequest = request;
    if(_tracer){
        NSMutableURLRequest *mutableReqeust = [backRequest mutableCopy];
        NSDictionary *traceHeader = [self.tracer networkTraceHeaderWithUrl:request.URL];
        if (traceHeader && traceHeader.allKeys.count>0) {
            [traceHeader enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
                [mutableReqeust setValue:value forHTTPHeaderField:field];
            }];
        }
        backRequest = mutableReqeust;
    }
    if(self.requestInterceptor){
        return self.requestInterceptor(backRequest)?:backRequest;
    }
    return backRequest;
}
- (void)interceptTask:(NSURLSessionTask *)task{
    dispatch_async(self.queue, ^{
        if(!task.originalRequest){
            return;
        }
        FTSessionTaskHandler *handler = [self getTraceHandler:task];
        if(!handler){
            FTSessionTaskHandler *handler = [[FTSessionTaskHandler alloc]init];
            handler.request = task.originalRequest;
            [self setTraceHandler:handler forKey:task];
            [self startResourceWithKey:handler.identifier];
        }
    });
}
- (void)taskMetricsCollected:(NSURLSessionTask *)task metrics:(NSURLSessionTaskMetrics *)metrics{
    dispatch_async(self.queue, ^{
        FTSessionTaskHandler *handler = [self getTraceHandler:task];
        if(!handler){
            return;
        }
        [handler taskReceivedMetrics:metrics];
    });
}
- (void)taskReceivedData:(NSURLSessionTask *)task data:(NSData *)data{
    dispatch_async(self.queue, ^{
        FTSessionTaskHandler *handler = [self getTraceHandler:task];
        if(!handler){
            return;
        }
        [handler taskReceivedData:data];
    });
}
- (void)taskCompleted:(NSURLSessionTask *)task error:(NSError *)error{
    dispatch_async(self.queue, ^{
        FTSessionTaskHandler *handler = [self getTraceHandler:task];
        if(!handler){
            return;
        }
        [handler taskCompleted:task error:error];
        [self removeTraceHandlerWithKey:task];
        NSDictionary *property;
        if(self.provider){
            property = self.provider(handler.request, handler.response, handler.data, handler.error);
        }
        [self stopResourceWithKey:handler.identifier property:property];
        __block NSString *span_id = nil,*trace_id=nil;
        if (self.tracer.enableLinkRumData) {
            [self.tracer unpackTraceHeader:task.currentRequest.allHTTPHeaderFields handler:^(NSString * _Nullable traceId, NSString * _Nullable spanID) {
                span_id = spanID;
                trace_id = traceId;
            }];
        }
        [self addResourceWithKey:handler.identifier metrics:handler.metricsModel content:handler.contentModel spanID:span_id traceID:trace_id];
    });
}

#pragma mark --------- external data ----------
// skywalking 需要参数 URL
-(NSDictionary *)getTraceHeaderWithKey:(NSString *)key url:(NSURL *)url{
    if(!_tracer){
        FTInnerLogError(@"SDK configuration Trace error, trace is not supported");
        return nil;
    }
    __block FTSessionTaskHandler *handler = [[FTSessionTaskHandler alloc]initWithIdentifier:key];
    NSDictionary *dict = nil;
    if(self.tracer.enableLinkRumData){
       dict = [self.tracer networkTraceHeaderWithUrl:url handler:^(NSString * _Nullable traceId, NSString * _Nullable spanID) {
            handler.traceID = traceId;
            handler.spanID = spanID;
        }];
        [self setTraceHandler:handler forKey:key];
    }
    else{
        dict = [self.tracer networkTraceHeaderWithUrl:url];
    }
    return  dict;
}
- (void)startResourceWithKey:(NSString *)key{
    if (self.rumResourceHandeler && [self.rumResourceHandeler respondsToSelector:@selector(startResourceWithKey:)]) {
        [self.rumResourceHandeler startResourceWithKey:key];
    }
}
- (void)startResourceWithKey:(NSString *)key property:(nullable NSDictionary *)property{
    if (self.rumResourceHandeler && [self.rumResourceHandeler respondsToSelector:@selector(startResourceWithKey:property:)]) {
        [self.rumResourceHandeler startResourceWithKey:key property:property];
    }
}
- (void)stopResourceWithKey:(nonnull NSString *)key{
    if (self.rumResourceHandeler && [self.rumResourceHandeler respondsToSelector:@selector(stopResourceWithKey:)]) {
        [self.rumResourceHandeler stopResourceWithKey:key];
    }
}
-(void)stopResourceWithKey:(NSString *)key property:(NSDictionary *)property{
    if (self.rumResourceHandeler && [self.rumResourceHandeler respondsToSelector:@selector(stopResourceWithKey:property:)]) {
        [self.rumResourceHandeler stopResourceWithKey:key property:property];
    }
}
- (void)addResourceWithKey:(NSString *)key metrics:(nullable FTResourceMetricsModel *)metrics content:(FTResourceContentModel *)content{
    FTSessionTaskHandler *handler = [self getTraceHandler:key];
    [self removeTraceHandlerWithKey:key];
    [self addResourceWithKey:key metrics:metrics content:content spanID:handler.spanID traceID:handler.traceID];
}
- (void)addResourceWithKey:(NSString *)key metrics:(nullable FTResourceMetricsModel *)metrics content:(FTResourceContentModel *)content spanID:(nullable NSString *)spanID traceID:(nullable NSString *)traceID{
    [self removeTraceHandlerWithKey:key];
    if (self.rumResourceHandeler && [self.rumResourceHandeler respondsToSelector:@selector(addResourceWithKey:metrics:content:spanID:traceID:)]) {
        [self.rumResourceHandeler addResourceWithKey:key metrics:metrics content:content spanID:spanID traceID:traceID];
    }
}
- (void)shutDown{
    dispatch_sync(self.queue, ^{});
    onceToken = 0;
    sharedInstance =nil;
}
@end
