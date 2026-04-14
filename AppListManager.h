//
//  AppListManager.h
//  DarkJIT
//

#ifndef AppListManager_h
#define AppListManager_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DJAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *dataContainerPath;
@property (nonatomic, copy) NSString *executableName;
@property (nonatomic, copy) NSString *iconPath;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) BOOL jitEnabled;
@property (nonatomic, assign) BOOL isRunning;
@end

@interface AppListManager : NSObject

/// Enumerate user-installed apps. Pre-exploit this uses LSApplicationWorkspace
/// which may return limited info. Post-exploit it supplements with filesystem.
+ (NSArray<DJAppInfo *> *)installedApps;

/// Re-scan with full filesystem access (call after sandbox escape)
+ (NSArray<DJAppInfo *> *)installedAppsWithFilesystemAccess;

/// Find the PID of a running app by bundle ID (walks kernel proc list)
+ (pid_t)pidForBundleID:(NSString *)bundleID;

/// Launch an app by bundle ID
+ (BOOL)launchAppWithBundleID:(NSString *)bundleID;

@end

#endif /* AppListManager_h */
