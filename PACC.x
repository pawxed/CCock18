#import "PACC.h"

const NSInteger PACCTagConnectivityCluster = 18005;
const NSInteger PACCTagMediaButtonMaterial = 18009;
const NSInteger kPageIndicatorTag = 181030;
const NSInteger kQuickAccessTag = 181000;
const NSInteger kMediaPlayerTag = 181040;
const NSInteger kPromoPageTag = 181050;

const void *PACCKeyCompactRadius = &PACCKeyCompactRadius;
const void *PACCKeyMediaMode = &PACCKeyMediaMode;
const void *PACCKeyMiniGlyphBaseSize = &PACCKeyMiniGlyphBaseSize;

static const CFStringRef kPrefsDomain = CFSTR("pawxed.ccock18.preferences");
NSString *const kReloadNotification = @"pawxed.ccock18/ReloadPrefs";

BOOL gEnabled = YES;
BOOL gQuickAccessButtonsEnabled = YES;
BOOL gPagingEnabled = YES;
BOOL gHapticsEnabled = YES;
BOOL gExperimentalPagingEnabled = YES;
BOOL gPageAnimating = NO;
BOOL gCCAModuleExpanded = NO;
BOOL gCircularModulesEnabled = NO;
BOOL gPromoPageEnabled = YES;
NSInteger gCurrentPage = 0;

static NSUInteger const kGridRows = 8;
static CGFloat const kGridCell = 67.0;
static CGFloat const kGridGap = 12.0;
#define kGridStep (kGridCell + kGridGap)
#define kPageSpan (kGridRows * kGridStep)

CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius) {
    CGFloat width  = visibleRect.size.width;
    CGFloat height = visibleRect.size.height;

    if (CGSizeEqualToSize(visibleRect.size, [UIScreen mainScreen].bounds.size) ||
        width <= 60 || height <= 60) {
        return radius;
    }

    if (gCircularModulesEnabled) {
        CGFloat minimum = MIN(width, height);
        CGFloat r       = minimum * 0.5;
        if (minimum >= 76.0) r = MIN(r, 38.0);
        return floor(r);
    }

    if (height >= 300 && height <= 400 && width >= 100 && width <= 200) {
        return radius;
    }
    if ((fabs(width - height) < 1.0 || width >= 250) && height <= 76) {
        return floor(MIN(width, height) / 2.0);
    }
    return 25;
}

static BOOL PrefBool(NSString *key, BOOL fallback) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, kPrefsDomain, &valid);
    return valid ? (BOOL)value : fallback;
}

void LoadPrefs(void) {
    CFPreferencesAppSynchronize(kPrefsDomain);
    gEnabled                     = PrefBool(@"Enabled", YES);
    gQuickAccessButtonsEnabled   = PrefBool(@"QuickAccessButtonsEnabled", YES);
    gPagingEnabled               = PrefBool(@"PagingEnabled", YES);
    gHapticsEnabled              = PrefBool(@"HapticsEnabled", YES);
    gExperimentalPagingEnabled   = PrefBool(@"ExperimentalPaging", NO);
    gEditModeEnabled             = PrefBool(@"EditModeEnabled", NO);
    gCircularModulesEnabled      = PrefBool(@"CircularModules", NO);
    gPromoPageEnabled            = PrefBool(@"PromoPageEnabled", YES);
    if (!gEditModeEnabled) gEditModeActive = NO;
}

void Haptic(void) {
    if (!gHapticsEnabled) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g prepare];
    [g impactOccurred];
}

CGFloat PageSpan(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    BOOL landscape = size.width > size.height;
    CGFloat screenH = size.height;

    NSUInteger gridRows = landscape ? 4 : 8;
    CGFloat step = 67.0 + 12.0;
    CGFloat pageSpan = (CGFloat)gridRows * step;

    CGFloat extra = screenH - pageSpan;
    NSUInteger spacerRows = extra > step * 0.35 ? (NSUInteger)ceil(extra / step) : 0;
    return (CGFloat)(gridRows + spacerRows) * step;
}

