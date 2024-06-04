//
//  FTNetworkMock.m
//  Examples
//
//  Created by hulilei on 2024/5/16.
//  Copyright © 2024 GuanceCloud. All rights reserved.
//

#import "FTNetworkMock.h"
#import "OHHTTPStubs.h"
#import "FTJSONUtil.h"
typedef void (^CompletionHandler)(void);
static CompletionHandler g_handler;

@implementation FTNetworkMock
+ (void)registerHandler:(void (^)(void))handler{
    g_handler = handler;
}
+ (void)networkOHHTTPStubs{
    [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        return YES;
    } withStubResponse:^OHHTTPStubsResponse*(NSURLRequest *request) {
        NSString *data  =[FTJSONUtil convertToJsonData:@{@"data":@"Hello World!",@"code":@200}];
        NSData *requestData = [data dataUsingEncoding:NSUTF8StringEncoding];
        return [OHHTTPStubsResponse responseWithData:requestData statusCode:200 headers:nil];
    }];
}
+ (void)networkOHHTTPStubsHandler{
    [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        return YES;
    } withStubResponse:^OHHTTPStubsResponse*(NSURLRequest *request) {
        NSString *data  =[FTJSONUtil convertToJsonData:@{@"data":@"Hello World!",@"code":@200}];
        NSData *requestData = [data dataUsingEncoding:NSUTF8StringEncoding];
        if(g_handler){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                g_handler();
                g_handler = nil;
            });
        }
        return [OHHTTPStubsResponse responseWithData:requestData statusCode:200 headers:nil];
    }];
}
@end
