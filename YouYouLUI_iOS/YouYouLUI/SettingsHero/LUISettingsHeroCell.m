// ============================================================================
// LUISettingsHeroCell.m — 一级页品牌卡（v3 墨玉 · 2026-09-20 用户拍板）
// 116pt · r24：左 48 圆头像（LUISettingsAvatarImage 返回：本机账号头像优先，否则内置默认头像 DefaultAvatar；都取不到时回落石墨底「L」字标，深色反转雾白）+ 3pt 外环；中 名字（本机昵称 > 服务器展示名）20/700 + 两枚胶囊（登录邮箱、
// 账号授权状态）；右上角原总开关位置只放一枚箭头（chevron.right，与入口行同款），箭头周围整片右上区域都是点按区，
// 点任意处经 onEntry 进「我的」账号页；底部两枚 28pt 玻璃按钮
// 「插件信息 ›」「更新日志 ›」——把此前 profile 行的点按目标与顶栏感叹号都收进来。
// 装饰：右上一组墨色同心水纹（1pt · 9%）+ 左上到右下一道白 55%→0 斜向高光，尾端极淡砂金。
// 设计稿：~/Desktop/LiquidUI设置页重设计_2026-09-20/设计稿-LiquidUI设置页重设计.html §组件解剖。
// ============================================================================

static const CGFloat LUISettingsHeroHeight = 116.0;
static const CGFloat LUISettingsHeroRadius = 24.0;

@interface LUISettingsHeroCell : UITableViewCell
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) CAGradientLayer *sheenLayer;
@property(nonatomic, strong) CAShapeLayer *rippleLayer;
@property(nonatomic, strong) UIView *avatarView;
@property(nonatomic, strong) UIImageView *avatarImageView;   // 微信头像（取到时盖住字标）
@property(nonatomic, strong) UILabel *avatarGlyph;           // 「L」字标兜底
@property(nonatomic, strong) CAShapeLayer *avatarRing;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *versionChip;
@property(nonatomic, strong) UIView *statusChip;
@property(nonatomic, strong) UIView *statusDot;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *entryButton;
@property(nonatomic, strong) UIImageView *entryChevronView;
@property(nonatomic, strong) UIButton *infoButton;
@property(nonatomic, strong) UIButton *logButton;
@property(nonatomic, copy) void (^onInfo)(void);
@property(nonatomic, copy) void (^onChangelog)(void);
@property(nonatomic, copy) void (^onEntry)(void);
- (void)configureWithTitle:(NSString *)title version:(NSString *)version key:(NSString *)key;
@end

@implementation LUISettingsHeroCell

/// 玻璃卡按品牌卡半径裁（LUISettingsLiquidCornerSpecForView 读此选择器）。
- (CGFloat)lui_liquidCardCornerRadius { return LUISettingsHeroRadius; }

static UIButton *LUISettingsHeroMakeButton(NSString *symbol, NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightMedium];
        cfg.image = [UIImage systemImageNamed:symbol withConfiguration:sym];
        cfg.imagePadding = 6.0;
        cfg.imagePlacement = NSDirectionalRectEdgeLeading;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 10.0, 0, 11.0);
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:[title stringByAppendingString:@"  ›"]
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]}];
        [t addAttributes:@{NSForegroundColorAttributeName: LUISettingsInk3Color()} range:NSMakeRange(t.length - 1, 1)];
        cfg.attributedTitle = t;
        cfg.baseForegroundColor = LUISettingsInkColor();
        // Transparent config background so liquid glass behind the control shows through.
        cfg.background.backgroundColor = [UIColor clearColor];
        b.configuration = cfg;
    } else {
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        [b setTitleColor:LUISettingsInkColor() forState:UIControlStateNormal];
    }
    b.tintColor = LUISettingsInkColor();
    b.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) b.layer.cornerCurve = kCACornerCurveContinuous;
    b.clipsToBounds = YES;
    b.backgroundColor = [UIColor clearColor];
    b.layer.borderWidth = 0;

    // Liquid glass surface (iOS 26+ UIGlassEffect via runtime; else systemMaterial blur).
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        Class glassCls = NSClassFromString(@"UIGlassEffect");
        if (glassCls) {
            effect = [[glassCls alloc] init];
        }
    }
    if (!effect) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.userInteractionEnabled = NO;
    glass.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    glass.tag = 90210; // layout marker
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b insertSubview:glass atIndex:0];
    return b;
}

