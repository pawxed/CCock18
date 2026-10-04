#import "PACC.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#ifdef __cplusplus
extern "C" {
#endif
BOOL PACCLIQIsActive(void);
id PACCLIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef struct CCUILayoutSize  { NSUInteger width;  NSUInteger height; } CCUILayoutSize;
typedef struct CCUILayoutPoint { NSUInteger x;      NSUInteger y;      } CCUILayoutPoint;
typedef struct CCUILayoutRect  { CCUILayoutPoint origin; CCUILayoutSize size; } CCUILayoutRect;
typedef struct { NSUInteger c, r, w, h; } PACRect;

static NSUInteger kPACCols = 4;
static NSUInteger kPACRows = 8;
static NSUInteger gPACEditEpoch = 0;
static CFTimeInterval gEditModeEnteredAt = 0;
static NSInteger gPACLastPresentationState = 1;
static CGFloat    kPACCell = 67.0;
static CGFloat    kPACgap  = 12.0;
static CGFloat    kPACStep = 79.0;

BOOL gEditModeEnabled = NO;
BOOL gEditModeActive  = NO;

static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditOrigins;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditSizes;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditBaseSizes;

static NSString *gPACPendingResizeID = nil;
static CCUILayoutSize gPACPendingResizeSize = {0, 0};
static NSTimeInterval gPACPendingResizeLastTouch = 0;

static Class kClsCCUIButtonModuleView;
static Class kClsCCUICAPackageView;
static Class kClsCABackdropLayer;

static const NSInteger kPACBorderTag       = 182000;
static const NSInteger kPACRemoveTag       = 182001;
static const NSInteger kPACResizeTag       = 182002;
static const NSInteger kPACHintTag         = 182003;
static const NSInteger kPACProxyTag        = 182004;
static const NSInteger kPACResetTag        = 182005;
static const NSInteger kPACShieldTag       = 182006;
static const NSInteger kPACProxyShadowTag  = 182007;

static const void *kPACBorderKey   = &kPACBorderKey;
static const void *kPACRemoveKey   = &kPACRemoveKey;
static const void *kPACResizeKey   = &kPACResizeKey;
static const void *kPACPresKey     = &kPACPresKey;
static const void *kPACMidKey      = &kPACMidKey;
static const void *kPACStartSzKey  = &kPACStartSzKey;
static const void *kPACGestKey     = &kPACGestKey;
static const void *kPACDragSrcKey  = &kPACDragSrcKey;
static const void *kPACDragProxyKey= &kPACDragProxyKey;
static const void *kPACDragGrabKey = &kPACDragGrabKey;
static const void *kPACOwnGestureKey = &kPACOwnGestureKey;
static const void *kPACDisabledGesturesKey = &kPACDisabledGesturesKey;
static const void *kPACResizedSetKey = &kPACResizedSetKey;
static const void *kPACLastCellKey     = &kPACLastCellKey;
static const void *kPACOrigLayoutKey   = &kPACOrigLayoutKey;
static const void *kPACLastRadiusKey   = &kPACLastRadiusKey;
static const void *kPACLastPresKey     = &kPACLastPresKey;
static const void *kPACOrigRadiiKey    = &kPACOrigRadiiKey;
static const void *kPACLandscapeCleanKey = &kPACLandscapeCleanKey;
static const void *kPACIconPinKey = &kPACIconPinKey;
static const CGFloat kPACBorderWidth = 4.0;
static const CGFloat kPACBorderInset = 3.5;
static CFTimeInterval gPACRotationQuietUntil = 0;

static NSString *PACMid(UIViewController *vc);
static CGRect PACVisibleFrame(UIViewController *m, UIViewController *overlay);
static UIViewController *PACModuleAtPoint(CGPoint pt, UIViewController *overlay);
static CGPoint PACGridBase(UIViewController *overlay);
static NSUInteger PACVisibleRowCap(UIViewController *ov);
static NSArray<NSNumber *> *PACKnownBaseSize(NSString *mid);
static void PACEnsureBaseSize(UIViewController *m, UIViewController *ov);
static void PACEffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static void PACPresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static BOOL PACModuleSupportsResizing(NSString *mid);
static CCUILayoutSize PACResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation);
static BOOL PACSizeAllowed(NSUInteger w, NSUInteger h);
static BOOL PACDragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h);
static NSString *PACPrettyNameForModule(UIViewController *m);
static BOOL PACRectsOverlap(PACRect a, PACRect b);
static BOOL PACFindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow);
static id PACSettingsProvider(void);
static NSArray<NSString *> *PACProviderOrderedIdentifiers(void);
static UIView *PACModuleButtonView(UIView *moduleView);
static NSArray<UIView *> *PACCompactGlyphHosts(UIView *view);
static void PACLayoutModuleIcon(UIViewController *m);
static void PACRestoreModuleIcon(UIViewController *m);
static CGFloat PACRadiusForSize(NSUInteger w, NSUInteger h);
static void PACApplyRadiusToModule(UIViewController *m);
static void PACRefreshPresentation(UIViewController *m, UIViewController *ov);
static BOOL PACWasResizedFromOneByOne(NSString *mid);
static void PACApplyChrome(UIViewController *m, UIViewController *ov);
static void PACStripChrome(UIViewController *m);
static void PACRestoreModuleRadius(UIViewController *m);
static void PACInstallGestures(UIViewController *ov);
static BOOL PACEditAllowed(void);
static BOOL PACIsLandscape(void);
static void PACTearDownModule(UIViewController *m);
static void PACTearDownAllModules(UIViewController *ov);
static void PACScheduleRotationRefresh(void);

static void PACInitCachedClasses(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kClsCCUIButtonModuleView = NSClassFromString(@"CCUIButtonModuleView");
        kClsCCUICAPackageView    = NSClassFromString(@"CCUICAPackageView");
        kClsCABackdropLayer      = NSClassFromString(@"CABackdropLayer");
    });
}

static void PACEnsureStore(void) {
    if (!gEditOrigins) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridOrigins"), CFSTR("pawxed.ccock18.preferences"));
        gEditOrigins = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridSizes"), CFSTR("pawxed.ccock18.preferences"));
        gEditSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditBaseSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditBaseSizes"), CFSTR("pawxed.ccock18.preferences"));
        gEditBaseSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
}

static void PACSaveStore(void) {
    PACEnsureStore();
    CFPreferencesSetAppValue(CFSTR("EditGridOrigins"), (__bridge CFPropertyListRef)[gEditOrigins copy], CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditGridSizes"),   (__bridge CFPropertyListRef)[gEditSizes copy],   CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditBaseSizes"),   (__bridge CFPropertyListRef)[gEditBaseSizes copy], CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesAppSynchronize(CFSTR("pawxed.ccock18.preferences"));
}

static BOOL PACIsNotchedDevice(void) {
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (w && w.safeAreaInsets.bottom >= 1.0) return YES;
    return NO;
}

static BOOL PACIsLandscape(void) {
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (win) {
        CGSize sz = win.bounds.size;
        if (sz.width > 1.0 && sz.height > 1.0) return sz.width > sz.height;
    }
    CGSize sz = UIScreen.mainScreen.bounds.size;
    return sz.width > sz.height;
}

static BOOL PACIsNonNotchedDevice(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    if (MAX(size.width, size.height) >= 800.0) return NO;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window && window.safeAreaInsets.bottom >= 1.0) return NO;
    return YES;
}

static void PACRefreshGridConstants(void) {
    BOOL landscape = PACIsLandscape();
    kPACCols = landscape ? 8 : 4;
    kPACRows = landscape ? 4 : 8;
    kPACCell = 67.0;
    kPACgap  = 12.0;
    kPACStep = kPACCell + kPACgap;
}

static BOOL PACEditAllowed(void) {
    if (!gEnabled || !gEditModeEnabled) return NO;
    if (PACIsLandscape()) return NO;
    return YES;
}

static NSString *PACGridKey(NSString *mid) {
    if (!mid.length) return mid;
    return PACIsLandscape() ? [@"L|" stringByAppendingString:mid]
                            : [@"P|" stringByAppendingString:mid];
}

static NSArray<NSNumber *> *PACGetOrigin(NSString *mid) {
    if (!mid.length) return nil;
    PACEnsureStore();
    NSString *key = PACGridKey(mid);
    NSArray<NSNumber *> *v = gEditOrigins[key];
    if (v) return v;
    if (!PACIsLandscape()) return gEditOrigins[mid];
    return nil;
}

static void PACSetOrigin(NSString *mid, NSArray<NSNumber *> *value) {
    if (!mid.length) return;
    PACEnsureStore();
    NSString *key = PACGridKey(mid);
    if (value) gEditOrigins[key] = value;
    else       [gEditOrigins removeObjectForKey:key];
}

static void PACInvalidateOtherOrientationOriginForModule(NSString *mid) {
    if (!mid.length) return;
    PACEnsureStore();
    BOOL landscape = PACIsLandscape();
    NSString *otherPrefix = landscape ? @"P|" : @"L|";
    NSString *key = [otherPrefix stringByAppendingString:mid];
    [gEditOrigins removeObjectForKey:key];
    if (!landscape) {
        [gEditOrigins removeObjectForKey:mid];
    }
}

static NSArray<NSNumber *> *PACSourceOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *fromPrefix = toLandscape ? @"P|" : @"L|";
    NSArray *v = gEditOrigins[[fromPrefix stringByAppendingString:mid]];
    if (v) return v;
    if (toLandscape) return gEditOrigins[mid];
    return nil;
}

static NSArray<NSNumber *> *PACTargetOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";
    return gEditOrigins[[toPrefix stringByAppendingString:mid]];
}

static void PACMigrateMissingOrigins(UIViewController *ov) {
    if (!ov) return;
    PACEnsureStore();
    PACRefreshGridConstants();

    BOOL toLandscape = PACIsLandscape();
    NSUInteger fromCols = toLandscape ? 4 : 8;
    NSUInteger fromRows = toLandscape ? 8 : 4;
    NSUInteger toCols   = toLandscape ? 8 : 4;
    NSUInteger toRows   = toLandscape ? 4 : 8;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";

    NSMutableArray<NSDictionary *> *toMigrate = [NSMutableArray array];
    NSMutableArray<NSString *>     *already   = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;

        if (PACTargetOriginForRotation(mid, toLandscape)) {
            [already addObject:mid];
            continue;
        }
        NSArray<NSNumber *> *src = PACSourceOriginForRotation(mid, toLandscape);
        if (src.count < 2) continue;

        NSUInteger c = src[0].unsignedIntegerValue;
        NSUInteger a = src[1].unsignedIntegerValue;
        NSUInteger page = a / fromRows;
        NSUInteger r    = a % fromRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;
        if (!PACDragSizeAllowedForModule(mid, w, h)) { w = 1; h = 1; }

        [toMigrate addObject:@{
            @"mid":  mid,
            @"c":    @(c),
            @"r":    @(r),
            @"page": @(page),
            @"w":    @(w),
            @"h":    @(h),
        }];
    }

    if (!toMigrate.count) return;

    [toMigrate sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *k in @[@"page", @"r", @"c"]) {
            NSInteger va = [a[k] integerValue];
            NSInteger vb = [b[k] integerValue];
            if (va != vb) return va < vb ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"mid"] compare:b[@"mid"]];
    }];

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, NSValue *> *> *pages =
        [NSMutableDictionary dictionary];

    for (NSString *mid in already) {
        NSArray<NSNumber *> *o = PACTargetOriginForRotation(mid, toLandscape);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        NSUInteger page = a / toRows;
        NSUInteger r    = a % toRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;

        NSMutableDictionary *map = pages[@(page)];
        if (!map) { map = [NSMutableDictionary dictionary]; pages[@(page)] = map; }
        PACRect pr = {c, r, w, h};
        map[mid] = [NSValue value:&pr withObjCType:@encode(PACRect)];
    }

    for (NSDictionary *e in toMigrate) {
        NSString *mid = e[@"mid"];
        NSUInteger srcC = [e[@"c"]    unsignedIntegerValue];
        NSUInteger srcR = [e[@"r"]    unsignedIntegerValue];
        NSUInteger page = [e[@"page"] unsignedIntegerValue];
        NSUInteger w    = [e[@"w"]    unsignedIntegerValue];
        NSUInteger h    = [e[@"h"]    unsignedIntegerValue];

        NSUInteger prefC = (NSUInteger)llround(((double)srcC / (double)fromCols) * (double)toCols);
        NSUInteger prefR = (NSUInteger)llround(((double)srcR / (double)fromRows) * (double)toRows);
        if (prefC + w > toCols) prefC = (toCols >= w) ? (toCols - w) : 0;
        if (prefR + h > toRows) prefR = (toRows >= h) ? (toRows - h) : 0;

        NSMutableDictionary<NSString *, NSValue *> *placed = pages[@(page)];
        if (!placed) { placed = [NSMutableDictionary dictionary]; pages[@(page)] = placed; }

        NSUInteger maxRow = (toRows >= h) ? (toRows - h) : 0;
        NSUInteger outC = prefC, outR = prefR;
        BOOL ok = PACFindFreeCellFor(placed, prefC, prefR, w, h, maxRow, &outC, &outR);

        if (!ok) {
            NSUInteger p = page + 1;
            while (p < 8) {
                NSMutableDictionary *next = pages[@(p)];
                if (!next) { next = [NSMutableDictionary dictionary]; pages[@(p)] = next; }
                if (PACFindFreeCellFor(next, 0, 0, w, h, maxRow, &outC, &outR)) {
                    placed = next; page = p; ok = YES; break;
                }
                p++;
            }
        }
        if (!ok) continue;

        PACRect pr = {outC, outR, w, h};
        placed[mid] = [NSValue value:&pr withObjCType:@encode(PACRect)];
        gEditOrigins[[toPrefix stringByAppendingString:mid]] =
            @[@(outC), @(page * toRows + outR)];
    }

    PACSaveStore();
}

