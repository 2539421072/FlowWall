// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import "FWDisplay.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#pragma mark - 图层槽位

@interface FWSlot : NSObject
@property (nonatomic, strong) CALayer *container;
@property (nonatomic, strong) CALayer *imageLayer;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy) NSString *itemID;
- (void)teardown;
@end

@implementation FWSlot

- (instancetype)init {
    self = [super init];
    if (self) {
        _container = [CALayer layer];
        _container.masksToBounds = YES;
        _container.opacity = 0.0f;
    }
    return self;
}

- (void)teardown {
    [_player pause];
    [_looper disableLooping];
    [_player removeAllItems];
    _playerLayer.player = nil;
    [_playerLayer removeFromSuperlayer];
    [_imageLayer removeFromSuperlayer];
    _imageLayer.contents = nil;
    _playerLayer = nil;
    _imageLayer = nil;
    _player = nil;
    _looper = nil;
    _itemID = nil;
}

@end

#pragma mark - 壁纸窗口

@implementation FWWallpaperWindow

- (instancetype)initWithScreen:(NSScreen *)screen {
    NSRect frame = screen.frame;
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) return nil;

    FWSurfaceView *surface = [[FWSurfaceView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    self.contentView = surface;

    NSWindowLevel level = (NSWindowLevel)(CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) - 1);
    self.level = level;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                              NSWindowCollectionBehaviorStationary |
                              NSWindowCollectionBehaviorIgnoresCycle |
                              NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.backgroundColor = [NSColor blackColor];
    self.opaque = YES;
    self.hasShadow = NO;
    self.ignoresMouseEvents = YES;
    self.movable = NO;
    self.movableByWindowBackground = NO;
    self.releasedWhenClosed = NO;
    self.animationBehavior = NSWindowAnimationBehaviorNone;
    self.excludedFromWindowsMenu = YES;
    self.tabbingMode = NSWindowTabbingModeDisallowed;
    self.titleVisibility = NSWindowTitleHidden;
    self.titlebarAppearsTransparent = YES;
    self.restorable = NO;
    [self setFrame:frame display:NO];
    return self;
}

- (FWSurfaceView *)surfaceView {
    return (FWSurfaceView *)self.contentView;
}

- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

- (void)attachToScreen:(NSScreen *)screen {
    if (!NSEqualRects(self.frame, screen.frame)) {
        [self setFrame:screen.frame display:NO];
    }
    FWSurfaceView *surface = self.surfaceView;
    if (surface) {
        surface.frame = NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height);
        [surface setNeedsLayout:YES];
        [surface layoutSubtreeIfNeeded];
    }
}

@end

#pragma mark - 渲染视图

@implementation FWSurfaceView {
    FWSlot *_slots[2];
    NSInteger _front;
    NSString *_currentItemID;
    BOOL _hasContent;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        CALayer *root = [CALayer layer];
        root.backgroundColor = [NSColor blackColor].CGColor;
        root.masksToBounds = YES;
        self.layer = root;

        _slots[0] = [FWSlot new];
        _slots[1] = [FWSlot new];
        for (int i = 0; i < 2; i++) {
            _slots[i].container.frame = NSMakeRect(0, 0, frameRect.size.width, frameRect.size.height);
            [root addSublayer:_slots[i].container];
        }
        _front = 0;
    }
    return self;
}

- (BOOL)isOpaque { return YES; }
- (BOOL)isFlipped { return NO; }

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self fw_layoutLayers];
}

- (void)layout {
    [super layout];
    [self fw_layoutLayers];
}

- (void)fw_layoutLayers {
    CGRect rect = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < 2; i++) {
        FWSlot *slot = _slots[i];
        slot.container.frame = rect;
        slot.imageLayer.frame = rect;
        slot.playerLayer.frame = rect;
    }
    [CATransaction commit];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    CGFloat scale = self.window.backingScaleFactor;
    for (int i = 0; i < 2; i++) {
        _slots[i].imageLayer.contentsScale = scale;
        _slots[i].playerLayer.contentsScale = scale;
    }
}

- (NSString *)currentItemID { return _currentItemID; }
- (BOOL)hasContent { return _hasContent; }

- (NSString *)gravityForScale:(NSInteger)mode {
    switch (mode) {
        case FWScaleModeFit: return kCAGravityResizeAspect;
        case FWScaleModeStretch: return kCAGravityResize;
        default: return kCAGravityResizeAspectFill;
    }
}

