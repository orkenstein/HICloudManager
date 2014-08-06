//
//  HICloudManager.m
//  Hab It!
//
//  Created by orkenstein on 10.03.14.
//  Copyright (c) 2014 savefon.mobi. All rights reserved.
//

#import "HICloudManager.h"
#import "HISettingsManager.h"
#import <MMProgressHUD.h>

NSString *const HIICloudDataImportedNotification = @"HIICloudDataImportedNotification";
NSString *const HICoreDataStackInitNotification = @"HICoreDataStackInitNotification";

static NSString *const kICloudStoreName = @"iCloudStore.sqlite";
static NSString *const kICloudContentNameKey = @"savefonmobiHabIt";

@interface HICloudManager ()
@property(nonatomic, assign) BOOL coreDataInitialised;
@property(nonatomic, copy) NSData *currentICloudToken;
@property(nonatomic, copy) NSURL *lastICloudStoreURL;

@end

@interface NSPersistentStoreCoordinator ()
+ (NSDictionary *)MR_autoMigrationOptions;
- (void)MR_createPathToStoreFileIfNeccessary:(NSURL *)urlForStore;

@end

@implementation HICloudManager

SHARED_INSTANCE_GCD_USING_BLOCK(^{
    HICloudManager *manager = [[HICloudManager alloc] init];
    [manager registerNotifications];
    return manager;
})

#pragma mark - Notifications

- (void)registerNotifications {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(storeDidImportNotifications:)
                                               name:NSPersistentStoreDidImportUbiquitousContentChangesNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(storeDidChangeNotifications:)
                                               name:NSPersistentStoreCoordinatorStoresDidChangeNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(storeWillChangeNotifications:)
                                               name:NSPersistentStoreCoordinatorStoresWillChangeNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(storeWillRemoveChangeNotifications:)
                                               name:NSPersistentStoreCoordinatorWillRemoveStoreNotification
                                             object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)storeDidImportNotifications:(NSNotification *)notification {
}

- (void)storeDidChangeNotifications:(NSNotification *)notification {
  NSPersistentStoreUbiquitousTransitionType type =
      [notification.userInfo[NSPersistentStoreUbiquitousTransitionTypeKey] integerValue];
  BOOL importCompleted = (type == NSPersistentStoreUbiquitousTransitionTypeInitialImportCompleted);
  if (importCompleted == YES) {
    [__settings setDefaults:@(YES) forKey:HIICloudImportedKey];
    [MMProgressHUD dismissWithSuccess:NSLocalizedString(@"Success!", nil)];
    [[NSNotificationCenter defaultCenter] postNotificationName:HIICloudDataImportedNotification object:self];
  }
}

- (void)storeWillChangeNotifications:(NSNotification *)notification {
}

- (void)storeWillRemoveChangeNotifications:(NSNotification *)notification {
}

- (BOOL)iCloudAvailable {
  id currentiCloudToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
  return currentiCloudToken != nil;
}

#pragma mark - Core Data

