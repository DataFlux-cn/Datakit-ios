//
//  NSURLSession+FTSwizzler.m
//  FTMobileAgent
//
//  Created by hulilei on 2022/9/13.
//  Copyright © 2022 DataFlux-cn. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.


#import "NSURLSession+FTSwizzler.h"
#import "URLSessionAutoInstrumentation.h"
#import "FTURLSessionDelegate.h"
#import "FTURLSessionInterceptorProtocol.h"
typedef void (^CompletionHandler)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);
@implementation NSURLSession (FTSwizzler)
- (NSURLSessionDataTask *)ft_dataTaskWithURL:(NSURL *)url{
    if (self.delegate && [self.delegate conformsToProtocol:@protocol(FTURLSessionDelegateProviding)]){
        id<FTURLSessionDelegateProviding> ftDelegate = (id<FTURLSessionDelegateProviding>)self.delegate;
        FTURLSessionDelegate *sessionDelegate =  ftDelegate.ftURLSessionDelegate;
        id<URLSessionInterceptorType> interceptor = sessionDelegate.instrumentation.interceptor;
        NSURLSessionDataTask *task = [self ft_dataTaskWithURL:url];
        if (@available(iOS 13.0, *)) {
            [interceptor taskCreated:task session:self];
        }
        return task;
    }else{
        return [self ft_dataTaskWithURL:url];
    }
}
- (NSURLSessionDataTask *)ft_dataTaskWithURL:(NSURL *)url completionHandler:(CompletionHandler)completionHandler{
    if (self.delegate && [self.delegate conformsToProtocol:@protocol(FTURLSessionDelegateProviding)]){
        id<FTURLSessionDelegateProviding> ftDelegate = (id<FTURLSessionDelegateProviding>)self.delegate;
        FTURLSessionDelegate *sessionDelegate =  ftDelegate.ftURLSessionDelegate;
        id<URLSessionInterceptorType> interceptor = sessionDelegate.instrumentation.interceptor;
        
        NSURLSessionDataTask *task;
        if (completionHandler) {
            NSURLSessionDataTask *taskReference;
            CompletionHandler newCompletionHandler = ^(NSData * data, NSURLResponse * response, NSError * error){
                completionHandler(data,response,error);
                if (taskReference){
                    if (data) {
                        [interceptor taskReceivedData:taskReference data:data];
                    }
                    [interceptor taskCompleted:taskReference error:error];
                }
            };
            task = [self ft_dataTaskWithURL:url completionHandler:newCompletionHandler];
            taskReference = task;
        }
        [interceptor taskCreated:task session:self];
        return task;
    }else{
        return [self ft_dataTaskWithURL:url completionHandler:completionHandler];
    }
}
- (NSURLSessionDataTask *)ft_dataTaskWithRequest:(NSURLRequest *)request{
    if (self.delegate && [self.delegate conformsToProtocol:@protocol(FTURLSessionDelegateProviding)]){
        id<FTURLSessionDelegateProviding> ftDelegate = (id<FTURLSessionDelegateProviding>)self.delegate;
        FTURLSessionDelegate *sessionDelegate =  ftDelegate.ftURLSessionDelegate;
        id<URLSessionInterceptorType> interceptor = sessionDelegate.instrumentation.interceptor;
        NSURLRequest *newRequest = [interceptor injectTraceHeader:request];
        NSURLSessionDataTask *task = [self ft_dataTaskWithRequest:newRequest];
        if (@available(iOS 13.0, *)) {
            [interceptor taskCreated:task session:self];
        }
        return task;
    }else{
        return [self ft_dataTaskWithRequest:request];
    }
}
- (NSURLSessionDataTask *)ft_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(CompletionHandler)completionHandler{
    if (self.delegate && [self.delegate conformsToProtocol:@protocol(FTURLSessionDelegateProviding)]){
        id<FTURLSessionDelegateProviding> ftDelegate = (id<FTURLSessionDelegateProviding>)self.delegate;
        FTURLSessionDelegate *sessionDelegate =  ftDelegate.ftURLSessionDelegate;
        id<URLSessionInterceptorType> interceptor = sessionDelegate.instrumentation.interceptor;
        NSURLSessionDataTask *task;
        if (completionHandler) {
            NSURLSessionDataTask *taskReference;
            CompletionHandler newCompletionHandler = ^(NSData * data, NSURLResponse * response, NSError * error){
                completionHandler(data,response,error);
                if (taskReference){
                    if (data) {
                        [interceptor taskReceivedData:taskReference data:data];
                    }
                    [interceptor taskCompleted:taskReference error:error];
                }
            };
            NSURLRequest *newRequest = [interceptor injectTraceHeader:request];
            task = [self ft_dataTaskWithRequest:newRequest completionHandler:newCompletionHandler];
            taskReference = task;
        }
        [interceptor taskCreated:task session:self];
        return task;
        
    }else{
        return [self ft_dataTaskWithRequest:request completionHandler:completionHandler];
    }
}
@end