- (AVLayerVideoGravity)videoGravityForScale:(NSInteger)mode {
    switch (mode) {
        case FWScaleModeFit: return AVLayerVideoGravityResizeAspect;
        case FWScaleModeStretch: return AVLayerVideoGravityResize;
        default: return AVLayerVideoGravityResizeAspectFill;
    }
}

- (void)showImage:(CGImageRef)image
           itemID:(NSString *)itemID
            scale:(NSInteger)scaleMode
         animated:(BOOL)animated
         duration:(double)duration {
    if (!image) return;
    FWSlot *incoming = _slots[1 - _front];
    [incoming teardown];

    CALayer *layer = [CALayer layer];
    layer.contents = (__bridge id)image;
    layer.contentsGravity = [self gravityForScale:scaleMode];
    layer.masksToBounds = YES;
    layer.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    layer.contentsScale = self.window.backingScaleFactor;
    [incoming.container addSublayer:layer];
    incoming.imageLayer = layer;
    incoming.itemID = itemID;

    _currentItemID = [itemID copy];
    _hasContent = YES;
    [self commitIncoming:incoming animated:animated duration:duration];
}

- (void)showVideoAtPath:(NSString *)path
                 itemID:(NSString *)itemID
                  scale:(NSInteger)scaleMode
               animated:(BOOL)animated
               duration:(double)duration {
    FWSlot *incoming = _slots[1 - _front];
    [incoming teardown];

    NSURL *url = [NSURL fileURLWithPath:path];
    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
    player.muted = YES;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    player.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;

    AVPlayerItem *templateItem = [AVPlayerItem playerItemWithURL:url];
    templateItem.preferredForwardBufferDuration = 1.0;
    AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:templateItem];

    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.videoGravity = [self videoGravityForScale:scaleMode];
    layer.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    layer.backgroundColor = [NSColor blackColor].CGColor;
    layer.contentsScale = self.window.backingScaleFactor;

    [incoming.container addSublayer:layer];
    incoming.playerLayer = layer;
    incoming.player = player;
    incoming.looper = looper;
    incoming.itemID = itemID;

    _currentItemID = [itemID copy];
    _hasContent = YES;
    [self commitIncoming:incoming animated:animated duration:duration];
    [player play];
}

- (void)commitIncoming:(FWSlot *)incoming animated:(BOOL)animated duration:(double)duration {
    FWSlot *outgoing = _slots[_front];
    CGRect rect = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    incoming.container.frame = rect;
    for (CALayer *l in incoming.container.sublayers) l.frame = rect;
    [CATransaction commit];

    BOOL hasOutgoing = outgoing.container.sublayers.count > 0;
    BOOL shouldAnimate = animated && duration > 0.02 && hasOutgoing;

    if (shouldAnimate) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        incoming.container.opacity = 1.0f;
        [CATransaction commit];

        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        anim.fromValue = @0.0;
        anim.toValue = @1.0;
        anim.duration = duration;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [incoming.container addAnimation:anim forKey:@"fwFadeIn"];

        _front = 1 - _front;
        __weak typeof(self) weakSelf = self;
        __weak FWSlot *weakOutgoing = outgoing;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.03) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            FWSlot *out = weakOutgoing;
            if (!self || !out) return;
            if (self->_slots[self->_front] != out) [out teardown];
        });
    } else {
        _front = 1 - _front;
        [outgoing teardown];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        incoming.container.opacity = 1.0f;
        [CATransaction commit];
    }
}

- (NSString *)playbackState {
    for (int i = 0; i < 2; i++) {
        FWSlot *slot = _slots[i];
        if (slot.player) {
            return [NSString stringWithFormat:@"rate=%.1f readyForDisplay=%@ itemStatus=%ld",
                    slot.player.rate,
                    slot.playerLayer.isReadyForDisplay ? @"YES" : @"NO",
                    (long)slot.player.currentItem.status];
        }
    }
    return @"no-player";
}

- (void)clearSurface {
    for (int i = 0; i < 2; i++) {
        [_slots[i] teardown];
        _slots[i].container.opacity = 0.0f;
    }
    _currentItemID = nil;
    _hasContent = NO;
}

- (void)setSuspended:(BOOL)suspended {
    for (int i = 0; i < 2; i++) {
        AVQueuePlayer *p = _slots[i].player;
        if (!p) continue;
        if (suspended) {
            if (p.rate != 0) [p pause];
        } else {
            if (p.rate == 0) [p play];
        }
    }
}