static NSString *PACMid(UIViewController *vc) {
    if (!vc) return nil;
    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier"]) {
        @try { id v = [vc valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v; }
        @catch (__unused NSException *e) {}
    }
    return nil;
}

static CGRect PACVisibleFrame(UIViewController *m, UIViewController *overlay) {
    if (!m.view || !overlay.view) return CGRectZero;
    CGRect f = [m.view convertRect:m.view.bounds toView:overlay.view];
    UIViewController *col = ModuleCollection(overlay);
    if (col.view) {
        CATransform3D sub = col.view.layer.sublayerTransform;
        f.origin.x += sub.m41;
        f.origin.y += sub.m42;
    }
    return f;
}

static UIViewController *PACModuleAtPoint(CGPoint pt, UIViewController *overlay) {
    UIViewController *best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (UIViewController *m in ModuleControllers(overlay)) {
        CGRect f = PACVisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        if (CGRectContainsPoint(f, pt)) {
            CGFloat d = hypot(CGRectGetMidX(f) - pt.x, CGRectGetMidY(f) - pt.y);
            if (d < bestD) { bestD = d; best = m; }
        }
    }
    return best;
}

static CGPoint PACGridBase(UIViewController *overlay) {
    PACRefreshGridConstants();
    PACEnsureStore();
    CGFloat bx = CGFLOAT_MAX, by = CGFLOAT_MAX;
    NSUInteger page = (NSUInteger)gCurrentPage;
    for (UIViewController *m in ModuleControllers(overlay)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        if (a / kPACRows != page) continue;
        NSUInteger lr = a % kPACRows;
        CGRect f = PACVisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        CGFloat x = CGRectGetMinX(f) - (CGFloat)c * kPACStep;
        CGFloat y = CGRectGetMinY(f) - (CGFloat)lr * kPACStep;
        if (x < bx) bx = x;
        if (y < by) by = y;
    }
    if (bx == CGFLOAT_MAX) {
        CGFloat w = CGRectGetWidth(overlay.view.bounds);
        CGFloat gw = kPACCols * kPACCell + (kPACCols - 1) * kPACgap;
        bx = (w - gw) * 0.5;
        by = 100.0;
    }
    return CGPointMake(bx, by);
}

static NSUInteger PACVisibleRowCap(UIViewController *ov) {
    if (!ov || !ov.view) return kPACRows - 1;
    CGPoint base = PACGridBase(ov);
    CGFloat overlayH = CGRectGetHeight(ov.view.bounds);
    CGFloat safeBottom = ov.view.safeAreaInsets.bottom;
    if (safeBottom < 1.0) safeBottom = 20.0;
    CGFloat usableBottom = overlayH - safeBottom - 8.0;
    CGFloat usableH = usableBottom - base.y;
    if (usableH < kPACStep) return 0;
    NSInteger rows = (NSInteger)floor(usableH / kPACStep);
    if (rows <= 0) rows = 1;
    NSUInteger cap = (NSUInteger)MAX(0, MIN((NSInteger)kPACRows - 1, rows - 1));
    return cap;
}

static NSArray<NSNumber *> *PACKnownBaseSize(NSString *mid) {
    if (!mid.length) return nil;
    NSString *lower = mid.lowercaseString;
    NSArray<NSArray<NSString *> *> *entries = @[
        @[@"control-center.connectivitymodule", @"2", @"2"],
        @[@"connectivitymodule", @"2", @"2"],
        @[@"mediaremote.controlcenter.nowplaying", @"2", @"2"],
        @[@"mediaremote.controlcenter.audio", @"1", @"2"],
        @[@"control-center.displaymodule", @"1", @"2"],
        @[@"control-center.focusui", @"2", @"1"],
        @[@"focusui", @"2", @"1"],
        @[@"donotdisturb", @"2", @"1"],
    ];
    for (NSArray *entry in entries) {
        if ([lower containsString:entry[0]]) {
            return @[@([entry[1] integerValue]), @([entry[2] integerValue])];
        }
    }
    return nil;
}

static void PACEnsureBaseSize(UIViewController *m, UIViewController *ov) {
    NSString *mid = PACMid(m);
    if (!mid.length) return;

    NSArray<NSNumber *> *known = PACKnownBaseSize(mid);
    if (known.count == 2) {
        if (![gEditBaseSizes[mid] isEqualToArray:known]) {
            gEditBaseSizes[mid] = known;
            PACSaveStore();
        }
        return;
    }

    if (gEditSizes[mid]) {
        if (![gEditBaseSizes[mid] isEqualToArray:@[@1, @1]]) {
            gEditBaseSizes[mid] = @[@1, @1];
            PACSaveStore();
        }
        return;
    }

    NSArray<NSNumber *> *existing = gEditBaseSizes[mid];
    if (existing.count >= 2 &&
        (existing[0].integerValue != 1 || existing[1].integerValue != 1)) {
        gEditBaseSizes[mid] = @[@1, @1];
        PACSaveStore();
        return;
    }
    if (existing) return;

    CGRect f = PACVisibleFrame(m, ov);
    if (CGRectIsEmpty(f)) return;
    NSUInteger w = (NSUInteger)MAX(1, MIN((NSInteger)kPACCols, (NSInteger)llround((CGRectGetWidth(f) + kPACgap) / kPACStep)));
    NSUInteger h = (NSUInteger)MAX(1, MIN((NSInteger)kPACRows, (NSInteger)llround((CGRectGetHeight(f) + kPACgap) / kPACStep)));
    gEditBaseSizes[mid] = @[@(w), @(h)];
    PACSaveStore();
}

static void PACEffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    PACEnsureStore();
    NSArray<NSNumber *> *s = gEditSizes[mid];
    if (!s) s = gEditBaseSizes[mid];
    *w = s.count >= 2 ? s[0].unsignedIntegerValue : 1;
    *h = s.count >= 2 ? s[1].unsignedIntegerValue : 1;
}

static void PACPresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    if (gPACPendingResizeID && [gPACPendingResizeID isEqualToString:mid] &&
        gPACPendingResizeSize.width && gPACPendingResizeSize.height) {
        *w = gPACPendingResizeSize.width;
        *h = gPACPendingResizeSize.height;
        return;
    }
    PACEffectiveSize(mid, w, h);
}

typedef struct { NSTimeInterval duration; CGFloat c1x, c1y, c2x, c2y; } PACAnimSpec;

static PACAnimSpec PACResizeSpec(void) {
    if (gExperimentalPagingEnabled) return (PACAnimSpec){0.58, 0.32, 0.72, 0.0, 1.0};
    return (PACAnimSpec){0.25, 0.25, 0.10, 0.25, 1.0};
}

static CAMediaTimingFunction *PACResizeTiming(PACAnimSpec sp) {
    return [CAMediaTimingFunction functionWithControlPoints:(float)sp.c1x :(float)sp.c1y :(float)sp.c2x :(float)sp.c2y];
}

static BOOL PACAnimationsAllowed(void) {
    return CACurrentMediaTime() >= gPACRotationQuietUntil;
}

static BOOL PACModuleSupportsResizing(NSString *mid) {
    if (!mid.length) return NO;
    NSString *lower = mid.lowercaseString;
    if ([lower isEqualToString:@"com.apple.control-center.displaymodule"]) return NO;
    if ([lower containsString:@"mediaremote.controlcenter"]) return NO;
    if ([lower isEqualToString:@"com.apple.control-center.connectivitymodule"]) return NO;
    if ([lower containsString:@"connectivitymodule"]) return NO;
    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (!base) base = PACKnownBaseSize(mid);
    if (base.count < 2) return NO;
    NSUInteger w = base[0].unsignedIntegerValue;
    NSUInteger h = base[1].unsignedIntegerValue;
    if (w == 1 && h == 1) return YES;
    if (w == 2 && h == 2) return YES;
    return NO;
}

static BOOL PACSizeAllowed(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return NO;
    if (w > kPACCols || h > kPACRows) return NO;
    if (w > 4 || h > 4) return NO;
    if (w == 1 && h == 2) return NO;
    if (h == 1 && w == 3) return NO;
    if (h == 1 && w == 4) return NO;
    return YES;
}

static BOOL PACDragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h) {
    if (PACSizeAllowed(w, h)) return YES;
    if (PACModuleSupportsResizing(mid)) return NO;
    NSUInteger bw = 1, bh = 1;
    PACEffectiveSize(mid, &bw, &bh);
    return (w == bw && h == bh);
}

static CCUILayoutSize PACResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation) {
    NSInteger dc = (NSInteger)floor(translation.x / kPACStep + 0.5);
    NSInteger dr = (NSInteger)floor(translation.y / kPACStep + 0.5);
    NSInteger nw = MAX(1, MIN(4, (NSInteger)startW + dc));
    NSInteger nh = MAX(1, MIN(4, (NSInteger)startH + dr));
    return (CCUILayoutSize){(NSUInteger)nw, (NSUInteger)nh};
}

static NSString *PACBundleDisplayName(NSBundle *bundle) {
    if (!bundle) return nil;
    static NSSet<NSString *> *ignored = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ignored = [NSSet setWithArray:@[
            @"ControlCenter", @"ControlCenterSettings", @"ControlCenterUIKit",
            @"ControlCenterServices", @"ControlCenterUI", @"ControlCenterSettingsBundles",
            @"CCSupport", @"SpringBoard", @"Preferences", @"UIKit", @"Foundation"]];
    });
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!name.length) name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (!name.length) return nil;
    if ([ignored containsObject:name]) return nil;
    return name;
}

static NSString *PACPrettyNameForModule(UIViewController *m) {
    if (!m) return @"Control";

    NSString *mid = PACMid(m);
    NSString *lower = mid.lowercaseString;

    if ([lower containsString:@"screencapture"]) return @"Screen Recording";
    if ([lower containsString:@"control-center.displaymodule"] ||
        [lower isEqualToString:@"displaymodule"]) return @"Brightness";
    if ([lower containsString:@"controlcenter.audio"]) return @"Volume";
    if ([lower containsString:@"accessibility"]) return @"Accessibility Shortcuts";

    id contentModule = nil;
    @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
    for (NSString *key in @[@"displayName", @"title"]) {
        @try {
            id v = [contentModule valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v;
        } @catch (__unused NSException *e) {}
    }

    id prov = PACSettingsProvider();
    if (prov) {
        id meta = nil;
        SEL metaSel = NSSelectorFromString(@"moduleMetadataForModuleIdentifier:");
        if ([prov respondsToSelector:metaSel]) {
            meta = ((id (*)(id, SEL, id))objc_msgSend)(prov, metaSel, mid);
        }
        if (!meta) {
            @try {
                NSDictionary *all = [prov valueForKey:@"moduleMetadata"];
                if ([all isKindOfClass:NSDictionary.class]) meta = all[mid];
            } @catch (__unused NSException *e) {}
        }
        for (NSString *key in @[@"displayName", @"name", @"title", @"localizedName"]) {
            @try {
                id v = [meta valueForKey:key];
                if ([v isKindOfClass:NSString.class] && [v length]) return v;
            } @catch (__unused NSException *e) {}
        }
        NSURL *bundleURL = nil;
        NSString *bundlePath = nil;
        @try { id v = [meta valueForKey:@"bundleURL"];
            if ([v isKindOfClass:NSURL.class]) bundleURL = v; } @catch (__unused NSException *e) {}
        @try { id v = [meta valueForKey:@"bundlePath"];
            if ([v isKindOfClass:NSString.class]) bundlePath = v; } @catch (__unused NSException *e) {}
        NSBundle *bundle = bundleURL ? [NSBundle bundleWithURL:bundleURL]
                      : bundlePath ? [NSBundle bundleWithPath:bundlePath] : nil;
        NSString *metaBundleName = PACBundleDisplayName(bundle);
        if (metaBundleName.length) return metaBundleName;
    }

    if (contentModule) {
        NSString *classBundleName = PACBundleDisplayName([NSBundle bundleForClass:[contentModule class]]);
        if (classBundleName.length) return classBundleName;
    }

    NSString *label = m.view.accessibilityLabel;
    if (label.length) return label;
    UIView *pres = objc_getAssociatedObject(m.view, kPACPresKey);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (pres && v == pres) continue;
        if (v.accessibilityLabel.length) { label = v.accessibilityLabel; break; }
        [queue addObjectsFromArray:v.subviews];
    }
    if (label.length) return label;

    if (!mid.length) return @"Control";
    NSString *last = [mid componentsSeparatedByString:@"."].lastObject;
    if ([last hasSuffix:@"Module"] && last.length > 6) last = [last substringToIndex:last.length - 6];
    if (!last.length) return @"Control";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < last.length; i++) {
        unichar c = [last characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
            [result appendString:@" "];
        }
        [result appendFormat:@"%C", c];
    }
    return result.length ? result : @"Control";
}

