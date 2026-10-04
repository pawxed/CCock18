#import "PACC.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <notify.h>
#include <mach-o/dyld.h>

static NSString * const kPACCLIQPrefsDomain       = @"dylv.liquidassprefs";
static NSString * const kPACCLIQReloadNote        = @"dylv.liquidassprefs/Reload";
static NSString * const kPACCLIQGroupName         = @"dylv.liquidglass.sharedGroup";
static NSString * const kPACCLIQControlCenterType = @"dylv.liquidglass.cc.r2";
static const NSInteger  kPACCLIQGlassTag          = 190001;

static NSString *sPACCLIQActiveFilterType = nil;
static BOOL      sPACCLIQLiquidassFound = NO;
static BOOL      sPACCLIQLoggedProbe = NO;

#ifdef __cplusplus
extern "C" {
#endif
BOOL PACCLIQIsActive(void);
id PACCLIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef id (*PACCLIQFilterFactoryFn)(Class, SEL, NSString *);

static void PACCLIQLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void PACCLIQLog(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Library/Accessibility/liquidglass.log", "a");
    if (!f) return;
    fputs("[PACCLIQ] ", f);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static BOOL PACCLIQControlCenterEnabled(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPACCLIQPrefsDomain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
        CFSTR("ControlCenter.Enabled"),
        (__bridge CFStringRef)kPACCLIQPrefsDomain,
        &valid);
    return valid ? (BOOL)value : YES;
}

static BOOL PACCLIQContainsCI(const char *haystack, const char *needle) {
    if (!haystack || !needle) return NO;
    size_t hn = strlen(haystack);
    size_t nn = strlen(needle);
    if (nn == 0 || nn > hn) return NO;
    for (size_t i = 0; i + nn <= hn; i++) {
        size_t j = 0;
        for (; j < nn; j++) {
            char a = haystack[i + j];
            char b = needle[j];
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
        }
        if (j == nn) return YES;
    }
    return NO;
}

static BOOL PACCLIQProbeLiquidass(void) {
    if (sPACCLIQLiquidassFound) return YES;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (PACCLIQContainsCI(name, "liquid") || PACCLIQContainsCI(name, "dylv")) {
            sPACCLIQLiquidassFound = YES;
            if (!sPACCLIQLoggedProbe) {
                sPACCLIQLoggedProbe = YES;
                PACCLIQLog("Liquidass found (dyld): %s", name);
            }
            return YES;
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
        @"/Library/MobileSubstrate/DynamicLibraries",
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *file in files) {
            const char *n = file.UTF8String;
            if (PACCLIQContainsCI(n, "liquid") || PACCLIQContainsCI(n, "dylv")) {
                sPACCLIQLiquidassFound = YES;
                if (!sPACCLIQLoggedProbe) {
                    sPACCLIQLoggedProbe = YES;
                    PACCLIQLog("Liquidass found (disk): %s", n);
                }
                return YES;
            }
        }
    }
    return NO;
}

static BOOL PACCLIQShouldGlass(void) {
    if (!PACCLIQProbeLiquidass()) return NO;
    return PACCLIQControlCenterEnabled();
}

static id PACCLIQMakeFilter(NSString *typeName) {
    Class filterCls = NSClassFromString(@"CAFilter");
    if (!filterCls) return nil;
    SEL factorySel = NSSelectorFromString(@"filterWithType:");
    if (![filterCls respondsToSelector:factorySel]) return nil;
    PACCLIQFilterFactoryFn factory = (PACCLIQFilterFactoryFn)objc_msgSend;
    return factory(filterCls, factorySel, typeName);
}

#ifdef __cplusplus
extern "C" {
#endif

BOOL PACCLIQIsActive(void) {
    return PACCLIQShouldGlass();
}

id PACCLIQBuildGlassFilter(void) {
    if (!PACCLIQShouldGlass()) return nil;
    return PACCLIQMakeFilter(kPACCLIQControlCenterType);
}

#ifdef __cplusplus
}
#endif

@interface PACCLIQGlassView : UIView
@property (nonatomic, assign) CGFloat glassCornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
- (void)applyGlassFilter;
- (void)forceReapply;
@end

@interface PACCLIQGlassView ()
- (BOOL)filterIsLive;
@end

@implementation PACCLIQGlassView

+ (Class)layerClass {
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    return backdropCls ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _glassCornerRadius = radius;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    [self applyGlassFilter];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyGlassFilter];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.glassCornerRadius;
    [self applyGlassFilter];
}

- (BOOL)filterIsLive {
    NSArray *filters = self.layer.filters;
    if (filters.count != 1 || !sPACCLIQActiveFilterType) return NO;
    NSString *type = nil;
    @try { type = [filters[0] valueForKey:@"type"]; } @catch (...) {}
    return type.length && [type isEqualToString:sPACCLIQActiveFilterType];
}

