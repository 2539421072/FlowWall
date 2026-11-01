// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import "FWAppDelegate.h"
#import "FWCore.h"
#import "FWDisplay.h"
#import "FWSettings.h"
#import "FWLoginItem.h"
#import <mach/mach.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

@implementation FWAppDelegate {
    FWConfigStore *_store;
    FWEngine *_engine;
    FWSettingsWindowController *_settingsController;
    NSStatusItem *_statusItem;
    BOOL _didAutoOpen;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    _store = [FWConfigStore shared];
    _engine = [[FWEngine alloc] initWithStore:_store];

    [self setupStatusItem];
    [self setupMainMenu];
    [_engine start];

    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if ([args containsObject:@"--dark"]) {
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    if ([args containsObject:@"--light"]) {
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    BOOL forceSettings = NO;
    NSString *snapshotPath = nil;
    BOOL diag = NO;
    BOOL snapshotGeneral = NO;
    NSString *windowShotPath = nil;
    for (NSUInteger i = 1; i < args.count; i++) {
        if ([args[i] isEqualToString:@"--settings"]) forceSettings = YES;
        if ([args[i] isEqualToString:@"--diag"]) diag = YES;
        if ([args[i] isEqualToString:@"--snapshot"] && i + 1 < args.count) snapshotPath = args[i + 1];
        if ([args[i] isEqualToString:@"--general"]) snapshotGeneral = YES;
        if ([args[i] isEqualToString:@"--windowshot"] && i + 1 < args.count) windowShotPath = args[i + 1];
    }
    if ([args containsObject:@"--test-login"]) {
        NSLog(@"[FlowWall] 登录项初始 enabled=%d approval=%d", FWLoginItemIsEnabled(), FWLoginItemNeedsApproval());
        NSString *err = FWLoginItemSetEnabled(YES);
        NSLog(@"[FlowWall] 注册结果=%@ enabled=%d approval=%d", err ?: @"成功",
              FWLoginItemIsEnabled(), FWLoginItemNeedsApproval());
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *err2 = FWLoginItemSetEnabled(NO);
            NSLog(@"[FlowWall] 已回滚=%@ enabled=%d", err2 ?: @"成功", FWLoginItemIsEnabled());
        });
    }
    if (diag) [self printDiagnostics];
    if ([args containsObject:@"--perf"]) [self startPerfLogging];

    __weak typeof(self) weakSelf = self;

    if (snapshotPath.length) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self openSettings:nil];
            if (snapshotGeneral) [self->_settingsController selectPaneWithKey:@"__general__"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSWindow *win = self->_settingsController.window;
                NSView *view = win.contentView;
                NSData *pdf = [view dataWithPDFInsideRect:view.bounds];
                BOOL ok = [pdf writeToFile:snapshotPath atomically:YES];
                NSLog(@"[FlowWall] 界面快照 %@ (%lu bytes)", ok ? @"已写入" : @"失败", (unsigned long)pdf.length);
            });
        });
    }

    if (windowShotPath.length) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self openSettings:nil];
            if (snapshotGeneral) [self->_settingsController selectPaneWithKey:@"__general__"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self captureWindowToPath:windowShotPath];
            });
        });
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self->_didAutoOpen) return;
        self->_didAutoOpen = YES;
        if (forceSettings || [self->_store totalItemCount] == 0) {
            [self openSettings:nil];
        }
    });
}

- (void)captureWindowToPath:(NSString *)path {
    NSWindow *win = _settingsController.window;
    if (!win) {
        NSLog(@"[FlowWall] 窗口截图失败：设置窗口不存在");
        return;
    }
    [win displayIfNeeded];
    CGWindowID wid = (CGWindowID)win.windowNumber;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef img = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, wid,
                                             kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
#pragma clang diagnostic pop
    if (!img) {
        NSLog(@"[FlowWall] 窗口截图失败：无录屏权限");
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    if (dest) {
        CGImageDestinationAddImage(dest, img, NULL);
        CGImageDestinationFinalize(dest);
        CFRelease(dest);
        NSLog(@"[FlowWall] 窗口截图已写入 %@ (%zux%zu)", path,
              CGImageGetWidth(img), CGImageGetHeight(img));
    }
    CGImageRelease(img);
}

- (void)startPerfLogging {
    __block double lastCPU = 0;
    __block CFAbsoluteTime lastTime = CFAbsoluteTimeGetCurrent();
    NSTimer *timer = [NSTimer timerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t) {
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);
        double cpu = usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6 +
                     usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        double percent = (cpu - lastCPU) / (now - lastTime) * 100.0;
        lastCPU = cpu;
        lastTime = now;
        struct mach_task_basic_info info;
        mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
        double rssMB = 0;
        if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            rssMB = info.resident_size / 1048576.0;
        }
        NSMutableString *states = [NSMutableString string];
        for (NSString *line in [self->_engine playbackStates]) [states appendFormat:@" [%@]", line];
        NSLog(@"[PERF] CPU=%.1f%% RSS=%.0fMB%@", percent, rssMB, states);
    }];
    timer.tolerance = 0.5;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)printDiagnostics {
    NSLog(@"[FlowWall] ---- 诊断 ----");
    for (NSScreen *screen in [NSScreen screens]) {
        NSString *key = FWDisplayIdentifierForScreen(screen);
        NSURL *wallpaper = [[NSWorkspace sharedWorkspace] desktopImageURLForScreen:screen];
        NSLog(@"[FlowWall] 屏幕 %@ key=%@ 系统壁纸=%@", screen.localizedName,
              [key substringToIndex:MIN(8u, key.length)], wallpaper.lastPathComponent ?: @"-");
    }
    NSLog(@"[FlowWall] 层级: desktop=%d desktopIcon=%d ours=%ld",
          (int)CGWindowLevelForKey(kCGDesktopWindowLevelKey),
          (int)CGWindowLevelForKey(kCGDesktopIconWindowLevelKey),
          (long)(CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) - 1));

    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSInteger pid = (NSInteger)getpid();
    for (NSDictionary *w in (__bridge NSArray *)list) {
        if ([w[(id)kCGWindowOwnerPID] integerValue] != pid) continue;
        NSLog(@"[FlowWall] 窗口 layer=%@ onscreen=%@ bounds=%@",
              w[(id)kCGWindowLayer], w[(id)kCGWindowIsOnscreen], w[(id)kCGWindowBounds]);
    }
    if (list) CFRelease(list);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (NSString *line in [self->_engine playbackStates]) {
            NSLog(@"[FlowWall] 播放状态 %@", line);
        }
    });
    NSLog(@"[FlowWall] ---- 诊断结束 ----");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_store save];
    [_engine stop];
}