static BOOL PACRectsOverlap(PACRect a, PACRect b) {
    return (a.c < b.c + b.w && b.c < a.c + a.w &&
            a.r < b.r + b.h && b.r < a.r + a.h);
}

static BOOL PACFindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow) {
    if (w == 0 || h == 0 || w > kPACCols || h > kPACRows) return NO;
    NSInteger maxC = (NSInteger)kPACCols - (NSInteger)w;
    NSInteger maxR = MIN((NSInteger)maxRow, (NSInteger)kPACRows - (NSInteger)h);
    if (maxC < 0 || maxR < 0) return NO;

    BOOL found = NO;
    NSInteger bestScore = NSIntegerMax;
    NSUInteger bestCol = 0, bestRow = 0;

    for (NSInteger r = 0; r <= maxR; r++) {
        for (NSInteger c = 0; c <= maxC; c++) {
            PACRect t = {(NSUInteger)c, (NSUInteger)r, w, h};
            BOOL ok = YES;
            for (NSValue *v in occupied.allValues) {
                PACRect o = {};
                [v getValue:&o];
                if (PACRectsOverlap(t, o)) { ok = NO; break; }
            }
            if (!ok) continue;
            NSInteger dx = c - (NSInteger)preferCol;
            NSInteger dy = r - (NSInteger)preferRow;
            NSInteger score = labs((long)dx) + labs((long)dy);
            if (score < bestScore ||
                (score == bestScore && (r < (NSInteger)bestRow ||
                 (r == (NSInteger)bestRow && c < (NSInteger)bestCol)))) {
                bestScore = score;
                bestCol = (NSUInteger)c;
                bestRow = (NSUInteger)r;
                found = YES;
            }
        }
    }
    if (found) { *outCol = bestCol; *outRow = bestRow; }
    return found;
}

static id PACSettingsProvider(void) {
    Class c = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL s = NSSelectorFromString(@"sharedProvider");
    return (c && [c respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(c, s) : nil;
}

static NSArray<NSString *> *PACProviderOrderedIdentifiers(void) {
    id prov = PACSettingsProvider();
    SEL sel = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
    if (!prov || ![prov respondsToSelector:sel]) return nil;
    id list = ((id (*)(id, SEL))objc_msgSend)(prov, sel);
    return [list isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)list : nil;
}

static UIView *PACModuleButtonView(UIView *moduleView) {
    if (!moduleView) return moduleView;
    if (kClsCCUIButtonModuleView && [moduleView isKindOfClass:kClsCCUIButtonModuleView]) return moduleView;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:moduleView.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        if (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]) return v;
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return moduleView;
}

static NSArray<UIView *> *PACCompactGlyphHosts(UIView *view) {
    if (!view) return @[];
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    for (NSString *key in @[@"_glyphImageView", @"glyphImageView", @"_glyphPackageView", @"glyphPackageView"]) {
        @try {
            id cand = [view valueForKey:key];
            if ([cand isKindOfClass:UIView.class] && ![hosts containsObject:cand]) [hosts addObject:cand];
        } @catch (__unused NSException *e) {}
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:view.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL hit = kClsCCUICAPackageView && [v isKindOfClass:kClsCCUICAPackageView];
        if (!hit) {
            NSString *cls = NSStringFromClass(v.class);
            hit = [cls isEqualToString:@"CCUICAPackageView"] || [cls containsString:@"CAPackage"];
        }
        if (!hit && [v isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)v;
            CGFloat mn = MIN(CGRectGetWidth(v.bounds), CGRectGetHeight(v.bounds));
            hit = iv.image != nil && mn >= 16.0 && !v.hidden && v.alpha > 0.01;
        }
        if (hit && ![hosts containsObject:v]) [hosts addObject:v];
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return hosts;
}

static BOOL PACIsGeometryKeyPath(NSString *keyPath) {
    return [keyPath hasPrefix:@"position"] ||
           [keyPath hasPrefix:@"bounds"] ||
           [keyPath hasPrefix:@"transform"] ||
           [keyPath hasPrefix:@"anchorPoint"];
}

static BOOL PACViewIsPinnedGlyph(UIView *view) {
    BOOL glyphSeen = NO;
    UIView *a = view;
    for (NSUInteger i = 0; a && i < 8; i++, a = a.superview) {
        if (objc_getAssociatedObject(a, kPACIconPinKey)) return glyphSeen;
        NSString *cls = NSStringFromClass(a.class);
        if ([a isKindOfClass:UIImageView.class] || [cls containsString:@"CAPackage"]) glyphSeen = YES;
    }
    return NO;
}

static BOOL PACShouldBlockGlyphAnimation(CALayer *layer, CAAnimation *anim) {
    if (![anim isKindOfClass:CAPropertyAnimation.class]) return NO;
    if (!PACIsGeometryKeyPath(((CAPropertyAnimation *)anim).keyPath)) return NO;
    CALayer *l = layer;
    for (NSUInteger i = 0; l && i < 8; i++, l = l.superlayer) {
        id d = l.delegate;
        if ([d isKindOfClass:UIView.class]) return PACViewIsPinnedGlyph((UIView *)d);
    }
    return NO;
}

static void PACLayoutModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = PACModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = PACCompactGlyphHosts(buttonView);
    CGPoint targetInButton = CGPointMake(kPACCell * 0.5, kPACCell * 0.5);
    objc_setAssociatedObject(buttonView, kPACIconPinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *glyph in glyphs) {
        UIView *host = glyph.superview;
        if (!host) continue;
        CGPoint target = [buttonView convertPoint:targetInButton toView:host];

        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            for (NSString *k in [glyph.layer.animationKeys copy]) {
                CAAnimation *a = [glyph.layer animationForKey:k];
                if ([a isKindOfClass:CAPropertyAnimation.class] &&
                    PACIsGeometryKeyPath(((CAPropertyAnimation *)a).keyPath)) {
                    [glyph.layer removeAnimationForKey:k];
                }
            }
            glyph.layer.transform = CATransform3DIdentity;
            glyph.center = target;
            [CATransaction commit];
        }];
    }
}

static void PACRestoreModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = PACModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = PACCompactGlyphHosts(buttonView);
    for (UIView *glyph in glyphs) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [glyph.layer removeAnimationForKey:@"pac.glide"];
        glyph.transform = CGAffineTransformIdentity;
        [CATransaction commit];
    }
}

static CGFloat PACRadiusForSize(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return 22.0;

    CGFloat widthPt  = (CGFloat)w * kPACCell + ((CGFloat)w - 1.0) * kPACgap;
    CGFloat heightPt = (CGFloat)h * kPACCell + ((CGFloat)h - 1.0) * kPACgap;
    if (widthPt <= 0.0 || heightPt <= 0.0) return 22.0;

    return calculatedRadius(CGRectMake(0.0, 0.0, widthPt, heightPt), 22.0);
}

static void PACRememberLayerState(UIView *v, NSMapTable<UIView *, NSDictionary *> *table) {
    if (!v || [table objectForKey:v]) return;
    [table setObject:@{ @"r":     @(v.layer.cornerRadius),
                        @"curve": v.layer.cornerCurve ?: kCACornerCurveCircular,
                        @"mask":  @(v.layer.masksToBounds) }
              forKey:v];
}

static BOOL PACModuleIsExpanded(UIViewController *m) {
    if (gCCAModuleExpanded) return YES;
    SEL sel = NSSelectorFromString(@"isExpanded");
    if ([m respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(m, sel)) return YES;
    UIView *root = m.view;
    if (!root) return NO;
    CGSize ms = root.bounds.size;

    NSString *mid = PACMid(m);
    if (mid.length && ms.width > 1.0 && ms.height > 1.0) {
        NSUInteger w = 1, h = 1;
        PACPresentationSize(mid, &w, &h);
        CGFloat ew = (CGFloat)w * kPACCell + ((CGFloat)w - 1.0) * kPACgap;
        CGFloat eh = (CGFloat)h * kPACCell + ((CGFloat)h - 1.0) * kPACgap;
        if (ms.width > ew * 1.35 + 8.0 || ms.height > eh * 1.35 + 8.0) return YES;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 80) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        NSString *cls = NSStringFromClass(v.class);
        if (([cls containsString:@"CCUIContentModuleContentContainer"] || [cls containsString:@"SliderView"]) &&
            (CGRectGetWidth(v.bounds) > ms.width + 14.0 || CGRectGetHeight(v.bounds) > ms.height + 14.0)) {
            return YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void PACSetRadius(CALayer *layer, CGFloat radius, BOOL animate) {
    CGFloat from = radius;
    if (animate) {
        CALayer *pl = layer.presentationLayer;
        from = pl ? pl.cornerRadius : layer.cornerRadius;
    }
    layer.cornerRadius = radius;
    layer.cornerCurve = kCACornerCurveContinuous;
    layer.masksToBounds = YES;
    CABasicAnimation *running = (CABasicAnimation *)[layer animationForKey:@"pac.radius"];
    BOOL sameGoal = running && [running.toValue isKindOfClass:NSNumber.class] &&
                    fabs([running.toValue doubleValue] - radius) < 0.01;
    if (animate && !sameGoal && fabs(from - radius) > 0.5) {
        PACAnimSpec sp = PACResizeSpec();
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        a.fromValue = @(from);
        a.toValue = @(radius);
        a.duration = sp.duration;
        a.timingFunction = PACResizeTiming(sp);
        [layer addAnimation:a forKey:@"pac.radius"];
    }
}

static void PACRunMaybeWithoutAnimation(void (^block)(void)) {
    if (CACurrentMediaTime() < gPACRotationQuietUntil) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            block();
            [CATransaction commit];
        }];
    } else {
        block();
    }
}

