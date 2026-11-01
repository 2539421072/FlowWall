// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import "FWCore.h"
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

NSString * const FWConfigDidChangeNotification = @"FWConfigDidChangeNotification";

#pragma mark - 格式化

NSString *FWFormatInterval(double seconds) {
    NSInteger s = (NSInteger)llround(seconds);
    if (s < 60) return [NSString stringWithFormat:@"%ld 秒", (long)s];
    if (s % 3600 == 0) return [NSString stringWithFormat:@"%ld 小时", (long)(s / 3600)];
    if (s % 60 == 0) return [NSString stringWithFormat:@"%ld 分钟", (long)(s / 60)];
    return [NSString stringWithFormat:@"%ld 分 %ld 秒", (long)(s / 60), (long)(s % 60)];
}

NSString *FWFormatResolution(CGSize size) {
    return [NSString stringWithFormat:@"%.0f × %.0f", size.width, size.height];
}

NSString *FWDisplayIdentifierForScreen(NSScreen *screen) {
    NSNumber *num = screen.deviceDescription[@"NSScreenNumber"];
    if (num) {
        CGDirectDisplayID displayID = (CGDirectDisplayID)[num unsignedIntValue];
        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
        if (uuid) {
            CFStringRef s = CFUUIDCreateString(NULL, uuid);
            NSString *result = [(__bridge NSString *)s lowercaseString];
            if (s) CFRelease(s);
            CFRelease(uuid);
            if (result.length) return result;
        }
        return [NSString stringWithFormat:@"display-%u", (unsigned)displayID];
    }
    return [@"screen-" stringByAppendingString:screen.localizedName ?: @"unknown"];
}

CGSize FWDisplayPixelSize(NSScreen *screen) {
    CGFloat scale = screen.backingScaleFactor;
    return CGSizeMake(NSWidth(screen.frame) * scale, NSHeight(screen.frame) * scale);
}

#pragma mark - FWMediaItem

@implementation FWMediaItem

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    FWMediaItem *item = [FWMediaItem new];
    item.itemID = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
    item.path = dict[@"path"] ?: @"";
    item.video = [dict[@"kind"] isEqualToString:@"video"];
    return item;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.itemID ?: [[NSUUID UUID] UUIDString],
        @"path": self.path ?: @"",
        @"kind": self.video ? @"video" : @"image"
    };
}

- (NSString *)fileName { return self.path.lastPathComponent ?: @""; }
- (NSString *)folderName { return self.path.stringByDeletingLastPathComponent.lastPathComponent ?: @""; }
- (NSURL *)fileURL { return [NSURL fileURLWithPath:self.path]; }
- (BOOL)exists { return [[NSFileManager defaultManager] fileExistsAtPath:self.path]; }

@end

#pragma mark - FWMedia

static NSSet *FWImageExtensions(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"tif", @"tiff",
                                    @"bmp", @"gif", @"webp", @"avif", @"jp2"]];
    });
    return set;
}

static NSSet *FWVideoExtensions(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"mov", @"mp4", @"m4v", @"mpg", @"mpeg", @"3gp", @"ts"]];
    });
    return set;
}

@implementation FWMedia

+ (BOOL)isSupportedPath:(NSString *)path {
    return [self isVideoPath:path] || [FWImageExtensions() containsObject:path.pathExtension.lowercaseString];
}

+ (BOOL)isVideoPath:(NSString *)path {
    return [FWVideoExtensions() containsObject:path.pathExtension.lowercaseString];
}

+ (NSArray<NSString *> *)collectFromDirectory:(NSString *)dir limit:(NSUInteger)limit {
    NSMutableArray *result = [NSMutableArray array];
    NSURL *url = [NSURL fileURLWithPath:dir];
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtURL:url
                                                   includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                                                                 errorHandler:nil];
    for (NSURL *u in e) {
        if (result.count >= limit) break;
        if (![self isSupportedPath:u.path]) continue;
        NSNumber *isReg = nil;
        [u getResourceValue:&isReg forKey:NSURLIsRegularFileKey error:NULL];
        if (isReg.boolValue) [result addObject:u.path];
    }
    [result sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];
    return result;
}

+ (BOOL)canDecodeImagePath:(NSString *)path {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) return NO;
    BOOL ok = CGImageSourceGetCount(src) > 0;
    CFRelease(src);
    return ok;
}