UIViewController *OverlayIn(UIViewController *root) {
    if (!root) return nil;
    NSString *name = NSStringFromClass(root.class);
    if ([name containsString:@"ControlCenterOverlayViewController"] ||
        [name isEqualToString:@"CCUIModularControlCenterOverlayViewController"]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = OverlayIn(child);
        if (found) return found;
    }
    if (root.presentedViewController) return OverlayIn(root.presentedViewController);
    return nil;
}

BOOL IsModuleController(UIViewController *controller) {
    return [NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"];
}

BOOL IsConnectivityController(UIViewController *controller) {
    return [NSStringFromClass(controller.class) isEqualToString:@"CCUIConnectivityModuleViewController"];
}

NSArray<UIViewController *> *ModuleControllers(UIViewController *root) {
    if (!root) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (candidate != root && IsModuleController(candidate)) [result addObject:candidate];
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return result;
}

UIViewController *ModuleCollection(UIViewController *overlay) {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:overlay];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) containsString:@"ModuleCollectionViewController"]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIViewController *ConnectivityChild(UIViewController *controller, NSString *className) {
    NSMutableArray *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:className]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIView *PACCViewIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

UIView *PACCModuleAncestor(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"CCUIContentModuleContainerView"]) return ancestor;
    }
    return nil;
}

CGFloat PACCModuleCornerRadius(CGSize size) {
    CGFloat minimum = MIN(size.width, size.height);
    if (minimum <= 0.0) return 0.0;

    if (gCircularModulesEnabled) {
        CGFloat r = minimum * 0.5;
        if (minimum >= 76.0) r = MIN(r, 38.0);
        return floor(r);
    }

    BOOL oneByOne = fabs(size.width - size.height) <= 3.0 && minimum <= 76.0;
    return oneByOne ? minimum * 0.5 : MIN(32.0, MAX(22.0, minimum * 0.5 - 6.0));
}

CGFloat PACCRadiusForModule(UIView *module) {
    if (!module) return 0.0;
    CGFloat width = CGRectGetWidth(module.bounds), height = CGRectGetHeight(module.bounds);
    NSNumber *cached = objc_getAssociatedObject(module, PACCKeyCompactRadius);
    if (width > 0.0 && height > 0.0 && width < 190.0 && height < 190.0) {
        CGFloat radius = PACCModuleCornerRadius(module.bounds.size);
        objc_setAssociatedObject(module, PACCKeyCompactRadius, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return radius;
    }
    return cached ? cached.doubleValue : PACCModuleCornerRadius(module.bounds.size);
}

UIView *PACCAncestor(UIView *view, NSString *className) {
    for (; view; view = view.superview) if ([NSStringFromClass(view.class) isEqualToString:className]) return view;
    return nil;
}

NSString *PACCMediaMode(UIView *view) {
    UIView *nowPlaying = PACCAncestor(view, @"MRUNowPlayingView");
    if (!nowPlaying || !PACCAncestor(nowPlaying, @"CCUIContentModuleContentContainerView")) return nil;
    @try {
        NSInteger layout = [[nowPlaying valueForKey:@"_layout"] integerValue];
        if (layout == 1 || layout == 2) return nil;
    } @catch (__unused NSException *exception) {}
    if (CGRectGetWidth(nowPlaying.bounds) >= 230.0) return nil;
    NSString *mode = objc_getAssociatedObject(nowPlaying, PACCKeyMediaMode);
    if (mode) return mode;
    return @"compact";
}

NSArray *PACCMediaMaterialFilters(UIView *view) {
    UIView *nowPlaying = PACCAncestor(view, @"MRUNowPlayingView");
    UIView *transport = PACCViewIvar(nowPlaying, "_transportControlsView");
    for (UIView *candidate in transport.subviews) {
        if (![candidate isKindOfClass:NSClassFromString(@"MRUTransportButton")] || candidate.alpha < 0.99) continue;
        BOOL hasPackage = NO;
        for (UIView *child in candidate.subviews) if ([NSStringFromClass(child.class) isEqualToString:@"MRUCAPackageView"] && !CGRectIsEmpty(child.bounds)) { hasPackage = YES; break; }
        if (!hasPackage) continue;
        for (CALayer *layer in candidate.layer.sublayers) {
            NSArray *filters = layer.filters;
            if (filters.count == 1 && [filters.description containsString:@"vibrantDark"]) return filters;
        }
    }
    return nil;
}

void PACCResizeMediaRoutingGlyph(UIView *button) {
    if (!PACCAncestor(button, @"MRUNowPlayingHeaderView") || !PACCMediaMode(button)) return;
    CGFloat side = MIN(CGRectGetWidth(button.bounds), CGRectGetHeight(button.bounds));
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:button.subviews];
    while (queue.count) {
        UIView *child = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([child isKindOfClass:UIImageView.class] && !child.hidden && ((UIImageView *)child).image) {
            UIImageView *glyph = (UIImageView *)child;
            CGSize imageSize = glyph.image.size;
            CGFloat scale = side * (26.0 / 54.0) / MAX(imageSize.width, imageSize.height);
            CGRect target = CGRectMake((side - imageSize.width * scale) * 0.5, (side - imageSize.height * scale) * 0.5, imageSize.width * scale, imageSize.height * scale);
            glyph.contentMode = UIViewContentModeScaleAspectFit;
            child.frame = [button convertRect:target toView:child.superview];
        }
        [queue addObjectsFromArray:child.subviews];
    }
}

