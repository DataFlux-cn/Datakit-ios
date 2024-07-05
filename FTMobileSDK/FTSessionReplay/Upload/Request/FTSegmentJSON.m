//
//  FTSegmentJSON.m
//  FTMobileSDK
//
//  Created by hulilei on 2024/6/28.
//  Copyright © 2024 DataFlux-cn. All rights reserved.
//

#import "FTSegmentJSON.h"
#import "FTConstants.h"
@implementation FTSegmentJSON
-(instancetype)initWithData:(NSData *)data source:(NSString *)source{
    self = [super init];
    if(self){
        NSError *error;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        _appId = dict[@"applicationID"];
        _sessionID = dict[@"sessionID"];
        _viewID = dict[@"viewID"];
        _source = source?source:@"ios";
        _start = INT_MAX;
        _end = INT_MIN;
        NSArray *array = dict[@"records"];
        for (NSDictionary *record in array) {
            NSInteger type = [record[@"type"] integerValue];
            if (type == 0 || type == 2){
                _hasFullSnapshot = YES;
            }
            long long startTimestamp = [record[@"timestamp"] longLongValue];
            long long endTimestamp = [record[@"timestamp"] longLongValue];
            _start = MIN(_start, startTimestamp);
            _end = MAX(_end, endTimestamp);
        }
        _recordsCount = array.count;
        _records = array;
    }
    return self;
}
- (void)mergeAnother:(FTSegmentJSON *)another{
    NSMutableArray *records = [NSMutableArray arrayWithArray:_records];
    [records addObjectsFromArray:another.records];
    self.records = records;
    _start = MIN(_start, another.start);
    _end = MAX(_end, another.end);
    _recordsCount = _recordsCount + another.recordsCount;
    _hasFullSnapshot = _hasFullSnapshot || another.hasFullSnapshot;
}
- (NSDictionary *)toJSONODict{
    return @{FT_RUM_KEY_SESSION_ID:self.sessionID,
             FT_KEY_VIEW_ID:self.viewID,
             FT_APP_ID:self.appId,
             @"start":@(self.start),
             @"end":@(self.end),
             @"has_full_snapshot":self.hasFullSnapshot?@"true":@"false",
             @"records_count":@(self.recordsCount),
             @"records":self.records,
             @"source":self.source,
    };
}
@end