- (void)updateScaleMode:(NSInteger)mode {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < 2; i++) {
        _slots[i].imageLayer.contentsGravity = [self gravityForScale:mode];
        _slots[i].playerLayer.videoGravity = [self videoGravityForScale:mode];
    }
    [CATransaction commit];
}

@end

#pragma mark - 单屏控制器

@implementation FWDisplayController {
    NSString *_displayKey;
    NSScreen *_screen;
    FWConfigStore *_store;
    FWWallpaperWindow *_window;
    NSString *_signature;
    NSDate *_nextSwitch;
    BOOL _suspended;
    BOOL _covered;
    BOOL _coverScheduled;
    FWMediaItem *_currentItem;
    NSInteger _failedStreak;
    id _occlusionToken;
}

- (instancetype)initWithKey:(NSString *)key
                     screen:(NSScreen *)screen
                      store:(FWConfigStore *)store {
    self = [super init];
    if (self) {
        _displayKey = [key copy];
        _screen = screen;
        _store = store;
        _window = [[FWWallpaperWindow alloc] initWithScreen:screen];
        __weak typeof(self) weakSelf = self;
        _occlusionToken = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSWindowDidChangeOcclusionStateNotification
                        object:_window
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) { [weakSelf occlusionChanged]; }];
    }
    return self;
}

- (void)dealloc {
    if (_occlusionToken) [[NSNotificationCenter defaultCenter] removeObserver:_occlusionToken];
    [_window orderOut:nil];
}

- (NSString *)displayKey { return _displayKey; }
- (NSScreen *)screen { return _screen; }
- (NSString *)currentItemName { return _currentItem.fileName; }

- (NSString *)queueIndexText {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (items.count == 0) return nil;
    NSInteger cursor = MIN(MAX(0, [_store cursorForDisplay:_displayKey]), (NSInteger)items.count - 1);
    return [NSString stringWithFormat:@"%ld / %lu", (long)(cursor + 1), (unsigned long)items.count];
}

- (NSInteger)maxPixelSize {
    NSSize size = _screen.frame.size;
    CGFloat scale = _screen.backingScaleFactor;
    return (NSInteger)llround(MAX(size.width, size.height) * scale);
}

- (NSString *)signatureForItems:(NSArray *)items {
    NSMutableString *s = [NSMutableString string];
    for (NSDictionary *d in items) [s appendFormat:@"%@,", d[@"id"]];
    [s appendFormat:@"|%ld|%d|%d",
        (long)[_store scaleModeForDisplay:_displayKey],
        [_store enabledForDisplay:_displayKey],
        [_store shuffleForDisplay:_displayKey]];
    return s;
}

- (void)applyForce:(BOOL)force {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    BOOL enabled = [_store enabledForDisplay:_displayKey];
    // 队列为空或该屏停用时，撤掉覆盖层，让系统壁纸重新显示
    BOOL shouldShow = enabled && items.count > 0;

    if (shouldShow) {
        if (force || !_window.isVisible) {
            [_window attachToScreen:_screen];
            [_window orderFrontRegardless];
        }
    } else {
        [_window orderOut:nil];
    }

    NSString *sig = [self signatureForItems:items];
    if (!force && _signature && [sig isEqualToString:_signature]) {
        [_window.surfaceView updateScaleMode:[_store scaleModeForDisplay:_displayKey]];
        return;
    }
    _signature = sig;
    [_window.surfaceView updateScaleMode:[_store scaleModeForDisplay:_displayKey]];

    if (!shouldShow) {
        if (items.count == 0) {
            [_window.surfaceView clearSurface];
            _currentItem = nil;
        }
        _nextSwitch = nil;
        return;
    }

    NSInteger idx = [_store cursorForDisplay:_displayKey];
    if (idx < 0 || idx >= (NSInteger)items.count) idx = 0;
    if (_currentItem) {
        for (NSUInteger i = 0; i < items.count; i++) {
            if ([items[i][@"id"] isEqualToString:_currentItem.itemID]) { idx = (NSInteger)i; break; }
        }
    }
    [_store setCursor:idx display:_displayKey];
    [self showIndex:idx animated:NO];
}

- (void)updateWithScreen:(NSScreen *)screen {
    _screen = screen;
    [_window attachToScreen:screen];
    if ([_store enabledForDisplay:_displayKey]) [_window orderFrontRegardless];
}

- (void)reassert {
    if (![_store enabledForDisplay:_displayKey]) return;
    [_window attachToScreen:_screen];
    [_window orderFrontRegardless];
}

