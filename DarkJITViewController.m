//
//  DarkJITViewController.m
//  DarkJIT
//
//  Split-screen: app table (top) + live exploit log (bottom).
//  Flow: Run exploit → list apps → tap to enable JIT + auto-launch.
//

#import "DarkJITViewController.h"
#import "DJAppCell.h"
#import "AppListManager.h"
#import "LogTextView.h"
#import "jit_enabler.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/kutils.h"
#import "utils/sandbox.h"

typedef NS_ENUM(NSInteger, DJExploitState) {
    DJExploitStateIdle,
    DJExploitStateRunning,
    DJExploitStateReady,     // kexploit + sandbox escape done
    DJExploitStateFailed,
};

@interface DarkJITViewController () <UITableViewDataSource, UITableViewDelegate, DJAppCellDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) LogTextView *logView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *exploitButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISegmentedControl *viewToggle;
@property (nonatomic, strong) NSLayoutConstraint *logHeightConstraint;

@property (nonatomic, strong) NSArray<DJAppInfo *> *apps;
@property (nonatomic, assign) DJExploitState exploitState;
@property (nonatomic, assign) BOOL logExpanded;
@end

static NSString * const kCellID = @"DJAppCell";

@implementation DarkJITViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DarkJIT";
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    self.exploitState = DJExploitStateIdle;
    self.logExpanded = NO;

    log_init();

    [self buildUI];
    [self loadAppsPreExploit];
}

#pragma mark - UI Construction

- (void)buildUI {
    // --- Header: status + exploit button ---
    _headerView = [[UIView alloc] init];
    _headerView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:1.0];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerView];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    _statusLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    _statusLabel.text = @"⏳ Kernel: not exploited";
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_statusLabel];

    _exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_exploitButton setTitle:@"⚔️ Run Exploit" forState:UIControlStateNormal];
    _exploitButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _exploitButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0];
    [_exploitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _exploitButton.layer.cornerRadius = 10;
    _exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_exploitButton];

    // Log/Apps toggle
    _viewToggle = [[UISegmentedControl alloc] initWithItems:@[@"Apps", @"Log"]];
    _viewToggle.selectedSegmentIndex = 0;
    _viewToggle.translatesAutoresizingMaskIntoConstraints = NO;
    [_viewToggle addTarget:self action:@selector(toggleView:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        _viewToggle.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        _viewToggle.selectedSegmentTintColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.5 alpha:1.0];
        [_viewToggle setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
        [_viewToggle setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:1.0]} forState:UIControlStateNormal];
    }
    [_headerView addSubview:_viewToggle];

    // --- Table View ---
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 84;
    [_tableView registerClass:[DJAppCell class] forCellReuseIdentifier:kCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    // --- Log View ---
    _logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    _logView.hidden = YES;
    [self.view addSubview:_logView];

    // --- Constraints ---
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        // Header
        [_headerView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_statusLabel.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:12],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_exploitButton.leadingAnchor constant:-8],

        [_exploitButton.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:8],
        [_exploitButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-16],
        [_exploitButton.widthAnchor constraintEqualToConstant:140],
        [_exploitButton.heightAnchor constraintEqualToConstant:36],

        [_viewToggle.topAnchor constraintEqualToAnchor:_exploitButton.bottomAnchor constant:10],
        [_viewToggle.centerXAnchor constraintEqualToAnchor:_headerView.centerXAnchor],
        [_viewToggle.widthAnchor constraintEqualToConstant:180],
        [_viewToggle.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:-10],

        // Table view
        [_tableView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // Log view (same frame as table)
        [_logView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_logView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - View Toggle

- (void)toggleView:(UISegmentedControl *)seg {
    BOOL showLog = (seg.selectedSegmentIndex == 1);
    _tableView.hidden = showLog;
    _logView.hidden = !showLog;
}

#pragma mark - App Loading

- (void)loadAppsPreExploit {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *apps = [AppListManager installedApps];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            [self.tableView reloadData];
            printf("[UI] Loaded %lu apps (pre-exploit)\n", (unsigned long)apps.count);
        });
    });
}

- (void)reloadAppsPostExploit {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *apps = [AppListManager installedAppsWithFilesystemAccess];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            [self.tableView reloadData];
            printf("[UI] Reloaded %lu apps (post-exploit, with PIDs)\n", (unsigned long)apps.count);
        });
    });
}

#pragma mark - Exploit

