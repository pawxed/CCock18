#import "PACC.h"

@interface CCAPageIndicator () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) NSUInteger dragStartPage;
@property (nonatomic, assign) NSUInteger interactiveStartPage;
@property (nonatomic, assign) CGFloat interactiveProgress;
@property (nonatomic, assign) CGFloat interactiveTranslation;
@property (nonatomic, assign) CFTimeInterval interactiveBeganTime;
@property (nonatomic, assign) CFTimeInterval lastSampleTime;
@property (nonatomic, assign) CGFloat viscousProgress;
@property (nonatomic, assign) CGFloat previousRawProgress;
@property (nonatomic, assign) CGFloat filteredVelocity;
@property (nonatomic, assign) CGFloat jelloScaleX;
@property (nonatomic, assign) CGFloat jelloScaleY;
@property (nonatomic, assign) CGFloat heldScale;
@property (nonatomic, assign) CGFloat heldAlphaFactor;
@property (nonatomic, weak) UIView *savedCollectionView;
@property (nonatomic, assign) CGRect restHostFrame;
@property (nonatomic, assign) NSUInteger animationToken;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CATransform3D baseCollectionSublayerTransform;
@property (nonatomic, assign) BOOL suspendedForLandscape;
@end

static BOOL PACCIndicatorIsLandscape(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}

static NSArray<NSString *> *PACCIndicatorIcons(void) {
    static NSArray<NSString *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @[@"heart.fill", @"music.note", @"pawprint.fill"];
    });
    return icons;
}

static UIImage *PACCIndicatorSymbolForPage(NSUInteger index, CGFloat pointSize) {
    NSArray<NSString *> *icons = PACCIndicatorIcons();
    NSString *name = (index < icons.count) ? icons[index] : @"circle.fill";

    UIImage *image = PACCBundledSymbol(name, UIColor.whiteColor, NO);
    if (!image) image = [UIImage systemImageNamed:name];
    if (!image) return nil;

    if (!image.symbolConfiguration) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                            weight:UIImageSymbolWeightSemibold];
        image = [image imageByApplyingSymbolConfiguration:cfg] ?: image;
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@implementation CCAPageIndicator

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        self.currentPage = 0;
        self.pageCount = gPromoPageEnabled ? 3 : 2;
        self.heldScale = 1.0;
        self.heldAlphaFactor = 1.0;
        self.jelloScaleX = 1.0;
        self.jelloScaleY = 1.0;
        self.baseCollectionSublayerTransform = CATransform3DIdentity;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        self.panRecognizer = pan;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceOrientationChanged:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)deviceOrientationChanged:(NSNotification *)note {
    __weak CCAPageIndicator *weakSelf = self;
    for (NSNumber *delay in @[@0.05, @0.4, @0.9]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf syncLandscapeState]; });
    }
}

- (void)syncLandscapeState {
    BOOL landscape = PACCIndicatorIsLandscape();
    if (landscape == self.suspendedForLandscape) return;
    self.suspendedForLandscape = landscape;

    if (landscape) {
        if (self.panRecognizer.enabled) {
            self.panRecognizer.enabled = NO;
            self.panRecognizer.enabled = YES;
        }
        if (self.currentPage != 0 && self.overlay) {
            if (gExperimentalPagingEnabled) [self experimentalSetCurrentPage:0 forOverlay:self.overlay];
            else                            [self stableSetCurrentPage:0 forOverlay:self.overlay];
        }
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    } else {
        self.hidden = NO;
        self.userInteractionEnabled = YES;
        [self captureCollectionBase];
        [self layoutButtons];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self syncLandscapeState];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self syncLandscapeState];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncLandscapeState];
}

- (BOOL)scrubbing {
    return self.scrubbingActive;
}

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

- (void)pulseCurrentButton {
    if (self.currentPage >= self.subviews.count) return;
    UIView *button = self.subviews[self.currentPage];
    [button.layer removeAnimationForKey:@"PACCIndicatorPulse"];
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    pulse.values = @[@1.0, @1.18, @0.95, @1.0];
    pulse.keyTimes = @[@0.0, @0.35, @0.72, @1.0];
    pulse.duration = 0.26;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [button.layer addAnimation:pulse forKey:@"PACCIndicatorPulse"];
}

- (void)setOverlay:(UIViewController *)overlay {
    _overlay = overlay;
    [self captureCollectionBase];
    [self rebuildButtons];
    [self syncLandscapeState];
}