- (void)setupCoreDataICloudEnable:(BOOL)iCloudEnabled withCompletion:(void (^)(void))completion {

  BOOL currentiCloudSetting = ([[__settings defaultsForKey:HIICloudSettingKey] integerValue] == HIICloudSettingEnabled);

  //  Skip the same setting. No need to bother Core Data...
  if (currentiCloudSetting == iCloudEnabled && self.coreDataInitialised == YES) {
    if (completion != nil) {
      completion();
      return;
    }
  }

  //  We going to change iCloud setting, so migrate, if stack alredy exists.
  BOOL shouldMigrateStore = self.coreDataInitialised;

  if (iCloudEnabled == YES && [self iCloudAvailable] == YES) {
    id currentiCloudToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
    self.currentICloudToken = currentiCloudToken;
    [__settings setDefaults:currentiCloudToken forKey:HIICloudLastTokenKey];

    if ([[__settings defaultsForKey:HIICloudImportedKey] boolValue] == NO && self.lastICloudStoreURL == nil) {
      [MMProgressHUD showWithTitle:NSLocalizedString(@"iCloud_Importing_HUD_title", nil)
                            status:NSLocalizedString(@"iCloud_Importing_HUD_status", nil)];
      [MMProgressHUD dismissAfterDelay:120];
    }

    if (shouldMigrateStore == YES) {
      [self migrateLocalToFallbackStore];
      //  Ensure
      [MagicalRecord cleanUp];
      
      //  remove existing icloud store
//      NSError *error = nil;
//      NSURL *fallbackURL = [NSPersistentStore MR_urlForStoreName:kICloudStoreName];
//      NSURL *iCloudURL = [NSPersistentStore MR_cloudURLForUbiqutiousContainer:nil];
//      NSDictionary *iCloudOptions =
//      [NSDictionary dictionaryWithObjectsAndKeys:kICloudContentNameKey, NSPersistentStoreUbiquitousContentNameKey,
//       iCloudURL, NSPersistentStoreUbiquitousContentURLKey, nil];
//      BOOL result = [NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:self.lastICloudStoreURL
//                                                                                         options:iCloudOptions
//                                                                                           error:&error];
//      NSLog(@"Icloud store was removed with result: %@\r Error: %@", result ? @"YES" : @"NO", error);
    }
    //  Setup iCloud stack
    [MagicalRecord setupCoreDataStackWithiCloudContainer:nil
                                          contentNameKey:kICloudContentNameKey
                                         localStoreNamed:kICloudStoreName
                                 cloudStorePathComponent:nil
                                              completion:^{
                                                  //  Notify
                                                  self.coreDataInitialised = YES;
                                                  [[NSNotificationCenter defaultCenter]
                                                      postNotificationName:HICoreDataStackInitNotification
                                                                    object:self];
                                                  self.lastICloudStoreURL = [[NSPersistentStore MR_defaultPersistentStore] URL];
                                                  if (completion != nil) {
                                                    completion();
                                                  }
                                              }];

  } else {

    if (shouldMigrateStore == YES) {
      [self migrateFallbackToLocalStore];
      //  Ensure
      [MagicalRecord cleanUp];
    }
    //  Setup usual stack
    [MagicalRecord setupAutoMigratingCoreDataStack];
    //  Notify
    self.coreDataInitialised = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:HICoreDataStackInitNotification object:self];
    if (completion != nil) {
      completion();
    }
  }
}

- (void)migrateLocalToFallbackStore {
  NSPersistentStore *currentLocalStore = [NSPersistentStore MR_defaultPersistentStore];
  NSURL *fallbackURL = [NSPersistentStore MR_urlForStoreName:kICloudStoreName];

  NSURL *iCloudURL = [NSPersistentStore MR_cloudURLForUbiqutiousContainer:nil];
  NSDictionary *iCloudOptions =
      [NSDictionary dictionaryWithObjectsAndKeys:kICloudContentNameKey, NSPersistentStoreUbiquitousContentNameKey,
                                                 iCloudURL, NSPersistentStoreUbiquitousContentURLKey, nil];

  NSLog(@"Migrate local store:\r\r%@\r\rTo URL:\r%@\r", currentLocalStore, fallbackURL);
  //  do the stuff
  [self migrateStore:currentLocalStore toUrl:self.lastICloudStoreURL withOptions:iCloudOptions removeExisting:YES];
}

- (void)migrateFallbackToLocalStore {
  NSPersistentStore *currentFallbackStore = [NSPersistentStore MR_defaultPersistentStore];
  NSURL *localURL = [NSPersistentStore MR_urlForStoreName:[MagicalRecord defaultStoreName]];
  NSMutableDictionary *migrateStoreOptions =
      [NSMutableDictionary dictionaryWithObjectsAndKeys:@YES, NSPersistentStoreRemoveUbiquitousMetadataOption,
                                                        @YES, NSMigratePersistentStoresAutomaticallyOption,
                                                        /*@YES, NSInferMappingModelAutomaticallyOption,*/ nil];

  NSLog(@"Migrate fallback store:\r\r%@\r\rTo URL:\r%@\r", currentFallbackStore, localURL);
  [self migrateStore:currentFallbackStore toUrl:localURL withOptions:migrateStoreOptions removeExisting:YES];
}

