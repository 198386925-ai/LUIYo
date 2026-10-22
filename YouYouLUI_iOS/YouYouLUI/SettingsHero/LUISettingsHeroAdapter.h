#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void), void (^onEntry)(void));
void LUIYoRefreshSettingsHero(UIView *view);
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font);
NS_ASSUME_NONNULL_END

// In-app IPA signing engine (vendored zsign). Declared here so the
// Swift side reaches it through the bridging header; the full
// contract lives in Vendor/zsign/luiyo_zsign.h.
int luiyo_zsign_sign(const char *ipaPath,
                     const char *p12Path,
                     const char *password,
                     const char *profilePath,
                     const char *outputPath,
                     const char *tempDir,
                     char * _Nullable errorBuffer,
                     int errorBufferSize);
