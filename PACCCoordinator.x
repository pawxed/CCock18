#import "PACC.h"

@implementation CCAQuickAccessHost
- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) sig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation { }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.05 || !self.userInteractionEnabled) return nil;
    for (UIView *sub in self.subviews.reverseObjectEnumerator) {
        if (sub.hidden || sub.alpha <= 0.05 || !sub.userInteractionEnabled) continue;
        CGPoint p = [self convertPoint:point toView:sub];
        UIView *hit = [sub hitTest:p withEvent:event];
        if (hit) return hit;
    }
    return nil;
}
@end

static NSArray<NSString *> *PACCDogFacts(void) {
    static NSArray<NSString *> *facts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        facts = @[
            @"dogs have about 1,700 taste buds while humans have around 9,000.",
            @"a dog's nose print is unique, just like a human fingerprint.",
            @"dogs can smell roughly 100,000 times better than humans can.",
            @"the average dog can learn around 165 words.",
            @"dogs dream just like humans do, mostly about their owners.",
            @"a dog's hearing is about four times sharper than a human's.",
            @"basenjis are the only breed of dog that cannot bark.",
            @"dogs sweat mainly through their paws.",
            @"a greyhound can run up to 45 miles per hour.",
            @"puppies are born deaf, blind and with no teeth.",
            @"dogs have three eyelids, and the third one keeps the eye moist.",
            @"dogs curl up to sleep to protect their vital organs.",
            @"the bond between dogs and humans goes back 15,000 years.",
            @"a wagging tail to the right usually means a dog is happy.",
            @"dogs can see in the dark far better than humans can.",
            @"the creator of this tweak is a golden retriever dog, no one will believe you.",
            @"did you know that"
        ];
    });
    return facts;
}

@interface CCAPromoPageView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *factLabel;
@end

@implementation CCAPromoPageView

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) sig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation { }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;

        UILabel *title = [UILabel new];
        title.text = @"made by pawxed";
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.numberOfLines = 1;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        [self addSubview:title];
        self.titleLabel = title;

        UILabel *fact = [UILabel new];
        fact.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        fact.textAlignment = NSTextAlignmentCenter;
        fact.numberOfLines = 0;
        fact.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:fact];
        self.factLabel = fact;

        [self refreshFact];
    }
    return self;
}

- (void)refreshFact {
    NSArray<NSString *> *facts = PACCDogFacts();
    if (!facts.count) return;
    NSUInteger index = arc4random_uniform((uint32_t)facts.count);
    if (facts.count > 1 && [facts[index] isEqualToString:self.factLabel.text]) {
        index = (index + 1) % facts.count;
    }
    self.factLabel.text = facts[index];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w < 1.0 || h < 1.0) return;

    CGFloat sidePad = 28.0;
    CGFloat contentW = w - sidePad * 2.0;

    self.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    CGSize titleFit = [self.titleLabel sizeThatFits:CGSizeMake(contentW, 60.0)];
    titleFit.width  = MIN(contentW, ceil(titleFit.width));
    titleFit.height = ceil(titleFit.height);

    self.factLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    CGFloat factW = contentW * 0.92;
    CGSize factFit = [self.factLabel sizeThatFits:CGSizeMake(factW, 260.0)];
    factFit.width  = MIN(factW, ceil(factFit.width));
    factFit.height = ceil(factFit.height);

    CGFloat gap = 10.0;
    CGFloat total = titleFit.height + gap + factFit.height;
    CGFloat y = floor((h - total) * 0.5);
    if (y < 4.0) y = 4.0;

    self.titleLabel.frame = CGRectMake(floor((w - titleFit.width) * 0.5), y,
                                       titleFit.width, titleFit.height);
    y += titleFit.height + gap;
    self.factLabel.frame = CGRectMake(floor((w - factFit.width) * 0.5), y,
                                      factFit.width, factFit.height);
}

@end

@implementation PACC