- (void)captureCollectionBase {
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;
    if (self.transitionActive) return;

    CATransform3D current = collection.view.layer.sublayerTransform;
    CGFloat span = PageSpan();
    current.m42 += (CGFloat)gCurrentPage * span;
    current.m41 = 0.0;
    current.m43 = 0.0;

    self.baseCollectionSublayerTransform = current;
}

- (void)setPageCount:(NSUInteger)pageCount {
    if (pageCount == 0) pageCount = 1;
    if (_pageCount == pageCount && self.subviews.count == pageCount) return;
    _pageCount = pageCount;
    [self rebuildButtons];
}

- (void)rebuildButtons {
    while (self.subviews.count > self.pageCount) [self.subviews.lastObject removeFromSuperview];
    while (self.subviews.count < self.pageCount) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tintColor = UIColor.whiteColor;
        NSUInteger page = self.subviews.count;
        objc_setAssociatedObject(button, @selector(tapped:), @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }
    [self layoutButtons];
}

- (void)layoutButtons {
    [self layoutIndicatorsWithScrubbing:NO touchY:0.0];
}

- (void)layoutIndicatorsWithScrubbing:(BOOL)scrubbing touchY:(CGFloat)touchY {
    if (self.pageCount == 0) return;
    CGFloat overlayH = self.overlay ? CGRectGetHeight(self.overlay.view.bounds) : CGRectGetHeight(UIScreen.mainScreen.bounds);

    CGFloat step = scrubbing ? 58.0 : 39.0;
    CGFloat hostH = step * (CGFloat)self.pageCount;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (scrubbing) {
        CGFloat rightEdge = CGRectGetMaxX(self.restHostFrame);
        if (rightEdge <= 0.0) rightEdge = CGRectGetMaxX(self.frame);
        CGFloat hostX = rightEdge - 58.0;
        CGFloat hostY = floor((overlayH - hostH) * 0.5);
        self.frame = CGRectMake(hostX, hostY, 58.0, hostH);
    }

    NSArray *buttons = self.subviews;
    NSUInteger count = buttons.count;
    NSUInteger index;
    for (index = 0; index < count; index++) {
        UIView *button = buttons[index];
        BOOL selected = ((NSInteger)index == (NSInteger)self.currentPage);

        if (scrubbing) {
            CGFloat centerY = ((CGFloat)index + 0.5) * step;
            CGFloat proximity = 1.0 - fabs(touchY - centerY) / 78.0;
            if (proximity < 0.0) proximity = 0.0;
            if (proximity > 1.0) proximity = 1.0;
            CGFloat scale = 1.18 + 1.68 * proximity + (selected ? 0.18 : 0.0);
            CGFloat rawSize = (index == 0 ? 16.0 : 12.0) * scale;
            CGFloat pointSize = rawSize < 38.0 ? rawSize : 38.0;
            CGFloat slideOut = 24.0 * proximity;
            CGFloat alpha = MIN(1.0, (selected ? 0.86 : 0.28) + 0.36 * proximity);
            CGFloat tintWhite = selected ? 1.0 : (0.12 + 0.72 * proximity);

            button.bounds = CGRectMake(0.0, 0.0, 58.0, step);
            button.center = CGPointMake(29.0 - slideOut, centerY);
            button.transform = CGAffineTransformIdentity;
            button.alpha = alpha;
            button.tintColor = [UIColor colorWithWhite:tintWhite alpha:1.0];

            UIButton *b = (UIButton *)button;
            UIImage *image = PACCIndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
        } else {
            CGFloat y = (CGFloat)index * step;
            button.frame = CGRectMake(0.0, y, 42.0, step);
            button.transform = CGAffineTransformIdentity;

            UIButton *b = (UIButton *)button;
            CGFloat pointSize = (index == 0) ? 16.0 : 12.0;
            UIImage *image = PACCIndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
            button.alpha = selected ? 1.0 : 0.72;
            button.tintColor = selected ? UIColor.whiteColor : [UIColor colorWithWhite:0.12 alpha:0.88];
        }
    }

    [CATransaction commit];
}

- (void)applyPageTransform {
    if (self.suspendedForLandscape) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat span = PageSpan();
    CGFloat pageOffset = -(CGFloat)self.currentPage * span + self.interactiveTranslation;

    CATransform3D target = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, pageOffset, 0.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = target;
    if (self.scrubbingActive) {
        collection.view.layer.transform = CATransform3DMakeScale(self.jelloScaleX, self.jelloScaleY, 1.0);
        collection.view.alpha = self.heldAlphaFactor;
    } else {
        collection.view.layer.transform = CATransform3DIdentity;
        collection.view.alpha = 1.0;
    }
    [CATransaction commit];
}

