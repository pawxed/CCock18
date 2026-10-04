#import "PACC.h"

BOOL gPagerScrubbing = NO;

%hook CALayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if ([self.superlayer.delegate
         isKindOfClass:NSClassFromString(@"CCUIButtonModuleView")]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

%hook MTMaterialLayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    NSArray<NSString *> *titles = @[@"modules", @"moduleFill.highlight.generatedRecipe"];
    if ([titles containsObject:self.recipeName]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

%hook CCUIModuleCollectionView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled) return;
    if (self.window) {
        [PACC.shared installMediaPlayerOnCollectionView:(UIScrollView *)self];
        [PACC.shared installPromoPageOnCollectionView:(UIScrollView *)self];
    }
}

- (void)layoutSubviews {
    static void *kPACCInLayoutKey = &kPACCInLayoutKey;

    if (objc_getAssociatedObject(self, kPACCInLayoutKey)) {
        %orig;
        return;
    }

    objc_setAssociatedObject(self, kPACCInLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (!gEnabled) {
        objc_setAssociatedObject(self, kPACCInLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UIScrollView *scroll = (UIScrollView *)(id)self;

    [PACC.shared layoutMediaPlayerForCollectionView:scroll];
    [PACC.shared layoutPromoPageForCollectionView:scroll];

    if (fabs(scroll.contentOffset.x) > 0.25 || fabs(scroll.contentOffset.y) > 0.25) {
        [scroll setContentOffset:CGPointZero animated:NO];
    }

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (!notched && !gPagerScrubbing) {
        CGFloat span = PageSpan();
        if (span > 0.0) {
            CATransform3D t = self.layer.sublayerTransform;
            CGFloat expected = -(CGFloat)gCurrentPage * span;
            if (fabs(t.m42 - expected) > 0.5) {
                t.m41 = 0.0;
                t.m42 = expected;
                t.m43 = 0.0;
                self.layer.sublayerTransform = t;
            }
        }
    }

    objc_setAssociatedObject(self, kPACCInLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    gCCAModuleExpanded = YES;
    UIViewController *overlay = (UIViewController *)(id)self;
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
    [UIView animateWithDuration:0.2 animations:^{
        indicator.alpha = 0.0;
    } completion:^(BOOL finished) {
        indicator.hidden = YES;
    }];
    %orig;
    (void)collection; (void)module;
}

- (void)moduleCollectionViewController:(id)collection didCloseExpandedModule:(id)module {
    %orig;
    gCCAModuleExpanded = NO;
    UIViewController *overlay = (UIViewController *)(id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [PACC.shared layoutPageIndicatorForOverlay:overlay];
        [PACC.shared installPageIndicatorOnOverlay:overlay];
        UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    });
    (void)collection; (void)module;
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    UIViewController *overlay = (UIViewController *)(id)self;
    if (!overlay.view) return;

    static void *kLastPresentationStateKey = &kLastPresentationStateKey;
    NSNumber *lastState = objc_getAssociatedObject(overlay, kLastPresentationStateKey);
    BOOL stateChanged = !lastState || lastState.integerValue != state;
    objc_setAssociatedObject(overlay, kLastPresentationStateKey, @(state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[overlay.view viewWithTag:kMediaPlayerTag];

    if (state == 1) {
        if (!notched) {
            UIViewController *collection = ModuleCollection(overlay);
            if (collection && collection.view) {
                CGFloat span = PageSpan();
                if (span > 0.0) {
                    CATransform3D t = collection.view.layer.sublayerTransform;
                    t.m41 = 0.0;
                    t.m42 = -(CGFloat)gCurrentPage * span;
                    t.m43 = 0.0;
                    collection.view.layer.sublayerTransform = t;
                }
            }
        }

        [PACC.shared updateQuickAccessButtonsForOverlay:overlay];
        [PACC.shared installPageIndicatorOnOverlay:overlay];
        [PACC.shared animateElementsInForOverlay:overlay];
        [PACC.shared adjustStatusBarForOverlay:overlay];
        [PACC.shared syncModuleVisibilityForOverlay:overlay];
        [PACC.shared applyHeaderMaterialHidden:(gCurrentPage == 1) forOverlay:overlay];

        if (player && stateChanged) {
            [player resetForPresentation];
            if (notched && gCurrentPage == 1) [player fadeIn];
        }
    } else if (state == 3) {
        [PACC.shared animateElementsOutForOverlay:overlay];

        if (player && stateChanged && gCurrentPage == 1 && notched) {
            [player fadeOut];
        }

        NSInteger savedPage = gCurrentPage;
        gCurrentPage = 0;
        [PACC.shared adjustStatusBarForOverlay:overlay];
        gCurrentPage = savedPage;
    }
}

- (void)viewDidLayoutSubviews {
    static void *kPACCInOverlayLayoutKey = &kPACCInOverlayLayoutKey;
    if (objc_getAssociatedObject(self, kPACCInOverlayLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kPACCInOverlayLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled) {
        UIViewController *overlay = (UIViewController *)(id)self;
        [PACC.shared layoutPageIndicatorForOverlay:overlay];
        [PACC.shared adjustStatusBarForOverlay:overlay];
    }

    objc_setAssociatedObject(self, kPACCInOverlayLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook MRUNowPlayingView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    PACCConfigureMedia((UIView *)(id)self);
}
%end

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    if (!PACCMediaMode(view)) return;
    CGFloat radius = view.layer.cornerRadius;
    for (UIView *child in view.subviews) {
        if (fabs(CGRectGetWidth(child.bounds) - CGRectGetWidth(view.bounds)) > 1.0 ||
            fabs(CGRectGetHeight(child.bounds) - CGRectGetHeight(view.bounds)) > 1.0) continue;
        child.layer.cornerRadius = radius;
        child.layer.cornerCurve = kCACornerCurveContinuous;
        child.layer.masksToBounds = YES;
    }
    UIView *backing = view.subviews.firstObject;
    NSArray *filters = PACCMediaMaterialFilters(view);
    if (backing && filters.count) { backing.backgroundColor = UIColor.whiteColor; backing.layer.filters = filters; }
}
%end

%hook MRUNowPlayingHeaderView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = PACCMediaMode(view);
    if (!mode) return;

    UIView *routing = PACCViewIvar(self, "_routingButton");
    UIView *label = PACCViewIvar(self, "_labelView");
    UIView *headerTransport = PACCViewIvar(self, "_transportButton");

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat side = 40.0;

    UIView *nowPlaying = PACCAncestor(view, @"MRUNowPlayingView");
    UIView *artwork = PACCViewIvar(nowPlaying, "_artworkView");
    UIView *transport = PACCViewIvar(nowPlaying, "_transportControlsView");

    NSArray *filters = PACCMediaMaterialFilters(view);
    CGFloat labelHeight = 34.0;
    CGFloat labelY = (artwork && transport ? (CGRectGetMaxY(artwork.frame) + CGRectGetMinY(transport.frame) - labelHeight) * 0.5 : 64.0) + 6.5;

    CGRect routingFrame = CGRectMake(width - 54, 14, side, side);
    CGRect labelFrame = CGRectMake(14, labelY, width - 28, labelHeight);

    [UIView performWithoutAnimation:^{
        if (headerTransport) headerTransport.hidden = YES;

        if (routing) {
            routing.frame = routingFrame;
            routing.hidden = NO;
            routing.alpha = 1;
            routing.backgroundColor = UIColor.clearColor;
            routing.tintColor = UIColor.whiteColor;
            routing.layer.filters = nil;
            routing.layer.cornerRadius = side / 2;
            routing.layer.masksToBounds = YES;

            UIView *material = [routing viewWithTag:PACCTagMediaButtonMaterial];
            if (!material) {
                material = [UIView new];
                material.tag = PACCTagMediaButtonMaterial;
                material.userInteractionEnabled = NO;
                [routing insertSubview:material atIndex:0];
            }
            material.frame = routing.bounds;
            if (filters.count) {
                material.backgroundColor = UIColor.whiteColor;
                material.layer.filters = filters;
            } else {
                material.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
                material.layer.filters = nil;
            }
            material.layer.cornerRadius = side / 2;
            material.layer.masksToBounds = YES;

            PACCResizeMediaRoutingGlyph(routing);
        }

        if (label) {
            label.frame = labelFrame;
            label.hidden = NO;
            label.alpha = 1;
        }
    }];
}
%end

%hook MRUNowPlayingLabelView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIView *view = (UIView *)self;
    if (!PACCMediaMode(view)) return;

    UIView *title       = PACCViewIvar(self, "_titleMarqueeView")       ?: PACCViewIvar(self, "_titleLabel");
    UIView *subtitle    = PACCViewIvar(self, "_subtitleMarqueeView")    ?: PACCViewIvar(self, "_subtitleLabel");
    UIView *placeholder = PACCViewIvar(self, "_placeholderMarqueeView");
    NSArray *filters    = PACCMediaMaterialFilters(view);

    view.layer.filters = nil;
    PACCViewIvar(self, "_routeLabel").hidden = YES;

    if ([self respondsToSelector:@selector(setTextAlignment:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setTextAlignment:), NSTextAlignmentLeft);
    }

    for (UIView *line in @[title ?: (id)NSNull.null,
                           subtitle ?: (id)NSNull.null,
                           placeholder ?: (id)NSNull.null]) {
        if ((id)line == NSNull.null) continue;
        if ([line respondsToSelector:@selector(setTextAlignment:)]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(line, @selector(setTextAlignment:), NSTextAlignmentLeft);
        }
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:line];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class] && filters.count) {
                ((UILabel *)child).textColor = UIColor.whiteColor;
                child.layer.filters = filters;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }

    if (placeholder && !placeholder.hidden) {
        CGFloat height = CGRectGetHeight(placeholder.bounds);
        placeholder.frame = CGRectMake(0.0,
                                       floor((CGRectGetHeight(view.bounds) - height) * 0.5),
                                       CGRectGetWidth(view.bounds),
                                       height);
    }

    if (!title || !subtitle) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat start = MAX(0, (CGRectGetHeight(view.bounds) - 31) / 2);

    title.frame    = CGRectMake(0, start,      width, 16);
    subtitle.frame = CGRectMake(0, start + 17, width, 14);

    for (UIView *line in @[title, subtitle]) {
        line.alpha = 1;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:line.subviews];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class]) {
                ((UILabel *)child).font = [UIFont systemFontOfSize:13
                                                          weight:(line == title
                                                                  ? UIFontWeightSemibold
                                                                  : UIFontWeightRegular)];
                ((UILabel *)child).textAlignment = NSTextAlignmentLeft;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }
}
%end