+ (BOOL)canPlayVideoPath:(NSString *)path {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"playable", @"tracks"] completionHandler:^{
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    BOOL playable = asset.isPlayable;
    BOOL hasVideo = [[asset tracksWithMediaType:AVMediaTypeVideo] count] > 0;
    return playable && hasVideo;
}

+ (NSArray<NSDictionary *> *)validatePaths:(NSArray<NSString *> *)paths
                                rejected:(NSArray<NSString *> **)rejected {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableArray *bad = [NSMutableArray array];
    for (NSString *path in paths) {
        BOOL isVideo = [self isVideoPath:path];
        if (!isVideo && ![FWImageExtensions() containsObject:path.pathExtension.lowercaseString]) {
            [bad addObject:path];
            continue;
        }
        BOOL ok = isVideo ? [self canPlayVideoPath:path] : [self canDecodeImagePath:path];
        if (!ok) {
            [bad addObject:path];
            continue;
        }
        FWMediaItem *item = [FWMediaItem new];
        item.itemID = [[NSUUID UUID] UUIDString];
        item.path = path;
        item.video = isVideo;
        [items addObject:[item dictionaryRepresentation]];
    }
    if (rejected) *rejected = bad;
    return items;
}

@end

#pragma mark - FWImageBox / FWImageLoader

@implementation FWImageBox {
    CGImageRef _image;
}

+ (instancetype)boxWithImage:(CGImageRef)image {
    FWImageBox *box = [FWImageBox new];
    box->_image = image ? CGImageRetain(image) : NULL;
    return box;
}

- (CGImageRef)cgImage { return _image; }

- (void)dealloc {
    if (_image) CGImageRelease(_image);
}

@end

@implementation FWImageLoader {
    NSCache *_cache;
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static FWImageLoader *loader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loader = [FWImageLoader new]; });
    return loader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSCache new];
        _cache.countLimit = 12;
        _cache.totalCostLimit = 320 * 1024 * 1024;
        _queue = dispatch_queue_create("flowwall.image.decode", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

+ (CGImageRef)newDownsampledImageAtPath:(NSString *)path maxPixel:(NSInteger)maxPixel {
    NSDictionary *srcOpts = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                      (__bridge CFDictionaryRef)srcOpts);
    if (!src) return NULL;
    NSDictionary *opts = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(64, maxPixel)),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    return image;
}

- (NSString *)cacheKey:(NSString *)path maxPixel:(NSInteger)px {
    return [NSString stringWithFormat:@"%@|%ld", path, (long)px];
}

- (FWImageBox *)cachedImageForPath:(NSString *)path maxPixel:(NSInteger)maxPixel {
    return [_cache objectForKey:[self cacheKey:path maxPixel:maxPixel]];
}

- (void)loadImageForPath:(NSString *)path
                maxPixel:(NSInteger)maxPixel
              completion:(void (^)(FWImageBox *box))completion {
    FWImageBox *hit = [self cachedImageForPath:path maxPixel:maxPixel];
    if (hit) { completion(hit); return; }
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        CGImageRef cg = [FWImageLoader newDownsampledImageAtPath:path maxPixel:maxPixel];
        FWImageBox *box = cg ? [FWImageBox boxWithImage:cg] : nil;
        if (cg) {
            size_t cost = CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg);
            CFRelease(cg);
            if (box) [self->_cache setObject:box forKey:[self cacheKey:path maxPixel:maxPixel] cost:cost];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(box); });
    });
}

- (void)prefetchPath:(NSString *)path maxPixel:(NSInteger)maxPixel {
    if ([self cachedImageForPath:path maxPixel:maxPixel]) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        CGImageRef cg = [FWImageLoader newDownsampledImageAtPath:path maxPixel:maxPixel];
        if (!cg) return;
        FWImageBox *box = [FWImageBox boxWithImage:cg];
        size_t cost = CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg);
        CFRelease(cg);
        [self->_cache setObject:box forKey:[self cacheKey:path maxPixel:maxPixel] cost:cost];
    });
}

- (void)clearCache { [_cache removeAllObjects]; }