- (void)beginInteractiveTransitionWithStartPage:(NSUInteger)startPage {
    if (self.suspendedForLandscape) return;
    if (!self.overlay) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    self.restHostFrame = self.frame;

    self.transitionActive = YES;
    self.scrubbingActive = YES;
    self.dragging = NO;
    self.interactiveStartPage = MIN(startPage, self.pageCount - 1);
    self.currentPage = self.interactiveStartPage;
    gCurrentPage = (NSInteger)self.interactiveStartPage;
    self.interactiveProgress = (CGFloat)self.interactiveStartPage;
    self.interactiveTranslation = 0.0;
    self.interactiveBeganTime = CACurrentMediaTime();
    self.heldScale = 1.0;
    self.heldAlphaFactor = 1.0;
    self.viscousProgress = (CGFloat)self.interactiveStartPage;
    self.previousRawProgress = (CGFloat)self.interactiveStartPage;
    self.filteredVelocity = 0.0;
    self.jelloScaleX = 1.0;
    self.jelloScaleY = 1.0;
    self.lastSampleTime = CACurrentMediaTime();

    self.savedCollectionView = collection.view;

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    if (pres) {
        collection.view.layer.sublayerTransform = pres.sublayerTransform;
        collection.view.layer.transform = pres.transform;
    }
    [collection.view.layer removeAllAnimations];
}