- (void)tick:(NSDate *)now {
    if (![_store enabledForDisplay:_displayKey]) return;
    if (!_store.rotationEnabled) return;
    if (_suspended || _covered) return;
    if (!_nextSwitch) return;
    if ([now compare:_nextSwitch] != NSOrderedAscending) {
        [self advanceAnimated:YES];
    }
}

- (void)advanceAnimated:(BOOL)animated {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (items.count == 0) return;
    NSInteger cursor = [_store cursorForDisplay:_displayKey];
    NSInteger idx;
    if ([_store shuffleForDisplay:_displayKey] && items.count > 1) {
        do {
            idx = (NSInteger)arc4random_uniform((uint32_t)items.count);
        } while (idx == cursor);
    } else {
        idx = (cursor + 1) % (NSInteger)items.count;
    }
    [_store setCursor:idx display:_displayKey];
    [self showIndex:idx animated:animated];
}

- (void)showCurrentAnimated:(BOOL)animated {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (items.count == 0) return;
    NSInteger idx = MIN(MAX(0, [_store cursorForDisplay:_displayKey]), (NSInteger)items.count - 1);
    [self showIndex:idx animated:animated];
}

- (void)showIndex:(NSInteger)index animated:(BOOL)animated {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (index < 0 || index >= (NSInteger)items.count) return;

    FWMediaItem *item = [FWMediaItem itemWithDictionary:items[index]];
    _currentItem = item;
    BOOL occl = (_window.occlusionState & NSWindowOcclusionStateVisible) != 0;
    NSLog(@"[FlowWall] %@ -> %@/%lu  %@  (%@, occl=%@)",
          _screen.localizedName, @(index + 1), (unsigned long)items.count,
          item.fileName, item.isVideo ? @"视频" : @"图片", occl ? @"visible" : @"hidden");

    NSInteger scaleMode = [_store scaleModeForDisplay:_displayKey];
    double fade = _store.fadeDuration;
    BOOL animate = animated && _window.surfaceView.hasContent && fade > 0.02;
    __weak typeof(self) weakSelf = self;

    if (!item.isVideo) {
        NSInteger maxPixel = [self maxPixelSize];
        NSString *itemID = item.itemID;
        [[FWImageLoader shared] loadImageForPath:item.path maxPixel:maxPixel completion:^(FWImageBox *box) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (![self->_currentItem.itemID isEqualToString:itemID]) return;
            if (!box) {
                NSLog(@"[FlowWall] 图片解码失败，跳过：%@", item.path);
                [self skipBrokenItem];
                return;
            }
            self->_failedStreak = 0;
            [self->_window.surfaceView showImage:box.cgImage
                                          itemID:itemID
                                           scale:scaleMode
                                        animated:animate
                                        duration:fade];
            [self prefetchAfter:index];
        }];
    } else {
        if (![[NSFileManager defaultManager] fileExistsAtPath:item.path]) {
            NSLog(@"[FlowWall] 视频文件不存在，跳过：%@", item.path);
            [self skipBrokenItem];
            return;
        }
        [_window.surfaceView showVideoAtPath:item.path
                                      itemID:item.itemID
                                       scale:scaleMode
                                    animated:animate
                                    duration:fade];
        [_window.surfaceView setSuspended:(_suspended || _covered)];
        _failedStreak = 0;
    }

    [self scheduleNextForItem:item];
}

- (void)scheduleNextForItem:(FWMediaItem *)item {
    _nextSwitch = nil;
    if (!_store.rotationEnabled) return;
    NSInteger mode = [_store rotationModeForDisplay:_displayKey];
    if (mode == FWRotationModeInterval) {
        _nextSwitch = [NSDate dateWithTimeIntervalSinceNow:[_store effectiveIntervalForDisplay:_displayKey]];
    } else if (mode == FWRotationModeMediaLength && item.isVideo) {
        [self scheduleAfterVideoDuration:item];
    }
}

- (void)scheduleAfterVideoDuration:(FWMediaItem *)item {
    NSString *path = item.path;
    NSString *itemID = item.itemID;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)));
        Float64 seconds = CMTimeGetSeconds(asset.duration);
        if (!isfinite(seconds) || seconds <= 0.1) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (![self->_currentItem.itemID isEqualToString:itemID]) return;
            if ([self->_store rotationModeForDisplay:self->_displayKey] != FWRotationModeMediaLength) return;
            self->_nextSwitch = [NSDate dateWithTimeIntervalSinceNow:seconds + 0.15];
        });
    });
}