static void PACApplyRadiusToModule(UIViewController *m) {
    if (!m || !m.view) return;
    if (PACIsLandscape()) return;
    objc_setAssociatedObject(m.view, kPACLandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *mid = PACMid(m);
    if (!mid.length) return;

    if (PACModuleIsExpanded(m)) {
        if (objc_getAssociatedObject(m.view, kPACLastRadiusKey)) PACRestoreModuleRadius(m);
        return;
    }

    NSUInteger w = 1, h = 1;
    PACEffectiveSize(mid, &w, &h);
    CGFloat radius = PACRadiusForSize(w, h);

    CGSize moduleSize = m.view.bounds.size;
    if (moduleSize.width < 1.0 || moduleSize.height < 1.0) return;

    NSValue *last = objc_getAssociatedObject(m.view, kPACLastRadiusKey);
    BOOL animateRadius = last != nil && PACAnimationsAllowed();
    BOOL resizeSettling = gPACPendingResizeID != nil ||
                          (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 1.4;
    if (last && !resizeSettling) {
        NSMapTable<UIView *, NSDictionary *> *styled = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
        for (UIView *v in styled.keyEnumerator.allObjects) {
            if (!v.window || !v.layer.masksToBounds) continue;
            BOOL sameSizeAsModule = fabs(CGRectGetWidth(v.bounds) - moduleSize.width) < 8.0 &&
                                    fabs(CGRectGetHeight(v.bounds) - moduleSize.height) < 8.0;
            if (sameSizeAsModule && fabs(v.layer.cornerRadius - radius) > 0.5) {
                last = nil;
                break;
            }
        }
    }
    if (last && !resizeSettling) {
        CGSize ls = last.CGSizeValue;
        if (fabs(ls.width  - moduleSize.width)  < 0.5 &&
            fabs(ls.height - moduleSize.height) < 0.5 &&
            fabs(m.view.layer.cornerRadius - radius) < 0.5) {
            return;
        }
    }
    objc_setAssociatedObject(m.view, kPACLastRadiusKey,
                             [NSValue valueWithCGSize:moduleSize],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
    if (!orig) {
        orig = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(m.view, kPACOrigRadiiKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    PACRunMaybeWithoutAnimation(^{
        PACRememberLayerState(m.view, orig);
        PACSetRadius(m.view.layer, radius, animateRadius);

        UIView *buttonView = PACModuleButtonView(m.view);
        if (buttonView) {
            PACRememberLayerState(buttonView, orig);
            PACSetRadius(buttonView.layer, radius, animateRadius);
        }

        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
        while (queue.count) {
            UIView *v = queue.lastObject;
            [queue removeLastObject];
            BOOL isPillName = (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]);
            if (!isPillName) {
                NSString *cls = NSStringFromClass(v.class);
                isPillName = [cls containsString:@"CCUIButtonModuleView"] ||
                             [cls containsString:@"CCUIContentModuleContentContainer"];
            }
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL fills = (fabs(vw - moduleSize.width)  < 8.0) &&
                         (fabs(vh - moduleSize.height) < 8.0);
            if (isPillName || fills) {
                PACRememberLayerState(v, orig);
                PACSetRadius(v.layer, radius, animateRadius);
            }
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    });
}

static void PACRestoreModuleRadius(UIViewController *m) {
    if (!m || !m.view) return;
    objc_setAssociatedObject(m.view, kPACLastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
    if (!orig) return;

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (UIView *v in orig.keyEnumerator.allObjects) {
            NSDictionary *st = [orig objectForKey:v];
            if (!st) continue;
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL smallSquare = vw > 1.0 && vh > 1.0 && fabs(vw - vh) < 1.5 && MIN(vw, vh) <= 76.0;
            if (smallSquare) {
                v.layer.cornerRadius = MIN(vw, vh) * 0.5;
                v.layer.cornerCurve  = kCACornerCurveContinuous;
            } else {
                v.layer.cornerRadius = [st[@"r"] doubleValue];
                v.layer.cornerCurve  = st[@"curve"] ?: kCACornerCurveCircular;
            }
            v.layer.masksToBounds = [st[@"mask"] boolValue];
        }
        [CATransaction commit];
    }];
}

static void PACTearDownModule(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *view = m.view;
    CGSize sz = view.bounds.size;
    NSValue *done = objc_getAssociatedObject(view, kPACLandscapeCleanKey);
    if (done && fabs(done.CGSizeValue.width  - sz.width)  < 0.5 &&
                fabs(done.CGSizeValue.height - sz.height) < 0.5) return;
    objc_setAssociatedObject(view, kPACLandscapeCleanKey, [NSValue valueWithCGSize:sz],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        UIView *pres = objc_getAssociatedObject(view, kPACPresKey);
        [pres removeFromSuperview];
        objc_setAssociatedObject(view, kPACPresKey,     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kPACLastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        PACStripChrome(m);
        PACRestoreModuleIcon(m);
        PACRestoreModuleRadius(m);

        [PACModuleButtonView(view) setNeedsLayout];

        [CATransaction commit];
    }];
}

static void PACTearDownAllModules(UIViewController *ov) {
    if (!ov) return;
    for (UIViewController *m in ModuleControllers(ov)) PACTearDownModule(m);
}

static BOOL PACWasResizedFromOneByOne(NSString *mid) {
    if (!mid.length) return NO;

    NSUInteger curW = 1, curH = 1;
    PACPresentationSize(mid, &curW, &curH);
    if (curW == 1 && curH == 1) return NO;

    NSArray<NSNumber *> *known = PACKnownBaseSize(mid);
    if (known.count >= 2) {
        return (known[0].integerValue == 1 && known[1].integerValue == 1);
    }

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey);
    if ([resized containsObject:mid]) return YES;

    if (gEditSizes[mid]) return YES;

    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (base.count >= 2) {
        return (base[0].integerValue == 1 && base[1].integerValue == 1);
    }
    return NO;
}

static UIViewPropertyAnimator *PACBezierAnimator(NSTimeInterval duration,
                                                 CGFloat c1x, CGFloat c1y,
                                                 CGFloat c2x, CGFloat c2y) {
    UICubicTimingParameters *timing =
        [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(c1x, c1y)
                                                controlPoint2:CGPointMake(c2x, c2y)];
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:duration
                                                                timingParameters:timing];
    a.interruptible = YES;
    a.userInteractionEnabled = YES;
    return a;
}

static UIView *PACMakeBorder(void) {
    UIView *v = [UIView new];
    v.userInteractionEnabled = NO;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = NO;
    
    v.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:0.35].CGColor;
    
    v.layer.borderWidth = kPACBorderWidth;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.08;
    v.layer.shadowRadius = 3.0;
    v.layer.shadowOffset = CGSizeZero;

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.85;
    pulse.toValue = @1.0;
    pulse.duration = 1.6;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:pulse forKey:@"PACEditPulse"];
    return v;
}

static UIButton *PACMakeRemoveButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACRemoveTag;
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    b.frame = CGRectMake(0, 0, 30, 30);
    b.layer.cornerRadius = 15.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = NO;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.14;
    b.layer.shadowRadius = 4.0;
    b.layer.shadowOffset = CGSizeMake(0, 1);

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg]];
    icon.tintColor = [UIColor colorWithWhite:0.10 alpha:0.85];
    icon.contentMode = UIViewContentModeCenter;
    icon.userInteractionEnabled = NO;
    icon.frame = b.bounds;
    icon.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b addSubview:icon];

    objc_setAssociatedObject(b, kPACMidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *PACMakeResizeButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACResizeTag;
    b.backgroundColor = UIColor.clearColor;
    b.frame = CGRectMake(0, 0, 42, 42);

    UIBezierPath *cornerPath = [UIBezierPath bezierPath];
    [cornerPath moveToPoint:CGPointMake(20.29, 40.01)];
    [cornerPath addCurveToPoint:CGPointMake(40.01, 20.29)
                  controlPoint1:CGPointMake(31.20, 40.01)
                  controlPoint2:CGPointMake(40.01, 31.20)];

    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    material.frame = b.bounds;
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled = NO;
    CAShapeLayer *materialMask = [CAShapeLayer layer];
    materialMask.path = cornerPath.CGPath;
    materialMask.fillColor = UIColor.clearColor.CGColor;
    materialMask.strokeColor = UIColor.blackColor.CGColor;
    materialMask.lineWidth = 12.0;
    materialMask.lineCap = kCALineCapRound;
    materialMask.lineJoin = kCALineJoinRound;
    material.layer.mask = materialMask;
    [b addSubview:material];

    CAShapeLayer *pill = [CAShapeLayer layer];
    pill.path = cornerPath.CGPath;
    pill.fillColor = UIColor.clearColor.CGColor;
    pill.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.82].CGColor;
    pill.lineWidth = 12.5;
    pill.lineCap = kCALineCapRound;
    pill.lineJoin = kCALineJoinRound;
    [b.layer addSublayer:pill];

    objc_setAssociatedObject(b, kPACMidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *PACMakeResetButton(void) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACResetTag;
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.90];
    b.layer.cornerRadius = 20.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = YES;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:cfg]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    icon.tag = 9001;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Reset Layout";
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.userInteractionEnabled = NO;
    label.tag = 9002;

    CGSize textSize = [label sizeThatFits:CGSizeMake(300, 20)];
    CGFloat iconSide = 18.0;
    CGFloat gap = 7.0;
    CGFloat padX = 16.0;
    CGFloat height = 40.0;
    CGFloat width = padX + iconSide + gap + textSize.width + padX;

    b.bounds = CGRectMake(0, 0, width, height);
    icon.frame = CGRectMake(padX, (height - iconSide) * 0.5, iconSide, iconSide);
    label.frame = CGRectMake(padX + iconSide + gap, 0, textSize.width, height);
    [b addSubview:icon];
    [b addSubview:label];
    return b;
}

static void PACAnimateChromeEntry(UIView *chrome) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.82, 0.82);
    UIViewPropertyAnimator *anim = PACBezierAnimator(0.45, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
    }];
    [anim startAnimation];
}

static void PACAnimateChromeEntryDelayed(UIView *chrome, NSTimeInterval delay) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.4, 0.4);
    chrome.alpha = 0.0;
    UIViewPropertyAnimator *anim = PACBezierAnimator(0.42, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
        chrome.alpha = 1.0;
    }];
    [anim startAnimationAfterDelay:delay];
}

@interface PACEditShield : UIView
@end

@implementation PACEditShield
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    return self;
}
@end

@interface PACLiveGlassProxyView : UIView
@end

@implementation PACLiveGlassProxyView
+ (Class)layerClass {
    return kClsCABackdropLayer ?: [CALayer class];
}
@end

static UIImage *PACSnapshotContentOnly(UIView *src, BOOL liquidassActive) {
    CGSize sz = src.bounds.size;
    if (sz.width < 1 || sz.height < 1) return nil;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:sz];

    if (!liquidassActive) {
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                     afterScreenUpdates:NO];
        }];
    }

    NSMutableArray<UIView *> *hidden = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:src.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL isMaterial = (kClsCABackdropLayer && [v.layer isKindOfClass:kClsCABackdropLayer]);
        if (!isMaterial) {
            NSString *cls = NSStringFromClass(v.class);
            isMaterial = [cls containsString:@"MTMaterial"] ||
                         [cls containsString:@"MaterialView"] ||
                         [cls containsString:@"Backdrop"] ||
                         [v isKindOfClass:UIVisualEffectView.class];
        }
        if (isMaterial) {
            if (!v.hidden && v.alpha > 0.01) {
                v.hidden = YES;
                [hidden addObject:v];
            }
        } else {
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    }

    UIColor *savedBg = src.backgroundColor;
    src.backgroundColor = UIColor.clearColor;

    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                 afterScreenUpdates:YES];
    }];

    for (UIView *v in hidden) v.hidden = NO;
    src.backgroundColor = savedBg;
    return result;
}

static void PACBringChromeToFront(UIViewController *ov) {
    if (!ov || !ov.view) return;
    UIView *shield = [ov.view viewWithTag:kPACShieldTag];
    if (shield) [ov.view bringSubviewToFront:shield];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
        UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
        if (rm) [ov.view bringSubviewToFront:rm];
        if (rz) [ov.view bringSubviewToFront:rz];
        UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
        if (pr) [ov.view bringSubviewToFront:pr];
    }
    UIView *rp = [ov.view viewWithTag:kPACResetTag];
    if (rp) [ov.view bringSubviewToFront:rp];
}

static UIView *PACModuleMoverView(UIViewController *m, UIViewController *col) {
    UIView *v = m.view;
    if (!v) return nil;
    UIView *stop = col.view;
    if (!stop) return v;
    UIView *cur = v;
    while (cur.superview && cur.superview != stop) cur = cur.superview;
    return cur.superview == stop ? cur : v;
}

static NSDictionary<NSString *, NSValue *> *PACCaptureModuleFrames(UIViewController *ov, NSString *excludeMid) {
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length || [mid isEqualToString:excludeMid]) continue;
        CGRect f = PACVisibleFrame(m, ov);
        if (CGRectIsEmpty(f)) continue;
        frames[mid] = [NSValue valueWithCGRect:f];
    }
    return frames;
}

static BOOL PACSlideModules(UIViewController *ov, NSDictionary<NSString *, NSValue *> *oldFrames) {
    if (!ov || !oldFrames.count || !PACAnimationsAllowed()) return NO;
    UIViewController *col = ModuleCollection(ov);
    PACAnimSpec sp = PACResizeSpec();
    BOOL started = NO;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        NSValue *oldValue = mid.length ? oldFrames[mid] : nil;
        if (!oldValue) continue;
        CGRect oldF = oldValue.CGRectValue;
        CGRect newF = PACVisibleFrame(m, ov);
        if (CGRectIsEmpty(newF)) continue;
        CGFloat dx = oldF.origin.x - newF.origin.x;
        CGFloat dy = oldF.origin.y - newF.origin.y;
        if (hypot(dx, dy) < 0.5) continue;

        UIView *mover = PACModuleMoverView(m, col);
        if (!mover) continue;
        if ([mover.layer animationForKey:@"position"]) continue;

        CABasicAnimation *running = (CABasicAnimation *)[mover.layer animationForKey:@"pac.slide"];
        if (running && [running.fromValue isKindOfClass:NSValue.class]) {
            CGPoint rf = [running.fromValue CGPointValue];
            if (hypot(rf.x - dx, rf.y - dy) < 0.5) continue;
        }

        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position"];
        slide.additive = YES;
        slide.fromValue = [NSValue valueWithCGPoint:CGPointMake(dx, dy)];
        slide.toValue = [NSValue valueWithCGPoint:CGPointZero];
        slide.duration = sp.duration;
        slide.timingFunction = PACResizeTiming(sp);
        [mover.layer addAnimation:slide forKey:@"pac.slide"];
        started = YES;
    }
    return started;
}

static void PACAnimateChromeRefreshExcluding(UIViewController *ov, NSString *excludeMid) {
    if (!ov || !ov.view || !gEditModeActive) return;
    PACAnimSpec sp = PACResizeSpec();
    UIViewPropertyAnimator *anim = PACBezierAnimator(sp.duration, sp.c1x, sp.c1y, sp.c2x, sp.c2y);
    [anim addAnimations:^{
        for (UIViewController *m in ModuleControllers(ov)) {
            if (excludeMid.length && [PACMid(m) isEqualToString:excludeMid]) continue;
            PACApplyChrome(m, ov);
        }
    }];
    [anim startAnimation];
    PACBringChromeToFront(ov);
}

