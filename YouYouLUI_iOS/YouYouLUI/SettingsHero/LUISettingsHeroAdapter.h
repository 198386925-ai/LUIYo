#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void), void (^onEntry)(void));
void LUIYoRefreshSettingsHero(UIView *view);
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font);
NS_ASSUME_NONNULL_END