- (void)skipBrokenItem {
    _failedStreak += 1;
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (items.count == 0 || _failedStreak > (NSInteger)items.count) return;
    NSInteger idx = ([_store cursorForDisplay:_displayKey] + 1) % (NSInteger)items.count;
    [_store setCursor:idx display:_displayKey];
    [self showIndex:idx animated:NO];
}

- (void)prefetchAfter:(NSInteger)index {
    NSArray *items = [_store itemsForDisplay:_displayKey];
    if (items.count < 2) return;
    NSDictionary *next = items[(index + 1) % (NSInteger)items.count];
    if ([next[@"kind"] isEqualToString:@"image"]) {
        [[FWImageLoader shared] prefetchPath:next[@"path"] maxPixel:[self maxPixelSize]];
    }
}

- (void)setSuspended:(BOOL)suspended {
    if (_suspended == suspended) return;
    _suspended = suspended;
    [_window.surfaceView setSuspended:(_suspended || _covered || ![_store enabledForDisplay:_displayKey])];
}

- (void)occlusionChanged {
    if (!_store.pauseWhenCovered || ![_store enabledForDisplay:_displayKey]) {
        _covered = NO;
        _coverScheduled = NO;
        [_window.surfaceView setSuspended:_suspended];
        return;
    }
    BOOL visible = (_window.occlusionState & NSWindowOcclusionStateVisible) != 0;
    if (visible) {
        _coverScheduled = NO;
        if (_covered) {
            _covered = NO;
            [_window.surfaceView setSuspended:_suspended];
        }
    } else {
        if (_coverScheduled || _covered) return;
        _coverScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !self->_coverScheduled) return;
            self->_covered = YES;
            [self->_window.surfaceView setSuspended:YES];
        });
    }
}

- (NSString *)playbackState {
    return [_window.surfaceView playbackState];
}

- (NSString *)debugState {
    BOOL visible = (_window.occlusionState & NSWindowOcclusionStateVisible) != 0;
    return [NSString stringWithFormat:@"%@ [%@] shown=%d item=%@ suspended=%d covered=%d",
            _screen.localizedName, visible ? @"visible" : @"occluded",
            _window.isVisible ? 1 : 0, _currentItem.fileName ?: @"-", _suspended, _covered];
}

@end

#pragma mark - 引擎

@implementation FWEngine {
    NSMutableDictionary<NSString *, FWDisplayController *> *_controllers;
    NSArray<NSDictionary *> *_screens;
    NSTimer *_timer;
    BOOL _paused;
    BOOL _sessionLocked;
    BOOL _screensAsleep;
    NSMutableArray *_observerTokens;
}

- (instancetype)initWithStore:(FWConfigStore *)store {
    self = [super init];
    if (self) {
        _store = store;
        _controllers = [NSMutableDictionary dictionary];
        _screens = @[];
        _observerTokens = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSDictionary *> *)screens { return _screens; }
- (BOOL)paused { return _paused; }
- (BOOL)sessionLocked { return _sessionLocked; }

- (void)start {
    [self reloadScreens];
    [self applyAll];
    [self startTimer];
    [self observeSystem];
    NSLog(@"[FlowWall] 引擎启动，显示器 %lu 台", (unsigned long)_screens.count);
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
    for (id token in _observerTokens) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:token];
        [[NSDistributedNotificationCenter defaultCenter] removeObserver:token];
    }
    [_observerTokens removeAllObjects];
}

- (void)startTimer {
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf tick];
    }];
    timer.tolerance = 0.25;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    _timer = timer;
}

- (void)tick {
    if (_paused) return;
    NSDate *now = [NSDate date];
    for (FWDisplayController *c in _controllers.allValues) {
        [c tick:now];
    }
}