static UILabel *LUISettingsHeroMakeChipLabel(UIFont *font) {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = LUISettingsInk2Color();
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 9.0;
    l.clipsToBounds = YES;
    l.backgroundColor = LUISettingsControlTrackColor();
    LUISettingsApplyTitleLabelChrome(l);
    return l;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = LUISettingsHeroRadius;
    if (@available(iOS 13.0, *)) self.contentView.layer.cornerCurve = kCACornerCurveContinuous;

    // 斜向高光：白 55% → 0（42%）→ 砂金 8% 收尾。
    _sheenLayer = [CAGradientLayer layer];
    _sheenLayer.startPoint = CGPointMake(0.0, 0.0);
    _sheenLayer.endPoint = CGPointMake(1.0, 1.0);
    _sheenLayer.locations = @[@0.0, @0.42, @1.0];
    [self.contentView.layer addSublayer:_sheenLayer];

    // 同心水纹：4 圈 1pt，右上出画。
    _rippleLayer = [CAShapeLayer layer];
    _rippleLayer.fillColor = UIColor.clearColor.CGColor;
    _rippleLayer.lineWidth = 1.0;
    [self.contentView.layer addSublayer:_rippleLayer];

    _avatarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48.0, 48.0)];
    _avatarView.layer.cornerRadius = 24.0;
    _avatarView.clipsToBounds = NO;
    _avatarGlyph = [[UILabel alloc] initWithFrame:_avatarView.bounds];
    _avatarGlyph.text = @"L";
    _avatarGlyph.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightHeavy];
    _avatarGlyph.textAlignment = NSTextAlignmentCenter;
    _avatarGlyph.textColor = LUISettingsOnInkColor();
    _avatarGlyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_avatarView addSubview:_avatarGlyph];
    // 微信头像自己裁圆（avatarView 不裁，外环 layer 出界 3pt）；aspectFill 铺满 48 圆。
    _avatarImageView = [[UIImageView alloc] initWithFrame:_avatarView.bounds];
    _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarImageView.clipsToBounds = YES;
    _avatarImageView.layer.cornerRadius = 24.0;
    _avatarImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _avatarImageView.hidden = YES;
    [_avatarView addSubview:_avatarImageView];
    _avatarRing = [CAShapeLayer layer];
    _avatarRing.fillColor = UIColor.clearColor.CGColor;
    _avatarRing.lineWidth = 1.0;
    _avatarRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(_avatarView.bounds, -3.0, -3.0)].CGPath;
    [_avatarView.layer addSublayer:_avatarRing];
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    _nameLabel.textColor = LUISettingsInkColor();
    LUISettingsApplyTitleLabelChrome(_nameLabel);
    [self.contentView addSubview:_nameLabel];

    _versionChip = LUISettingsHeroMakeChipLabel([UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium]);
    [self.contentView addSubview:_versionChip];

    _statusChip = [[UIView alloc] initWithFrame:CGRectZero];
    _statusChip.layer.cornerRadius = 9.0;
    _statusChip.clipsToBounds = YES;
    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(8.0, 6.0, 6.0, 6.0)];
    _statusDot.layer.cornerRadius = 3.0;
    [_statusChip addSubview:_statusDot];
    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    LUISettingsApplyTitleLabelChrome(_statusLabel);
    [_statusChip addSubview:_statusLabel];
    [self.contentView addSubview:_statusChip];

    // 右上角入口（原总开关的位置）：只放一枚箭头，不带任何文字；
    // 箭头周围整片右上区域（layoutSubviews 里铺满）都是点按区，
    // 点任意处触发 onEntry 进「我的」账号页。箭头是入口行同款的
    // SF chevron.right（13pt semibold、墨色），仅作视觉锚点、不吃触摸。
    _entryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _entryButton.backgroundColor = UIColor.clearColor;
    _entryButton.accessibilityLabel = @"我的账号资料";
    [_entryButton addTarget:self action:@selector(lui_entryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_entryButton];
    UIImageSymbolConfiguration *entryChevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
    UIImage *entryChevronImage = [[UIImage systemImageNamed:@"chevron.right" withConfiguration:entryChevronConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _entryChevronView = [[UIImageView alloc] initWithImage:entryChevronImage];
    _entryChevronView.tintColor = LUISettingsInkColor();
    _entryChevronView.contentMode = UIViewContentModeScaleAspectFit;
    _entryChevronView.userInteractionEnabled = NO;
    [self.contentView addSubview:_entryChevronView];

    _infoButton = LUISettingsHeroMakeButton(@"info.circle", @"插件信息");
    [_infoButton addTarget:self action:@selector(lui_infoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_infoButton];
    _logButton = LUISettingsHeroMakeButton(@"list.bullet.rectangle", @"更新日志");
    [_logButton addTarget:self action:@selector(lui_logTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_logButton];

    [self lui_refreshDecorColors];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lui_accountAuthUpdated:) name:@"LUIYoAccountAuthUpdated" object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)lui_accountAuthUpdated:(NSNotification *)note {
    [self lui_refreshTierChip];
    [self lui_refreshDisplayName];
    [self lui_refreshAuthChip];
    [self lui_refreshAvatar];
}

/// 名字与账号页同一套优先级：本机昵称（账号页里改的，按账号
/// 分键）> 服务器展示名（账号镜像 youyou.account.displayName）。
/// 服务器的名字第一次到达、或在账号页改了昵称时，正在看的
/// 页面也能立刻换上，不用等下次进页面。
- (void)lui_refreshDisplayName {
    NSString *_name = LUISettingsProfileNickname();
    if (_name.length == 0) _name = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.account.displayName"];
    if (_name.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.nameLabel.text = _name;
        [self setNeedsLayout];
    });
}

- (void)lui_refreshDecorColors {
    BOOL dark = LUISettingsLiquidTraitIsDark(self.traitCollection);
    UIColor *sheenA = [UIColor colorWithWhite:1.0 alpha:dark ? 0.10 : 0.55];
    UIColor *sheenB = [UIColor colorWithWhite:1.0 alpha:0.0];
    UIColor *gold = dark ? [UIColor colorWithRed:0.788 green:0.639 blue:0.416 alpha:0.10]
                         : [UIColor colorWithRed:0.690 green:0.541 blue:0.306 alpha:0.08];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.sheenLayer.colors = @[(id)sheenA.CGColor, (id)sheenB.CGColor, (id)gold.CGColor];
    self.rippleLayer.strokeColor = (dark ? [UIColor colorWithWhite:1.0 alpha:0.10]
                                         : [UIColor colorWithRed:0.106 green:0.114 blue:0.129 alpha:0.09]).CGColor;
    self.avatarRing.strokeColor = (dark ? [UIColor colorWithWhite:1.0 alpha:0.20]
                                        : [UIColor colorWithRed:0.106 green:0.114 blue:0.129 alpha:0.18]).CGColor;
    [CATransaction commit];
    // 头像：浅色石墨渐变底 + 暖纸字；深色雾白底 + 石墨字（LUISettingsOnInkColor 已是动态）。
    self.avatarView.backgroundColor = dark ? [UIColor colorWithRed:0.90 green:0.89 blue:0.87 alpha:1.0]
                                           : [UIColor colorWithRed:0.12 green:0.13 blue:0.15 alpha:1.0];
}

/// 资料卡胶囊只显示登录邮箱本身，不带任何等级前缀。配色沿用
/// 改版前免费/SVIP 两套胶囊方案、按账号授权状态切换：已授权 =
/// 砂金底白字，未授权 = 免费用户的中性灰。数据源是账号系统：
/// `AccountAuthorization` 把 status 结论镜像到 youyou.account.*
/// 三键（svip / 到期时间 / 邮箱）并广播 LUIYoAccountAuthUpdated；
/// 退出登录时三键已被清空，不会残留上一个账号的邮箱。
- (void)lui_refreshTierChip {
    NSUserDefaults *_defaults = NSUserDefaults.standardUserDefaults;
    BOOL _svip = [_defaults boolForKey:@"youyou.account.svip"];
    NSTimeInterval _expires = [_defaults doubleForKey:@"youyou.account.svipExpiresAt"];
    BOOL _authorized = _svip && _expires > NSDate.date.timeIntervalSince1970;
    NSString *_email = [_defaults stringForKey:@"youyou.account.email"] ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        self.versionChip.text = _email;
        self.versionChip.hidden = NO;
        if (_authorized) {
            self.versionChip.backgroundColor = [UIColor colorWithRed:0.78 green:0.60 blue:0.23 alpha:1.0];
            self.versionChip.textColor = [UIColor whiteColor];
        } else {
            self.versionChip.backgroundColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0];
            self.versionChip.textColor = [UIColor colorWithRed:0.45 green:0.45 blue:0.48 alpha:1.0];
        }
        [self setNeedsLayout];
    });
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([previousTraitCollection hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection]) {
            [self lui_refreshDecorColors];
        }
    }
}