void PACCConfigureMedia(UIView *view) {
    NSString *mode = PACCMediaMode(view);
    UIView *artwork = PACCViewIvar(view, "_artworkView"), *header = PACCViewIvar(view, "_headerView");
    UIView *time = PACCViewIvar(view, "_timeControlsView"), *transport = PACCViewIvar(view, "_transportControlsView"), *volume = PACCViewIvar(view, "_volumeControlsView");
    UIView *wrapper = PACCAncestor(view, @"MRUControlCenterView");
    if (!mode) {
        if (!objc_getAssociatedObject(view, PACCKeyMediaMode)) return;
        objc_setAssociatedObject(view, PACCKeyMediaMode, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        for (UIView *item in @[PACCViewIvar(wrapper, "_routingButton") ?: (id)NSNull.null, PACCViewIvar(wrapper, "_moreButton") ?: (id)NSNull.null, time ?: (id)NSNull.null, volume ?: (id)NSNull.null]) {
            if ((id)item != NSNull.null) { item.hidden = NO; item.alpha = 1.0; }
        }
        if (artwork) { artwork.backgroundColor = UIColor.clearColor; artwork.layer.cornerRadius = 0.0; artwork.layer.masksToBounds = NO; }
        return;
    }
    objc_setAssociatedObject(view, PACCKeyMediaMode, mode, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!header || !transport) return;
    CGFloat width = CGRectGetWidth(view.bounds);
    CGRect artworkFrame = CGRectMake(14, 14, 50, 50);
    UIView *module = PACCModuleAncestor(view);
    CGFloat artworkInset = MIN(CGRectGetMinX(artworkFrame), CGRectGetMinY(artworkFrame));
    CGFloat artworkRadius = MAX(0.0, PACCRadiusForModule(module) - artworkInset) * 0.75;
    [UIView performWithoutAnimation:^{
        view.clipsToBounds = YES;
        header.frame = view.bounds;
        for (UIView *item in @[PACCViewIvar(wrapper, "_routingButton") ?: (id)NSNull.null, PACCViewIvar(wrapper, "_moreButton") ?: (id)NSNull.null]) if ((id)item != NSNull.null) item.hidden = YES;
        if (artwork) { artwork.frame = artworkFrame; artwork.hidden = NO; artwork.alpha = 1.0; artwork.backgroundColor = UIColor.clearColor; artwork.layer.cornerRadius = artworkRadius; artwork.layer.cornerCurve = kCACornerCurveContinuous; artwork.layer.masksToBounds = YES; }
        transport.frame = CGRectMake(floor((width - 110.0) * 0.5), 102, 110, 44); transport.hidden = NO; transport.alpha = 1.0;
        if (time) { time.hidden = YES; time.alpha = 0; }
        if (volume) { volume.hidden = YES; volume.alpha = 0; }
    }];
}

UIViewController *PACCConnectivityChild(UIViewController *controller, NSString *className) {
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:controller.childViewControllers];
    while (queue.count) {
        UIViewController *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(candidate.class) isEqualToString:className]) return candidate;
        [queue addObjectsFromArray:candidate.childViewControllers];
    }
    return nil;
}