+ (instancetype)shared {
    static PACC *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (CGFloat)topInsetForOverlay:(UIViewController *)overlay {
    CGFloat safeTop = overlay.view.window.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = overlay.view.safeAreaInsets.top;
    return MAX(8.0, safeTop - 6.0);
}

- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [button setImage:image forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    return button;
}

- (void)installOnOverlay:(UIViewController *)overlay {
    if (!gEnabled || !overlay.view) return;
    [self updateQuickAccessButtonsForOverlay:overlay];
    [self installPageIndicatorOnOverlay:overlay];
    [self syncModuleVisibilityForOverlay:overlay];
    [self applyHeaderMaterialHidden:(gCurrentPage == 1) forOverlay:overlay];
    [self adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if ([collection.view isKindOfClass:UIScrollView.class]) {
        [self installPromoPageOnCollectionView:(UIScrollView *)collection.view];
    }
}

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay {
    [self syncModuleVisibilityForOverlay:overlay animated:NO];
}

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    BOOL hide = (gCurrentPage != 0);
    CGFloat targetAlpha = hide ? 0.0 : 1.0;

    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            [targets addObject:v];
        }
        [queue addObjectsFromArray:v.subviews];
    }

    if (animated && targets.count) {
        [UIView animateWithDuration:0.35 delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            for (UIView *v in targets) v.alpha = targetAlpha;
        } completion:nil];
    } else {
        for (UIView *v in targets) v.alpha = targetAlpha;
    }
}

- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            v.alpha = 1.0;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIHeaderPocketView"]) {
            for (UIView *child in v.subviews) {
                if ([NSStringFromClass(child.class) isEqualToString:@"MTMaterialView"]) {
                    child.hidden = hidden;
                }
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)adjustStatusBarForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay || !overlay.view) return;

    UIWindow *window = overlay.view.window;
    if (!window) return;
    if (window.hidden || window.alpha < 0.01) return;

    UIView *statusBar = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"UIStatusBar_Modern"]) {
            statusBar = v;
            break;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    if (!statusBar) return;

    static void *kStatusBarBaseTransformKey = &kStatusBarBaseTransformKey;
    NSValue *storedBase = objc_getAssociatedObject(statusBar, kStatusBarBaseTransformKey);
    if (!storedBase) {
        if (!CGAffineTransformIsIdentity(statusBar.transform)) return;
        objc_setAssociatedObject(statusBar, kStatusBarBaseTransformKey,
                                 [NSValue valueWithCGAffineTransform:statusBar.transform],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        storedBase = objc_getAssociatedObject(statusBar, kStatusBarBaseTransformKey);
    }
    CGAffineTransform base = storedBase.CGAffineTransformValue;

    CGFloat dy = (gCurrentPage == 1) ? -25.0 : 0.0;
    CGAffineTransform target = CGAffineTransformTranslate(base, 0, dy);

    if (CGAffineTransformEqualToTransform(statusBar.transform, target)) return;

    statusBar.layer.transform = CATransform3DMakeAffineTransform(target);
}

- (void)animateElementsInForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    if (host) {
        host.alpha = 0.0;
        host.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.45 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            host.alpha = 1.0;
            host.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    if (indicator) {
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    }
}

- (void)animateElementsOutForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    [UIView animateWithDuration:0.2 animations:^{
        if (host) {
            host.alpha = 0.0;
            host.transform = CGAffineTransformMakeScale(0.6, 0.6);
        }
        if (indicator) {
            indicator.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        if (indicator) {
            indicator.hidden = YES;
            indicator.alpha = 1.0;
        }
    }];
}

- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    if (!host) {
        host = [[CCAQuickAccessHost alloc] initWithFrame:CGRectZero];
        host.tag = kQuickAccessTag;
        host.backgroundColor = UIColor.clearColor;
        host.userInteractionEnabled = YES;
        [overlay.view addSubview:host];
    }
    CGFloat top = [self topInsetForOverlay:overlay];
    host.frame = CGRectMake(0, top, CGRectGetWidth(overlay.view.bounds), 44);
    host.hidden = !gQuickAccessButtonsEnabled;

    UIButton *plus = [host viewWithTag:181001];
    if (!plus) {
        plus = [self makeRoundButtonWithSymbol:@"plus" tag:181001];
        [plus addTarget:self action:@selector(addPressed:) forControlEvents:UIControlEventTouchUpInside];
        [host addSubview:plus];
    }
    UIButton *power = [host viewWithTag:181002];
    if (!power) {
        power = [self makeRoundButtonWithSymbol:@"power" tag:181002];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(powerPressed:)];
        hold.minimumPressDuration = 0.6;
        [power addGestureRecognizer:hold];
        [host addSubview:power];
    }
    CGFloat btnSize = 36;
    CGFloat margin = 22;
    plus.frame = CGRectMake(margin, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    power.frame = CGRectMake(CGRectGetWidth(host.bounds) - margin - btnSize, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    [overlay.view bringSubviewToFront:host];
}

- (void)addPressed:(UIButton *)sender {
    if (!gEnabled) return;
    Haptic();
    UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    SEL sel = NSSelectorFromString(@"presentAddSheet");
    if (overlay && [overlay respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(overlay, sel);
    }
}

- (void)powerPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    Haptic();
    Class factoryClass = NSClassFromString(@"SBUIPowerDownViewControllerFactory");
    SEL sel = NSSelectorFromString(@"newPowerDownViewController");
    if (![factoryClass respondsToSelector:sel]) return;
    UIViewController *power = ((id (*)(id, SEL))objc_msgSend)(factoryClass, sel);
    if (!power) return;
    UIViewController *presenter = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!presenter || presenter.presentedViewController) return;
    power.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:power animated:YES completion:nil];
}