- (void)observeSystem {
    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSNotificationCenter *wnc = ws.notificationCenter;

    [_observerTokens addObject:[nc addObserverForName:FWConfigDidChangeNotification
                                               object:nil queue:[NSOperationQueue mainQueue]
                                           usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self applyAll];
    }]];

    [_observerTokens addObject:[nc addObserverForName:NSApplicationDidChangeScreenParametersNotification
                                               object:nil queue:[NSOperationQueue mainQueue]
                                           usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self reloadScreens];
        [self applyAll];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reassertAll];
        });
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceScreensDidSleepNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_screensAsleep = YES;
        [self updateSuspension];
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceScreensDidWakeNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_screensAsleep = NO;
        [self updateSuspension];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reassertAll];
        });
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceSessionDidResignActiveNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_sessionLocked = YES;
        [self updateSuspension];
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceSessionDidBecomeActiveNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_sessionLocked = NO;
        [self updateSuspension];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reassertAll];
        });
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reassertAll];
        });
    }]];

    [_observerTokens addObject:[wnc addObserverForName:NSWorkspaceDidWakeNotification
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reassertAll];
        });
    }]];

    NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
    [_observerTokens addObject:[dnc addObserverForName:@"com.apple.screenIsLocked"
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_sessionLocked = YES;
        [self updateSuspension];
    }]];
    [_observerTokens addObject:[dnc addObserverForName:@"com.apple.screenIsUnlocked"
                                                object:nil queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification *n) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_sessionLocked = NO;
        [self updateSuspension];
    }]];
}

- (void)updateSuspension {
    BOOL suspend = _sessionLocked || _screensAsleep;
    for (FWDisplayController *c in _controllers.allValues) {
        [c setSuspended:suspend];
    }
}

- (void)reloadScreens {
    NSArray<NSScreen *> *live = [NSScreen screens];
    NSMutableSet *used = [NSMutableSet set];
    NSMutableArray *infos = [NSMutableArray array];
    NSMutableDictionary *next = [NSMutableDictionary dictionary];

    for (NSScreen *screen in live) {
        NSString *key = FWDisplayIdentifierForScreen(screen);
        if ([used containsObject:key]) {
            NSInteger n = 2;
            while ([used containsObject:[NSString stringWithFormat:@"%@#%ld", key, (long)n]]) n++;
            key = [NSString stringWithFormat:@"%@#%ld", key, (long)n];
        }
        [used addObject:key];
        [_store ensureDisplay:key name:screen.localizedName];

        CGSize pixel = FWDisplayPixelSize(screen);
        [infos addObject:@{
            @"key": key,
            @"name": screen.localizedName ?: @"显示器",
            @"width": @(NSWidth(screen.frame)),
            @"height": @(NSHeight(screen.frame)),
            @"pixelWidth": @(pixel.width),
            @"pixelHeight": @(pixel.height),
            @"scale": @(screen.backingScaleFactor),
            @"isMain": @(screen == [NSScreen mainScreen])
        }];

        FWDisplayController *existing = _controllers[key];
        if (existing) {
            [existing updateWithScreen:screen];
            next[key] = existing;
        } else {
            next[key] = [[FWDisplayController alloc] initWithKey:key screen:screen store:_store];
        }
    }

    for (NSString *key in _controllers.allKeys) {
        if (!next[key]) {
            [_controllers[key] setSuspended:YES];
            NSLog(@"[FlowWall] 显示器已断开: %@", [key substringToIndex:MIN(8u, key.length)]);
        }
    }

    _controllers = next;
    _screens = infos;
}

- (void)applyAll {
    for (FWDisplayController *c in _controllers.allValues) [c applyForce:NO];
}

- (void)refreshAll {
    for (FWDisplayController *c in _controllers.allValues) [c applyForce:YES];
}

- (void)reassertAll {
    for (FWDisplayController *c in _controllers.allValues) [c reassert];
}

- (void)advanceAll {
    for (FWDisplayController *c in _controllers.allValues) [c advanceAnimated:YES];
}

- (void)advanceDisplay:(NSString *)key {
    [_controllers[key] advanceAnimated:YES];
}

- (void)showCurrentForDisplay:(NSString *)key {
    [_controllers[key] showCurrentAnimated:NO];
}

- (NSString *)currentItemNameForDisplay:(NSString *)key {
    return [_controllers[key] currentItemName];
}

- (NSString *)queueIndexForDisplay:(NSString *)key {
    return [_controllers[key] queueIndexText];
}

- (void)setPaused:(BOOL)paused {
    if (_paused == paused) return;
    _paused = paused;
    NSLog(@"[FlowWall] 轮换%@", paused ? @"暂停" : @"继续");
}

- (void)togglePaused { [self setPaused:!_paused]; }

- (NSArray<NSString *> *)playbackStates {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in _controllers.allKeys) {
        [result addObject:[NSString stringWithFormat:@"%@: %@ | %@", _controllers[key].screen.localizedName,
                           [_controllers[key] playbackState], [_controllers[key] debugState]]];
    }
    return result;
}

@end