static void PACAnimateChromeRefresh(UIViewController *ov) {
    PACAnimateChromeRefreshExcluding(ov, nil);
}

static void PACAdjustStatusBar(UIViewController *ov) {
    if (!ov) return;
    PACC *pacc = [PACC shared];
    if ([pacc respondsToSelector:@selector(adjustStatusBarForOverlay:)]) {
        [pacc adjustStatusBarForOverlay:ov];
    }
}

static void PACSettleEditLayoutEx(UIViewController *ov, BOOL refreshChrome) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEditModeActive) return;
        if (refreshChrome) PACAnimateChromeRefresh(ov);
        PACAdjustStatusBar(ov);
    });
    static const double delays[] = { 0.30, 0.65 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            PACAdjustStatusBar(ov);
        });
    }
}

static void PACSettleEditLayout(UIViewController *ov) {
    PACSettleEditLayoutEx(ov, YES);
}

static void PACForceExitEdit(UIViewController *ov) {
    gEditModeActive = NO;
    gPACEditEpoch++;
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (!ov || !ov.view) return;
    for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);
    [[ov.view viewWithTag:kPACShieldTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACResetTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACHintTag] removeFromSuperview];
    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kPACDisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    ind.alpha = 1.0;
}

@interface PACEditProxy : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)bgHold:(UILongPressGestureRecognizer *)g;
- (void)shieldPan:(UIGestureRecognizer *)g;
- (void)shieldTap:(UITapGestureRecognizer *)g;
- (void)resizePan:(UIPanGestureRecognizer *)g;
- (void)removeTap:(UIButton *)b;
- (void)resetTap:(UIButton *)b;
- (void)exitEditOn:(UIViewController *)ov;
- (void)compactGridAfterRemoval:(UIViewController *)ov;
- (void)relayout:(UIViewController *)ov;
- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov;
- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov;
@end

@implementation PACEditProxy
+ (instancetype)shared {
    static PACEditProxy *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (!PACEditAllowed()) return NO;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return NO;
    if (g.view != ov.view) return YES;
    if ([g isKindOfClass:UILongPressGestureRecognizer.class]) {
        UIView *v = touch.view;
        while (v) {
            for (UIViewController *m in ModuleControllers(ov)) {
                if (m.view == v) return NO;
            }
            if (v == ov.view) break;
            v = v.superview;
        }
    }
    return YES;
}

- (void)bgHold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!PACEditAllowed()) return;
    PACRefreshGridConstants();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (gEditModeActive) {
    if ([ov.view viewWithTag:kPACShieldTag].superview) return;
    PACForceExitEdit(ov);
    return;
    }

    CGPoint lp = [g locationInView:ov.view];
    if (PACModuleAtPoint(lp, ov)) return;

    gEditModeActive = YES;
    gPACEditEpoch++;
    gEditModeEnteredAt = CACurrentMediaTime();
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    for (UIViewController *m in ModuleControllers(ov)) {
        PACEnsureBaseSize(m, ov);
        PACApplyRadiusToModule(m);
    }

    PACEditShield *shield = (PACEditShield *)[ov.view viewWithTag:kPACShieldTag];
    if (!shield) {
        shield = [[PACEditShield alloc] initWithFrame:ov.view.bounds];
        shield.tag = kPACShieldTag;
        shield.backgroundColor = UIColor.clearColor;
        shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        shield.userInteractionEnabled = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;

        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        hold.minimumPressDuration = 0.22;
        hold.allowableMovement = 12.0;
        hold.cancelsTouchesInView = YES;

        [pan requireGestureRecognizerToFail:hold];

        [shield addGestureRecognizer:pan];
        [shield addGestureRecognizer:hold];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shieldTap:)];
        tap.cancelsTouchesInView = NO;
        [shield addGestureRecognizer:tap];

        [ov.view addSubview:shield];
    } else if (shield.superview != ov.view) {
        [shield removeFromSuperview];
        [ov.view addSubview:shield];
    }
    shield.hidden = NO;
    shield.frame = ov.view.bounds;

    NSMutableArray<UIGestureRecognizer *> *disabled = [NSMutableArray array];
    UIView *walk = ov.view.superview;
    while (walk) {
        for (UIGestureRecognizer *gr in walk.gestureRecognizers) {
            if (!gr.enabled) continue;
            if ([gr isKindOfClass:UIPanGestureRecognizer.class] ||
                [gr isKindOfClass:UIPinchGestureRecognizer.class] ||
                [gr isKindOfClass:UISwipeGestureRecognizer.class]) {
                gr.enabled = NO;
                [disabled addObject:gr];
            }
        }
        walk = walk.superview;
    }
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, disabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (UIViewController *m in ModuleControllers(ov)) PACApplyChrome(m, ov);

    UIButton *reset = (UIButton *)[ov.view viewWithTag:kPACResetTag];
    if (!reset) {
        reset = PACMakeResetButton();
        [reset addTarget:self action:@selector(resetTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:reset];
    }
    CGFloat safeTop = ov.view.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = 20.0;
    reset.center = CGPointMake(CGRectGetMidX(ov.view.bounds), safeTop + 32.0);
    reset.alpha = 0.0;
    reset.transform = CGAffineTransformMakeTranslation(0, -8);
    UIViewPropertyAnimator *resetAnim = PACBezierAnimator(0.32, 0.32, 0.72, 0.0, 1.0);
    [resetAnim addAnimations:^{
        reset.alpha = 1.0;
        reset.transform = CGAffineTransformIdentity;
    }];
    [resetAnim startAnimationAfterDelay:0.05];
    [ov.view bringSubviewToFront:reset];

    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 0.0; }];
}

- (void)shieldTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    CGPoint pt = [g locationInView:ov.view];
    if (PACModuleAtPoint(pt, ov)) return;
    [self exitEditOn:ov];
}

- (void)exitEditOn:(UIViewController *)ov {
    if (!gEditModeActive) return;
    gEditModeActive = NO;
    gPACEditEpoch++;
    NSUInteger epochAtExit = gPACEditEpoch;
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    NSMutableArray<UIView *> *chromeViews = [NSMutableArray array];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIView *v = m.view;
        if (!v) continue;
        UIView *b = objc_getAssociatedObject(v, kPACBorderKey);
        UIButton *rm = objc_getAssociatedObject(v, kPACRemoveKey);
        UIButton *rz = objc_getAssociatedObject(v, kPACResizeKey);
        if (b) [chromeViews addObject:b];
        if (rm) [chromeViews addObject:rm];
        if (rz) [chromeViews addObject:rz];
        objc_setAssociatedObject(PACModuleButtonView(v), kPACIconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACRemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (chromeViews.count) {
        UIViewPropertyAnimator *exitAnim = PACBezierAnimator(0.24, 0.4, 0.0, 0.2, 1.0);
        [exitAnim addAnimations:^{
            for (UIView *v in chromeViews) {
                v.alpha = 0.0;
                v.transform = CGAffineTransformMakeScale(0.85, 0.85);
            }
        }];
        [exitAnim addCompletion:^(__unused UIViewAnimatingPosition pos) {
            if (epochAtExit != gPACEditEpoch) return;
            for (UIView *v in chromeViews) [v removeFromSuperview];
        }];
        [exitAnim startAnimation];
    }

    UIView *shield = [ov.view viewWithTag:kPACShieldTag];
    [shield removeFromSuperview];

    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kPACDisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *reset = [ov.view viewWithTag:kPACResetTag];
    reset.tag = 0;
    UIViewPropertyAnimator *resetOut = PACBezierAnimator(0.2, 0.4, 0.0, 0.2, 1.0);
    [resetOut addAnimations:^{
        reset.alpha = 0.0;
        reset.transform = CGAffineTransformMakeTranslation(0, -8);
    }];
    [resetOut addCompletion:^(__unused UIViewAnimatingPosition pos) {
        if (epochAtExit != gPACEditEpoch) return;
        [reset removeFromSuperview];
    }];
    [resetOut startAnimation];

    [[ov.view viewWithTag:kPACHintTag] removeFromSuperview];

    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 1.0; }];
}

- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov {
    PACEnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;

    if (!PACDragSizeAllowedForModule(mid, w, h)) return NO;

    NSArray<NSNumber *> *oldO = PACGetOrigin(mid);
    if (oldO.count < 2) return NO;
    NSUInteger oldCol = oldO[0].unsignedIntegerValue;
    NSUInteger oldAbs = oldO[1].unsignedIntegerValue;
    NSUInteger oldRow = oldAbs % kPACRows;

    NSUInteger oldW = 1, oldH = 1;
    PACEffectiveSize(mid, &oldW, &oldH);
    if (oldCol == col && oldRow == row && (oldAbs / kPACRows) == page &&
        oldW == w && oldH == h) {
        return NO;
    }

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = PACMid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(oid);
        if (o.count < 2) continue;
        NSUInteger oc = o[0].unsignedIntegerValue;
        NSUInteger oa = o[1].unsignedIntegerValue;
        if (oa / kPACRows != page) continue;
        NSUInteger orow = oa % kPACRows;
        NSUInteger ow = 1, oh = 1;
        PACEffectiveSize(oid, &ow, &oh);
        PACRect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(PACRect)];
    }

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionaryWithDictionary:snapshot];
    PACRect targetRect = {col, row, w, h};
    placed[mid] = [NSValue value:&targetRect withObjCType:@encode(PACRect)];

    NSMutableArray<NSString *> *colliders = [NSMutableArray array];
    for (NSString *oid in snapshot) {
        PACRect other = {};
        [snapshot[oid] getValue:&other];
        if (PACRectsOverlap(targetRect, other)) [colliders addObject:oid];
    }

    [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        PACRect ra = {}, rb = {};
        [snapshot[a] getValue:&ra];
        [snapshot[b] getValue:&rb];
        if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
        if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];

    NSUInteger visibleCap = PACVisibleRowCap(ov);

    for (NSString *oid in colliders) {
        PACRect orig = {};
        [snapshot[oid] getValue:&orig];
        [placed removeObjectForKey:oid];
        NSUInteger maxTopRow = (visibleCap + 1 >= orig.h) ? (visibleCap - orig.h + 1) : 0;
        NSUInteger newC = 0, newR = 0;
        if (!PACFindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, maxTopRow, &newC, &newR)) {
            return NO;
        }
        PACRect np = {newC, newR, orig.w, orig.h};
        placed[oid] = [NSValue value:&np withObjCType:@encode(PACRect)];
    }

    for (NSString *oid in placed) {
        PACRect r = {};
        [placed[oid] getValue:&r];
        PACSetOrigin(oid, @[@(r.c), @(page * kPACRows + r.r)]);
    }
    return YES;
}