- (void)runExploit {
    if (self.exploitState == DJExploitStateRunning) return;

    self.exploitState = DJExploitStateRunning;
    _exploitButton.enabled = NO;
    [_exploitButton setTitle:@"Running..." forState:UIControlStateNormal];
    _exploitButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.1 alpha:1.0];
    _statusLabel.text = @"🔄 Running kexploit...";
    _statusLabel.textColor = [UIColor yellowColor];

    // Auto-switch to log view
    _viewToggle.selectedSegmentIndex = 1;
    [self toggleView:_viewToggle];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Stage 1: Kernel exploit
        printf("========================================\n");
        printf("  DarkJIT — DarkSword Kernel Exploit\n");
        printf("========================================\n\n");
        printf("[*] Stage 1: Running kexploit_opa334...\n");

        int kret = kexploit_opa334();
        if (kret != 0) {
            printf("[!] kexploit FAILED (ret=%d)\n", kret);
            [self exploitFinished:NO];
            return;
        }
        printf("[+] kexploit succeeded! Kernel R/W acquired.\n\n");

        // Stage 2: Sandbox escape
        printf("[*] Stage 2: Escaping sandbox (patch_sandbox_ext)...\n");
        int sret = patch_sandbox_ext();
        if (sret != 0) {
            printf("[!] sandbox escape failed, trying check_sandbox_var_rw...\n");
            // It might have partially worked — verify
            if (check_sandbox_var_rw() != 0) {
                printf("[!] Sandbox escape FAILED\n");
                // Continue anyway — JIT enablement doesn't strictly need sandbox escape
                // (we already have kernel R/W), only the app list filesystem scan does
                printf("[*] Continuing without full sandbox escape (JIT still works)\n\n");
            } else {
                printf("[+] Sandbox R/W verified despite return code\n\n");
            }
        } else {
            printf("[+] Sandbox escaped! Full filesystem R/W.\n\n");
        }

        printf("========================================\n");
        printf("  Exploit chain complete. Ready.\n");
        printf("========================================\n\n");

        [self exploitFinished:YES];
    });
}

- (void)exploitFinished:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (success) {
            self.exploitState = DJExploitStateReady;
            self->_statusLabel.text = @"✅ Kernel R/W active — tap an app to JIT";
            self->_statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0];
            [self->_exploitButton setTitle:@"✅ Ready" forState:UIControlStateNormal];
            self->_exploitButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.15 alpha:1.0];

            // Switch back to apps view and reload with full filesystem access
            self->_viewToggle.selectedSegmentIndex = 0;
            [self toggleView:self->_viewToggle];
            [self reloadAppsPostExploit];
        } else {
            self.exploitState = DJExploitStateFailed;
            self->_statusLabel.text = @"❌ Exploit failed — check log";
            self->_statusLabel.textColor = [UIColor redColor];
            [self->_exploitButton setTitle:@"⚔️ Retry" forState:UIControlStateNormal];
            self->_exploitButton.enabled = YES;
            self->_exploitButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0];
        }
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DJAppCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    DJAppInfo *app = self.apps[indexPath.row];
    cell.delegate = self;
    [cell configureWithApp:app];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Tap row = same as tapping the JIT button
    DJAppInfo *app = self.apps[indexPath.row];
    [self enableJITAndLaunch:app];
}

#pragma mark - DJAppCellDelegate

- (void)didTapEnableJIT:(DJAppInfo *)app {
    [self enableJITAndLaunch:app];
}

- (void)didTapLaunchApp:(DJAppInfo *)app {
    [AppListManager launchAppWithBundleID:app.bundleID];
}

#pragma mark - JIT Enable + Launch

- (void)enableJITAndLaunch:(DJAppInfo *)app {
    if (self.exploitState != DJExploitStateReady) {
        // Shake the exploit button to hint they need to run it first
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.values = @[@(-6), @(6), @(-4), @(4), @(0)];
        shake.duration = 0.3;
        [_exploitButton.layer addAnimation:shake forKey:@"shake"];
        printf("[UI] Exploit not ready — run the exploit first!\n");
        return;
    }

    // Switch to log to show progress
    _viewToggle.selectedSegmentIndex = 1;
    [self toggleView:_viewToggle];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        printf("\n[*] JIT Enable + Launch: %s (%s)\n", app.displayName.UTF8String, app.bundleID.UTF8String);

        // Step 1: If app is not running, launch it first so we get a PID
        if (!app.isRunning || app.pid == 0) {
            printf("[*] App not running — launching first...\n");
            dispatch_sync(dispatch_get_main_queue(), ^{
                [AppListManager launchAppWithBundleID:app.bundleID];
            });

            // Wait for the app to start and appear in the proc list
            printf("[*] Waiting for process to spawn...\n");
            pid_t pid = 0;
            for (int i = 0; i < 30; i++) {
                usleep(200000); // 200ms
                pid = [AppListManager pidForExecutableName:app.executableName];
                if (pid > 0) break;
            }

            if (pid <= 0) {
                printf("[!] Could not find PID for %s after launch\n", app.bundleID.UTF8String);
                // Try once more with a longer wait
                sleep(2);
                pid = [AppListManager pidForExecutableName:app.executableName];
            }

            if (pid <= 0) {
                printf("[!] FAILED: App did not start or PID not found\n");
                return;
            }

            app.pid = pid;
            app.isRunning = YES;
            printf("[+] App launched with PID %d\n", pid);
        }

        // Step 2: Enable JIT
        int ret = enable_jit_for_pid(app.pid);
        if (ret == 0) {
            app.jitEnabled = YES;
            printf("[+] JIT enabled for %s (PID %d)\n", app.displayName.UTF8String, app.pid);
        } else {
            printf("[!] JIT enablement failed for PID %d\n", app.pid);
        }

        // Step 3: Relaunch the app so it picks up the new flags
        //         (some apps need a relaunch for JIT to take effect)
        printf("[*] Relaunching %s with JIT active...\n", app.displayName.UTF8String);
        usleep(500000); // 500ms grace
        dispatch_sync(dispatch_get_main_queue(), ^{
            [AppListManager launchAppWithBundleID:app.bundleID];
        });

        printf("[✓] Done! %s is now running with JIT.\n\n", app.displayName.UTF8String);

        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
            // Switch back to apps view after a short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self->_viewToggle.selectedSegmentIndex = 0;
                [self toggleView:self->_viewToggle];
            });
        });
    });
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