#pragma mark - 菜单栏

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"流光壁纸"];
    [appMenu addItemWithTitle:@"打开设置" action:@selector(openSettings:) keyEquivalent:@","].target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出流光壁纸" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [NSApp setMainMenu:mainMenu];
}

- (void)setupStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"photo.on.rectangle.angled"
                               accessibilityDescription:@"流光壁纸"];
    image.template = YES;
    _statusItem.button.image = image;
    _statusItem.button.toolTip = @"流光壁纸";

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    _statusItem.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"打开设置…" action:@selector(openSettings:) keyEquivalent:@","];
    open.target = self;
    [menu addItem:open];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"全部显示器 · 下一张" action:@selector(advanceAll:) keyEquivalent:@""];
    next.target = self;
    [menu addItem:next];

    if (_engine.screens.count > 1) {
        for (NSDictionary *screen in _engine.screens) {
            NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:screen[@"name"] action:nil keyEquivalent:@""];
            NSMenu *sub = [[NSMenu alloc] init];
            NSMenuItem *one = [[NSMenuItem alloc] initWithTitle:@"下一张" action:@selector(advanceOne:) keyEquivalent:@""];
            one.target = self;
            one.representedObject = screen[@"key"];
            [sub addItem:one];
            NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"重新应用" action:@selector(refreshOne:) keyEquivalent:@""];
            refresh.target = self;
            refresh.representedObject = screen[@"key"];
            [sub addItem:refresh];
            parent.submenu = sub;
            [menu addItem:parent];
        }
    }

    NSMenuItem *pause = [[NSMenuItem alloc] initWithTitle:(_engine.paused ? @"继续轮换" : @"暂停轮换")
                                                  action:@selector(togglePause:)
                                           keyEquivalent:@""];
    pause.target = self;
    [menu addItem:pause];

    NSMenuItem *reapply = [[NSMenuItem alloc] initWithTitle:@"重新应用壁纸" action:@selector(reapply:) keyEquivalent:@""];
    reapply.target = self;
    [menu addItem:reapply];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"开机自动启动" action:@selector(toggleLogin:) keyEquivalent:@""];
    login.target = self;
    login.state = FWLoginItemIsEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:login];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出流光壁纸" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

#pragma mark - 动作

- (void)openSettings:(id)sender {
    if (!_settingsController) {
        _settingsController = [[FWSettingsWindowController alloc] initWithStore:_store engine:_engine];
    }
    [_settingsController present];
}

- (void)advanceAll:(id)sender {
    [_engine advanceAll];
}

- (void)advanceOne:(NSMenuItem *)sender {
    NSString *key = sender.representedObject;
    if (key) [_engine advanceDisplay:key];
}

- (void)refreshOne:(NSMenuItem *)sender {
    NSString *key = sender.representedObject;
    if (key) [_engine showCurrentForDisplay:key];
    [_engine reassertAll];
}

- (void)togglePause:(id)sender {
    [_engine togglePaused];
}

- (void)reapply:(id)sender {
    [_engine refreshAll];
    [_engine reassertAll];
}

- (void)toggleLogin:(id)sender {
    BOOL target = !FWLoginItemIsEnabled();
    NSString *error = FWLoginItemSetEnabled(target);
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法设置开机自启";
        alert.informativeText = [error stringByAppendingString:@"\n\n提示：请把「流光壁纸」拖到「应用程序」文件夹后再试。"];
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
    } else {
        _store.launchAtLogin = target;
    }
}

- (void)quit:(id)sender {
    [_store save];
    [NSApp terminate:nil];
}

@end