+ (NSImage *)thumbnailForPath:(NSString *)path video:(BOOL)isVideo maxPixel:(CGFloat)maxPixel {
    if (!isVideo) {
        CGImageRef cg = [self newDownsampledImageAtPath:path maxPixel:(NSInteger)maxPixel];
        if (!cg) return nil;
        NSImage *img = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(CGImageGetWidth(cg), CGImageGetHeight(cg))];
        CGImageRelease(cg);
        return img;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(maxPixel, maxPixel);
    gen.requestedTimeToleranceBefore = CMTimeMake(1, 1);
    gen.requestedTimeToleranceAfter = CMTimeMake(1, 1);
    CGImageRef cg = NULL;
    NSError *err = nil;
    cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(1.2, 600) actualTime:NULL error:&err];
    if (!cg) cg = [gen copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&err];
    if (!cg) return nil;
    NSImage *img = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(CGImageGetWidth(cg), CGImageGetHeight(cg))];
    CGImageRelease(cg);
    return img;
}

@end

#pragma mark - FWConfigStore

@implementation FWConfigStore {
    NSMutableDictionary *_root;
    NSUInteger _saveGeneration;
    BOOL _firstLaunch;
}

+ (instancetype)shared {
    static FWConfigStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [FWConfigStore new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *base = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSString *basePath = base.path;
        if (!basePath) basePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
        NSString *dir = [basePath stringByAppendingPathComponent:@"FlowWall"];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        _configPath = [dir stringByAppendingPathComponent:@"config.json"];

        NSDictionary *defaults = @{
            @"displays": [NSMutableDictionary dictionary],
            @"defaultInterval": @(30),
            @"fadeDuration": @(0.6),
            @"rotationEnabled": @(YES),
            @"launchAtLogin": @(NO),
            @"pauseWhenCovered": @(YES)
        };
        NSData *data = [NSData dataWithContentsOfFile:_configPath];
        if (data) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
            if ([obj isKindOfClass:[NSMutableDictionary class]]) {
                _root = obj;
                for (NSString *k in defaults) {
                    if (!_root[k]) _root[k] = defaults[k];
                }
                if (![_root[@"displays"] isKindOfClass:[NSMutableDictionary class]]) {
                    _root[@"displays"] = [NSMutableDictionary dictionary];
                }
            }
        }
        if (!_root) {
            _root = [defaults mutableCopy];
            _firstLaunch = YES;
        }
        NSLog(@"[FlowWall] 配置路径: %@", _configPath);
    }
    return self;
}

- (NSMutableDictionary *)root { return _root; }
- (BOOL)isFirstLaunch { return _firstLaunch; }

- (NSMutableDictionary *)displayDict:(NSString *)key {
    NSMutableDictionary *displays = _root[@"displays"];
    NSMutableDictionary *d = displays[key];
    if (![d isKindOfClass:[NSMutableDictionary class]]) {
        d = [@{
            @"id": key,
            @"name": @"",
            @"items": [NSMutableArray array],
            @"cursor": @0,
            @"scaleMode": @(FWScaleModeFill),
            @"rotationMode": @(FWRotationModeInterval),
            @"shuffle": @NO,
            @"enabled": @YES
        } mutableCopy];
        displays[key] = d;
    }
    if (![d[@"items"] isKindOfClass:[NSMutableArray class]]) d[@"items"] = [NSMutableArray array];
    return d;
}

- (BOOL)hasDisplay:(NSString *)key {
    return _root[@"displays"][key] != nil;
}

- (void)ensureDisplay:(NSString *)key name:(NSString *)name {
    NSMutableDictionary *d = [self displayDict:key];
    if (name.length && (!d[@"name"] || [d[@"name"] length] == 0)) {
        d[@"name"] = name;
        [self notifyChange];
    }
}

- (void)notifyChange {
    [self scheduleSave];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FWConfigDidChangeNotification object:self];
    });
}

#pragma mark 队列

- (NSArray<NSDictionary *> *)itemsForDisplay:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    return [(NSArray *)d[@"items"] copy];
}

- (void)setItems:(NSArray<NSDictionary *> *)items forDisplay:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    d[@"items"] = [items mutableCopy];
    NSInteger cursor = [d[@"cursor"] integerValue];
    if (items.count == 0) cursor = 0;
    else if (cursor >= (NSInteger)items.count) cursor = (NSInteger)items.count - 1;
    d[@"cursor"] = @(MAX(0, cursor));
    [self notifyChange];
}

