#import "LUISettingsHeroAdapter.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <math.h>
// Compatibility helpers live here; the supplied cell below remains byte-for-byte unchanged.
static UIColor *LUISettingsLiquidDynamicColor(UIColor *light, UIColor *dark) { return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) { return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light; }]; }
static UIColor *LUISettingsInkColor(void) { return UIColor.labelColor; }
static UIColor *LUISettingsInk2Color(void) { return UIColor.secondaryLabelColor; }
static UIColor *LUISettingsInk3Color(void) { return UIColor.tertiaryLabelColor; }
static UIColor *LUISettingsOnInkColor(void) { return LUISettingsLiquidDynamicColor(UIColor.whiteColor, UIColor.blackColor); }
static UIColor *LUISettingsControlTrackColor(void) { return UIColor.tertiarySystemFillColor; }
static UIColor *LUISettingsAccentColor(void) { return [UIColor colorWithRed:.69 green:.54 blue:.31 alpha:1]; }
static UIColor *LUISettingsBadgeBackgroundColor(void) { return [LUISettingsAccentColor() colorWithAlphaComponent:.12]; }
static BOOL LUISettingsLiquidTraitIsDark(UITraitCollection *t) { return t.userInterfaceStyle == UIUserInterfaceStyleDark; }
static void LUISettingsApplyTitleLabelChrome(UILabel *label) { label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = .85; }
static CGFloat LUISettingsSafeLineHeight(UIFont *font) { return font.lineHeight; }
static NSString *LUISettingsCurrentAccountEmail(void) {
    return [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.account.email"] ?: @"";
}

/// 本机昵称：在「我的账号资料」页可改，按账号邮箱分键存在
/// youyou.profile.nicknames 字典里（与 Swift 的 AccountProfileStore
/// 共用同一份存储，两边的键名不许漂移）。显示优先级最高，
/// 高于服务器下发的展示名。
static NSString *LUISettingsProfileNickname(void) {
    NSString *email = LUISettingsCurrentAccountEmail();
    if (email.length == 0) return nil;
    NSDictionary *map = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"youyou.profile.nicknames"];
    if (![map isKindOfClass:NSDictionary.class]) return nil;
    id raw = map[email];
    NSString *value = [raw isKindOfClass:NSString.class] ? raw : nil;
    return value.length ? value : nil;
}