- (void)shieldPan:(UIGestureRecognizer *)g {
    if (!PACEditAllowed()) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    PACRefreshGridConstants();

    if (g.state == UIGestureRecognizerStateBegan) {
        CGPoint pt = [g locationInView:ov.view];
        UIViewController *src = PACModuleAtPoint(pt, ov);
        if (!src) return;
        NSString *mid = PACMid(src);
        if (!mid.length) return;

        CGRect vis = PACVisibleFrame(src, ov);
        CGPoint grab = CGPointMake(pt.x - CGRectGetMinX(vis), pt.y - CGRectGetMinY(vis));

        UIView *shadow = [[UIView alloc] initWithFrame:vis];
        shadow.tag = kPACProxyShadowTag;
        shadow.userInteractionEnabled = NO;
        shadow.backgroundColor = UIColor.clearColor;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        shadow.layer.shadowOpacity = 0.35;
        shadow.layer.shadowRadius = 16.0;
        shadow.layer.shadowOffset = CGSizeMake(0, 8);
        shadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadow.bounds
                                                            cornerRadius:src.view.layer.cornerRadius].CGPath;
        [ov.view addSubview:shadow];

        BOOL liquidassActive = PACCLIQIsActive();
        CGFloat proxyRadius = src.view.layer.cornerRadius;

        UIView *proxy;
        if (liquidassActive) {
            proxy = [[PACLiveGlassProxyView alloc] initWithFrame:shadow.bounds];
        } else {
            proxy = [[UIView alloc] initWithFrame:shadow.bounds];
        }
        proxy.tag = kPACProxyTag;
        proxy.userInteractionEnabled = NO;
        proxy.layer.cornerRadius = proxyRadius;
        proxy.layer.cornerCurve = kCACornerCurveContinuous;
        proxy.layer.masksToBounds = YES;

        if (liquidassActive) {
            proxy.backgroundColor = UIColor.clearColor;
            if (kClsCABackdropLayer && [proxy.layer isKindOfClass:kClsCABackdropLayer]) {
                [proxy.layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
                [proxy.layer setValue:@YES forKey:@"windowServerAware"];
                [proxy.layer setValue:@"dylv.liquidglass.sharedGroup" forKey:@"groupName"];
                [proxy.layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
                [proxy.layer setValue:@(0.5) forKey:@"scale"];
                id glassFilter = PACCLIQBuildGlassFilter();
                if (glassFilter) proxy.layer.filters = @[glassFilter];
            }
        } else {
            proxy.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        }

        UIImage *snapImage = PACSnapshotContentOnly(src.view, liquidassActive);
        if (snapImage) {
            UIImageView *snap = [[UIImageView alloc] initWithImage:snapImage];
            snap.frame = proxy.bounds;
            snap.contentMode = UIViewContentModeScaleToFill;
            snap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [proxy addSubview:snap];
        }
        [shadow addSubview:proxy];

        UIView *pres = objc_getAssociatedObject(src.view, kPACPresKey);
        [UIView animateWithDuration:0.12
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            src.view.alpha = 0.0;
            pres.alpha = 0.0;
        } completion:nil];
        for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);

        NSDictionary *origLayout = [gEditOrigins copy] ?: @{};
        objc_setAssociatedObject(g, kPACOrigLayoutKey, origLayout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kPACLastCellKey, @[@(NSIntegerMax), @(NSIntegerMax)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kPACDragSrcKey,   src,    OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kPACDragProxyKey, shadow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACDragGrabKey,  [NSValue valueWithCGPoint:grab], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        UIViewController *src = objc_getAssociatedObject(g, kPACDragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kPACDragProxyKey);
        NSValue *gv = objc_getAssociatedObject(g, kPACDragGrabKey);
        if (!src || !shadow || !gv) return;
        CGPoint grab = gv.CGPointValue;
        CGPoint pt = [g locationInView:ov.view];
        NSString *mid = PACMid(src);
        NSUInteger w = 1, h = 1;
        PACEffectiveSize(mid, &w, &h);
        CGPoint base = PACGridBase(ov);

        CGRect f = shadow.frame;
        f.origin = CGPointMake(pt.x - grab.x, pt.y - grab.y);
        shadow.frame = f;

        NSInteger col = (NSInteger)lround((CGRectGetMinX(f) - base.x) / kPACStep);
        NSInteger row = (NSInteger)lround((CGRectGetMinY(f) - base.y) / kPACStep);
        col = MAX(0, MIN((NSInteger)kPACCols - (NSInteger)w, col));
        NSUInteger cap = PACVisibleRowCap(ov);
        NSInteger maxRow = MAX(0, (NSInteger)cap - (NSInteger)h + 1);
        row = MAX(0, MIN(maxRow, row));

        NSArray<NSNumber *> *last = objc_getAssociatedObject(g, kPACLastCellKey);
        if (!last ||
            [last[0] integerValue] != col ||
            [last[1] integerValue] != row) {
            objc_setAssociatedObject(g, kPACLastCellKey, @[@(col), @(row)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if ([self computeArrangementForMid:mid
                                          col:(NSUInteger)col
                                          row:(NSUInteger)row
                                            w:w h:h
                                      overlay:ov]) {
                [self relayout:ov];
            }
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        UIViewController *src = objc_getAssociatedObject(g, kPACDragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kPACDragProxyKey);
        __block UIViewController *heldSrc = src;

        if (g.state != UIGestureRecognizerStateEnded) {
            NSDictionary *origLayout = objc_getAssociatedObject(g, kPACOrigLayoutKey);
            if (origLayout) {
                PACEnsureStore();
                [gEditOrigins removeAllObjects];
                [gEditOrigins addEntriesFromDictionary:origLayout];
                PACSaveStore();
                [self relayout:ov];
            }
        } else {
            PACSaveStore();
        }

        if (shadow) {
            [shadow removeFromSuperview];
        }
        NSUInteger epochAtDragEnd = gPACEditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtDragEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            UIViewController *releaseSrc = heldSrc;
            if (releaseSrc) {
                UIView *pres = objc_getAssociatedObject(releaseSrc.view, kPACPresKey);
                [UIView animateWithDuration:0.18
                                      delay:0.0
                                    options:UIViewAnimationOptionCurveEaseOut |
                                            UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                    releaseSrc.view.alpha = 1.0;
                    pres.alpha = 1.0;
                } completion:nil];
            }
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });

        objc_setAssociatedObject(g, kPACDragSrcKey,   nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kPACDragProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACDragGrabKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACLastCellKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACOrigLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)compactGridAfterRemoval:(UIViewController *)ov {
    PACEnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;
    NSUInteger cap  = PACVisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger abs = o[1].unsignedIntegerValue;
        if (abs / kPACRows != page) continue;

        NSUInteger w = 1, h = 1;
        PACEffectiveSize(mid, &w, &h);
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger r = abs % kPACRows;

        PACRect rect = {c, r, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(PACRect)];
        [entries addObject:@{@"mid":mid, @"c":@(c), @"r":@(r), @"w":@(w), @"h":@(h)}];
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ar = [a[@"r"] integerValue], br = [b[@"r"] integerValue];
        if (ar != br) return ar < br ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ac = [a[@"c"] integerValue], bc = [b[@"c"] integerValue];
        return ac < bc ? NSOrderedAscending : (ac > bc ? NSOrderedDescending : NSOrderedSame);
    }];

    for (NSDictionary *e in entries) {
        NSString *mid = e[@"mid"];
        NSUInteger w = [e[@"w"] unsignedIntegerValue];
        NSUInteger h = [e[@"h"] unsignedIntegerValue];
        NSInteger oc = [e[@"c"] integerValue];
        NSInteger orr = [e[@"r"] integerValue];

        [placed removeObjectForKey:mid];

        NSInteger maxC = (NSInteger)kPACCols - (NSInteger)w;
        NSInteger maxR = (NSInteger)MIN(cap, kPACRows - 1) - (NSInteger)h + 1;
        NSInteger bestC = oc, bestR = orr;
        NSInteger bestScore = NSIntegerMax;
        BOOL found = NO;

        for (NSInteger r = 0; r <= maxR; r++) {
            for (NSInteger c = 0; c <= maxC; c++) {
                if (r > orr) continue;
                if (r == orr && c >= oc) continue;

                PACRect t = {(NSUInteger)c, (NSUInteger)r, w, h};
                BOOL ok = YES;
                for (NSValue *v in placed.allValues) {
                    PACRect o = {};
                    [v getValue:&o];
                    if (PACRectsOverlap(t, o)) { ok = NO; break; }
                }
                if (!ok) continue;

                NSInteger score = r * (NSInteger)kPACCols + c;
                if (score < bestScore) {
                    bestScore = score;
                    bestC = c;
                    bestR = r;
                    found = YES;
                }
            }
        }

        PACRect rect = {(NSUInteger)bestC, (NSUInteger)bestR, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(PACRect)];
        if (found) {
            PACSetOrigin(mid, @[@(bestC), @(page * kPACRows + bestR)]);
        }
    }
    PACSaveStore();
}

- (void)relayout:(UIViewController *)ov {
    UIViewController *col = ModuleCollection(ov);
    if (!col) return;

    SEL providerSel = NSSelectorFromString(@"_activePositionProvider");
    id provider = [col respondsToSelector:providerSel]
        ? ((id (*)(id, SEL))objc_msgSend)(col, providerSel) : nil;
    SEL regenSel = NSSelectorFromString(@"regenerateRectsWithOrderedIdentifiers:orderedSizes:");
    if (provider && [provider respondsToSelector:regenSel]) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        NSMutableArray<NSValue *> *sizes = [NSMutableArray array];
        for (UIViewController *m in ModuleControllers(ov)) {
            NSString *mid = PACMid(m);
            if (!mid.length) continue;
            NSUInteger w = 1, h = 1;
            PACEffectiveSize(mid, &w, &h);
            CCUILayoutSize sz = {w, h};
            [ids addObject:mid];
            [sizes addObject:[NSValue value:&sz withObjCType:@encode(CCUILayoutSize)]];
        }
        if (ids.count) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(provider, regenSel, ids, sizes);
        }
    }

    for (UIViewController *m in ModuleControllers(ov)) [m.view setNeedsLayout];
    [col.view setNeedsLayout];

    void (^fixups)(void) = ^{
        for (UIViewController *m in ModuleControllers(ov)) {
            UIView *superview = m.view.superview;
            if (!superview || superview == col.view) continue;
            NSString *sn = NSStringFromClass(superview.class);
            if (![sn containsString:@"ContentModuleContainer"] &&
                ![sn containsString:@"ModuleWrapper"]) continue;
            CGRect target = superview.bounds;
            if (!CGRectEqualToRect(m.view.bounds, target)) {
                m.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                m.view.frame = target;
            }
        }
        for (UIViewController *m in ModuleControllers(ov)) PACApplyRadiusToModule(m);
    };

    if (gExperimentalPagingEnabled) {
        UIViewPropertyAnimator *relayout = PACBezierAnimator(0.58, 0.32, 0.72, 0.0, 1.0);
        [relayout addAnimations:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        [relayout addCompletion:^(UIViewAnimatingPosition finalPosition) {
            if (finalPosition != UIViewAnimatingPositionEnd) return;
            fixups();
        }];
        [relayout startAnimation];
    } else {
        [UIView performWithoutAnimation:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        fixups();
    }
}

- (void)resizePan:(UIPanGestureRecognizer *)g {
    if (!PACEditAllowed()) return;
    UIButton *btn = (UIButton *)g.view;
    NSString *mid = objc_getAssociatedObject(btn, kPACMidKey);
    if (!mid.length) return;
    PACRefreshGridConstants();
    gPACPendingResizeLastTouch = CACurrentMediaTime();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        PACEnsureStore();
        NSUInteger sw = 1, sh = 1;
        PACEffectiveSize(mid, &sw, &sh);
        objc_setAssociatedObject(g, kPACStartSzKey, @[@(sw), @(sh)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gPACPendingResizeID = [mid copy];
        gPACPendingResizeSize = (CCUILayoutSize){sw, sh};
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        NSArray<NSNumber *> *s = objc_getAssociatedObject(g, kPACStartSzKey);
        if (s.count < 2) return;
        NSUInteger sw = s[0].unsignedIntegerValue, sh = s[1].unsignedIntegerValue;
        CGPoint t = [g translationInView:ov.view];
        CCUILayoutSize next = PACResizeCandidate(mid, sw, sh, t);
        if (!PACSizeAllowed(next.width, next.height)) {
            next = gPACPendingResizeSize;
        }
        if (next.width != gPACPendingResizeSize.width ||
            next.height != gPACPendingResizeSize.height) {
            gPACPendingResizeSize = next;

            NSArray<NSNumber *> *cur = PACGetOrigin(mid);
            if (cur.count >= 2) {
                NSUInteger cCol = cur[0].unsignedIntegerValue;
                NSUInteger cAbs = cur[1].unsignedIntegerValue;
                NSUInteger cRow = cAbs % kPACRows;
                [self computeArrangementForMid:mid
                                           col:cCol
                                           row:cRow
                                             w:next.width
                                             h:next.height
                                       overlay:ov];
            }

            [self relayout:ov];
            PACSettleEditLayout(ov);
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        CCUILayoutSize p = gPACPendingResizeSize;
        gPACPendingResizeID = nil;
        gPACPendingResizeSize = (CCUILayoutSize){0, 0};
        if (g.state == UIGestureRecognizerStateEnded && p.width && p.height &&
            PACSizeAllowed(p.width, p.height)) {
            [self commitResize:mid w:p.width h:p.height overlay:ov];
        }
        objc_setAssociatedObject(g, kPACStartSzKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self relayout:ov];
        PACSettleEditLayout(ov);
        NSUInteger epochAtResizeEnd = gPACEditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.62 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACRefreshPresentation(m, ov);
            }
        });
    }
}

- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov {
    PACEnsureStore();
    if (!PACSizeAllowed(w, h)) return;

    NSArray<NSNumber *> *o = PACGetOrigin(mid);
    if (o.count < 2) return;
    NSUInteger col = o[0].unsignedIntegerValue;
    NSUInteger absRow = o[1].unsignedIntegerValue;
    NSUInteger page = absRow / kPACRows;
    NSUInteger row = absRow % kPACRows;
    if (col + w > kPACCols) w = kPACCols - col;
    if (row + h > kPACRows) h = kPACRows - row;
    if (!PACSizeAllowed(w, h)) return;

    NSUInteger capR = PACVisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = PACMid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *oo = PACGetOrigin(oid);
        if (oo.count < 2) continue;
        NSUInteger oc = oo[0].unsignedIntegerValue;
        NSUInteger oa = oo[1].unsignedIntegerValue;
        if (oa / kPACRows != page) continue;
        NSUInteger orow = oa % kPACRows;
        NSUInteger ow = 1, oh = 1;
        PACEffectiveSize(oid, &ow, &oh);
        PACRect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(PACRect)];
    }

    BOOL resolved = NO;

    if (row + h <= capR + 1) {
        PACRect targetRect = {col, row, w, h};

        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];

        NSMutableArray<NSString *> *colliders = [NSMutableArray array];
        for (NSString *oid in snapshot) {
            PACRect other = {};
            [snapshot[oid] getValue:&other];
            if (PACRectsOverlap(targetRect, other)) [colliders addObject:oid];
        }
        for (NSString *oid in colliders) [placed removeObjectForKey:oid];
        placed[mid] = [NSValue value:&targetRect withObjCType:@encode(PACRect)];

        [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            PACRect ra = {}, rb = {};
            [snapshot[a] getValue:&ra];
            [snapshot[b] getValue:&rb];
            if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
            if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];

        BOOL allFit = YES;
        for (NSString *oid in colliders) {
            PACRect orig = {};
            [snapshot[oid] getValue:&orig];
            NSUInteger cMaxRow = (capR + 1 >= orig.h) ? (capR - orig.h + 1) : 0;
            NSUInteger nc = 0, nr = 0;
            if (!PACFindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, cMaxRow, &nc, &nr)) {
                allFit = NO;
                break;
            }
            PACRect np = {nc, nr, orig.w, orig.h};
            placed[oid] = [NSValue value:&np withObjCType:@encode(PACRect)];
        }

        if (allFit) {
            resolved = YES;
            gEditSizes[mid] = @[@(w), @(h)];
            for (NSString *oid in placed) {
                PACRect r = {};
                [placed[oid] getValue:&r];
                PACSetOrigin(oid, @[@(r.c), @(page * kPACRows + r.r)]);
            }
        }
    }

    if (!resolved) {
        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];
        NSUInteger cMaxRow = (capR + 1 >= h) ? (capR - h + 1) : 0;
        NSUInteger newCol = 0, newRow = 0;
        if (!PACFindFreeCellFor(placed, col, row, w, h, cMaxRow, &newCol, &newRow)) return;
        gEditSizes[mid]   = @[@(w), @(h)];
        PACSetOrigin(mid, @[@(newCol), @(page * kPACRows + newRow)]);
    }

    PACInvalidateOtherOrientationOriginForModule(mid);
    PACSaveStore();

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey);
    if (!resized) {
        resized = [NSMutableSet set];
        objc_setAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey, resized, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [resized addObject:mid];

    for (UIViewController *m in ModuleControllers(ov)) {
        if (![PACMid(m) isEqualToString:mid]) continue;
        id contentModule = nil;
        @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
        id ctx = nil;
        @try { ctx = [contentModule valueForKey:@"contentModuleContext"]; } @catch (__unused NSException *e) {}
        if ([ctx respondsToSelector:NSSelectorFromString(@"requestLayoutSizeUpdate")]) {
            ((void (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"requestLayoutSizeUpdate"));
        }
        break;
    }
}

- (void)removeTap:(UIButton *)b {
    if (!gEditModeActive) return;
    NSString *mid = objc_getAssociatedObject(b, kPACMidKey);
    if (!mid.length) return;
    if (gHapticsEnabled) Haptic();

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    UIViewController *victim = nil;
    for (UIViewController *m in ModuleControllers(ov)) {
        if ([PACMid(m) isEqualToString:mid]) { victim = m; break; }
    }
    UIView   *victimBorder = victim ? objc_getAssociatedObject(victim.view, kPACBorderKey) : nil;
    UIButton *victimRM     = victim ? objc_getAssociatedObject(victim.view, kPACRemoveKey) : nil;
    UIButton *victimRZ     = victim ? objc_getAssociatedObject(victim.view, kPACResizeKey) : nil;

    if (victim) {
        [UIView animateWithDuration:0.24
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            CGAffineTransform s = CGAffineTransformMakeScale(0.35, 0.35);
            victim.view.transform   = s;  victim.view.alpha   = 0.0;
            victimBorder.transform  = s;  victimBorder.alpha  = 0.0;
            victimRM.transform      = s;  victimRM.alpha      = 0.0;
            victimRZ.transform      = s;  victimRZ.alpha      = 0.0;
        } completion:nil];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id prov = PACSettingsProvider();
        SEL get = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
        SEL set = NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:");

        NSUInteger visibleCount = 0;
        for (UIViewController *m in ModuleControllers(ov)) {
            if (PACMid(m).length) visibleCount++;
        }
        NSArray *enabledNow = [prov respondsToSelector:get] ? ((id (*)(id, SEL))objc_msgSend)(prov, get) : nil;
        NSUInteger enabledCount = [enabledNow isKindOfClass:NSArray.class] ? enabledNow.count : 0;
        BOOL slide = PACIsNonNotchedDevice() && (visibleCount == 12 || enabledCount == 12);
        NSDictionary<NSString *, NSValue *> *oldFrames = slide ? PACCaptureModuleFrames(ov, mid) : nil;

        if ([prov respondsToSelector:get] && [prov respondsToSelector:set]) {
            NSArray *ids = ((id (*)(id, SEL))objc_msgSend)(prov, get);
            NSMutableArray *mut = [ids mutableCopy];
            [mut removeObject:mid];
            ((void (*)(id, SEL, id))objc_msgSend)(prov, set, mut);
        }

        PACEnsureStore();
        PACSetOrigin(mid, nil);
        [gEditSizes removeObjectForKey:mid];
        PACInvalidateOtherOrientationOriginForModule(mid);
        PACSaveStore();

        if (victim) PACStripChrome(victim);
        [victimBorder removeFromSuperview];
        [victimRM removeFromSuperview];
        [victimRZ removeFromSuperview];

        [self compactGridAfterRemoval:ov];
        [self relayout:ov];

        NSTimeInterval settleDelay = 0.45;
        if (slide) {
            PACSlideModules(ov, oldFrames);
            PACAnimateChromeRefreshExcluding(ov, mid);
            PACSettleEditLayoutEx(ov, NO);
            CFTimeInterval startedAt = CACurrentMediaTime();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!gEditModeActive) return;
                if (CACurrentMediaTime() - startedAt > 0.1) return;
                if (PACSlideModules(ov, oldFrames)) PACAnimateChromeRefreshExcluding(ov, mid);
            });
            settleDelay = MAX(settleDelay, PACResizeSpec().duration + 0.08);
        } else {
            PACSettleEditLayout(ov);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settleDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
        });
    });
}

- (void)resetTap:(UIButton *)b {
    if (!gEditModeActive) return;
    PACRefreshGridConstants();
    gPACEditEpoch++;
    NSUInteger epochAtReset = gPACEditEpoch;
    gEditModeEnteredAt = CACurrentMediaTime();
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    for (UIViewController *m in ModuleControllers(ov)) {
        PACEnsureBaseSize(m, ov);
    }

    NSArray<NSString *> *ordered = PACProviderOrderedIdentifiers();

    PACEnsureStore();
    NSString *prefix = PACIsLandscape() ? @"L|" : @"P|";
    for (NSString *key in [gEditOrigins.allKeys copy]) {
        if ([key hasPrefix:prefix]) [gEditOrigins removeObjectForKey:key];
    }
    [gEditSizes removeAllObjects];

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];

    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (ordered.count) [ids addObjectsFromArray:ordered];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        if (![ids containsObject:mid]) [ids addObject:mid];
    }

    NSUInteger perPage = kPACRows;
    for (NSString *mid in ids) {
        NSArray<NSNumber *> *base = gEditBaseSizes[mid];
        if (base.count < 2) base = PACKnownBaseSize(mid);
        if (base.count < 2) continue;
        NSUInteger w = base[0].unsignedIntegerValue;
        NSUInteger h = base[1].unsignedIntegerValue;
        if (w == 0 || h == 0 || w > kPACCols || h > kPACRows) continue;

        BOOL found = NO;
        for (NSUInteger page = 0; page < 4 && !found; page++) {
            NSUInteger maxR = kPACRows - h;
            NSUInteger maxC = kPACCols - w;
            for (NSUInteger r = 0; r <= maxR && !found; r++) {
                for (NSUInteger c = 0; c <= maxC; c++) {
                    PACRect t = {c, r, w, h};
                    BOOL ok = YES;
                    for (NSValue *v in placed.allValues) {
                        PACRect o = {};
                        [v getValue:&o];
                        if (PACRectsOverlap(t, o)) { ok = NO; break; }
                    }
                    if (!ok) continue;
                    PACRect copy = t;
                    placed[mid] = [NSValue value:&copy withObjCType:@encode(PACRect)];
                    PACSetOrigin(mid, @[@(c), @(page * perPage + r)]);
                    found = YES;
                    break;
                }
            }
        }
    }
    PACSaveStore();

    for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);
    UIView *hint = [ov.view viewWithTag:kPACHintTag];
    hint.hidden = YES;

    [UIView animateWithDuration:0.10 animations:^{
        b.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(__unused BOOL f) {
        [UIView animateWithDuration:0.18 delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ b.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }];

    [self relayout:ov];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (epochAtReset != gPACEditEpoch) return;
        if (!gEditModeActive) return;
        for (UIViewController *m in ModuleControllers(ov)) {
            PACApplyRadiusToModule(m);
            PACApplyChrome(m, ov);
            PACRefreshPresentation(m, ov);
        }
        UIView *shield = [ov.view viewWithTag:kPACShieldTag];
        if (shield) [ov.view bringSubviewToFront:shield];
        for (UIViewController *m in ModuleControllers(ov)) {
            UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
            UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
            if (rm) [ov.view bringSubviewToFront:rm];
            if (rz) [ov.view bringSubviewToFront:rz];
            UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
            if (pr) [ov.view bringSubviewToFront:pr];
        }
        [ov.view bringSubviewToFront:b];
    });
}

@end