- (void)addItems:(NSArray<NSDictionary *> *)items toDisplay:(NSString *)key {
    if (items.count == 0) return;
    NSMutableDictionary *d = [self displayDict:key];
    NSMutableArray *arr = d[@"items"];
    NSMutableSet *existing = [NSMutableSet set];
    for (NSDictionary *it in arr) {
        if (it[@"path"]) [existing addObject:it[@"path"]];
    }
    for (NSDictionary *it in items) {
        NSString *p = it[@"path"];
        if (!p || [existing containsObject:p]) continue;
        [existing addObject:p];
        [arr addObject:it];
    }
    [self notifyChange];
}

- (void)removeItemAtIndex:(NSInteger)index display:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    NSMutableArray *arr = d[@"items"];
    if (index < 0 || index >= (NSInteger)arr.count) return;
    [arr removeObjectAtIndex:index];
    NSInteger cursor = [d[@"cursor"] integerValue];
    if (index < cursor) cursor -= 1;
    if (arr.count == 0) cursor = 0;
    if (cursor >= (NSInteger)arr.count) cursor = (NSInteger)arr.count - 1;
    d[@"cursor"] = @(MAX(0, cursor));
    [self notifyChange];
}

- (void)moveItemFrom:(NSInteger)from to:(NSInteger)to display:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    NSMutableArray *arr = d[@"items"];
    if (from < 0 || from >= (NSInteger)arr.count) return;
    NSInteger target = to;
    if (target > from) target -= 1;
    if (target < 0) target = 0;
    if (target >= (NSInteger)arr.count) target = (NSInteger)arr.count - 1;
    if (target == from) return;
    id obj = arr[from];
    [arr removeObjectAtIndex:from];
    [arr insertObject:obj atIndex:target];
    d[@"cursor"] = @(0);
    [self notifyChange];
}

- (void)clearItemsForDisplay:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    [d[@"items"] removeAllObjects];
    d[@"cursor"] = @0;
    [self notifyChange];
}

- (void)shuffleItemsForDisplay:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    NSMutableArray *arr = d[@"items"];
    for (NSInteger i = (NSInteger)arr.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [arr exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    d[@"cursor"] = @0;
    [self notifyChange];
}

- (NSInteger)cursorForDisplay:(NSString *)key {
    return [[self displayDict:key][@"cursor"] integerValue];
}

- (void)setCursor:(NSInteger)cursor display:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    if ([d[@"cursor"] integerValue] == cursor) return;
    d[@"cursor"] = @(cursor);
    [self notifyChange];
}

#pragma mark 属性

- (NSInteger)integerForKey:(NSString *)k display:(NSString *)key def:(NSInteger)def {
    id v = [self displayDict:key][k];
    return v ? [v integerValue] : def;
}

- (void)setInteger:(NSInteger)v forKey:(NSString *)k display:(NSString *)key {
    [self displayDict:key][k] = @(v);
    [self notifyChange];
}

- (NSInteger)scaleModeForDisplay:(NSString *)key { return [self integerForKey:@"scaleMode" display:key def:FWScaleModeFill]; }
- (void)setScaleMode:(NSInteger)mode display:(NSString *)key { [self setInteger:mode forKey:@"scaleMode" display:key]; }
- (NSInteger)rotationModeForDisplay:(NSString *)key { return [self integerForKey:@"rotationMode" display:key def:FWRotationModeInterval]; }
- (void)setRotationMode:(NSInteger)mode display:(NSString *)key { [self setInteger:mode forKey:@"rotationMode" display:key]; }
- (BOOL)shuffleForDisplay:(NSString *)key { return [self integerForKey:@"shuffle" display:key def:0] != 0; }
- (void)setShuffle:(BOOL)shuffle display:(NSString *)key { [self setInteger:shuffle ? 1 : 0 forKey:@"shuffle" display:key]; }
- (BOOL)enabledForDisplay:(NSString *)key { return [self integerForKey:@"enabled" display:key def:1] != 0; }
- (void)setEnabled:(BOOL)enabled display:(NSString *)key { [self setInteger:enabled ? 1 : 0 forKey:@"enabled" display:key]; }

- (BOOL)hasIntervalOverride:(NSString *)key {
    return [self displayDict:key][@"intervalOverride"] != nil;
}

