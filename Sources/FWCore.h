// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

extern NSString * const FWConfigDidChangeNotification;

typedef NS_ENUM(NSInteger, FWScaleMode) {
    FWScaleModeFill = 0,
    FWScaleModeFit = 1,
    FWScaleModeStretch = 2
};

typedef NS_ENUM(NSInteger, FWRotationMode) {
    FWRotationModeInterval = 0,
    FWRotationModeMediaLength = 1,
    FWRotationModeManual = 2
};

FOUNDATION_EXPORT NSString *FWFormatInterval(double seconds);
FOUNDATION_EXPORT NSString *FWFormatResolution(CGSize size);
FOUNDATION_EXPORT NSString *FWDisplayIdentifierForScreen(NSScreen *screen);
FOUNDATION_EXPORT CGSize FWDisplayPixelSize(NSScreen *screen);

#pragma mark - 媒体条目

@interface FWMediaItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign, getter=isVideo) BOOL video;
+ (instancetype)itemWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
@property (nonatomic, readonly) NSString *fileName;
@property (nonatomic, readonly) NSString *folderName;
@property (nonatomic, readonly) NSURL *fileURL;
@property (nonatomic, readonly) BOOL exists;
@end

#pragma mark - 媒体工具

@interface FWMedia : NSObject
+ (BOOL)isSupportedPath:(NSString *)path;
+ (BOOL)isVideoPath:(NSString *)path;
+ (NSArray<NSString *> *)collectFromDirectory:(NSString *)dir limit:(NSUInteger)limit;
+ (NSArray<NSDictionary *> *)validatePaths:(NSArray<NSString *> *)paths
                                rejected:(NSArray<NSString *> **)rejected;
@end

#pragma mark - 图片缓存加载

@interface FWImageBox : NSObject
@property (nonatomic, readonly) CGImageRef cgImage;
+ (instancetype)boxWithImage:(CGImageRef)image;
@end

@interface FWImageLoader : NSObject
+ (instancetype)shared;
+ (CGImageRef)newDownsampledImageAtPath:(NSString *)path maxPixel:(NSInteger)maxPixel;
- (FWImageBox *)cachedImageForPath:(NSString *)path maxPixel:(NSInteger)maxPixel;
- (void)loadImageForPath:(NSString *)path
                maxPixel:(NSInteger)maxPixel
              completion:(void (^)(FWImageBox *box))completion;
- (void)prefetchPath:(NSString *)path maxPixel:(NSInteger)maxPixel;
- (void)clearCache;

+ (NSImage *)thumbnailForPath:(NSString *)path video:(BOOL)isVideo maxPixel:(CGFloat)maxPixel;
@end

#pragma mark - 配置存储

@interface FWConfigStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSString *configPath;
@property (nonatomic, readonly) NSMutableDictionary *root;
@property (nonatomic, readonly) BOOL isFirstLaunch;

- (NSMutableDictionary *)displayDict:(NSString *)key;
- (BOOL)hasDisplay:(NSString *)key;
- (void)ensureDisplay:(NSString *)key name:(NSString *)name;

- (NSArray<NSDictionary *> *)itemsForDisplay:(NSString *)key;
- (void)setItems:(NSArray<NSDictionary *> *)items forDisplay:(NSString *)key;
- (void)addItems:(NSArray<NSDictionary *> *)items toDisplay:(NSString *)key;
- (void)removeItemAtIndex:(NSInteger)index display:(NSString *)key;
- (void)moveItemFrom:(NSInteger)from to:(NSInteger)to display:(NSString *)key;
- (void)clearItemsForDisplay:(NSString *)key;
- (void)shuffleItemsForDisplay:(NSString *)key;
- (NSInteger)cursorForDisplay:(NSString *)key;
- (void)setCursor:(NSInteger)cursor display:(NSString *)key;

- (NSInteger)scaleModeForDisplay:(NSString *)key;
- (void)setScaleMode:(NSInteger)mode display:(NSString *)key;
- (NSInteger)rotationModeForDisplay:(NSString *)key;
- (void)setRotationMode:(NSInteger)mode display:(NSString *)key;
- (BOOL)shuffleForDisplay:(NSString *)key;
- (void)setShuffle:(BOOL)shuffle display:(NSString *)key;
- (BOOL)enabledForDisplay:(NSString *)key;
- (void)setEnabled:(BOOL)enabled display:(NSString *)key;
- (BOOL)hasIntervalOverride:(NSString *)key;
- (void)setHasIntervalOverride:(BOOL)has value:(double)value display:(NSString *)key;
- (double)effectiveIntervalForDisplay:(NSString *)key;

@property (nonatomic, assign) double defaultInterval;
@property (nonatomic, assign) double fadeDuration;
@property (nonatomic, assign) BOOL rotationEnabled;
@property (nonatomic, assign) BOOL launchAtLogin;
@property (nonatomic, assign) BOOL pauseWhenCovered;

- (NSUInteger)totalItemCount;
- (void)save;
@end

#pragma mark - 界面小工具

@interface FWTagLabel : NSView
+ (instancetype)tagWithText:(NSString *)text color:(NSColor *)color;
- (void)setTagText:(NSString *)text color:(NSColor *)color;
@end

@interface FWCardView : NSView
@end

/// 用语义色填充的背景视图：切换深浅色时自动重绘（layer.backgroundColor 存的是固定 CGColor，不会跟随外观）
@interface FWColorView : NSView
+ (instancetype)viewWithColor:(NSColor *)color;
@property (nonatomic, strong) NSColor *fillColor;
@end
