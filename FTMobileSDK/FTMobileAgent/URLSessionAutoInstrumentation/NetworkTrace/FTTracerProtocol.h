//
//  FTTracerProtocol.h
//  FTMobileSDK
//
//  Created by hulilei on 2022/9/15.
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


#ifndef FTTracerProtocol_h
#define FTTracerProtocol_h
NS_ASSUME_NONNULL_BEGIN

typedef void(^UnpackTraceHeaderHandler)(NSString * _Nullable traceId, NSString *_Nullable spanID);

@protocol FTTracerProtocol<NSObject>
- (NSDictionary *)networkTraceHeaderWithUrl:(NSURL *)url;

- (void)unpackTraceHeader:(NSDictionary *)header handler:(UnpackTraceHeaderHandler)handler;
@end
NS_ASSUME_NONNULL_END
#endif /* FTTracerProtocol_h */