- (void)updateInteractiveTransitionWithProgress:(CGFloat)progress touchY:(CGFloat)touchY {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;

    CGFloat physicsProgress = progress;
    if (progress < 0.0) physicsProgress = -log1p(-progress);
    else if (progress > maxProgress) physicsProgress = maxProgress + log1p(progress - maxProgress);

    NSUInteger previousCandidate = self.currentPage;

    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = self.lastSampleTime > 0.0 ? (CGFloat)(now - self.lastSampleTime) : (1.0 / 60.0);
    dt = MIN(0.050, MAX(1.0 / 120.0, dt));

    CGFloat rawVelocity = (physicsProgress - self.previousRawProgress) / dt;
    rawVelocity = MIN(8.0, MAX(-8.0, rawVelocity));
    CGFloat velocityResponse = 1.0 - exp(-dt * 11.0);
    self.filteredVelocity += (rawVelocity - self.filteredVelocity) * velocityResponse;

    CGFloat dragResponse = 1.0 - exp(-dt * 9.0);
    self.viscousProgress += (physicsProgress - self.viscousProgress) * dragResponse;

    CGFloat visualProgress = self.viscousProgress;
    NSUInteger candidate = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, visualProgress)));
    BOOL changedPage = (candidate != previousCandidate);
    if (changedPage) Haptic();
    CGFloat pageTension = physicsProgress - visualProgress;

    self.previousRawProgress = physicsProgress;
    self.lastSampleTime = now;
    self.interactiveProgress = MIN(maxProgress, MAX(0.0, progress));
    self.currentPage = candidate;
    gCurrentPage = (NSInteger)candidate;

    CGFloat overlayHeight = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubHostHeight = 58.0 * self.pageCount;
    CGFloat scrubHostMinY = floor((overlayHeight - scrubHostHeight) * 0.5);
    CGFloat fingerY = scrubHostMinY + touchY;

    CGFloat translationTarget = 0.0;
    BOOL endpointPull = NO;
    if (progress < 0.0) {
        CGFloat firstIconY = scrubHostMinY + 58.0 * 0.5;
        CGFloat upperLimitY = overlayHeight * 0.10;
        CGFloat pull = MIN(1.0, MAX(0.0, (firstIconY - fingerY) / MAX(1.0, firstIconY - upperLimitY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = -MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else if (progress > maxProgress) {
        CGFloat lastIconY = scrubHostMinY + ((CGFloat)self.pageCount - 0.5) * 58.0;
        CGFloat lowerLimitY = overlayHeight * 0.90;
        CGFloat pull = MIN(1.0, MAX(0.0, (fingerY - lastIconY) / MAX(1.0, lowerLimitY - lastIconY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else {
        translationTarget = (visualProgress - (CGFloat)candidate) * 22.0;
    }

    if (endpointPull) {
        self.interactiveTranslation += (translationTarget - self.interactiveTranslation) * dragResponse;
    } else {
        self.interactiveTranslation = translationTarget;
    }

    CGFloat entrance = self.interactiveBeganTime > 0.0
        ? MIN(1.0, MAX(0.0, (CACurrentMediaTime() - self.interactiveBeganTime) / 0.26)) : 1.0;
    entrance = entrance * entrance * entrance * (entrance * (entrance * 6.0 - 15.0) + 10.0);
    self.heldScale = 1.0 - 0.30 * entrance;
    self.heldAlphaFactor = 1.0 - 0.30 * entrance;

    CGFloat jelloInput = self.filteredVelocity * 0.0030 + pageTension * 0.022;
    CGFloat jello = MIN(0.025, MAX(-0.025, jelloInput)) * entrance;
    self.jelloScaleX = (1.0 - jello * 0.42) * self.heldScale;
    self.jelloScaleY = (1.0 + jello) * self.heldScale;

    [self applyPageTransform];
    if (changedPage) {
        [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
        CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
        if (player) {
            CGFloat targetAlpha = (candidate == 1) ? 1.0 : 0.0;
            if (fabs(player.alpha - targetAlpha) > 0.01) {
                [UIView animateWithDuration:0.15 animations:^{ player.alpha = targetAlpha; }];
            }
        }

        CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
        if (promo && candidate == 2) [promo refreshFact];
    }

    [self layoutIndicatorsWithScrubbing:YES touchY:touchY];
}

- (void)finishInteractiveTransitionWithTargetPage:(NSUInteger)targetPage {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSUInteger target = MIN(targetPage, self.pageCount - 1);
    self.interactiveBeganTime = 0.0;
    self.scrubbingActive = NO;
    self.currentPage = target;
    gCurrentPage = (NSInteger)target;
    self.interactiveTranslation = 0.0;

    [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
    [PACC.shared applyHeaderMaterialHidden:(target == 1) forOverlay:self.overlay];
    [PACC.shared adjustStatusBarForOverlay:self.overlay];

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = (target == 1) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && target == 2) [promo refreshFact];

    CGFloat span = PageSpan();
    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)target * span, 0.0);

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;
    CATransform3D fromTrans = pres ? pres.transform : collection.view.layer.transform;
    CGFloat fromAlpha = pres ? pres.opacity : collection.view.alpha;

    [collection.view.layer removeAnimationForKey:@"PAnimPageSlide"];
    [collection.view.layer removeAnimationForKey:@"PAnimScrubTransform"];
    [collection.view.layer removeAnimationForKey:@"PAnimScrubOpacity"];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    collection.view.layer.transform = CATransform3DIdentity;
    collection.view.alpha = 1.0;
    [CATransaction commit];

    CAMediaTimingFunction *curve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];

    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
    slide.fromValue = [NSValue valueWithCATransform3D:fromSub];
    slide.toValue   = [NSValue valueWithCATransform3D:toSub];
    slide.duration = 0.30;
    slide.timingFunction = curve;
    [collection.view.layer addAnimation:slide forKey:@"PAnimPageSlide"];

    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform"];
    scale.fromValue = [NSValue valueWithCATransform3D:fromTrans];
    scale.toValue   = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    scale.duration = 0.30;
    scale.timingFunction = curve;
    [collection.view.layer addAnimation:scale forKey:@"PAnimScrubTransform"];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(fromAlpha);
    fade.toValue = @1.0;
    fade.duration = 0.30;
    fade.timingFunction = curve;
    [collection.view.layer addAnimation:fade forKey:@"PAnimScrubOpacity"];

    [PACC.shared layoutPageIndicatorForOverlay:self.overlay];

    NSUInteger token = ++self.animationToken;
    __weak CCAPageIndicator *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CCAPageIndicator *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.animationToken != token) return;

        strongSelf.transitionActive = NO;
        strongSelf.scrubbingActive = NO;
        strongSelf.dragging = NO;
        strongSelf.savedCollectionView = nil;
        strongSelf.heldScale = 1.0;
        strongSelf.heldAlphaFactor = 1.0;
        strongSelf.jelloScaleX = 1.0;
        strongSelf.jelloScaleY = 1.0;
        strongSelf.viscousProgress = (CGFloat)target;
        strongSelf.filteredVelocity = 0.0;
        strongSelf.lastSampleTime = 0.0;

        gCurrentPage = (NSInteger)target;
        [strongSelf applyPageTransform];
        [strongSelf captureCollectionBase];
        [PACC.shared syncModuleVisibilityForOverlay:strongSelf.overlay animated:NO];
        [PACC.shared layoutPageIndicatorForOverlay:strongSelf.overlay];

        [strongSelf pulseCurrentButton];
    });
}

- (void)scrubPan:(UIPanGestureRecognizer *)gesture {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat overlayH = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubStep = 58.0;
    CGFloat scrubHostH = scrubStep * (CGFloat)self.pageCount;
    CGFloat scrubHostMinY = floor((overlayH - scrubHostH) * 0.5);

    CGPoint location = [gesture locationInView:self.superview];
    CGFloat touchY = location.y - scrubHostMinY;
    CGFloat progress = (touchY - scrubStep * 0.5) / scrubStep;
    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;
    progress = MIN(maxProgress + 0.9, MAX(-0.9, progress));

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.dragStartPage = self.currentPage;
        if (!self.transitionActive) {
            [self beginInteractiveTransitionWithStartPage:self.currentPage];
        }
        [self updateInteractiveTransitionWithProgress:progress touchY:touchY];

    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.transitionActive) {
            [self updateInteractiveTransitionWithProgress:progress touchY:touchY];
        }

    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        if (self.transitionActive && self.scrubbingActive) {
            NSUInteger target;
            if (gesture.state == UIGestureRecognizerStateEnded) {
                target = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, progress)));
            } else {
                target = self.dragStartPage;
            }
            [self finishInteractiveTransitionWithTargetPage:target];
        }
    }
}