- (void)configureWithTitle:(NSString *)title version:(NSString *)version key:(NSString *)key {
    // 【液态重设计】品牌卡同走玻璃卡（不经 ApplyCellChrome，需单独挂）。
    LUISettingsApplyLiquidCardBackground(self);
    self.contentView.backgroundColor = UIColor.clearColor;
    self.key = key;
    NSString *_dn = LUISettingsProfileNickname();
    if (_dn.length == 0) _dn = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.account.displayName"];
    self.nameLabel.text = _dn.length ? _dn : @"LUIYo";
    [self lui_refreshTierChip];
    [self lui_refreshAvatar];
    [self lui_refreshAuthChip];
    [self setNeedsLayout];
}

/// 头像：本机账号头像（在「我的账号资料」页里改、按账号分键）
/// 优先，没有改过时是内置默认头像；资源缺失才露出石墨底「L」字标。
- (void)lui_refreshAvatar {
    UIImage *avatar = LUISettingsAvatarImage();
    self.avatarImageView.image = avatar;
    self.avatarImageView.hidden = avatar == nil;
    self.avatarGlyph.hidden = avatar != nil;
}

/// 状态胶囊改显账号授权，与邮箱胶囊同一数据源（AccountAuthorization
/// 镜像的 youyou.account.svip / svipExpiresAt，退出登录时已清空）：
/// 已授权 = 砂金点金字，未授权 = 灰点灰字；随 LUIYoAccountAuthUpdated
/// 与邮箱胶囊、展示名一起刷新，不另存第二份状态。
- (void)lui_refreshAuthChip {
    NSUserDefaults *_defaults = NSUserDefaults.standardUserDefaults;
    BOOL _svip = [_defaults boolForKey:@"youyou.account.svip"];
    NSTimeInterval _expires = [_defaults doubleForKey:@"youyou.account.svipExpiresAt"];
    BOOL _authorized = _svip && _expires > NSDate.date.timeIntervalSince1970;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = _authorized ? @"已授权" : @"未授权";
        self.statusLabel.textColor = _authorized ? LUISettingsLiquidDynamicColor([UIColor colorWithRed:0.49 green:0.38 blue:0.20 alpha:1.0],
                                                                                 [UIColor colorWithRed:0.85 green:0.75 blue:0.56 alpha:1.0])
                                                 : LUISettingsInk2Color();
        self.statusDot.backgroundColor = _authorized ? LUISettingsAccentColor() : LUISettingsInk3Color();
        self.statusChip.backgroundColor = _authorized ? LUISettingsBadgeBackgroundColor() : LUISettingsControlTrackColor();
        [self setNeedsLayout];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat W = CGRectGetWidth(b);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.sheenLayer.frame = b;
    // 水纹圆心在右上出画处：设计稿 230 方框 right:-54 / top:-64 → 圆心 (W − 61, 51)，四圈半径 42 / 66 / 90 / 112。
    CGPoint c = CGPointMake(W - 61.0, 51.0);
    UIBezierPath *ripple = [UIBezierPath bezierPath];
    CGFloat radii[4] = {42.0, 66.0, 90.0, 112.0};
    for (int i = 0; i < 4; i++) {
        [ripple appendPath:[UIBezierPath bezierPathWithArcCenter:c radius:radii[i] startAngle:0 endAngle:2 * M_PI clockwise:YES]];
    }
    self.rippleLayer.path = ripple.CGPath;
    self.rippleLayer.frame = b;
    [CATransaction commit];

    CGFloat padX = 16.0, padTop = 14.0;
    self.avatarView.frame = CGRectMake(padX, padTop, 48.0, 48.0);
    // 右上角入口：箭头原地占原开关的锚点（右缘贴 padX、垂直对齐头像
    // 中心）；点按区是卡片右上整片（宽 176、高到按钮行顶），区内点
    // 任意处都触发入口。名字/胶囊的可用宽度以箭头左缘为界。
    CGFloat topSectionH = padTop + 48.0 + 12.0;
    CGFloat entryZoneW = 176.0;
    self.entryButton.frame = CGRectMake(W - entryZoneW, 0, entryZoneW, topSectionH);
    CGSize entryChevronSize = self.entryChevronView.image.size;
    CGFloat entryChevronW = MAX(8.0, entryChevronSize.width);
    CGFloat entryChevronH = MAX(13.0, entryChevronSize.height);
    self.entryChevronView.frame = CGRectMake(W - padX - entryChevronW, padTop + 24.0 - entryChevronH * 0.5, entryChevronW, entryChevronH);
    CGFloat metaX = CGRectGetMaxX(self.avatarView.frame) + 13.0;
    CGFloat metaW = MAX(0.0, CGRectGetMinX(self.entryChevronView.frame) - 6.0 - metaX);
    CGFloat nameH = MAX(24.0, ceil(LUISettingsSafeLineHeight(self.nameLabel.font)));
    CGFloat chipH = 18.0;
    CGFloat blockH = nameH + 5.0 + chipH;
    CGFloat nameY = padTop + MAX(0.0, floor((48.0 - blockH) * 0.5));
    self.nameLabel.frame = CGRectMake(metaX, nameY, metaW, nameH);
    CGFloat chipY = CGRectGetMaxY(self.nameLabel.frame) + 5.0;
    CGFloat x = metaX;
    if (!self.versionChip.hidden) {
        CGFloat vw = MIN(metaW, ceil([self.versionChip sizeThatFits:CGSizeMake(metaW, chipH)].width) + 16.0);
        self.versionChip.frame = CGRectMake(x, chipY, vw, chipH);
        x += vw + 6.0;
    }
    CGFloat sw = ceil([self.statusLabel sizeThatFits:CGSizeMake(metaW, chipH)].width);
    CGFloat statusW = MIN(MAX(0.0, metaX + metaW - x), 8.0 + 6.0 + 5.0 + sw + 8.0);
    self.statusChip.frame = CGRectMake(x, chipY, statusW, chipH);
    self.statusDot.frame = CGRectMake(8.0, (chipH - 6.0) * 0.5, 6.0, 6.0);
    self.statusLabel.frame = CGRectMake(19.0, 0, MAX(0.0, statusW - 19.0 - 8.0), chipH);

    // 底部两枚按钮：28 高，紧挨着从左排，按标题自适应宽。
    CGFloat btnY = topSectionH;
    CGFloat bx = padX;
    for (UIButton *btn in @[self.infoButton, self.logButton]) {
        CGFloat bw = ceil([btn sizeThatFits:CGSizeMake(200.0, 28.0)].width);
        btn.frame = CGRectMake(bx, btnY, bw, 28.0);
        UIView *glass = [btn viewWithTag:90210];
        if (glass) glass.frame = btn.bounds;
        bx += bw + 8.0;
    }
}

- (void)lui_infoTapped { if (self.onInfo) self.onInfo(); }
- (void)lui_logTapped { if (self.onChangelog) self.onChangelog(); }
- (void)lui_entryTapped { if (self.onEntry) self.onEntry(); }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.onInfo = nil;
    self.onChangelog = nil;
    self.onEntry = nil;
}
@end
