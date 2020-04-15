//
//  FTLocationManager.m
//  FTMobileAgent
//
//  Created by 胡蕾蕾 on 2020/1/8.
//  Copyright © 2020 hll. All rights reserved.
//

#import "FTLocationManager.h"
#import <CoreLocation/CoreLocation.h>


#import "ZYLog.h"
@interface FTLocationManager () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@end
@implementation FTLocationManager
static FTLocationManager *sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)sharedInstance {
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}
- (instancetype)init {
    if (self = [super init]) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.country = @"N/A";
        self.city = @"N/A";
        self.province = @"N/A";
    }
    return self;
}
- (void)startUpdatingLocation {
    @try {
        //判断当前设备定位服务是否打开
        if (![CLLocationManager locationServicesEnabled]) {
            ZYDebug(@"设备尚未打开定位服务");
            return;
        }
        if (@available(iOS 8.0, *)) {
            [self.locationManager requestWhenInUseAuthorization];
        }
        if (_isUpdatingLocation == NO) {
            [self.locationManager startUpdatingLocation];
            _isUpdatingLocation = YES;
        }
    }@catch (NSException *e) {
        ZYDebug(@"%@ error: %@", self, e);
    }
}
-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations{
    CLLocation *currentLocation = [locations lastObject];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    
    [geocoder reverseGeocodeLocation:currentLocation completionHandler:^(NSArray *array, NSError *error){
        if (error) {
            self.isUpdatingLocation = NO;
            if (self.updateLocationBlock) {
                self.updateLocationBlock(self.country,self.province,self.city, error);
            }
            [manager stopUpdatingLocation];
            return;
        }
        if (array.count > 0){
            CLPlacemark *placemark = [array objectAtIndex:0];
            //将获得的所有信息显示到label上
            ZYDebug(@"%@",placemark.name);
            //获取城市
            NSString *province = placemark.administrativeArea;
            NSString *city = placemark.locality;
            NSString *country = placemark.country;
            if (!province){
                //四大直辖市的城市信息无法通过locality获得，只能通过获取省份的方法来获得（如果city为空，或province为空 则可知为直辖市）
                province =placemark.locality;
            }else if (!city) {
                //四大直辖市的城市信息无法通过locality获得，只能通过获取省份的方法来获得（如果city为空，则可知为直辖市）
                city = placemark.administrativeArea;
            }
            self.country = country;
            self.city = city;
            self.province = province;
            //暂时设置为APP一个生命周期内只需要获取一次
            [manager stopUpdatingLocation];
            if (self.isUpdatingLocation&&self.updateLocationBlock) {
                self.updateLocationBlock(country,province,city, error);
            }
            self.isUpdatingLocation = NO;
        }else if (error == nil && [array count] == 0){
            [manager stopUpdatingLocation];
            NSString *domain = @"com.ft.mobile.sdk.FTMobileAgent";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey:@"No results were returned."};
            NSError *error = [NSError errorWithDomain:domain
                                                 code:104
                                             userInfo:userInfo];
            ZYDebug(@"No results were returned.");
            if (self.isUpdatingLocation&&self.updateLocationBlock) {
                self.updateLocationBlock(self.country,self.province,self.city, error);
            }
            self.isUpdatingLocation = NO;
        }

    }];
    
}
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    switch (status)
    {
        case kCLAuthorizationStatusDenied:{                  // 拒绝授权
            ZYDebug(@"授权失败：用户拒绝授权或未开启定位服务");
            NSString *domain = @"com.ft.mobile.sdk.FTMobileAgent";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey:@"用户拒绝授权或未开启定位服务"};
            NSError *error = [NSError errorWithDomain:domain
                                                 code:104
                                             userInfo:userInfo];
            if (self.updateLocationBlock) {
                self.updateLocationBlock(self.country,self.province,self.city, error);
            }
        }
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:     // 在使用期间使用定位
            ZYDebug(@"授权成功：用户允许应用“使用期间”使用定位服务");
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
            ZYDebug(@"授权成功：用户允许应用“始终”使用定位服务");    // 始终使用定位服务
            break;
        case kCLAuthorizationStatusNotDetermined:
            break;
        case kCLAuthorizationStatusRestricted:
            
            break;
    }
}
@end