- (void)buttonTouchDown:(UIButton *)sender {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        self.animationToken++;
        self.transitionActive = NO;
        self.scrubbingActive = NO;
    }

    [self beginInteractiveTransitionWithStartPage:self.currentPage];

    CGFloat touchY = ((CGFloat)targetPage + 0.5) * 58.0;
    [self updateInteractiveTransitionWithProgress:(CGFloat)targetPage touchY:touchY];
}

- (void)buttonTapped:(UIButton *)sender {
    if (!self.overlay || !gPagingEnabled) return;
    if (self.dragging) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        Haptic();
        [self finishInteractiveTransitionWithTargetPage:targetPage];
        return;
    }

    if (targetPage == self.currentPage) return;
    Haptic();
    [self setCurrentPage:targetPage forOverlay:self.overlay];
}

- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (self.suspendedForLandscape) return;
    if (gExperimentalPagingEnabled) {
        [self experimentalSetCurrentPage:page forOverlay:overlay];
    } else {
        [self stableSetCurrentPage:page forOverlay:overlay];
    }
}

- (void)stableSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (page == self.currentPage) return;

    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [PACC.shared applyHeaderMaterialHidden:(page == 1) forOverlay:overlay];
    [PACC.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        if (page == 1) [player fadeIn];
        else [player fadeOut];
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && page == 2) [promo refreshFact];

    [PACC.shared syncModuleVisibilityForOverlay:overlay animated:YES];

    CATransform3D target = collection.view.layer.sublayerTransform;
    target.m41 = 0.0;
    target.m42 = -(CGFloat)page * span;
    target.m43 = 0.0;

    gPageAnimating = YES;
    [UIView animateWithDuration:0.35 animations:^{
        collection.view.layer.sublayerTransform = target;
    } completion:^(BOOL finished) {
        gPageAnimating = NO;
    }];

    [self layoutButtons];

    [self pulseCurrentButton];
}

- (void)experimentalSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (self.transitionActive || self.scrubbingActive) return;
    if (page == self.currentPage) return;

    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [PACC.shared applyHeaderMaterialHidden:(page == 1) forOverlay:overlay];
    [PACC.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();

    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)page * span, 0.0);
    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;

    [collection.view.layer removeAnimationForKey:@"PAnimPageSlide"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    [CATransaction commit];

    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
    slide.fromValue = [NSValue valueWithCATransform3D:fromSub];
    slide.toValue   = [NSValue valueWithCATransform3D:toSub];
    slide.duration = 0.52;
    slide.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];
    [collection.view.layer addAnimation:slide forKey:@"PAnimPageSlide"];

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = (page == 1) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && page == 2) [promo refreshFact];

    [PACC.shared syncModuleVisibilityForOverlay:overlay animated:YES];
    [self layoutButtons];

    [self pulseCurrentButton];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.suspendedForLandscape) return NO;
    if (!gExperimentalPagingEnabled) return NO;
    if (gestureRecognizer == self.panRecognizer) {
        if (!gPagingEnabled || self.pageCount <= 1) return NO;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self];
        return fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

@end