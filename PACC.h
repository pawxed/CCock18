#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#ifdef __cplusplus
extern "C" {
#endif

extern const NSInteger PACCTagConnectivityCluster;
extern const NSInteger PACCTagMediaButtonMaterial;
extern const NSInteger kPageIndicatorTag;
extern const NSInteger kQuickAccessTag;
extern const NSInteger kMediaPlayerTag;
extern const NSInteger kPromoPageTag;

extern const void *PACCKeyCompactRadius;
extern const void *PACCKeyMediaMode;
extern const void *PACCKeyMiniGlyphBaseSize;

extern BOOL gEnabled;
extern BOOL gQuickAccessButtonsEnabled;
extern BOOL gPagingEnabled;
extern BOOL gHapticsEnabled;
extern BOOL gExperimentalPagingEnabled;
extern BOOL gPageAnimating;
extern BOOL gPagerScrubbing;
extern BOOL gCCAModuleExpanded;
extern NSInteger gCurrentPage;
extern NSString *const kReloadNotification;
extern BOOL gEditModeEnabled;
extern BOOL gEditModeActive;
extern BOOL gCircularModulesEnabled;
extern BOOL gPromoPageEnabled;
void PACCLoadEditPrefs(void);

CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius);
void LoadPrefs(void);
void Haptic(void);
CGFloat PageSpan(void);

UIViewController *OverlayIn(UIViewController *root);
BOOL IsModuleController(UIViewController *controller);
BOOL IsConnectivityController(UIViewController *controller);
NSArray<UIViewController *> *ModuleControllers(UIViewController *root);
UIViewController *ModuleCollection(UIViewController *overlay);
UIViewController *ConnectivityChild(UIViewController *controller, NSString *className);
UIView *PACCViewIvar(id object, const char *name);

UIView *PACCModuleAncestor(UIView *view);
CGFloat PACCModuleCornerRadius(CGSize size);
CGFloat PACCRadiusForModule(UIView *module);
UIView *PACCAncestor(UIView *view, NSString *className);
NSString *PACCMediaMode(UIView *view);
NSArray *PACCMediaMaterialFilters(UIView *view);
void PACCResizeMediaRoutingGlyph(UIView *button);
void PACCConfigureMedia(UIView *view);
UIViewController *PACCConnectivityChild(UIViewController *controller, NSString *className);
UIView *PACCModuleMaterial(void);
NSArray *PACCConnectivityVibrantFilters(UIView *root);
void PACCScaleMiniGlyphs(UIView *root, CGFloat scale);
UIImage *PACCBundledSymbol(NSString *name, UIColor *color, BOOL hierarchical);
void PACCConfigureConnectivity(UIViewController *controller);
CGRect PACCVisibleModuleBounds(UIViewController *overlay);

#ifdef __cplusplus
}
#endif

@interface MTMaterialLayer : CALayer
@property (nonatomic, copy, readwrite) NSString *recipeName;
@property (atomic, assign, readonly) CGRect visibleRect;
@end

@interface CALayer ()
@property (atomic, assign, readwrite) id unsafeUnretainedDelegate;
@end

@interface MRUNowPlayingView : UIView @end
@interface MRUArtworkView : UIView @end
@interface MRUNowPlayingHeaderView : UIView @end
@interface MRUNowPlayingLabelView : UIView @end
@interface MRUNowPlayingTransportControlsView : UIView @end
@interface MRUTransportButton : UIButton @end

@interface CCUIModuleCollectionView : UIScrollView @end

@interface PAnim : NSObject
+ (void)popViews:(NSArray<UIView *> *)views;
@end

@interface CCAPageIndicator : UIView
@property (nonatomic, weak) UIViewController *overlay;
@property (nonatomic) NSUInteger currentPage;
@property (nonatomic) NSUInteger pageCount;
@property (nonatomic, assign) BOOL transitionActive;
@property (nonatomic, assign) BOOL scrubbingActive;
@property (nonatomic, assign, readonly) BOOL scrubbing;
- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay;
- (void)layoutButtons;
- (void)captureCollectionBase;
@end

@interface CCAQuickAccessHost : UIView
@end

@interface CCAMediaPlayerView : UIView
- (void)setupUI;
- (void)refresh;
- (void)resetForPresentation;
- (void)fadeIn;
- (void)fadeOut;
- (void)slideOut;
- (void)slideOffScreen;
@end

@interface CCAPromoPageView : UIView
- (void)refreshFact;
@end

@interface PACC : NSObject
+ (instancetype)shared;
- (void)installOnOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay;
- (void)adjustStatusBarForOverlay:(UIViewController *)overlay;
- (void)animateElementsInForOverlay:(UIViewController *)overlay;
- (void)animateElementsOutForOverlay:(UIViewController *)overlay;
- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay;
- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay;
- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay;
- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView;
- (void)installPromoPageOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutPromoPageForCollectionView:(UIScrollView *)collectionView;
- (CGFloat)topInsetForOverlay:(UIViewController *)overlay;
- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag;
@end