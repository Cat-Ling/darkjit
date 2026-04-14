//
//  AppListManager.m
//  DarkJIT
//
//  Enumerate user-installed apps via LSApplicationWorkspace + filesystem fallback.
//

#import "AppListManager.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/kutils.h"
#import "kexploit/krw.h"
#import "kexploit/offsets.h"
#import <objc/runtime.h>
#import <dlfcn.h>

#pragma mark - Private API declarations

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)bundleId;
- (NSString *)applicationIdentifier;
- (NSURL *)bundleURL;
- (NSURL *)dataContainerURL;
- (NSString *)localizedName;
- (NSString *)bundleVersion;
- (NSString *)shortVersionString;
- (NSString *)applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

#pragma mark - DJAppInfo

@implementation DJAppInfo
@end

#pragma mark - AppListManager

@implementation AppListManager

+ (NSArray<DJAppInfo *> *)installedApps {
    NSMutableArray<DJAppInfo *> *result = [NSMutableArray array];

    Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    if (!LSAppWorkspace) {
        // Try loading the framework
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    }

    if (!LSAppWorkspace) {
        printf("[APPLIST] LSApplicationWorkspace not available\n");
        return result;
    }

    id workspace = [LSAppWorkspace defaultWorkspace];
    NSArray *allApps = [workspace allApplications];
    printf("[APPLIST] LSApplicationWorkspace returned %lu apps\n", (unsigned long)allApps.count);

    for (LSApplicationProxy *proxy in allApps) {
        NSString *bundleID = [proxy applicationIdentifier];
        if (!bundleID) continue;

        // Filter out Apple system apps
        NSString *appType = [proxy applicationType];
        if ([appType isEqualToString:@"System"]) continue;

        // Also skip Apple bundle IDs
        if ([bundleID hasPrefix:@"com.apple."]) continue;

        DJAppInfo *info = [[DJAppInfo alloc] init];
        info.bundleID = bundleID;
        info.displayName = [proxy localizedName] ?: bundleID;
        info.version = [proxy shortVersionString] ?: [proxy bundleVersion] ?: @"?";

        NSURL *bundleURL = [proxy bundleURL];
        if (bundleURL) info.bundlePath = [bundleURL path];

        NSURL *dataURL = [proxy dataContainerURL];
        if (dataURL) info.dataContainerPath = [dataURL path];

        // Try to find icon in bundle
        if (info.bundlePath) {
            info.iconPath = [self findIconInBundle:info.bundlePath];

            // Read executable name from Info.plist
            NSString *plistPath = [info.bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            info.executableName = plist[@"CFBundleExecutable"];

            // Prefer plist display name
            NSString *plistName = plist[@"CFBundleDisplayName"] ?: plist[@"CFBundleName"];
            if (plistName.length > 0) info.displayName = plistName;
        }

        info.pid = 0;
        info.jitEnabled = NO;
        info.isRunning = NO;

        [result addObject:info];
    }

    // Sort by display name
    [result sortUsingComparator:^NSComparisonResult(DJAppInfo *a, DJAppInfo *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];

    return result;
}

+ (NSArray<DJAppInfo *> *)installedAppsWithFilesystemAccess {
    // Start with the LSApplicationWorkspace results
    NSMutableArray<DJAppInfo *> *result = [[self installedApps] mutableCopy];
    NSMutableSet *knownBundleIDs = [NSMutableSet set];
    for (DJAppInfo *app in result) {
        [knownBundleIDs addObject:app.bundleID];
    }

    // Scan /var/containers/Bundle/Application/ for apps not found via LS
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appsDir = @"/var/containers/Bundle/Application";
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:appsDir error:nil]) {
        NSString *uuidPath = [appsDir stringByAppendingPathComponent:uuid];
        for (NSString *item in [fm contentsOfDirectoryAtPath:uuidPath error:nil]) {
            if (![item hasSuffix:@".app"]) continue;

            NSString *appPath = [uuidPath stringByAppendingPathComponent:item];
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString *bundleID = plist[@"CFBundleIdentifier"];
            if (!bundleID || [knownBundleIDs containsObject:bundleID]) continue;
            if ([bundleID hasPrefix:@"com.apple."]) continue;

            DJAppInfo *info = [[DJAppInfo alloc] init];
            info.bundleID = bundleID;
            info.displayName = plist[@"CFBundleDisplayName"] ?: plist[@"CFBundleName"] ?: bundleID;
            info.version = plist[@"CFBundleShortVersionString"] ?: plist[@"CFBundleVersion"] ?: @"?";
            info.bundlePath = appPath;
            info.executableName = plist[@"CFBundleExecutable"];
            info.iconPath = [self findIconInBundle:appPath];

            // Find data container
            info.dataContainerPath = [self findDataContainerForBundleID:bundleID];

            [result addObject:info];
            [knownBundleIDs addObject:bundleID];
        }
    }

    // Update running state + PIDs via kernel proc list
    [self updateRunningState:result];

    // Sort
    [result sortUsingComparator:^NSComparisonResult(DJAppInfo *a, DJAppInfo *b) {
        // Running apps first
        if (a.isRunning != b.isRunning) return a.isRunning ? NSOrderedAscending : NSOrderedDescending;
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];

    printf("[APPLIST] Total apps (with filesystem): %lu\n", (unsigned long)result.count);
    return result;
}

+ (void)updateRunningState:(NSMutableArray<DJAppInfo *> *)apps {
    uint64_t cur_proc = proc_self();
    if (!cur_proc) return;

    // Build a block to find matching app with prefix checks
    DJAppInfo *(^findAppByName)(NSString *) = ^DJAppInfo *(NSString *p_name_str) {
        for (DJAppInfo *app in apps) {
            if (app.executableName.length > 0) {
                // p_name might be truncated to 15 chars by XNU MAXCOMLEN
                if (p_name_str.length == 15) {
                    if ([app.executableName hasPrefix:p_name_str]) return app;
                } else {
                    if ([app.executableName isEqualToString:p_name_str]) return app;
                }
            }
        }
        return nil;
    };

    uint64_t proc = cur_proc;
    int scanned = 0;
    while (proc && scanned < 500) {
        char *name = proc_get_p_name(proc);
        if (name) {
            DJAppInfo *app = findAppByName([NSString stringWithUTF8String:name]);
            if (app) {
                app.pid = kread32(proc + off_proc_p_pid);
                app.isRunning = YES;
            }
        }
        proc = kread64(proc + off_proc_p_list_le_next);
        if (!proc || proc == cur_proc) break;
        scanned++;
    }

    proc = kread64(cur_proc + off_proc_p_list_le_prev);
    scanned = 0;
    while (proc && scanned < 500) {
        char *name = proc_get_p_name(proc);
        if (name) {
            DJAppInfo *app = findAppByName([NSString stringWithUTF8String:name]);
            if (app && !app.isRunning) {
                app.pid = kread32(proc + off_proc_p_pid);
                app.isRunning = YES;
            }
        }
        proc = kread64(proc + off_proc_p_list_le_prev);
        if (!proc || proc == cur_proc) break;
        scanned++;
    }
}

+ (pid_t)pidForExecutableName:(NSString *)execName {
    if (!execName || execName.length == 0) return 0;

    // XNU truncates p_name to 15 characters (MAXCOMLEN)
    NSString *searchName = execName;
    if (searchName.length > 15) {
        searchName = [searchName substringToIndex:15];
    }

    uint64_t cur_proc = proc_self();
    if (!cur_proc) return 0;
    
    // Do our own walk so we can strncmp/prefix match
    uint64_t proc = cur_proc;
    while (proc) {
        char *name = proc_get_p_name(proc);
        if (name) {
            NSString *pNameStr = [NSString stringWithUTF8String:name];
            if ([pNameStr isEqualToString:searchName] || (pNameStr.length == 15 && [execName hasPrefix:pNameStr])) {
                return kread32(proc + off_proc_p_pid);
            }
        }
        proc = kread64(proc + off_proc_p_list_le_next);
        if (!proc || proc == cur_proc) break;
    }
    
    proc = kread64(cur_proc + off_proc_p_list_le_prev);
    while (proc) {
        char *name = proc_get_p_name(proc);
        if (name) {
            NSString *pNameStr = [NSString stringWithUTF8String:name];
            if ([pNameStr isEqualToString:searchName] || (pNameStr.length == 15 && [execName hasPrefix:pNameStr])) {
                return kread32(proc + off_proc_p_pid);
            }
        }
        proc = kread64(proc + off_proc_p_list_le_prev);
        if (!proc || proc == cur_proc) break;
    }
    return 0;
}

+ (BOOL)launchAppWithBundleID:(NSString *)bundleID {
    Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    if (!LSAppWorkspace) return NO;

    id workspace = [LSAppWorkspace defaultWorkspace];
    BOOL result = [workspace openApplicationWithBundleID:bundleID];
    printf("[APPLIST] Launch %s: %s\n", bundleID.UTF8String, result ? "OK" : "FAILED");
    return result;
}

#pragma mark - Helpers

+ (NSString *)findIconInBundle:(NSString *)bundlePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];

    // CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconFiles
    NSDictionary *icons = info[@"CFBundleIcons"];
    NSDictionary *primary = icons[@"CFBundlePrimaryIcon"];
    NSArray *iconFiles = primary[@"CFBundleIconFiles"];
    if (!iconFiles) iconFiles = info[@"CFBundleIconFiles"];

    NSString *bestIcon = nil;
    unsigned long long bestSize = 0;

    if (iconFiles.count > 0) {
        for (NSString *iconName in iconFiles) {
            NSArray *variants = @[
                iconName,
                [iconName stringByAppendingString:@"@2x.png"],
                [iconName stringByAppendingString:@"@3x.png"],
                [iconName stringByAppendingString:@"@2x~iphone.png"],
                [iconName stringByAppendingString:@"@3x~iphone.png"],
                [NSString stringWithFormat:@"%@.png", iconName],
            ];
            for (NSString *v in variants) {
                NSString *full = [bundlePath stringByAppendingPathComponent:v];
                NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
                unsigned long long sz = [attrs fileSize];
                if (sz > bestSize) { bestSize = sz; bestIcon = full; }
            }
        }
    }

    // Fallback: scan for Icon*.png / AppIcon*.png
    if (!bestIcon) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:bundlePath error:nil]) {
            if (([file hasPrefix:@"Icon"] || [file hasPrefix:@"icon"] || [file hasPrefix:@"AppIcon"])
                && [file hasSuffix:@".png"]) {
                NSString *full = [bundlePath stringByAppendingPathComponent:file];
                NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
                unsigned long long sz = [attrs fileSize];
                if (sz > bestSize) { bestSize = sz; bestIcon = full; }
            }
        }
    }

    return bestIcon;
}

+ (NSString *)findDataContainerForBundleID:(NSString *)bundleID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dataDir = @"/var/mobile/Containers/Data/Application";
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:dataDir error:nil]) {
        NSString *uuidPath = [dataDir stringByAppendingPathComponent:uuid];
        NSString *metaPlist = [uuidPath stringByAppendingPathComponent:
            @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPlist];
        if ([meta[@"MCMMetadataIdentifier"] isEqualToString:bundleID]) {
            return uuidPath;
        }
    }
    return nil;
}

@end