%hook MRUTransportButton
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    PACCResizeMediaRoutingGlyph((UIView *)(id)self);
}
%end

%hook MRUNowPlayingTransportControlsView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = PACCMediaMode(view);
    if (!mode) return;

    UIView *left = PACCViewIvar(self, "_leftButton");
    UIView *center = PACCViewIvar(self, "_centerButton");
    UIView *right = PACCViewIvar(self, "_rightButton");

    if (!left || !center || !right) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat y = CGRectGetHeight(view.bounds) / 2;
    CGFloat spacing = width * 0.32;

    left.hidden = NO;
    center.center = CGPointMake(width / 2, y);
    left.center = CGPointMake(width / 2 - spacing, y);
    right.center = CGPointMake(width / 2 + spacing, y);

    PACCViewIvar(self, "_leadingButton").hidden = YES;
    PACCViewIvar(self, "_routingButton").hidden = YES;
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [PACC.shared installOnOverlay:(UIViewController *)self];
    }
}
- (void)viewDidLayoutSubviews {
    static void *kPACCInVCLayoutKey = &kPACCInVCLayoutKey;
    if (objc_getAssociatedObject(self, kPACCInVCLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kPACCInVCLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [PACC.shared updateQuickAccessButtonsForOverlay:(UIViewController *)self];
        [PACC.shared layoutPageIndicatorForOverlay:(UIViewController *)self];
    }
    if ([NSStringFromClass(self.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) {
        UIViewController *controller = (UIViewController *)(id)self;
        PACCConfigureConnectivity(controller);
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakController) PACCConfigureConnectivity(weakController); });
    }

    objc_setAssociatedObject(self, kPACCInVCLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUISliderModuleViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIViewController *vc = (UIViewController *)self;
    NSString *className = NSStringFromClass(vc.class);
    UIColor *tintColor = nil;

    if ([className containsString:@"Brightness"]) {
        tintColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
    } else if ([className containsString:@"Volume"]) {
        tintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    }

    if (tintColor) {
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:[UISlider class]]) {
                UISlider *slider = (UISlider *)sub;
                slider.tintColor = tintColor;
                slider.minimumTrackTintColor = tintColor;
            }
            if ([NSStringFromClass(sub.class) containsString:@"Slider"]) {
                sub.tintColor = tintColor;
                for (UIView *child in sub.subviews) {
                    child.tintColor = tintColor;
                }
            }
        }
    }
}
%end

static void PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    LoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (overlay) [PACC.shared installOnOverlay:overlay];
    });
}

%ctor {
    @autoreleasepool {
        LoadPrefs();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged,
                                        (__bridge CFStringRef)kReloadNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}