static UIImage *LUISettingsAvatarImage(void) {
    // 头像优先级：本机账号头像（账号页里改的，文件存在
    // Application Support/AccountAvatars/，文件名按账号记录在
    // youyou.profile.avatarFiles 字典）> 内置默认头像 DefaultAvatar。
    NSString *email = LUISettingsCurrentAccountEmail();
    if (email.length) {
        NSDictionary *map = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"youyou.profile.avatarFiles"];
        id raw = [map isKindOfClass:NSDictionary.class] ? map[email] : nil;
        NSString *fileName = [raw isKindOfClass:NSString.class] ? raw : nil;
        if (fileName.length) {
            NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"AccountAvatars"];
            UIImage *local = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:fileName]];
            if (local) return local;
        }
    }
    return [UIImage imageNamed:@"DefaultAvatar"];
}
static void LUISettingsApplyLiquidCardBackground(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    UIView *background = [UIView new];background.backgroundColor = LUISettingsLiquidDynamicColor([UIColor colorWithWhite:.99 alpha:1],[UIColor colorWithWhite:.13 alpha:1]);background.layer.cornerRadius = 24;background.clipsToBounds = YES;cell.backgroundView = background;
}
#include "LUISettingsHeroCell.m"
static UIFont *_LUIYoHeroCustomFont = nil;
static UIFont *LUIYoLoadThemeFontFromDisk(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) return nil;
    NSString *fontPath = [paths[0] stringByAppendingPathComponent:@"ThemeFont.data"];
    NSData *data = [NSData dataWithContentsOfFile:fontPath];
    if (!data || data.length == 0) return nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (!provider) return nil;
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!cgFont) return nil;
    NSString *fontName = (__bridge_transfer NSString *)CGFontCopyPostScriptName(cgFont);
    CFErrorRef error = NULL;
    if (!CTFontManagerRegisterGraphicsFont(cgFont, &error)) {
        // Already registered, try to use it anyway
    }
    CGFontRelease(cgFont);
    if (!fontName) return nil;
    return [UIFont fontWithName:fontName size:16.0];
}
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font);
/// Build 38: the 我的 page dropped liquid glass. The hero card body was
/// already a solid-filled background view; the two bottom buttons still
/// carried a UIVisualEffectView glass surface (tag 90210, created and
/// laid out by the cell). Neutralise it in place — no effect, flat
/// control-track fill — so the buttons read as solid chips over the
/// solid card, without touching the supplied cell file.
static void LUIYoSolidifyHeroButtons(LUISettingsHeroCell *cell) {
    for (UIButton *button in @[cell.infoButton, cell.logButton]) {
        UIView *surface = [button viewWithTag:90210];
        if ([surface isKindOfClass:UIVisualEffectView.class]) {
            UIVisualEffectView *effectView = (UIVisualEffectView *)surface;
            effectView.effect = nil;
            effectView.backgroundColor = LUISettingsControlTrackColor();
            effectView.contentView.backgroundColor = LUISettingsControlTrackColor();
        }
    }
}
void LUIYoRefreshSettingsHero(UIView *view) {
    if (![view isKindOfClass:LUISettingsHeroCell.class]) return;
    LUISettingsHeroCell *cell = (LUISettingsHeroCell *)view;
    // Self-sufficient: load theme font from disk if not in memory (fixes instability)
    if (!_LUIYoHeroCustomFont) {
        _LUIYoHeroCustomFont = LUIYoLoadThemeFontFromDisk();
    }
    // 名字与账号页同一套优先级：本机昵称（账号页里改的）>
    // 账号展示名（服务器分配的「LUI用户+4位数字」，由
    // AccountAuthorization 镜像到 youyou.account.displayName；
    // 服务器还没给名时镜像里是本机按账号生成的同格式兜底名）。
    // 两者皆空只可能是账号状态还没回来过，用品牌名占位一瞬。
    NSString *name = LUISettingsProfileNickname();
    if (name.length == 0) name = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.account.displayName"];
    if (name.length == 0) name = @"LUIYo";
    NSString *shortVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.6";
    NSString *buildNum = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    NSString *version = [NSString stringWithFormat:@"Version%@ Build%@", shortVer, buildNum];
    [cell configureWithTitle:name version:version key:@"luiyo.hero.enabled"];
    LUIYoSolidifyHeroButtons(cell);
    // Use custom theme font if set, otherwise default system font.
    cell.nameLabel.font = _LUIYoHeroCustomFont ? [_LUIYoHeroCustomFont fontWithSize:18.0] : [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    cell.nameLabel.attributedText = nil;
    cell.nameLabel.text = name;
    cell.nameLabel.textColor = LUISettingsInkColor();
    cell.nameLabel.accessibilityValue = name;
    cell.versionChip.layer.cornerRadius = 9;
    // The app has its own appearance selector; UIKit's inherited trait can be stale
    // while a page transition is in progress. Resolve the hero from that explicit
    // preference first, and consult the live window trait only in System mode.
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.appearanceMode"] ?: @"system";
    BOOL useDark;
    if ([mode isEqualToString:@"light"]) useDark = NO;
    else if ([mode isEqualToString:@"dark"]) useDark = YES;
    else {
        UITraitCollection *traits = cell.window.traitCollection ?: cell.traitCollection;
        useDark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    NSString *appearance = useDark ? @"dark" : @"light";
    NSString *key = [@"youyou.heroCardColor." stringByAppendingString:appearance];
    NSString *savedHex = [NSUserDefaults.standardUserDefaults stringForKey:key];
    // A stale saved dark card color must never override explicit Light mode.
    NSString *hex = useDark ? (savedHex.length ? savedHex : @"#1C1C1E") : @"#FFFFFF";
    unsigned int value = 0;
    [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
    UIColor *resolved = [UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:((value)&255)/255.0 alpha:1];
    cell.backgroundView.backgroundColor = resolved;
    cell.overrideUserInterfaceStyle = useDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    [cell setNeedsLayout];
    // Re-apply custom theme font if one was set (refresh resets to system fonts).
    if (_LUIYoHeroCustomFont) LUIYoSetSettingsHeroFont(cell, _LUIYoHeroCustomFont);
}
/// Set a custom theme font on the hero's labels. Pass nil to revert to system fonts.
static void LUIYoSetHeroButtonFont(UIButton *button, UIFont *font) {
    // Skip if the font is already correct (avoid flicker from repeated rebuilds).
    UIFont *current = button.titleLabel.font;
    if (current && [current.fontName isEqualToString:font.fontName] && fabs(current.pointSize - font.pointSize) < 0.1) {
        return;
    }
    button.titleLabel.font = font;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = button.configuration;
        if (cfg) {
            // Rebuild attributedTitle with the new font, preserving the chevron.
            NSString *title = cfg.attributedTitle ? cfg.attributedTitle.string : [button titleForState:UIControlStateNormal];
            // Strip trailing chevron glyph if present (added as separate attribute).
            NSString *clean = [title stringByReplacingOccurrencesOfString:@" ›" withString:@""];
            NSMutableAttributedString *t = [[NSMutableAttributedString alloc]
                initWithString:[clean stringByAppendingString:@" ›"]
                attributes:@{NSFontAttributeName: font}];
            [t addAttributes:@{NSForegroundColorAttributeName: button.tintColor ?: UIColor.labelColor}
                       range:NSMakeRange(t.length - 1, 1)];
            cfg.attributedTitle = t;
            button.configuration = cfg;
        }
    }
}
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font) {
    _LUIYoHeroCustomFont = font;
    if (![view isKindOfClass:LUISettingsHeroCell.class]) return;
    LUISettingsHeroCell *cell = (LUISettingsHeroCell *)view;
    if (font) {
        cell.nameLabel.font = [font fontWithSize:18.0];
        cell.versionChip.font = [font fontWithSize:10.5];
        cell.statusLabel.font = [font fontWithSize:11.0];
        cell.avatarGlyph.font = [font fontWithSize:21.0];
        LUIYoSetHeroButtonFont(cell.infoButton, [font fontWithSize:12.0]);
        LUIYoSetHeroButtonFont(cell.logButton, [font fontWithSize:12.0]);
    } else {
        cell.nameLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
        cell.versionChip.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
        cell.statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        cell.avatarGlyph.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightHeavy];
        LUIYoSetHeroButtonFont(cell.infoButton, [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]);
        LUIYoSetHeroButtonFont(cell.logButton, [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]);
    }
}
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void), void (^onEntry)(void)) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"luiyo.hero.enabled":@YES}];
    // 卡上只展示头像与名字，不挂任何点按编辑手势；
    // 修改头像/昵称的入口在右上角箭头进去的「我的账号资料」页里。
    LUISettingsHeroCell *cell = [[LUISettingsHeroCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.onInfo = onInfo;cell.onChangelog = onChangelog;cell.onEntry = onEntry;
    LUIYoRefreshSettingsHero(cell);
    return cell;
}