- (void)snapToFirstPageForOverlay:(UIViewController *)overlay {
    if (gCurrentPage == 0) return;
    gCurrentPage = 0;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    CATransform3D t = collection.view.layer.sublayerTransform;
    t.m41 = 0.0;
    t.m42 = 0.0;
    t.m43 = 0.0;
    collection.view.layer.sublayerTransform = t;

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) player.alpha = 0.0;
}

- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay {
    if (!gPagingEnabled) {
        [[overlay.view viewWithTag:kPageIndicatorTag] removeFromSuperview];
        return;
    }

    NSUInteger pageCount = gPromoPageEnabled ? 3 : 2;
    if ((NSInteger)gCurrentPage >= (NSInteger)pageCount) {
        [self snapToFirstPageForOverlay:overlay];
    }

    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) {
        indicator = [[CCAPageIndicator alloc] initWithFrame:CGRectZero];
        indicator.tag = kPageIndicatorTag;
        [overlay.view addSubview:indicator];
    }
    indicator.pageCount = pageCount;
    indicator.overlay = overlay;
    indicator.hidden = gCCAModuleExpanded;
    indicator.transform = CGAffineTransformIdentity;
    [self layoutPageIndicatorForOverlay:overlay];
    [overlay.view bringSubviewToFront:indicator];
}

- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay {
    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) return;
    if (indicator.scrubbing)
return;
    CGFloat step = 39.0;
    CGFloat width = 42.0;
    CGFloat height = step * MAX((NSUInteger)1, indicator.pageCount);
    CGFloat screenRight = CGRectGetWidth(overlay.view.bounds);

    static void *kPagerRightEdgeKey = &kPagerRightEdgeKey;
    NSNumber *cachedEdge = objc_getAssociatedObject(indicator, kPagerRightEdgeKey);

    CGRect modules = PACCVisibleModuleBounds(overlay);
    CGFloat moduleRight = CGRectIsNull(modules) ? 0.0 : CGRectGetMaxX(modules);

    if ((gCurrentPage == 0 || !cachedEdge) && moduleRight > 0.0) {
        objc_setAssociatedObject(indicator, kPagerRightEdgeKey, @(moduleRight),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cachedEdge = @(moduleRight);
    }
    if (cachedEdge) moduleRight = cachedEdge.doubleValue;

    CGFloat centerX = moduleRight > 0.0 ? (moduleRight + screenRight) * 0.5 : screenRight - 21.0;
    indicator.frame = CGRectMake(centerX - width * 0.5,
                                 floor((CGRectGetHeight(overlay.view.bounds) - height) * 0.5),
                                 width, height);

    [indicator layoutButtons];
    [indicator captureCollectionBase];
}

- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView {
    if (!gEnabled || !gPagingEnabled) {
        [[collectionView viewWithTag:kMediaPlayerTag] removeFromSuperview];
        return;
    }
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) {
        player = [[CCAMediaPlayerView alloc] initWithFrame:CGRectZero];
        player.tag = kMediaPlayerTag;
        player.alpha = 0.0;
        [collectionView addSubview:player];
    }
    [self layoutMediaPlayerForCollectionView:collectionView];
}

- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView {
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenW = CGRectGetWidth(screenBounds);
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();

    BOOL notched = (screenH >= 800.0);

    CGFloat minTop = notched ? 100.0 : 145.0;
    CGFloat bottomMargin = 20.0;
    CGFloat availableH = screenH - minTop - bottomMargin;

    CGFloat cardW = screenW * (notched ? 0.86 : 0.84);
    CGFloat aspect = 1.60;
    CGFloat cardH = cardW * aspect;
    if (cardH > availableH) {
        cardH = availableH;
        cardW = cardH / aspect;
    }

    CGFloat cardTopScreen = (screenH - cardH) * 0.5;
    if (cardTopScreen < minTop) cardTopScreen = minTop;

    CGFloat x = (screenW - cardW) * 0.5;

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0, cardTopScreen, 0, 0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span;
    } else {
        frameY = span + cardTopScreen;
    }

    CGRect targetBounds = CGRectMake(0, 0, cardW, cardH);
    CGPoint targetCenter = CGPointMake(x + cardW * 0.5, frameY + cardH * 0.5);

    if (!CGRectEqualToRect(player.bounds, targetBounds)) {
        player.bounds = targetBounds;
    }
    if (!CGPointEqualToPoint(player.center, targetCenter)) {
        player.center = targetCenter;
    }
}

- (void)installPromoPageOnCollectionView:(UIScrollView *)collectionView {
    if (!gEnabled || !gPagingEnabled || !gPromoPageEnabled) {
        [[collectionView viewWithTag:kPromoPageTag] removeFromSuperview];
        return;
    }
    CCAPromoPageView *promo = (CCAPromoPageView *)[collectionView viewWithTag:kPromoPageTag];
    if (!promo) {
        promo = [[CCAPromoPageView alloc] initWithFrame:CGRectZero];
        promo.tag = kPromoPageTag;
        [collectionView addSubview:promo];
    }
    [self layoutPromoPageForCollectionView:collectionView];
}

- (void)layoutPromoPageForCollectionView:(UIScrollView *)collectionView {
    CCAPromoPageView *promo = (CCAPromoPageView *)[collectionView viewWithTag:kPromoPageTag];
    if (!promo) return;

    if (!gEnabled || !gPagingEnabled || !gPromoPageEnabled) {
        [promo removeFromSuperview];
        return;
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat screenW = CGRectGetWidth(screenBounds);
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();

    CGFloat promoW = CGRectGetWidth(collectionView.bounds);
    if (promoW < 1.0) promoW = screenW;
    CGFloat promoH = MIN(240.0, MAX(160.0, screenH * 0.28));

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0.0, (screenH - promoH) * 0.5, 0.0, 0.0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span * 2.0;
    } else {
        frameY = span * 2.0 + (screenH - promoH) * 0.5;
    }

    promo.bounds = CGRectMake(0.0, 0.0, promoW, promoH);
    promo.center = CGPointMake(floor(promoW * 0.5), floor(frameY + promoH * 0.5));
}

@end