// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import <Cocoa/Cocoa.h>
#import "FWCore.h"

#pragma mark - 桌面窗口

@class FWSurfaceView;

@interface FWWallpaperWindow : NSWindow
@property (nonatomic, strong, readonly) FWSurfaceView *surfaceView;
- (instancetype)initWithScreen:(NSScreen *)screen;
- (void)attachToScreen:(NSScreen *)screen;
@end

#pragma mark - 渲染视图

@interface FWSurfaceView : NSView
@property (nonatomic, readonly) NSString *currentItemID;
@property (nonatomic, readonly) BOOL hasContent;
- (void)showImage:(CGImageRef)image
           itemID:(NSString *)itemID
            scale:(NSInteger)scaleMode
         animated:(BOOL)animated
         duration:(double)duration;
- (void)showVideoAtPath:(NSString *)path
                 itemID:(NSString *)itemID
                  scale:(NSInteger)scaleMode
               animated:(BOOL)animated
               duration:(double)duration;
- (NSString *)playbackState;
- (void)clearSurface;
- (void)setSuspended:(BOOL)suspended;
- (void)updateScaleMode:(NSInteger)mode;
@end

#pragma mark - 单屏控制器

@interface FWDisplayController : NSObject
@property (nonatomic, readonly) NSString *displayKey;
@property (nonatomic, strong, readonly) NSScreen *screen;
@property (nonatomic, readonly) NSString *currentItemName;
@property (nonatomic, readonly) NSString *queueIndexText;
@property (nonatomic, readonly) NSString *debugState;

- (instancetype)initWithKey:(NSString *)key
                     screen:(NSScreen *)screen
                      store:(FWConfigStore *)store;
- (void)applyForce:(BOOL)force;
- (void)updateWithScreen:(NSScreen *)screen;
- (void)reassert;
- (void)tick:(NSDate *)now;
- (void)advanceAnimated:(BOOL)animated;
- (void)showCurrentAnimated:(BOOL)animated;
- (void)setSuspended:(BOOL)suspended;
@end

#pragma mark - 引擎

@interface FWEngine : NSObject
@property (nonatomic, strong, readonly) FWConfigStore *store;
@property (nonatomic, readonly) NSArray<NSDictionary *> *screens;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) BOOL sessionLocked;

- (instancetype)initWithStore:(FWConfigStore *)store;
- (void)start;
- (void)stop;
- (void)reloadScreens;
- (void)applyAll;
- (void)refreshAll;
- (void)reassertAll;
- (void)advanceAll;
- (void)advanceDisplay:(NSString *)key;
- (void)showCurrentForDisplay:(NSString *)key;
- (NSString *)currentItemNameForDisplay:(NSString *)key;
- (NSString *)queueIndexForDisplay:(NSString *)key;
- (void)setPaused:(BOOL)paused;
- (void)togglePaused;
- (NSArray<NSString *> *)playbackStates;
@end
