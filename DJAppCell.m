//
//  DJAppCell.m
//  DarkJIT
//

#import "DJAppCell.h"

@interface DJAppCell ()
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UIButton *jitButton;
@property (nonatomic, strong) DJAppInfo *appInfo;
@end

@implementation DJAppCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    // Container with subtle border
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:1.0];
    card.layer.cornerRadius = 12;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:card];

    // App icon
    _appIcon = [[UIImageView alloc] init];
    _appIcon.contentMode = UIViewContentModeScaleAspectFill;
    _appIcon.layer.cornerRadius = 13;
    _appIcon.layer.masksToBounds = YES;
    _appIcon.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_appIcon];

    // Name label
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _nameLabel.textColor = [UIColor whiteColor];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_nameLabel];

    // Bundle ID label
    _bundleLabel = [[UILabel alloc] init];
    _bundleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _bundleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_bundleLabel];

    // Status row: dot + label
    _statusDot = [[UIView alloc] init];
    _statusDot.layer.cornerRadius = 4;
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_statusLabel];

    // JIT + Launch button (single action)
    _jitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _jitButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _jitButton.layer.cornerRadius = 8;
    _jitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_jitButton addTarget:self action:@selector(jitTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:_jitButton];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        // Card insets
        [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],

        // Icon
        [_appIcon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [_appIcon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [_appIcon.widthAnchor constraintEqualToConstant:52],
        [_appIcon.heightAnchor constraintEqualToConstant:52],

        // Name
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:12],
        [_nameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_jitButton.leadingAnchor constant:-8],

        // Bundle ID
        [_bundleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_bundleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
        [_bundleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_jitButton.leadingAnchor constant:-8],

        // Status dot
        [_statusDot.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_statusDot.topAnchor constraintEqualToAnchor:_bundleLabel.bottomAnchor constant:5],
        [_statusDot.widthAnchor constraintEqualToConstant:8],
        [_statusDot.heightAnchor constraintEqualToConstant:8],

        // Status label
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:4],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:_statusDot.centerYAnchor],

        // JIT button
        [_jitButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [_jitButton.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [_jitButton.widthAnchor constraintEqualToConstant:90],
        [_jitButton.heightAnchor constraintEqualToConstant:34],
    ]];
}

- (void)configureWithApp:(DJAppInfo *)app {
    _appInfo = app;
    _nameLabel.text = app.displayName;
    _bundleLabel.text = app.bundleID;

    // Load icon
    if (app.iconPath) {
        UIImage *icon = [UIImage imageWithContentsOfFile:app.iconPath];
        _appIcon.image = icon;
    } else {
        _appIcon.image = nil;
    }

    // Status
    if (app.jitEnabled) {
        _statusDot.backgroundColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0];
        _statusLabel.text = @"JIT Active";
        _statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1.0];

        [_jitButton setTitle:@"Relaunch" forState:UIControlStateNormal];
        _jitButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.35 blue:0.15 alpha:1.0];
        [_jitButton setTitleColor:[UIColor colorWithRed:0.3 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
    } else if (app.isRunning) {
        _statusDot.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
        _statusLabel.text = [NSString stringWithFormat:@"Running (PID %d)", app.pid];
        _statusLabel.textColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];

        [_jitButton setTitle:@"Enable JIT" forState:UIControlStateNormal];
        _jitButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.40 alpha:1.0];
        [_jitButton setTitleColor:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    } else {
        _statusDot.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        _statusLabel.text = @"Not running";
        _statusLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];

        [_jitButton setTitle:@"JIT Launch" forState:UIControlStateNormal];
        _jitButton.backgroundColor = [UIColor colorWithRed:0.25 green:0.15 blue:0.35 alpha:1.0];
        [_jitButton setTitleColor:[UIColor colorWithRed:0.7 green:0.4 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    }
}

- (void)jitTapped {
    if (!_appInfo) return;

    // Disable button to prevent double-tap
    _jitButton.enabled = NO;
    [_jitButton setTitle:@"..." forState:UIControlStateNormal];

    // Single action: enable JIT + launch
    if ([_delegate respondsToSelector:@selector(didTapEnableJIT:)]) {
        [_delegate didTapEnableJIT:_appInfo];
    }
}

@end