- (void)applyGlassFilter {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    if (!PACCLIQShouldGlass()) {
        if (layer.filters.count) layer.filters = nil;
        sPACCLIQActiveFilterType = nil;
        return;
    }
    if ([self filterIsLive]) return;

    @try {
        [layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@YES forKey:@"windowServerAware"];
        if (![layer valueForKey:@"groupName"]) {
            [layer setValue:kPACCLIQGroupName forKey:@"groupName"];
        }
        [layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
        [layer setValue:@(0.5) forKey:@"scale"];

        NSString *previous = sPACCLIQActiveFilterType;
        id glassFilter = PACCLIQMakeFilter(kPACCLIQControlCenterType);
        if (glassFilter) {
            sPACCLIQActiveFilterType = kPACCLIQControlCenterType;
            if (![previous isEqualToString:kPACCLIQControlCenterType]) {
                PACCLIQLog("active filter = %s", kPACCLIQControlCenterType.UTF8String);
            }
            layer.filters = @[glassFilter];
            return;
        }

        if (previous) PACCLIQLog("ControlCenter filter unavailable");
        sPACCLIQActiveFilterType = nil;
    } @catch (NSException *e) {
        PACCLIQLog("applyGlassFilter exception: %s", e.reason.UTF8String);
    }
}

- (void)forceReapply {
    self.layer.filters = nil;
    [self applyGlassFilter];
}

@end

static void PACCLIQRestoreBlur(UIView *mediaPlayer) {
    if (!mediaPlayer) return;
    @try {
        UIView *blur = [mediaPlayer valueForKey:@"blurView"];
        if ([blur isKindOfClass:UIView.class]) blur.hidden = NO;
    } @catch (...) {}
}

static PACCLIQGlassView *PACCLIQInstallGlass(UIView *host, CGFloat radius) {
    if (!host) return nil;

    PACCLIQGlassView *glass = (PACCLIQGlassView *)[host viewWithTag:kPACCLIQGlassTag];

    if (!PACCLIQShouldGlass()) {
        if (glass) {
            glass.layer.filters = nil;
            glass.hidden = YES;
        }
        return nil;
    }

    if (!glass) {
        glass = [[PACCLIQGlassView alloc] initWithFrame:host.bounds cornerRadius:radius];
        glass.tag = kPACCLIQGlassTag;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:glass atIndex:0];
    }
    glass.hidden = NO;
    glass.frame = host.bounds;
    glass.glassCornerRadius = radius;
    if (![glass filterIsLive]) [glass forceReapply];
    [host sendSubviewToBack:glass];
    return glass;
}

static void PACCLIQRemoveAllGlass(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    NSMutableArray<UIView *> *all = [NSMutableArray arrayWithObject:overlay.view];
    while (all.count) {
        UIView *v = all.firstObject;
        [all removeObjectAtIndex:0];
        PACCLIQGlassView *g = (PACCLIQGlassView *)[v viewWithTag:kPACCLIQGlassTag];
        if (g) {
            g.layer.filters = nil;
            [g removeFromSuperview];
        }
        [all addObjectsFromArray:v.subviews];
    }

    PACCLIQRestoreBlur([overlay.view viewWithTag:kMediaPlayerTag]);
    sPACCLIQActiveFilterType = nil;
}

%hook CCAMediaPlayerView
- (void)layoutSubviews {
    %orig;

    if (!PACCLIQShouldGlass()) {
        PACCLIQRestoreBlur(self);
        PACCLIQGlassView *stale = (PACCLIQGlassView *)[self viewWithTag:kPACCLIQGlassTag];
        if (stale) {
            stale.layer.filters = nil;
            [stale removeFromSuperview];
        }
        return;
    }

    PACCLIQGlassView *glass = PACCLIQInstallGlass(self, self.layer.cornerRadius);
    if (!glass) return;
    if ([glass filterIsLive]) {
        @try {
            UIView *blur = [self valueForKey:@"blurView"];
            if ([blur isKindOfClass:UIView.class]) blur.hidden = YES;
        } @catch (...) {}
    }
}
%end

static void PACCLIQReapplyAll(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    UIView *mediaPlayer = [overlay.view viewWithTag:kMediaPlayerTag];
    if (!mediaPlayer) return;

    PACCLIQGlassView *glass = (PACCLIQGlassView *)[mediaPlayer viewWithTag:kPACCLIQGlassTag];
    if (glass) [glass forceReapply];

    [mediaPlayer setNeedsLayout];
}

static void PACCLIQScheduleReapply(void) {
    for (NSNumber *delay in @[ @1.5, @3.0, @5.0, @8.0, @12.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (PACCLIQProbeLiquidass()) {
                PACCLIQReapplyAll();
            } else {
                PACCLIQRemoveAllGlass();
            }
        });
    }
}

static void PACCLIQPrefsReloadCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!PACCLIQProbeLiquidass()) {
            PACCLIQRemoveAllGlass();
            return;
        }
        PACCLIQReapplyAll();
    });
}

%ctor {
    @autoreleasepool {
        PACCLIQLog("PACCLIQ loaded");

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PACCLIQPrefsReloadCallback,
            (__bridge CFStringRef)kPACCLIQReloadNote,
            NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        PACCLIQScheduleReapply();
    }
}