UIView *PACCModuleMaterial(void) {
    Class materialClass = NSClassFromString(@"MTMaterialView");
    SEL factory = NSSelectorFromString(@"materialViewWithRecipe:");
    if ([materialClass respondsToSelector:factory]) return ((id (*)(id, SEL, long long))objc_msgSend)(materialClass, factory, 4);
    return [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
}

NSArray *PACCConnectivityVibrantFilters(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUIRoundButton"]) {
            NSArray *filters = view.subviews.firstObject.layer.filters;
            if (filters.count) return filters;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

void PACCScaleMiniGlyphs(UIView *root, CGFloat scale) {
    if (!root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSMutableArray<UIView *> *packages = [NSMutableArray array];
    NSMutableArray<UIView *> *images = [NSMutableArray array];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUICAPackageView"]) [packages addObject:view];
        else if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image && !PACCAncestor(view, @"CCUICAPackageView")) [images addObject:view];
        [queue addObjectsFromArray:view.subviews];
    }
    for (UIView *view in packages) view.transform = CGAffineTransformMakeScale(scale, scale);
    for (UIView *view in images) {
        NSValue *stored = objc_getAssociatedObject(view, PACCKeyMiniGlyphBaseSize);
        CGSize base = stored ? stored.CGSizeValue : view.frame.size;
        if (!stored) objc_setAssociatedObject(view, PACCKeyMiniGlyphBaseSize, [NSValue valueWithCGSize:base], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGPoint center = view.center;
        view.transform = CGAffineTransformIdentity;
        view.bounds = CGRectMake(0.0, 0.0, base.width * scale, base.height * scale);
        view.center = center;
    }
}

UIImage *PACCBundledSymbol(NSString *name, UIColor *color, BOOL hierarchical) {
    static NSBundle *bundle, *privateBundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = @"/var/jb/Library/Application Support/CC18/CC18.bundle";
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) path = @"/Library/Application Support/CC18/CC18.bundle";
        bundle = [NSBundle bundleWithPath:path];
        privateBundle = [NSBundle bundleWithPath:[path stringByAppendingPathComponent:@"PrivateSymbols.bundle"]];
    });
    BOOL privateSymbol = [name isEqualToString:@"calculator.fill"] || [name isEqualToString:@"music"] || [name isEqualToString:@"network.connected.to.line.below.fill"];
    UIImage *image = [UIImage imageNamed:name inBundle:privateSymbol ? privateBundle : bundle compatibleWithTraitCollection:nil];
    if (!image) image = [UIImage systemImageNamed:name];
    if (hierarchical) image = [image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    if (!hierarchical) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return image;
}