static void PACRefreshPresentationImpl(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    NSString *mid = PACMid(m);
    if (!mid.length) return;

    PACEnsureStore();
    PACEnsureBaseSize(m, ov);

    if (PACModuleIsExpanded(m)) return;

    NSUInteger curW = 1, curH = 1;
    PACPresentationSize(mid, &curW, &curH);

    UIView *buttonView = PACModuleButtonView(m.view);
    if (!buttonView) return;

    BOOL animate = PACAnimationsAllowed();
    NSUInteger radiusW = 1, radiusH = 1;
    PACEffectiveSize(mid, &radiusW, &radiusH);
    CGFloat radius = PACRadiusForSize(radiusW, radiusH);
    PACSetRadius(buttonView.layer, radius, animate && objc_getAssociatedObject(m.view, kPACLastRadiusKey) != nil);

    BOOL isResizedFromOneByOne = PACWasResizedFromOneByOne(mid);

    UIView *pres = objc_getAssociatedObject(m.view, kPACPresKey);
    if (!isResizedFromOneByOne) {
        if (pres) {
            objc_setAssociatedObject(m.view, kPACPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (animate && pres.superview) {
                [UIView animateWithDuration:0.15
                                      delay:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{ pres.alpha = 0.0; }
                                 completion:^(__unused BOOL finished) { [pres removeFromSuperview]; }];
            } else {
                [pres removeFromSuperview];
            }
        }
        objc_setAssociatedObject(m.view, kPACLastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PACRestoreModuleIcon(m);
        return;
    }

    PACLayoutModuleIcon(m);

    NSString *newText = PACPrettyNameForModule(m);
    CGSize bvSize = buttonView.bounds.size;
    NSUInteger sig = 1469598103934665603ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.width))  * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.height)) * 1099511628211ULL;
    sig = (sig ^ curW) * 1099511628211ULL;
    sig = (sig ^ curH) * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)newText.hash) * 1099511628211ULL;

    NSNumber *lastSig = objc_getAssociatedObject(m.view, kPACLastPresKey);
    if (lastSig && lastSig.unsignedIntegerValue == sig &&
        pres && pres.superview == buttonView) {
        return;
    }
    objc_setAssociatedObject(m.view, kPACLastPresKey, @(sig), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *titleLabel = nil;
    BOOL created = (!pres || pres.superview != buttonView);
    if (created) {
        [pres removeFromSuperview];
        pres = [[UIView alloc] initWithFrame:buttonView.bounds];
        pres.userInteractionEnabled = NO;
        pres.backgroundColor = UIColor.clearColor;
        pres.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        pres.clipsToBounds = YES;
        pres.alpha = animate ? 0.0 : 1.0;

        titleLabel = [[UILabel alloc] init];
        titleLabel.tag = 9001;
        titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.numberOfLines = 2;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.textAlignment = NSTextAlignmentLeft;
        [pres addSubview:titleLabel];

        objc_setAssociatedObject(m.view, kPACPresKey, pres, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [buttonView addSubview:pres];
    } else {
        titleLabel = (UILabel *)[pres viewWithTag:9001];
    }

    if (created) {
        [UIView performWithoutAnimation:^{ pres.frame = buttonView.bounds; }];
    } else {
        pres.frame = buttonView.bounds;
    }
    pres.hidden = NO;

    titleLabel.text = newText;

    CGFloat W = CGRectGetWidth(pres.bounds);
    CGFloat H = CGRectGetHeight(pres.bounds);
    CGFloat lineHeight = 14.3333;
    CGFloat textW;
    CGFloat textX;
    CGFloat iconCenterY = H * 0.5;
    if (curW > 1 && curH == 1) {
        textX = kPACCell - 10.0;
        iconCenterY = H * 0.5;
        textW = MAX(0.0, W - textX - 12.0);
    } else {
        textX = curW > 1 ? 21.0 : 10.0;
        textW = MAX(0.0, W - textX - (curW > 1 ? 24.0 : 10.0));
    }
    CGSize measured = [titleLabel.text boundingRectWithSize:CGSizeMake(textW, lineHeight * 2.0)
                                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                 attributes:@{NSFontAttributeName: titleLabel.font}
                                                    context:nil].size;
    CGFloat titleH = measured.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;

    CGFloat top;
    if (curW > 1 && curH == 1) {
        top = iconCenterY - titleH * 0.5;
        if (top < 4.0) top = 4.0;
        if (top > H - titleH - 4.0) top = H - titleH - 4.0;
    } else {
        top = MAX(kPACCell + 7.0, H - 17.3333 - titleH);
    }
    CGRect labelFrame = CGRectMake(textX, top, textW, titleH);
    if (created) {
        [UIView performWithoutAnimation:^{ titleLabel.frame = labelFrame; }];
    } else {
        titleLabel.frame = labelFrame;
    }
    [buttonView bringSubviewToFront:pres];
    [pres bringSubviewToFront:titleLabel];

    if (created && animate) {
        [UIView animateWithDuration:0.22
                              delay:0.08
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{ pres.alpha = 1.0; }
                         completion:nil];
    }
}

static void PACRefreshPresentation(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    if (PACIsLandscape()) return;
    objc_setAssociatedObject(m.view, kPACLandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PACRunMaybeWithoutAnimation(^{ PACRefreshPresentationImpl(m, ov); });
}

static void PACApplyChrome(UIViewController *m, UIViewController *ov) {
    if (!gEditModeActive) return;
    if (PACIsLandscape()) return;
    UIView *view = m.view;
    if (!view) return;
    NSString *mid = PACMid(m);
    if (!mid.length) return;
    CGRect vis = PACVisibleFrame(m, ov);
    if (CGRectIsEmpty(vis)) return;

    PACApplyRadiusToModule(m);

    CGFloat radius = view.layer.cornerRadius;
    if (radius < 1.0) radius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;

    UIView *border = objc_getAssociatedObject(view, kPACBorderKey);
    BOOL borderIsNew = (border == nil);
    if (borderIsNew) {
        border = PACMakeBorder();
        objc_setAssociatedObject(view, kPACBorderKey, border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [ov.view addSubview:border];

    border.frame = CGRectInset(vis, -kPACBorderInset, -kPACBorderInset);
    CGFloat anchorRadius = radius;
    if (anchorRadius < 1.0) {
        anchorRadius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;
    }
    border.layer.cornerRadius = anchorRadius + kPACBorderInset;
    border.hidden = NO;
    if (borderIsNew) PACAnimateChromeEntry(border);

    UIButton *rm = objc_getAssociatedObject(view, kPACRemoveKey);
    BOOL rmIsNew = (rm == nil);
    if (rmIsNew) {
        rm = PACMakeRemoveButton(mid);
        [rm addTarget:[PACEditProxy shared] action:@selector(removeTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(view, kPACRemoveKey, rm, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [ov.view addSubview:rm];
    }
    CGFloat rmSize = 30.0;
    rm.frame = CGRectMake(vis.origin.x - 8.0, vis.origin.y - 8.0, rmSize, rmSize);
    rm.hidden = NO;
    if (rmIsNew) PACAnimateChromeEntryDelayed(rm, 0.04);

    BOOL supportsResize = PACModuleSupportsResizing(mid);
    objc_setAssociatedObject(PACModuleButtonView(view), kPACIconPinKey,
                             supportsResize ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *rz = objc_getAssociatedObject(view, kPACResizeKey);
    if (supportsResize) {
        BOOL rzIsNew = (rz == nil);
        if (rzIsNew) {
            rz = PACMakeResizeButton(mid);
            objc_setAssociatedObject(view, kPACResizeKey, rz, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIPanGestureRecognizer *rp = [[UIPanGestureRecognizer alloc] initWithTarget:[PACEditProxy shared] action:@selector(resizePan:)];
            rp.maximumNumberOfTouches = 1;
            rp.cancelsTouchesInView = YES;
            [rz addGestureRecognizer:rp];
            [ov.view addSubview:rz];
        }
        CGFloat rzSize = 42.0;
        CGFloat rzOverhang = 2.0;
        rz.frame = CGRectMake(CGRectGetMaxX(vis) - rzSize + rzOverhang,
                              CGRectGetMaxY(vis) - rzSize + rzOverhang,
                              rzSize, rzSize);
        rz.hidden = NO;
        if (rzIsNew) PACAnimateChromeEntryDelayed(rz, 0.04);
    } else if (rz) {
        [rz removeFromSuperview];
        objc_setAssociatedObject(view, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    PACRefreshPresentation(m, ov);
}

static void PACStripChrome(UIViewController *m) {
    UIView *view = m.view;
    if (!view) return;
    objc_setAssociatedObject(PACModuleButtonView(view), kPACIconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(view, kPACBorderKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kPACRemoveKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kPACResizeKey) removeFromSuperview];
    objc_setAssociatedObject(view, kPACBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kPACRemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PACInstallGestures(UIViewController *ov) {
    if (!ov.view) return;
    if (objc_getAssociatedObject(ov, kPACGestKey)) return;
    objc_setAssociatedObject(ov, kPACGestKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[PACEditProxy shared] action:@selector(bgHold:)];
    hold.minimumPressDuration = 0.55;
    hold.cancelsTouchesInView = NO;
    hold.delegate = [PACEditProxy shared];
    objc_setAssociatedObject(hold, kPACOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [ov.view addGestureRecognizer:hold];
}

%hook CCUIModuleCollectionViewController

- (CCUILayoutRect)layoutView:(id)layoutView layoutRectForSubview:(UIView *)subview {
    CCUILayoutRect r = %orig;
    if (!PACEditAllowed()) return r;
    PACRefreshGridConstants();

    NSDictionary *containers = nil;
    @try { containers = [(id)self valueForKey:@"moduleContainerViewByIdentifier"]; }
    @catch (__unused NSException *e) {}
    __block NSString *mid = nil;
    [containers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        UIView *cand = [value isKindOfClass:UIView.class] ? value
                    : ([value respondsToSelector:@selector(view)] ? [value view] : nil);
        if (cand == subview) { mid = key; *stop = YES; }
    }];
    if (!mid.length) return r;

    PACEnsureStore();

    PACMigrateMissingOrigins(OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController));

    if (!PACGetOrigin(mid) && !gEditOrigins[mid]) {
        PACSetOrigin(mid, @[@(r.origin.x), @(r.origin.y)]);
    }

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize s = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        r.size = s;
    }

    BOOL pendingFresh = gPACPendingResizeID &&
                        [mid isEqualToString:gPACPendingResizeID] &&
                        gPACPendingResizeSize.width &&
                        gPACPendingResizeSize.height &&
                        (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        r.size = gPACPendingResizeSize;
    }

    NSArray<NSNumber *> *o = PACGetOrigin(mid);
    if (!o) o = gEditOrigins[mid];
    if (o.count >= 2) {
        CCUILayoutPoint p = { o[0].unsignedIntegerValue, o[1].unsignedIntegerValue };
        r.origin = p;
    }
    return r;
}

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext:(id)context forOrientation:(NSInteger)orientation {
    CCUILayoutSize s = %orig;
    if (!PACEditAllowed()) return s;
    NSString *mid = nil;
    if ([context respondsToSelector:@selector(moduleIdentifier)]) {
        mid = ((id (*)(id, SEL))objc_msgSend)(context, @selector(moduleIdentifier));
    }
    if (!mid.length) return s;
    PACEnsureStore();

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize ns = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        s = ns;
    }

    BOOL pendingFresh = gPACPendingResizeID &&
                        [mid isEqualToString:gPACPendingResizeID] &&
                        gPACPendingResizeSize.width &&
                        gPACPendingResizeSize.height &&
                        (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        s = gPACPendingResizeSize;
    }
    return s;
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (gEditModeActive && PACShouldBlockGlyphAnimation((CALayer *)self, anim)) return;
    %orig;
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PACEditAllowed()) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        PACRefreshGridConstants();
        PACInstallGestures((UIViewController *)self);
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!gEditModeActive) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [[PACEditProxy shared] exitEditOn:(UIViewController *)self];
    }
}
%end

%hook CCUIContentModuleContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!PACEditAllowed()) {
        if (PACIsLandscape()) PACTearDownModule((UIViewController *)self);
        return;
    }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    UIViewController *module = (UIViewController *)self;

    PACApplyRadiusToModule(module);
    PACRefreshPresentation(module, ov);

    __weak UIViewController *wm = module;
    __weak UIViewController *wo = ov;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *m2 = wm, *o2 = wo;
        if (!m2 || !o2) return;
        PACApplyRadiusToModule(m2);
        PACRefreshPresentation(m2, o2);
    });
}

%end

%hook CCUIButtonModuleView

- (void)layoutSubviews {
    %orig;
    BOOL landscape = PACIsLandscape();
    if (!landscape && !PACEditAllowed()) return;
    UIResponder *r = (UIResponder *)(id)self;
    UIViewController *module = nil;
    while (r) {
        if ([r isKindOfClass:UIViewController.class] &&
            [NSStringFromClass(((UIViewController *)r).class) containsString:@"ContentModuleContainerViewController"]) {
            module = (UIViewController *)r;
            break;
        }
        r = r.nextResponder;
    }
    if (!module) return;
    if (landscape) { PACTearDownModule(module); return; }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    PACApplyRadiusToModule(module);
    PACRefreshPresentation(module, ov);

    __weak UIViewController *wm = module;
    __weak UIViewController *wo = ov;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *m2 = wm, *o2 = wo;
        if (!m2 || !o2) return;
        PACApplyRadiusToModule(m2);
        PACRefreshPresentation(m2, o2);
    });
}

%end

%hook CCUIModularControlCenterOverlayViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    gPACRotationQuietUntil = CACurrentMediaTime() + 1.0;
    if (size.width > size.height) {
        UIViewController *ov = (UIViewController *)self;
        if (gEditModeActive) [[PACEditProxy shared] exitEditOn:ov];
        PACTearDownAllModules(ov);
    }
    [coordinator animateAlongsideTransition:nil
                                 completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> ctx) {
        PACScheduleRotationRefresh();
    }];
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    if (state == 1) return;
    if (!gEditModeActive) return;
    if (CACurrentMediaTime() - gEditModeEnteredAt < 1.0) return;
    [[PACEditProxy shared] exitEditOn:(UIViewController *)self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PACIsLandscape()) {
        PACTearDownAllModules((UIViewController *)self);
        return;
    }
    if (!PACEditAllowed()) return;
    UIViewController *ov = (UIViewController *)self;
    if (!ov.view) return;

    PACRefreshGridConstants();

    for (NSInteger i = 0; i < 8; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(i * 0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *o2 = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
            if (!o2) return;
            if (!PACEditAllowed()) return;
            for (UIViewController *m in ModuleControllers(o2)) {
                PACApplyRadiusToModule(m);
                PACRefreshPresentation(m, o2);
            }
        });
    }
}

%end

static void PACPostRotationRefresh(void) {
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    if (PACIsLandscape()) {
        if (gEditModeActive) [[PACEditProxy shared] exitEditOn:ov];
        PACTearDownAllModules(ov);
        return;
    }
    if (!PACEditAllowed()) return;
    PACRefreshGridConstants();
    for (UIViewController *m in ModuleControllers(ov)) {
        if (!m.view) continue;
        objc_setAssociatedObject(m.view, kPACLastPresKey,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(m.view, kPACLastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PACApplyRadiusToModule(m);
        PACRefreshPresentation(m, ov);
    }
}

static void PACScheduleRotationRefresh(void) {
    gPACRotationQuietUntil = CACurrentMediaTime() + 1.0;
    static const double delays[] = { 0.0, 0.15, 0.45, 0.90 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ PACPostRotationRefresh(); });
    }
}

static void PACEditReload(__unused CFNotificationCenterRef c,
                          __unused void *o, __unused CFStringRef n,
                          __unused const void *obj,
                          __unused CFDictionaryRef u) {
    if (!gEditModeEnabled && gEditModeActive) {
        UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (ov) [[PACEditProxy shared] exitEditOn:ov];
    }
}

%ctor {
    @autoreleasepool {
        PACInitCachedClasses();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, PACEditReload,
                                        (__bridge CFStringRef)kReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            UIDeviceOrientation o = UIDevice.currentDevice.orientation;
            if (!UIDeviceOrientationIsPortrait(o) && !UIDeviceOrientationIsLandscape(o)) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (PACIsLandscape() && gEditModeActive) {
                    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
                    if (ov) [[PACEditProxy shared] exitEditOn:ov];
                }
                PACScheduleRotationRefresh();
            });
        }];
    }
}