- (void)migrateStore:(NSPersistentStore *)store
               toUrl:(NSURL *)migrateURL
         withOptions:(NSDictionary *)options
      removeExisting:(BOOL)removeExisting {

  if (store == nil || migrateURL == nil) {
    return;
  }

  NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
  //  Perform the stuff coordinated
  [coordinator coordinateWritingItemAtURL:migrateURL options:NSFileCoordinatorWritingForReplacing error:nil byAccessor:^(NSURL *newURL) {
    NSLog(@"Content of migration folder:\r%@",
          [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[newURL URLByDeletingLastPathComponent] path]
                                                              error:nil]);
    //  remove previous file
    if ([[NSFileManager defaultManager] fileExistsAtPath:newURL.path] == YES && removeExisting == YES) {
      [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
      
      NSLog(@"Content of migration folder (item was removed):\r%@",
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[newURL URLByDeletingLastPathComponent] path]
                                                                error:nil]);
    }
    [[NSPersistentStoreCoordinator MR_defaultStoreCoordinator] MR_createPathToStoreFileIfNeccessary:newURL];
    
    NSError *error = nil;
    [[NSPersistentStoreCoordinator MR_defaultStoreCoordinator] lock];
    NSPersistentStore *newStore =
    [[NSPersistentStoreCoordinator MR_defaultStoreCoordinator] migratePersistentStore:store
                                                                                toURL:newURL
                                                                              options:options
                                                                             withType:NSSQLiteStoreType
                                                                                error:&error];
    [[NSPersistentStoreCoordinator MR_defaultStoreCoordinator] unlock];
    NSAssert(newStore != nil, @"Migration failed:\r%@", error);
    NSLog(@"Content of migration folder\r%@",
          [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[newURL URLByDeletingLastPathComponent] path]
                                                              error:nil]);
  }];
}

- (void)grantICloudAccess:(BOOL)dialogOnlyIfNeeded withCompletion:(void (^)(BOOL))completion {
  HIICloudSetting iCloudSetting = [[__settings defaultsForKey:HIICloudSettingKey] integerValue];

  if (iCloudSetting == HIICloudSettingUnknown || dialogOnlyIfNeeded == NO) {
    [self showICloudDialogWithCompletion:^(HIICloudSetting blockiCloudSetting) {
        //  Setup Core Data after dialog
        BOOL enableICloud = (blockiCloudSetting == HIICloudSettingEnabled);
        [__cloud setupCoreDataICloudEnable:enableICloud
                            withCompletion:^{
                                [__settings setDefaults:@(blockiCloudSetting) forKey:HIICloudSettingKey];
                                if (completion != nil) {
                                  completion(enableICloud);
                                }
                            }];
    }];
  } else {
    BOOL enableICloud = (iCloudSetting == HIICloudSettingEnabled);
    [__cloud setupCoreDataICloudEnable:enableICloud
                        withCompletion:^{
                            if (completion != nil) {
                              completion(enableICloud);
                            }
                        }];
  }
}

- (void)showICloudDialogWithCompletion:(void (^)(HIICloudSetting iCloudSetting))completion {
  UIAlertView *alert = nil;
  BOOL iCloudAvailable = [self iCloudAvailable];

  if (iCloudAvailable == YES) {
    alert = [UIAlertView alertWithTitle:NSLocalizedString(@"iCloud_alert_title", nil)
                                message:NSLocalizedString(@"iCloud_enable_alert_message", nil)];

    [alert addButtonWithTitle:NSLocalizedString(@"iCloud_enable_alert_use_option", nil)
                      handler:^(UIAlertView *alert) {
                          if (completion != nil) {
                            completion(HIICloudSettingEnabled);
                          }
                      }];
    [alert addButtonWithTitle:NSLocalizedString(@"iCloud_enable_alert_do_not_use_option", nil)
                      handler:^(UIAlertView *alert) {
                          if (completion != nil) {
                            completion(HIICloudSettingDisabled);
                          }
                      }];
  } else {
    alert = [UIAlertView alertWithTitle:NSLocalizedString(@"iCloud_alert_title", nil)
                                message:NSLocalizedString(@"iCloud_unavailable_alert_message", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)
                      handler:^(UIAlertView *alert) {
                          if (completion != nil) {
                            completion(HIICloudSettingUnknown);
                          }
                      }];
    [alert addButtonWithTitle:NSLocalizedString(@"iCloud_enable_alert_do_not_use_option", nil)
                      handler:^(UIAlertView *alert) {
                          if (completion != nil) {
                            completion(HIICloudSettingDisabled);
                          }
                      }];
  }

  [alert show];
}

@end
