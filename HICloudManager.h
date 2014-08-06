//
//  HICloudManager.h
//  Hab It!
//
//  Created by orkenstein on 10.03.14.
//  Copyright (c) 2014 savefon.mobi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MagicalRecord.h>

#define __cloud [HICloudManager sharedInstance]

extern NSString *const HIICloudDataImportedNotification;
extern NSString *const HICoreDataStackInitNotification;

typedef NS_ENUM(NSInteger, HIICloudSetting) {
  HIICloudSettingUnknown = 0,
  HIICloudSettingDisabled,
  HIICloudSettingEnabled
};

@interface HICloudManager : NSObject
@property(nonatomic, assign, readonly) BOOL coreDataInitialised;
@property(nonatomic, copy, readonly) NSData *currentICloudToken;

+ (instancetype)sharedInstance;

//  iCloud
- (BOOL)iCloudAvailable;
- (void)setupCoreDataICloudEnable:(BOOL)iCloudEnabled
                   withCompletion:(void (^)(void))completion;
- (void)grantICloudAccess:(BOOL)dialogOnlyIfNeeded
           withCompletion:(void(^)(BOOL accesGranted))completion;

@end