void PACCConfigureConnectivity(UIViewController *controller) {
    UIView *root = controller.view;
    CGFloat side = MIN(CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds));
    UIView *cluster = [root viewWithTag:PACCTagConnectivityCluster];
    if (side <= 0.0 || CGRectGetWidth(root.bounds) >= 190.0 || CGRectGetHeight(root.bounds) >= 190.0) {
        cluster.hidden = YES;
        for (NSString *name in @[@"CCUIConnectivityAirplaneViewController", @"CCUIConnectivityCellularDataViewController", @"CCUIConnectivityWifiViewController", @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityAirDropViewController", @"CCUIConnectivityHotspotViewController"]) {
            UIView *view = PACCConnectivityChild(controller, name).view;
            view.hidden = NO;
            view.alpha = 1.0;
            view.userInteractionEnabled = YES;
            view.transform = CGAffineTransformIdentity;
            PACCScaleMiniGlyphs(view, 1.0);
        }
        return;
    }
    CGFloat inset = MAX(6.0, round(side * 0.103));
    CGFloat gap = MAX(4.0, round(side * 0.055));
    CGFloat cell = floor((side - inset * 2.0 - gap) * 0.5);
    CGFloat originX = round((CGRectGetWidth(root.bounds) - (cell * 2.0 + gap)) * 0.5);
    CGFloat originY = round((CGRectGetHeight(root.bounds) - (cell * 2.0 + gap)) * 0.5);
    CGRect topLeft = CGRectMake(originX, originY, cell, cell);
    CGRect topRight = CGRectMake(originX + cell + gap, originY, cell, cell);
    CGRect bottomLeft = CGRectMake(originX, originY + cell + gap, cell, cell);
    CGRect bottomRight = CGRectMake(originX + cell + gap, originY + cell + gap, cell, cell);

    NSDictionary<NSString *, NSValue *> *visible = @{
        @"CCUIConnectivityAirplaneViewController": [NSValue valueWithCGRect:topLeft],
        @"CCUIConnectivityWifiViewController": [NSValue valueWithCGRect:bottomLeft],
        @"CCUIConnectivityAirDropViewController": [NSValue valueWithCGRect:topRight]
    };
    for (NSString *name in visible) {
        UIView *view = PACCConnectivityChild(controller, name).view;
        view.frame = visible[name].CGRectValue;
        view.hidden = NO;
        view.alpha = 1.0;
    }
    CGFloat naturalMiniCell = floor(cell * 0.444);
    CGFloat naturalMiniGap = cell - naturalMiniCell * 2.0;
    CGFloat requestedMiniGap = MAX(2.0, naturalMiniGap - 3.0);
    CGFloat miniCell = floor((cell - requestedMiniGap) * 0.5);
    CGFloat miniGap = cell - miniCell * 2.0;
    if (!cluster) {
        cluster = [[UIView alloc] initWithFrame:bottomRight];
        cluster.tag = PACCTagConnectivityCluster;
        cluster.userInteractionEnabled = NO;
        NSArray<NSString *> *symbols = @[@"antenna.radiowaves.left.and.right", @"bluetooth", @"personalhotspot", @"network"];
        NSArray<UIColor *> *colors = @[
            [UIColor colorWithRed:0.26 green:0.66 blue:1.0 alpha:0.48],
            [UIColor colorWithRed:0.36 green:0.20 blue:1.0 alpha:1.0],
            [UIColor.whiteColor colorWithAlphaComponent:0.30],
            [UIColor.whiteColor colorWithAlphaComponent:0.30]
        ];
        for (NSUInteger index = 0; index < symbols.count; index++) {
            UIView *tile = [UIView new];
            tile.backgroundColor = [colors[index] colorWithAlphaComponent:index == 1 ? 0.85 : 0.18];
            if (index == 3) {
                UIView *backing = [UIView new];
                backing.tag = 2;
                backing.backgroundColor = UIColor.whiteColor;
                backing.hidden = YES;
                backing.userInteractionEnabled = NO;
                [tile addSubview:backing];
            }
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:9.0 weight:UIImageSymbolWeightSemibold];
            UIImage *symbolImage = index == 3 ? PACCBundledSymbol(@"network.connected.to.line.below.fill", UIColor.whiteColor, NO) : [UIImage systemImageNamed:symbols[index] withConfiguration:configuration];
            UIImageView *icon = [[UIImageView alloc] initWithImage:symbolImage];
            icon.tag = 1;
            icon.contentMode = UIViewContentModeCenter;
            icon.tintColor = colors[index];
            [tile addSubview:icon];
            if (index < 3) tile.hidden = YES;
            [cluster addSubview:tile];
        }
        [root addSubview:cluster];
    }
    cluster.hidden = NO;
    cluster.frame = bottomRight;
    [cluster.subviews enumerateObjectsUsingBlock:^(UIView *tile, NSUInteger index, __unused BOOL *stop) {
        CGFloat x = (index % 2) * (miniCell + miniGap), y = (index / 2) * (miniCell + miniGap);
        tile.frame = CGRectMake(x, y, miniCell, miniCell);
        tile.layer.cornerRadius = miniCell * 0.5;
        tile.layer.masksToBounds = YES;
        [tile viewWithTag:1].frame = tile.bounds;
        [tile viewWithTag:2].frame = tile.bounds;
        tile.hidden = index < 3;
    }];
    UIView *vpnTile = cluster.subviews.lastObject;
    UIView *vpnBacking = [vpnTile viewWithTag:2];
    NSArray *vibrantFilters = PACCConnectivityVibrantFilters(root);
    if (vibrantFilters.count) { vpnBacking.layer.filters = vibrantFilters; vpnBacking.hidden = NO; }
    vpnTile.backgroundColor = UIColor.clearColor;
    ((UIImageView *)[vpnTile viewWithTag:1]).tintColor = UIColor.whiteColor;
    [root bringSubviewToFront:cluster];
    NSArray<NSString *> *miniClasses = @[@"CCUIConnectivityCellularDataViewController", @"CCUIConnectivityBluetoothViewController", @"CCUIConnectivityHotspotViewController"];
    NSUInteger slot = 0;
    for (NSString *className in miniClasses) {
        UIViewController *child = PACCConnectivityChild(controller, className);
        UIView *view = child.view;
        if (!view) continue;
        view.hidden = NO;
        view.alpha = 1.0;
        view.userInteractionEnabled = NO;
        view.transform = CGAffineTransformIdentity;
        view.bounds = CGRectMake(0.0, 0.0, cell, cell);
        view.center = CGPointMake(CGRectGetMinX(bottomRight) + (slot % 2) * (miniCell + miniGap) + miniCell * 0.5,
            CGRectGetMinY(bottomRight) + (slot / 2) * (miniCell + miniGap) + miniCell * 0.5);
        view.transform = CGAffineTransformMakeScale(miniCell / cell, miniCell / cell);
        PACCScaleMiniGlyphs(view, 1.2);
        [root bringSubviewToFront:view];
        slot++;
    }
    vpnTile.frame = CGRectMake((slot % 2) * (miniCell + miniGap), (slot / 2) * (miniCell + miniGap), miniCell, miniCell);
    [cluster bringSubviewToFront:vpnTile];
}

CGRect PACCVisibleModuleBounds(UIViewController *overlay) {
    CGRect bounds = CGRectNull;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithArray:overlay.childViewControllers];
    while (queue.count) {
        UIViewController *controller = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(controller.class) containsString:@"ContentModuleContainerViewController"] &&
            !controller.view.hidden && controller.view.alpha > 0.01) {
            CGRect frame = [controller.view convertRect:controller.view.bounds toView:overlay.view];
            if (CGRectIntersectsRect(frame, overlay.view.bounds)) bounds = CGRectIsNull(bounds) ? frame : CGRectUnion(bounds, frame);
        }
        [queue addObjectsFromArray:controller.childViewControllers];
    }
    return bounds;
}