- (void)setHasIntervalOverride:(BOOL)has value:(double)value display:(NSString *)key {
    NSMutableDictionary *d = [self displayDict:key];
    if (has) d[@"intervalOverride"] = @(MAX(5, value));
    else [d removeObjectForKey:@"intervalOverride"];
    [self notifyChange];
}

- (double)effectiveIntervalForDisplay:(NSString *)key {
    id v = [self displayDict:key][@"intervalOverride"];
    double interval = v ? [v doubleValue] : self.defaultInterval;
    return MAX(1, interval);
}

- (double)defaultInterval { return [_root[@"defaultInterval"] doubleValue]; }
- (void)setDefaultInterval:(double)v { _root[@"defaultInterval"] = @(v); [self notifyChange]; }

- (double)fadeDuration { return [_root[@"fadeDuration"] doubleValue]; }
- (void)setFadeDuration:(double)v { _root[@"fadeDuration"] = @(v); [self notifyChange]; }

- (BOOL)rotationEnabled { return [_root[@"rotationEnabled"] boolValue]; }
- (void)setRotationEnabled:(BOOL)v { _root[@"rotationEnabled"] = @(v); [self notifyChange]; }

- (BOOL)launchAtLogin { return [_root[@"launchAtLogin"] boolValue]; }
- (void)setLaunchAtLogin:(BOOL)v { _root[@"launchAtLogin"] = @(v); [self notifyChange]; }

- (BOOL)pauseWhenCovered { return [_root[@"pauseWhenCovered"] boolValue]; }
- (void)setPauseWhenCovered:(BOOL)v { _root[@"pauseWhenCovered"] = @(v); [self notifyChange]; }

- (NSUInteger)totalItemCount {
    NSUInteger total = 0;
    for (NSDictionary *d in [_root[@"displays"] allValues]) {
        total += [(NSArray *)d[@"items"] count];
    }
    return total;
}

#pragma mark 存储

- (void)scheduleSave {
    _saveGeneration++;
    NSUInteger gen = _saveGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || gen != self->_saveGeneration) return;
        [self save];
    });
}

- (void)save {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:_root
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&err];
    if (!data) {
        NSLog(@"[FlowWall] 配置序列化失败: %@", err);
        return;
    }
    if (![data writeToFile:_configPath atomically:YES]) {
        NSLog(@"[FlowWall] 配置写入失败: %@", _configPath);
    }
}

@end

#pragma mark - 界面小工具

@implementation FWTagLabel {
    NSAttributedString *_attr;
    NSColor *_tint;
}

+ (instancetype)tagWithText:(NSString *)text color:(NSColor *)color {
    FWTagLabel *label = [FWTagLabel new];
    [label setTagText:text color:color];
    return label;
}

- (void)setTagText:(NSString *)text color:(NSColor *)color {
    _tint = color ?: [NSColor secondaryLabelColor];
    _attr = [[NSAttributedString alloc] initWithString:text ?: @""
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: _tint
        }];
    self.wantsLayer = YES;
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize {
    NSSize s = _attr.size;
    return NSMakeSize(ceil(s.width) + 12, ceil(s.height) + 4);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:5 yRadius:5];
    [[_tint colorWithAlphaComponent:0.12] setFill];
    [path fill];
    NSSize s = _attr.size;
    NSRect textRect = NSMakeRect(6, (NSHeight(self.bounds) - s.height) / 2.0, s.width, s.height);
    [_attr drawInRect:textRect];
}

@end

@implementation FWCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        [self updateColors];
    }
    return self;
}

- (void)updateColors {
    self.layer.backgroundColor = [NSColor.controlBackgroundColor CGColor];
    self.layer.borderColor = [[NSColor labelColor] colorWithAlphaComponent:0.08].CGColor;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                        xRadius:12 yRadius:12];
    [[NSColor controlBackgroundColor] setFill];
    [path fill];
    [[[NSColor labelColor] colorWithAlphaComponent:0.08] setStroke];
    path.lineWidth = 1;
    [path stroke];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self fw_refreshLayerColors];
}

- (void)fw_refreshLayerColors {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [self updateColors];
    }];
}

@end

@implementation FWColorView

+ (instancetype)viewWithColor:(NSColor *)color {
    FWColorView *view = [[FWColorView alloc] initWithFrame:NSZeroRect];
    view.fillColor = color;
    return view;
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect)dirtyRect {
    [(self.fillColor ?: [NSColor windowBackgroundColor]) setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
}

@end
