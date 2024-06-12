//
//  FTSnapshotProcessor.m
//  FTMobileSDK
//
//  Created by hulilei on 2024/6/12.
//  Copyright © 2024 DataFlux-cn. All rights reserved.
//

#import "FTSnapshotProcessor.h"
#import "FTViewTreeSnapshotProducer.h"
#import "FTViewAttributes.h"
#import "FTTouchCircle.h"
#import "FTViewAttributes.h"
#import "FTSRWireframe.h"
#import "FTSRWireframesBuilder.h"
#import "NSDate+FTUtil.h"
#import "FTSRRecord.h"
#import "FTNodesFlattener.h"
@interface FTSnapshotProcessor()
/// 记录上一页面基本数据，用来判断是否是新页面
@property (nonatomic, strong) FTViewTreeSnapshot *lastSnapshot;
/// 用来比较增量数据
@property (nonatomic, strong) NSArray<FTSRWireframe *> *lastSRWireframes;
@property (nonatomic, strong) FTNodesFlattener *flattener;
@end
@implementation FTSnapshotProcessor
- (void)process:(FTViewTreeSnapshot *)viewTreeSnapshot touches:(NSMutableArray <FTTouchCircle *> *)touches{
    __weak typeof(self) weakSelf = self;

    dispatch_async(self.queue, ^{
        [weakSelf processSync:viewTreeSnapshot touches:touches];
    });
}

- (void)processSync:(FTViewTreeSnapshot *)viewTreeSnapshot touches:(NSMutableArray <FTTouchCircle *> *)touches{
        NSMutableArray<FTSRWireframe *> *wireframes = [[NSMutableArray alloc]init];
        NSArray<id <FTSRWireframesBuilder>> *nodes = [self.flattener flattenNodes:viewTreeSnapshot];
        for (id<FTSRWireframesBuilder> builder in nodes) {
            [wireframes addObjectsFromArray:[builder buildWireframes]];
        }
        // 2.将数据转换成存储要求的格式
        NSMutableArray<FTSRRecord> *records =(NSMutableArray<FTSRRecord>*)[[NSMutableArray alloc]init];
        // 3.进行判断是新增，还是新的 View
        // 3.1.新的 view 全量保存
        if (self.lastSnapshot == nil || self.lastSnapshot.context.sessionID != viewTreeSnapshot.context.sessionID || self.lastSnapshot.context.viewID != viewTreeSnapshot.context.viewID){
            // meta focus full
            FTSRMetaRecord *metaRecord = [[FTSRMetaRecord alloc]initWithViewTreeSnapshot:viewTreeSnapshot];
            FTSRFocusRecord *focusRecord = [[FTSRFocusRecord alloc]initWithTimestamp:[viewTreeSnapshot.context.date ft_nanosecondTimeStamp]];
            focusRecord.hasFocus = YES;
            FTSRFullSnapshotRecord *fullRecord = [[FTSRFullSnapshotRecord alloc]initWithTimestamp:[viewTreeSnapshot.context.date ft_nanosecondTimeStamp]];
            fullRecord.wireframes = wireframes;
            [records addObject:metaRecord];
            [records addObject:focusRecord];
            [records addObject:fullRecord];
        }else{
            // 3.2.已经存在 view ，进行增量判断，算法比较，获取 增量、减量、更新
            MutationData *mutation = [[MutationData alloc]initWithTimestamp:[viewTreeSnapshot.context.date ft_nanosecondTimeStamp]];
            [mutation createIncrementalSnapshotRecords:wireframes lastWireframes:self.lastSRWireframes];
            [records addObject:mutation];
        }
        // 4.将 touches 看做增量添加
        if (touches.count>0){
            long long tm =  [touches firstObject].timestamp;
            for (FTTouchCircle *touch in touches) {
                PointerInteractionData *pointer = [[PointerInteractionData alloc]initWithTimestamp:tm touch:touch];
                [records addObject:pointer];
            }
        }
        // 5.数据写入
        FTSRFullRecord *fullRecord = [[FTSRFullRecord alloc]initWithContext:viewTreeSnapshot.context records:records];
        NSDictionary *data = [fullRecord toDictionary];
        // 6.记录本次数据用于与下次数据比较
        self.lastSnapshot = viewTreeSnapshot;
        self.lastSRWireframes = wireframes;
}
@end
