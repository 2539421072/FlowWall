// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import "FWSettings.h"
#import "FWLoginItem.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - 基础控件

static NSTextField *FWLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: [NSColor labelColor];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

@interface FWLineView : NSView
@end

@implementation FWLineView
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor separatorColor] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
}
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 1); }
@end

static NSView *FWLine(void) {
    FWLineView *v = [[FWLineView alloc] init];
    [v.heightAnchor constraintEqualToConstant:1].active = YES;
    return v;
}

/// 左文右控件的一行
static NSView *FWRow(NSArray<NSView *> *leftViews, NSView *right, CGFloat vpad) {
    NSView *row = [[NSView alloc] init];
    NSStackView *left = [NSStackView stackViewWithViews:leftViews ?: @[]];
    left.orientation = NSUserInterfaceLayoutOrientationVertical;
    left.alignment = NSLayoutAttributeLeading;
    left.spacing = 2;
    left.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:left];
    [NSLayoutConstraint activateConstraints:@[
        [left.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [left.topAnchor constraintEqualToAnchor:row.topAnchor constant:vpad],
        [left.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-vpad]
    ]];
    if (right) {
        right.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:right];
        [NSLayoutConstraint activateConstraints:@[
            [right.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
            [right.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [right.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:vpad],
            [left.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-12]
        ]];
    } else {
        [left.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-14].active = YES;
    }
    return row;
}

static FWCardView *FWCardWithRows(NSArray<NSView *> *rows) {
    FWCardView *card = [[FWCardView alloc] initWithFrame:NSZeroRect];
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    stack.alignment = NSLayoutAttributeLeading;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i > 0) {
            NSView *line = FWLine();
            [stack addArrangedSubview:line];
            [line.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
        NSView *row = rows[i];
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    return card;
}

static NSTextField *FWCardHeader(NSString *title) {
    NSTextField *label = FWLabel(title, 11, NSFontWeightSemibold, [NSColor secondaryLabelColor]);
    return label;
}

#pragma mark - 缩略图

@interface FWThumbView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, strong) NSImageView *placeholderView;
@end

@implementation FWThumbView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 7;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.07].CGColor;
        self.layer.contentsGravity = kCAGravityResizeAspectFill;

        _placeholderView = [[NSImageView alloc] init];
        _placeholderView.image = [NSImage imageWithSystemSymbolName:@"photo" accessibilityDescription:nil];
        _placeholderView.contentTintColor = [NSColor tertiaryLabelColor];
        _placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_placeholderView];
        [NSLayoutConstraint activateConstraints:@[
            [_placeholderView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_placeholderView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_placeholderView.widthAnchor constraintEqualToConstant:16],
            [_placeholderView.heightAnchor constraintEqualToConstant:16]
        ]];
    }
    return self;
}

- (void)setImage:(NSImage *)image {
    _image = image;
    CGImageRef cg = image ? [image CGImageForProposedRect:NULL context:nil hints:nil] : NULL;
    self.layer.contents = cg ? (__bridge id)cg : nil;
    _placeholderView.hidden = (cg != NULL);
}

@end

#pragma mark - 队列行

@interface FWQueueCellView : NSTableCellView
@property (nonatomic, copy) void (^onDelete)(void);
- (void)configureWithItem:(FWMediaItem *)item isCurrent:(BOOL)isCurrent;
@end

@implementation FWQueueCellView {
    FWThumbView *_thumb;
    NSTextField *_name;
    FWTagLabel *_kindTag;
    NSTextField *_folder;
    FWTagLabel *_playing;
    NSButton *_deleteButton;
    NSTrackingArea *_tracking;
    BOOL _hover;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8;

        _thumb = [[FWThumbView alloc] initWithFrame:NSZeroRect];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_thumb];

        _name = FWLabel(@"", 12.5, NSFontWeightRegular, [NSColor labelColor]);
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_name];

        _kindTag = [FWTagLabel tagWithText:@"图片" color:[NSColor systemTealColor]];
        _kindTag.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_kindTag];

        _folder = FWLabel(@"", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        _folder.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_folder];

        _playing = [FWTagLabel tagWithText:@"播放中" color:[NSColor controlAccentColor]];
        _playing.translatesAutoresizingMaskIntoConstraints = NO;
        _playing.hidden = YES;
        [self addSubview:_playing];

        _deleteButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"trash"
                                                           accessibilityDescription:@"移除"]
                                           target:self
                                           action:@selector(deleteTapped:)];
        _deleteButton.bordered = NO;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _deleteButton.hidden = YES;
        [self addSubview:_deleteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_thumb.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_thumb.widthAnchor constraintEqualToConstant:42],
            [_thumb.heightAnchor constraintEqualToConstant:42],

            [_name.leadingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:10],
            [_name.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_playing.leadingAnchor constant:-8],

            [_kindTag.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_kindTag.centerYAnchor constraintEqualToAnchor:_folder.centerYAnchor],
            [_kindTag.heightAnchor constraintEqualToConstant:16],

            [_folder.leadingAnchor constraintEqualToAnchor:_kindTag.trailingAnchor constant:6],
            [_folder.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:4],
            [_folder.trailingAnchor constraintLessThanOrEqualToAnchor:_playing.leadingAnchor constant:-8],

            [_playing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_playing.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_playing.heightAnchor constraintEqualToConstant:16],

            [_deleteButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:20]
        ]];
    }
    return self;
}

- (void)configureWithItem:(FWMediaItem *)item isCurrent:(BOOL)isCurrent {
    _name.stringValue = item.fileName;
    _name.font = [NSFont systemFontOfSize:12.5 weight:isCurrent ? NSFontWeightSemibold : NSFontWeightRegular];
    [_kindTag setTagText:(item.isVideo ? @"视频" : @"图片")
                   color:(item.isVideo ? [NSColor systemPurpleColor] : [NSColor systemTealColor])];
    if (item.exists) {
        _folder.stringValue = item.folderName;
        _folder.textColor = [NSColor secondaryLabelColor];
    } else {
        _folder.stringValue = @"文件已丢失";
        _folder.textColor = [NSColor systemRedColor];
    }
    _playing.hidden = !isCurrent;
    _thumb.image = nil;
    NSString *itemID = item.itemID;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSImage *img = [FWImageLoader thumbnailForPath:item.path video:item.isVideo maxPixel:100];
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (![self->_name.stringValue isEqualToString:item.fileName]) return;
            self->_thumb.image = img;
            (void)itemID;
        });
    });
    [self updateAppearance];
}

- (void)updateAppearance {
    NSColor *bg = [NSColor clearColor];
    if (_hover) bg = [[NSColor labelColor] colorWithAlphaComponent:0.045];
    self.layer.backgroundColor = bg.CGColor;
    _deleteButton.hidden = !_hover;
    if (_hover) _playing.hidden = YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                               owner:self
                                            userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)event {
    _hover = YES;
    [self updateAppearance];
}

- (void)mouseExited:(NSEvent *)event {
    _hover = NO;
    [self updateAppearance];
}

- (void)deleteTapped:(id)sender {
    if (self.onDelete) self.onDelete();
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateAppearance];
}

@end

#pragma mark - 侧边栏行

@interface FWSidebarCell : NSTableCellView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subLabel;
@end

@implementation FWSidebarCell

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _iconView = [[NSImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentTintColor = [NSColor secondaryLabelColor];
        [self addSubview:_iconView];

        _titleLabel = FWLabel(@"", 12.5, NSFontWeightMedium, [NSColor labelColor]);
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _subLabel = FWLabel(@"", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        _subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_subLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18],
            [_iconView.heightAnchor constraintEqualToConstant:18],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],

            [_subLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],
            [_subLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4]
        ]];
    }
    return self;
}

@end

#pragma mark - 显示器详情面板

@interface FWDropCardView : FWCardView
@property (nonatomic, copy) void (^onPathsDropped)(NSArray<NSString *> *paths);
@end

@implementation FWDropCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSArray<NSString *> *)droppedPaths:(id<NSDraggingInfo>)info {
    NSPasteboard *pb = info.draggingPasteboard;
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[NSURL.class]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in urls) {
        if (url.isFileURL) [paths addObject:url.path];
    }
    return paths;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if ([self droppedPaths:sender].count == 0) return NSDragOperationNone;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [NSColor controlAccentColor].CGColor;
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.layer.borderWidth = 1;
    self.layer.borderColor = [[NSColor labelColor] colorWithAlphaComponent:0.08].CGColor;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    [self draggingExited:sender];
    NSArray<NSString *> *paths = [self droppedPaths:sender];
    if (paths.count == 0) return NO;
    if (self.onPathsDropped) self.onPathsDropped(paths);
    return YES;
}

@end

@interface FWDisplayPane : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, copy) NSString *displayKey;
@property (nonatomic, strong) NSDictionary *screenInfo;
- (instancetype)initWithStore:(FWConfigStore *)store
                      engine:(FWEngine *)engine
                         key:(NSString *)key
                  screenInfo:(NSDictionary *)info;
- (void)reload;
@end

@implementation FWDisplayPane {
    FWConfigStore *_store;
    FWEngine *_engine;

    NSTextField *_titleLabel;
    FWTagLabel *_resTag;
    FWTagLabel *_pixelTag;
    FWTagLabel *_mainTag;
    NSSwitch *_enabledSwitch;

    FWTagLabel *_countTag;
    NSTableView *_table;
    NSScrollView *_tableScroll;
    NSTextField *_emptyLabel;
    FWCardView *_queueCard;

    NSSegmentedControl *_modeSeg;
    NSSegmentedControl *_scaleSeg;
    NSSwitch *_shuffleSwitch;
    NSSwitch *_followGlobalSwitch;
    NSSegmentedControl *_intervalSeg;
    NSStepper *_intervalStepper;
    NSTextField *_intervalValueLabel;
    NSTextField *_currentLabel;
    NSTextField *_indexLabel;

    NSView *_intervalContainer;
    NSButton *_advanceButton;
    BOOL _suppressActions;
}

- (instancetype)initWithStore:(FWConfigStore *)store
                       engine:(FWEngine *)engine
                          key:(NSString *)key
                   screenInfo:(NSDictionary *)info {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _store = store;
        _engine = engine;
        _displayKey = [key copy];
        _screenInfo = info;
        [self buildUI];
        [self reload];
    }
    return self;
}

- (BOOL)isFlipped { return NO; }

#pragma mark 构建

- (void)buildUI {
    // 头部
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:header];

    _titleLabel = FWLabel(_screenInfo[@"name"] ?: @"显示器", 20, NSFontWeightBold, [NSColor labelColor]);
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:_titleLabel];

    _resTag = [FWTagLabel tagWithText:@"—" color:[NSColor secondaryLabelColor]];
    _pixelTag = [FWTagLabel tagWithText:@"—" color:[NSColor secondaryLabelColor]];
    _mainTag = [FWTagLabel tagWithText:@"主显示器" color:[NSColor controlAccentColor]];
    _mainTag.hidden = ![(_screenInfo[@"isMain"] ?: @NO) boolValue];

    NSStackView *tags = [NSStackView stackViewWithViews:@[_resTag, _pixelTag, _mainTag]];
    tags.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    tags.spacing = 6;
    tags.alignment = NSLayoutAttributeCenterY;
    tags.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:tags];

    _enabledSwitch = [[NSSwitch alloc] init];
    _enabledSwitch.target = self;
    _enabledSwitch.action = @selector(enabledChanged:);
    _enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:_enabledSwitch];

    NSTextField *enabledLabel = FWLabel(@"在此显示器播放", 12, NSFontWeightRegular, [NSColor labelColor]);
    enabledLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:enabledLabel];

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22],
        [header.topAnchor constraintEqualToAnchor:self.topAnchor constant:20],
        [header.heightAnchor constraintEqualToConstant:52],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:header.topAnchor],

        [tags.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [tags.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],

        [_enabledSwitch.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [_enabledSwitch.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [enabledLabel.trailingAnchor constraintEqualToAnchor:_enabledSwitch.leadingAnchor constant:-8],
        [enabledLabel.centerYAnchor constraintEqualToAnchor:_enabledSwitch.centerYAnchor]
    ]];

    // 队列卡片
    FWDropCardView *queueCard = [[FWDropCardView alloc] initWithFrame:NSZeroRect];
    queueCard.translatesAutoresizingMaskIntoConstraints = NO;
    _queueCard = queueCard;
    [self addSubview:_queueCard];

    __weak typeof(self) weakPane = self;
    queueCard.onPathsDropped = ^(NSArray<NSString *> *paths) {
        __strong typeof(weakPane) self = weakPane;
        if (!self) return;
        NSMutableArray<NSURL *> *urls = [NSMutableArray array];
        for (NSString *path in paths) {
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
                for (NSString *child in [FWMedia collectFromDirectory:path limit:800]) {
                    [urls addObject:[NSURL fileURLWithPath:child]];
                }
            } else {
                [urls addObject:[NSURL fileURLWithPath:path]];
            }
        }
        [self ingestPaths:urls];
    };

    NSView *queueHeader = [[NSView alloc] init];
    queueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [_queueCard addSubview:queueHeader];

    NSTextField *queueTitle = FWLabel(@"播放队列", 13, NSFontWeightSemibold, [NSColor labelColor]);
    queueTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [queueHeader addSubview:queueTitle];

    _countTag = [FWTagLabel tagWithText:@"0 项" color:[NSColor secondaryLabelColor]];
    _countTag.translatesAutoresizingMaskIntoConstraints = NO;
    [queueHeader addSubview:_countTag];

    NSButton *addFiles = [NSButton buttonWithTitle:@"添加文件" target:self action:@selector(addFiles:)];
    addFiles.controlSize = NSControlSizeSmall;
    addFiles.bezelStyle = NSBezelStyleRounded;
    NSButton *addFolder = [NSButton buttonWithTitle:@"添加文件夹" target:self action:@selector(addFolder:)];
    addFolder.controlSize = NSControlSizeSmall;
    addFolder.bezelStyle = NSBezelStyleRounded;

    NSPopUpButton *menuButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    menuButton.controlSize = NSControlSizeSmall;
    menuButton.bordered = YES;
    NSMenu *moreMenu = [[NSMenu alloc] init];
    [moreMenu addItemWithTitle:@"按文件名排序" action:@selector(sortItems:) keyEquivalent:@""].target = self;
    [moreMenu addItemWithTitle:@"打乱队列顺序" action:@selector(shuffleItems:) keyEquivalent:@""].target = self;
    [moreMenu addItem:[NSMenuItem separatorItem]];
    [moreMenu addItemWithTitle:@"清空队列" action:@selector(clearItems:) keyEquivalent:@""].target = self;
    NSMenuItem *placeholder = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    placeholder.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:@"更多"];
    [moreMenu insertItem:placeholder atIndex:0];
    menuButton.menu = moreMenu;
    [menuButton.widthAnchor constraintEqualToConstant:34].active = YES;

    NSStackView *actions = [NSStackView stackViewWithViews:@[addFiles, addFolder, menuButton]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [queueHeader addSubview:actions];

    [NSLayoutConstraint activateConstraints:@[
        [queueHeader.leadingAnchor constraintEqualToAnchor:_queueCard.leadingAnchor],
        [queueHeader.trailingAnchor constraintEqualToAnchor:_queueCard.trailingAnchor],
        [queueHeader.topAnchor constraintEqualToAnchor:_queueCard.topAnchor],
        [queueHeader.heightAnchor constraintEqualToConstant:42],

        [queueTitle.leadingAnchor constraintEqualToAnchor:queueHeader.leadingAnchor constant:14],
        [queueTitle.centerYAnchor constraintEqualToAnchor:queueHeader.centerYAnchor],

        [_countTag.leadingAnchor constraintEqualToAnchor:queueTitle.trailingAnchor constant:8],
        [_countTag.centerYAnchor constraintEqualToAnchor:queueHeader.centerYAnchor],
        [_countTag.heightAnchor constraintEqualToConstant:16],

        [actions.trailingAnchor constraintEqualToAnchor:queueHeader.trailingAnchor constant:-12],
        [actions.centerYAnchor constraintEqualToAnchor:queueHeader.centerYAnchor]
    ]];

    NSView *queueLine = FWLine();
    queueLine.translatesAutoresizingMaskIntoConstraints = NO;
    [_queueCard addSubview:queueLine];

    _table = [[NSTableView alloc] init];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.rowHeight = 58;
    _table.intercellSpacing = NSMakeSize(0, 2);
    _table.backgroundColor = [NSColor clearColor];
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(handleDoubleClick:);
    [_table registerForDraggedTypes:@[@"com.flowwall.queue.row"]];

    _tableScroll = [[NSScrollView alloc] init];
    _tableScroll.hasVerticalScroller = YES;
    _tableScroll.drawsBackground = NO;
    _tableScroll.documentView = _table;
    _tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_queueCard addSubview:_tableScroll];

    _emptyLabel = FWLabel(@"把图片或视频拖到这里\n或点击右上角「添加文件 / 添加文件夹」", 12, NSFontWeightRegular,
                          [NSColor secondaryLabelColor]);
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.maximumNumberOfLines = 3;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_queueCard addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [queueLine.leadingAnchor constraintEqualToAnchor:_queueCard.leadingAnchor],
        [queueLine.trailingAnchor constraintEqualToAnchor:_queueCard.trailingAnchor],
        [queueLine.topAnchor constraintEqualToAnchor:queueHeader.bottomAnchor],

        [_tableScroll.leadingAnchor constraintEqualToAnchor:_queueCard.leadingAnchor constant:6],
        [_tableScroll.trailingAnchor constraintEqualToAnchor:_queueCard.trailingAnchor constant:-6],
        [_tableScroll.topAnchor constraintEqualToAnchor:queueLine.bottomAnchor constant:4],
        [_tableScroll.bottomAnchor constraintEqualToAnchor:_queueCard.bottomAnchor constant:-6],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_queueCard.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_queueCard.centerYAnchor constant:10],
        [_emptyLabel.widthAnchor constraintLessThanOrEqualToAnchor:_queueCard.widthAnchor constant:-40]
    ]];

    // 选项卡片
    NSView *modeRow = FWRow(@[FWLabel(@"轮换方式", 12.5, NSFontWeightRegular, [NSColor labelColor])],
                            nil, 9);
    _modeSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"定时间隔", @"跟随视频时长", @"手动切换"]
                                                  trackingMode:NSSegmentSwitchTrackingSelectOne
                                                        target:self
                                                        action:@selector(modeChanged:)];
    _modeSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [_modeSeg.widthAnchor constraintEqualToConstant:300].active = YES;
    [modeRow addSubview:_modeSeg];
    [NSLayoutConstraint activateConstraints:@[
        [_modeSeg.trailingAnchor constraintEqualToAnchor:modeRow.trailingAnchor constant:-14],
        [_modeSeg.centerYAnchor constraintEqualToAnchor:modeRow.centerYAnchor]
    ]];

    NSView *scaleRow = FWRow(@[FWLabel(@"图片缩放", 12.5, NSFontWeightRegular, [NSColor labelColor])], nil, 9);
    _scaleSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"填充屏幕", @"完整显示", @"拉伸铺满"]
                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                         target:self
                                                         action:@selector(scaleChanged:)];
    _scaleSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [_scaleSeg.widthAnchor constraintEqualToConstant:300].active = YES;
    [scaleRow addSubview:_scaleSeg];
    [NSLayoutConstraint activateConstraints:@[
        [_scaleSeg.trailingAnchor constraintEqualToAnchor:scaleRow.trailingAnchor constant:-14],
        [_scaleSeg.centerYAnchor constraintEqualToAnchor:scaleRow.centerYAnchor]
    ]];

    _shuffleSwitch = [[NSSwitch alloc] init];
    _shuffleSwitch.target = self;
    _shuffleSwitch.action = @selector(shuffleChanged:);
    NSView *shuffleRow = FWRow(@[FWLabel(@"随机顺序播放", 12.5, NSFontWeightRegular, [NSColor labelColor])],
                               _shuffleSwitch, 9);

    // 间隔行（两行布局）
    _intervalContainer = [[NSView alloc] init];
    NSTextField *intervalTitle = FWLabel(@"轮换间隔", 12.5, NSFontWeightRegular, [NSColor labelColor]);
    intervalTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:intervalTitle];

    _followGlobalSwitch = [[NSSwitch alloc] init];
    _followGlobalSwitch.target = self;
    _followGlobalSwitch.action = @selector(followGlobalChanged:);
    _followGlobalSwitch.controlSize = NSControlSizeMini;
    _followGlobalSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:_followGlobalSwitch];

    NSTextField *followLabel = FWLabel(@"跟随全局", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    followLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:followLabel];

    _intervalSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"15秒", @"30秒", @"1分", @"5分", @"15分", @"30分", @"1时"]
                                                      trackingMode:NSSegmentSwitchTrackingSelectOne
                                                            target:self
                                                            action:@selector(intervalPresetChanged:)];
    _intervalSeg.controlSize = NSControlSizeSmall;
    _intervalSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:_intervalSeg];

    _intervalValueLabel = FWLabel(@"30 秒", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _intervalValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _intervalValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:_intervalValueLabel];

    _intervalStepper = [[NSStepper alloc] init];
    _intervalStepper.minValue = 5;
    _intervalStepper.maxValue = 86400;
    _intervalStepper.increment = 5;
    _intervalStepper.valueWraps = NO;
    _intervalStepper.controlSize = NSControlSizeSmall;
    _intervalStepper.target = self;
    _intervalStepper.action = @selector(intervalStepperChanged:);
    _intervalStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [_intervalContainer addSubview:_intervalStepper];

    [NSLayoutConstraint activateConstraints:@[
        [intervalTitle.leadingAnchor constraintEqualToAnchor:_intervalContainer.leadingAnchor constant:14],
        [intervalTitle.topAnchor constraintEqualToAnchor:_intervalContainer.topAnchor constant:10],

        [_followGlobalSwitch.trailingAnchor constraintEqualToAnchor:_intervalContainer.trailingAnchor constant:-14],
        [_followGlobalSwitch.centerYAnchor constraintEqualToAnchor:intervalTitle.centerYAnchor],

        [followLabel.trailingAnchor constraintEqualToAnchor:_followGlobalSwitch.leadingAnchor constant:-6],
        [followLabel.centerYAnchor constraintEqualToAnchor:intervalTitle.centerYAnchor],

        [_intervalSeg.leadingAnchor constraintEqualToAnchor:_intervalContainer.leadingAnchor constant:14],
        [_intervalSeg.topAnchor constraintEqualToAnchor:intervalTitle.bottomAnchor constant:10],
        [_intervalSeg.bottomAnchor constraintEqualToAnchor:_intervalContainer.bottomAnchor constant:-12],
        [self->_intervalContainer.heightAnchor constraintGreaterThanOrEqualToConstant:70],
        [_intervalSeg.trailingAnchor constraintLessThanOrEqualToAnchor:_intervalValueLabel.leadingAnchor constant:-12],

        [_intervalStepper.trailingAnchor constraintEqualToAnchor:_intervalContainer.trailingAnchor constant:-14],
        [_intervalStepper.centerYAnchor constraintEqualToAnchor:_intervalSeg.centerYAnchor],

        [_intervalValueLabel.trailingAnchor constraintEqualToAnchor:_intervalStepper.leadingAnchor constant:-6],
        [_intervalValueLabel.centerYAnchor constraintEqualToAnchor:_intervalSeg.centerYAnchor]
    ]];
    [_intervalSeg setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    // 当前播放行
    NSView *currentRow = [[NSView alloc] init];
    NSTextField *currentTitle = FWLabel(@"当前播放", 12.5, NSFontWeightRegular, [NSColor labelColor]);
    currentTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [currentRow addSubview:currentTitle];
    _currentLabel = FWLabel(@"暂无", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _currentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [currentRow addSubview:_currentLabel];
    _indexLabel = FWLabel(@"", 11, NSFontWeightRegular, [NSColor tertiaryLabelColor]);
    _indexLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [currentRow addSubview:_indexLabel];
    _advanceButton = [NSButton buttonWithTitle:@"立即切换" target:self action:@selector(advanceTapped:)];
    _advanceButton.controlSize = NSControlSizeSmall;
    _advanceButton.bezelStyle = NSBezelStyleRounded;
    _advanceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [currentRow addSubview:_advanceButton];

    [NSLayoutConstraint activateConstraints:@[
        [currentTitle.leadingAnchor constraintEqualToAnchor:currentRow.leadingAnchor constant:14],
        [currentTitle.topAnchor constraintEqualToAnchor:currentRow.topAnchor constant:9],
        [currentTitle.bottomAnchor constraintEqualToAnchor:currentRow.bottomAnchor constant:-9],

        [_currentLabel.leadingAnchor constraintEqualToAnchor:currentTitle.trailingAnchor constant:10],
        [_currentLabel.centerYAnchor constraintEqualToAnchor:currentTitle.centerYAnchor],
        [_currentLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_indexLabel.leadingAnchor constant:-10],

        [_indexLabel.trailingAnchor constraintEqualToAnchor:_advanceButton.leadingAnchor constant:-12],
        [_indexLabel.centerYAnchor constraintEqualToAnchor:currentTitle.centerYAnchor],

        [_advanceButton.trailingAnchor constraintEqualToAnchor:currentRow.trailingAnchor constant:-14],
        [_advanceButton.centerYAnchor constraintEqualToAnchor:currentTitle.centerYAnchor]
    ]];

    FWCardView *optionsCard = FWCardWithRows(@[modeRow, scaleRow, shuffleRow, _intervalContainer, currentRow]);
    optionsCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:optionsCard];

    [NSLayoutConstraint activateConstraints:@[
        [_queueCard.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22],
        [_queueCard.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22],
        [_queueCard.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:16],
        [_queueCard.heightAnchor constraintGreaterThanOrEqualToConstant:150],

        [optionsCard.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22],
        [optionsCard.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22],
        [optionsCard.topAnchor constraintEqualToAnchor:_queueCard.bottomAnchor constant:16],
        [optionsCard.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-20]
    ]];

    [_queueCard setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
}

#pragma mark 刷新

- (void)reload {
    _suppressActions = YES;
    NSArray<NSDictionary *> *items = [_store itemsForDisplay:_displayKey];
    NSInteger cursor = [_store cursorForDisplay:_displayKey];

    NSNumber *w = _screenInfo[@"width"], *h = _screenInfo[@"height"];
    NSNumber *pw = _screenInfo[@"pixelWidth"], *ph = _screenInfo[@"pixelHeight"];
    [_resTag setTagText:[NSString stringWithFormat:@"%.0f × %.0f", w.doubleValue, h.doubleValue]
                  color:[NSColor secondaryLabelColor]];
    [_pixelTag setTagText:[NSString stringWithFormat:@"%.0f × %.0f px", pw.doubleValue, ph.doubleValue]
                    color:[NSColor secondaryLabelColor]];
    [_countTag setTagText:[NSString stringWithFormat:@"%lu 项", (unsigned long)items.count]
                    color:[NSColor secondaryLabelColor]];

    _enabledSwitch.state = [_store enabledForDisplay:_displayKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _modeSeg.selectedSegment = [_store rotationModeForDisplay:_displayKey];
    _scaleSeg.selectedSegment = [_store scaleModeForDisplay:_displayKey];
    _shuffleSwitch.state = [_store shuffleForDisplay:_displayKey] ? NSControlStateValueOn : NSControlStateValueOff;

    NSInteger mode = [_store rotationModeForDisplay:_displayKey];
    _intervalContainer.hidden = (mode != FWRotationModeInterval);
    BOOL follows = ![_store hasIntervalOverride:_displayKey];
    _followGlobalSwitch.state = follows ? NSControlStateValueOn : NSControlStateValueOff;
    double interval = [_store effectiveIntervalForDisplay:_displayKey];
    _intervalSeg.enabled = !follows;
    _intervalStepper.enabled = !follows;
    _intervalValueLabel.textColor = follows ? [NSColor tertiaryLabelColor] : [NSColor secondaryLabelColor];
    _intervalValueLabel.stringValue = FWFormatInterval(interval);
    _intervalStepper.doubleValue = interval;

    NSArray<NSNumber *> *presets = @[@15, @30, @60, @300, @900, @1800, @3600];
    NSInteger selected = -1;
    for (NSUInteger i = 0; i < presets.count; i++) {
        if (fabs(presets[i].doubleValue - interval) < 0.5) { selected = (NSInteger)i; break; }
    }
    [_intervalSeg setSelectedSegment:selected];

    NSString *current = [_engine currentItemNameForDisplay:_displayKey];
    _currentLabel.stringValue = current.length ? current : @"暂无";
    _indexLabel.stringValue = [_engine queueIndexForDisplay:_displayKey] ?: @"";

    _emptyLabel.hidden = items.count > 0;
    _tableScroll.hidden = items.count == 0;
    [_table reloadData];
    if (cursor < (NSInteger)items.count) {
        [_table scrollRowToVisible:MIN(cursor, MAX(0, (NSInteger)items.count - 1))];
    }
    _suppressActions = NO;
}

#pragma mark 表格

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[_store itemsForDisplay:_displayKey].count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray<NSDictionary *> *items = [_store itemsForDisplay:_displayKey];
    if (row < 0 || row >= (NSInteger)items.count) return nil;
    FWQueueCellView *cell = [tableView makeViewWithIdentifier:@"queue" owner:self];
    if (!cell) {
        cell = [[FWQueueCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 58)];
        cell.identifier = @"queue";
    }
    FWMediaItem *item = [FWMediaItem itemWithDictionary:items[row]];
    __weak typeof(self) weakSelf = self;
    __weak FWQueueCellView *weakCell = cell;
    cell.onDelete = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSInteger idx = [self->_table rowForView:weakCell];
        if (idx >= 0) [self->_store removeItemAtIndex:idx display:self->_displayKey];
    };
    [cell configureWithItem:item isCurrent:([_store cursorForDisplay:_displayKey] == row)];
    return cell;
}

- (void)handleDoubleClick:(id)sender {
    NSInteger row = _table.clickedRow;
    if (row < 0) return;
    [_store setCursor:row display:_displayKey];
    [_engine showCurrentForDisplay:_displayKey];
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard {
    [pboard declareTypes:@[@"com.flowwall.queue.row"] owner:self];
    [pboard setString:[NSString stringWithFormat:@"%ld", (long)rowIndexes.firstIndex]
              forType:@"com.flowwall.queue.row"];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if ([info.draggingPasteboard availableTypeFromArray:@[@"com.flowwall.queue.row"]]) {
        [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
        return NSDragOperationMove;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    NSString *value = [info.draggingPasteboard stringForType:@"com.flowwall.queue.row"];
    if (!value) return NO;
    [_store moveItemFrom:value.integerValue to:row display:_displayKey];
    return YES;
}

#pragma mark 动作

- (void)enabledChanged:(NSSwitch *)sender {
    if (_suppressActions) return;
    [_store setEnabled:(sender.state == NSControlStateValueOn) display:_displayKey];
}

- (void)modeChanged:(NSSegmentedControl *)sender {
    if (_suppressActions) return;
    [_store setRotationMode:sender.selectedSegment display:_displayKey];
}

- (void)scaleChanged:(NSSegmentedControl *)sender {
    if (_suppressActions) return;
    [_store setScaleMode:sender.selectedSegment display:_displayKey];
}

- (void)shuffleChanged:(NSSwitch *)sender {
    if (_suppressActions) return;
    [_store setShuffle:(sender.state == NSControlStateValueOn) display:_displayKey];
}

- (void)followGlobalChanged:(NSSwitch *)sender {
    if (_suppressActions) return;
    if (sender.state == NSControlStateValueOn) {
        [_store setHasIntervalOverride:NO value:0 display:_displayKey];
    } else {
        [_store setHasIntervalOverride:YES value:_store.defaultInterval display:_displayKey];
    }
}

- (void)intervalPresetChanged:(NSSegmentedControl *)sender {
    if (_suppressActions || sender.selectedSegment < 0) return;
    NSArray<NSNumber *> *presets = @[@15, @30, @60, @300, @900, @1800, @3600];
    if (sender.selectedSegment < (NSInteger)presets.count) {
        [_store setHasIntervalOverride:YES value:presets[sender.selectedSegment].doubleValue display:_displayKey];
    }
}

- (void)intervalStepperChanged:(NSStepper *)sender {
    if (_suppressActions) return;
    [_store setHasIntervalOverride:YES value:sender.doubleValue display:_displayKey];
}

- (void)advanceTapped:(id)sender {
    [_engine advanceDisplay:_displayKey];
}

- (void)sortItems:(id)sender {
    NSMutableArray *items = [[_store itemsForDisplay:_displayKey] mutableCopy];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *pathA = a[@"path"];
        NSString *pathB = b[@"path"];
        return [pathA.lastPathComponent localizedStandardCompare:pathB.lastPathComponent];
    }];
    [_store setItems:items forDisplay:_displayKey];
    [_store setCursor:0 display:_displayKey];
}

- (void)shuffleItems:(id)sender {
    [_store shuffleItemsForDisplay:_displayKey];
}

- (void)clearItems:(id)sender {
    [_store clearItemsForDisplay:_displayKey];
}

- (void)addFiles:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowedContentTypes = @[UTTypeImage, UTTypeMovie, UTTypeMPEG4Movie, UTTypeQuickTimeMovie];
    panel.message = @"选择要加入播放队列的图片或视频";
    panel.prompt = @"添加到队列";
    NSModalResponse response = [panel runModal];
    [NSApp activateIgnoringOtherApps:YES];
    if (response == NSModalResponseOK) {
        [self ingestPaths:panel.URLs];
    }
}

- (void)addFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowedContentTypes = @[UTTypeFolder];
    panel.message = @"选择文件夹，自动收集其中的图片与视频";
    panel.prompt = @"添加";
    NSModalResponse response = [panel runModal];
    [NSApp activateIgnoringOtherApps:YES];
    if (response != NSModalResponseOK) return;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in panel.URLs) {
        [paths addObjectsFromArray:[FWMedia collectFromDirectory:url.path limit:800]];
    }
    if (paths.count == 0) {
        [self showToast:@"该文件夹里没有找到支持的图片或视频"];
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *path in paths) [urls addObject:[NSURL fileURLWithPath:path]];
    [self ingestPaths:urls];
}

- (void)ingestPaths:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in urls) {
        if ([FWMedia isSupportedPath:url.path]) [paths addObject:url.path];
    }
    if (paths.count == 0) {
        [self showToast:@"没有可用的图片或视频"];
        return;
    }
    [self showToast:[NSString stringWithFormat:@"正在检查 %lu 个文件…", (unsigned long)paths.count]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *rejected = nil;
        NSArray<NSDictionary *> *items = [FWMedia validatePaths:paths rejected:&rejected];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            NSUInteger before = [self->_store itemsForDisplay:self->_displayKey].count;
            [self->_store addItems:items toDisplay:self->_displayKey];
            NSUInteger after = [self->_store itemsForDisplay:self->_displayKey].count;
            NSUInteger added = after - before;
            if (added == 0 && items.count == 0) {
                [self showToast:@"这些文件都无法播放，已跳过"];
            } else if (rejected.count > 0) {
                [self showToast:[NSString stringWithFormat:@"已添加 %lu 项，跳过 %lu 个不支持的文件",
                                 (unsigned long)added, (unsigned long)rejected.count]];
            } else {
                [self showToast:[NSString stringWithFormat:@"已添加 %lu 项", (unsigned long)added]];
            }
        });
    });
}

- (void)showToast:(NSString *)text {
    NSTextField *toast = FWLabel(text, 12, NSFontWeightMedium, [NSColor whiteColor]);
    toast.alignment = NSTextAlignmentCenter;
    toast.wantsLayer = YES;
    toast.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.78].CGColor;
    toast.layer.cornerRadius = 14;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-28],
        [toast.heightAnchor constraintEqualToConstant:30],
        [toast.widthAnchor constraintGreaterThanOrEqualToConstant:120]
    ]];
    toast.alphaValue = 0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.18;
        toast.animator.alphaValue = 1;
    } completionHandler:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                ctx.duration = 0.25;
                toast.animator.alphaValue = 0;
            } completionHandler:^{
                [toast removeFromSuperview];
            }];
        });
    }];
}

@end

#pragma mark - 通用设置面板

@interface FWGeneralPane : NSView
- (instancetype)initWithStore:(FWConfigStore *)store engine:(FWEngine *)engine;
- (void)reload;
@end

@implementation FWGeneralPane {
    FWConfigStore *_store;
    FWEngine *_engine;
    NSSwitch *_loginSwitch;
    NSSwitch *_rotationSwitch;
    NSSwitch *_coveredSwitch;
    NSSegmentedControl *_presetSeg;
    NSStepper *_stepper;
    NSTextField *_intervalLabel;
    NSSlider *_fadeSlider;
    NSTextField *_fadeLabel;
    NSTextField *_infoLabel;
    BOOL _suppress;
}

- (instancetype)initWithStore:(FWConfigStore *)store engine:(FWEngine *)engine {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _store = store;
        _engine = engine;
        [self buildUI];
        [self reload];
    }
    return self;
}

- (void)buildUI {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 900)];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = doc;

    NSTextField *title = FWLabel(@"通用设置", 20, NSFontWeightBold, [NSColor labelColor]);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:title];
    NSTextField *subtitle = FWLabel(@"启动项、性能与全局行为", 11.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:subtitle];

    // 启动
    _loginSwitch = [[NSSwitch alloc] init];
    _loginSwitch.target = self;
    _loginSwitch.action = @selector(loginChanged:);
    NSView *loginRow = FWRow(@[FWLabel(@"开机自动启动", 12.5, NSFontWeightRegular, [NSColor labelColor]),
                               FWLabel(@"登录后在后台启动，壁纸立即生效", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor])],
                             _loginSwitch, 10);
    FWCardView *loginCard = FWCardWithRows(@[[self headerView:@"启动"], loginRow]);

    // 轮换
    _rotationSwitch = [[NSSwitch alloc] init];
    _rotationSwitch.target = self;
    _rotationSwitch.action = @selector(rotationChanged:);
    NSView *rotationRow = FWRow(@[FWLabel(@"启用自动轮换", 12.5, NSFontWeightRegular, [NSColor labelColor]),
                                  FWLabel(@"关闭后所有显示器保持当前画面", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor])],
                                _rotationSwitch, 10);

    NSView *intervalRow = [[NSView alloc] init];
    NSTextField *intervalTitle = FWLabel(@"默认轮换间隔", 12.5, NSFontWeightRegular, [NSColor labelColor]);
    intervalTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [intervalRow addSubview:intervalTitle];
    _intervalLabel = FWLabel(@"30 秒", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _intervalLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _intervalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [intervalRow addSubview:_intervalLabel];
    _presetSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"15秒", @"30秒", @"1分", @"5分", @"15分", @"30分", @"1时"]
                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                          target:self
                                                          action:@selector(presetChanged:)];
    _presetSeg.controlSize = NSControlSizeSmall;
    _presetSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [intervalRow addSubview:_presetSeg];
    _stepper = [[NSStepper alloc] init];
    _stepper.minValue = 5;
    _stepper.maxValue = 86400;
    _stepper.increment = 5;
    _stepper.controlSize = NSControlSizeSmall;
    _stepper.target = self;
    _stepper.action = @selector(stepperChanged:);
    _stepper.translatesAutoresizingMaskIntoConstraints = NO;
    [intervalRow addSubview:_stepper];

    [NSLayoutConstraint activateConstraints:@[
        [intervalTitle.leadingAnchor constraintEqualToAnchor:intervalRow.leadingAnchor constant:14],
        [intervalTitle.topAnchor constraintEqualToAnchor:intervalRow.topAnchor constant:10],

        [_intervalLabel.trailingAnchor constraintEqualToAnchor:_stepper.leadingAnchor constant:-6],
        [_intervalLabel.centerYAnchor constraintEqualToAnchor:intervalTitle.centerYAnchor],

        [_stepper.trailingAnchor constraintEqualToAnchor:intervalRow.trailingAnchor constant:-14],
        [_stepper.centerYAnchor constraintEqualToAnchor:intervalTitle.centerYAnchor],

        [_presetSeg.leadingAnchor constraintEqualToAnchor:intervalRow.leadingAnchor constant:14],
        [_presetSeg.trailingAnchor constraintLessThanOrEqualToAnchor:_intervalLabel.leadingAnchor constant:-12],
        [_presetSeg.topAnchor constraintEqualToAnchor:intervalTitle.bottomAnchor constant:10],
        [_presetSeg.bottomAnchor constraintEqualToAnchor:intervalRow.bottomAnchor constant:-12],
        // 显式最小高度：NSStackView 会把无 intrinsic 高度的行压扁，导致控件贴边
        [intervalRow.heightAnchor constraintGreaterThanOrEqualToConstant:70]
    ]];
    [_presetSeg setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];

    FWCardView *rotationCard = FWCardWithRows(@[[self headerView:@"轮换"], rotationRow, intervalRow]);

    // 性能
    _coveredSwitch = [[NSSwitch alloc] init];
    _coveredSwitch.target = self;
    _coveredSwitch.action = @selector(coveredChanged:);
    NSView *coveredRow = FWRow(@[FWLabel(@"桌面被完全遮挡时暂停视频", 12.5, NSFontWeightRegular, [NSColor labelColor]),
                                 FWLabel(@"全屏办公时停止解码，显著降低功耗与显存占用", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor])],
                               _coveredSwitch, 10);

    _fadeSlider = [[NSSlider alloc] init];
    _fadeSlider.minValue = 0;
    _fadeSlider.maxValue = 3;
    _fadeSlider.continuous = YES;
    _fadeSlider.target = self;
    _fadeSlider.action = @selector(fadeChanged:);
    _fadeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_fadeSlider.widthAnchor constraintEqualToConstant:150].active = YES;
    _fadeLabel = FWLabel(@"0.6 秒", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _fadeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _fadeLabel.alignment = NSTextAlignmentRight;
    _fadeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_fadeLabel.widthAnchor constraintEqualToConstant:52].active = YES;

    NSStackView *fadeControls = [NSStackView stackViewWithViews:@[_fadeSlider, _fadeLabel]];
    fadeControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fadeControls.spacing = 8;
    fadeControls.alignment = NSLayoutAttributeCenterY;
    NSView *fadeRow = FWRow(@[FWLabel(@"淡入淡出时长", 12.5, NSFontWeightRegular, [NSColor labelColor]),
                              FWLabel(@"切换壁纸时的过渡动画，0 秒为直接切换", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor])],
                            fadeControls, 10);

    NSButton *clearCache = [NSButton buttonWithTitle:@"清除" target:self action:@selector(clearCache:)];
    clearCache.controlSize = NSControlSizeSmall;
    clearCache.bezelStyle = NSBezelStyleRounded;
    NSView *cacheRow = FWRow(@[FWLabel(@"图片解码缓存", 12.5, NSFontWeightRegular, [NSColor labelColor]),
                               FWLabel(@"按屏幕分辨率降采样并缓存，切换瞬时完成", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor])],
                             clearCache, 10);

    FWCardView *perfCard = FWCardWithRows(@[[self headerView:@"性能与效果"], fadeRow, coveredRow, cacheRow]);

    // 维护
    NSButton *reapply = [NSButton buttonWithTitle:@"重新应用壁纸" target:self action:@selector(reapply:)];
    reapply.controlSize = NSControlSizeSmall;
    reapply.bezelStyle = NSBezelStyleRounded;
    NSButton *reveal = [NSButton buttonWithTitle:@"打开配置位置" target:self action:@selector(revealConfig:)];
    reveal.controlSize = NSControlSizeSmall;
    reveal.bezelStyle = NSBezelStyleRounded;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[reapply, reveal]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;

    _infoLabel = FWLabel(@"", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    NSView *maintainRow = FWRow(@[_infoLabel], buttons, 10);
    FWCardView *maintainCard = FWCardWithRows(@[[self headerView:@"维护"], maintainRow]);

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        title, subtitle, loginCard, rotationCard, perfCard, maintainCard
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:16 afterView:subtitle];
    [doc addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:22],
        [title.topAnchor constraintEqualToAnchor:doc.topAnchor constant:20],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-22],
        [stack.topAnchor constraintEqualToAnchor:title.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-24],
        [doc.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
    ]];

    for (NSView *v in @[loginCard, rotationCard, perfCard, maintainCard]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
}

- (NSView *)headerView:(NSString *)title {
    NSView *container = [[NSView alloc] init];
    NSTextField *label = FWCardHeader(title);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        [container.heightAnchor constraintEqualToConstant:32]
    ]];
    return container;
}

- (void)reload {
    _suppress = YES;
    _loginSwitch.state = [self loginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    _rotationSwitch.state = _store.rotationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _coveredSwitch.state = _store.pauseWhenCovered ? NSControlStateValueOn : NSControlStateValueOff;
    _fadeSlider.doubleValue = _store.fadeDuration;
    _fadeLabel.stringValue = [NSString stringWithFormat:@"%.1f 秒", _store.fadeDuration];
    _intervalLabel.stringValue = FWFormatInterval(_store.defaultInterval);
    _stepper.doubleValue = _store.defaultInterval;
    NSArray<NSNumber *> *presets = @[@15, @30, @60, @300, @900, @1800, @3600];
    NSInteger selected = -1;
    for (NSUInteger i = 0; i < presets.count; i++) {
        if (fabs(presets[i].doubleValue - _store.defaultInterval) < 0.5) { selected = (NSInteger)i; break; }
    }
    [_presetSeg setSelectedSegment:selected];
    _infoLabel.stringValue = [NSString stringWithFormat:@"显示器 %lu 台 · 共 %lu 项素材 · 配置：%@",
                              (unsigned long)_engine.screens.count,
                              (unsigned long)[_store totalItemCount],
                              _store.configPath.lastPathComponent];
    _suppress = NO;
}

- (BOOL)loginEnabled {
    return FWLoginItemIsEnabled();
}

- (void)loginChanged:(NSSwitch *)sender {
    if (_suppress) return;
    BOOL on = sender.state == NSControlStateValueOn;
    NSString *error = FWLoginItemSetEnabled(on);
    if (error) {
        _loginSwitch.state = [self loginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法设置开机自启";
        alert.informativeText = [error stringByAppendingString:@"\n\n提示：请先把「流光壁纸」拖到「应用程序」文件夹后再试。"];
        alert.alertStyle = NSAlertStyleWarning;
        [alert runModal];
    } else {
        _store.launchAtLogin = on;
    }
}

- (void)rotationChanged:(NSSwitch *)sender {
    if (_suppress) return;
    _store.rotationEnabled = (sender.state == NSControlStateValueOn);
}

- (void)coveredChanged:(NSSwitch *)sender {
    if (_suppress) return;
    _store.pauseWhenCovered = (sender.state == NSControlStateValueOn);
}

- (void)fadeChanged:(NSSlider *)sender {
    if (_suppress) return;
    _store.fadeDuration = sender.doubleValue;
    _fadeLabel.stringValue = [NSString stringWithFormat:@"%.1f 秒", sender.doubleValue];
}

- (void)presetChanged:(NSSegmentedControl *)sender {
    if (_suppress || sender.selectedSegment < 0) return;
    NSArray<NSNumber *> *presets = @[@15, @30, @60, @300, @900, @1800, @3600];
    if (sender.selectedSegment < (NSInteger)presets.count) {
        _store.defaultInterval = presets[sender.selectedSegment].doubleValue;
    }
}

- (void)stepperChanged:(NSStepper *)sender {
    if (_suppress) return;
    _store.defaultInterval = sender.doubleValue;
}

- (void)clearCache:(id)sender {
    [[FWImageLoader shared] clearCache];
    [_engine refreshAll];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"图片缓存已清除";
    alert.informativeText = @"下次切换时会重新按屏幕分辨率解码。";
    [alert runModal];
}

- (void)reapply:(id)sender {
    [_engine refreshAll];
}

- (void)revealConfig:(id)sender {
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:_store.configPath]]];
}

@end

#pragma mark - 窗口控制器

@interface FWSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation FWSettingsWindowController {
    FWConfigStore *_store;
    FWEngine *_engine;
    NSTableView *_sidebarTable;
    NSView *_contentContainer;
    NSView *_currentPane;
    NSArray<NSDictionary *> *_sidebarItems;
}

- (instancetype)initWithStore:(FWConfigStore *)store engine:(FWEngine *)engine {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1020, 728)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"流光壁纸";
    // 透明标题栏 + 全尺寸内容：侧边栏毛玻璃可以从窗口顶端一直延伸到底，与原生设置类窗口一致
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    window.minSize = NSMakeSize(920, 620);
    [window center];
    window.releasedWhenClosed = NO;
    [window setFrameAutosaveName:@"FlowWallSettingsWindow"];

    self = [super initWithWindow:window];
    if (self) {
        _store = store;
        _engine = engine;
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleConfigChange:)
                                                     name:FWConfigDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleScreenChange:)
                                                     name:NSApplicationDidChangeScreenParametersNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)selectPaneWithKey:(NSString *)key {
    [self reloadSidebar];
    for (NSUInteger i = 0; i < _sidebarItems.count; i++) {
        if ([_sidebarItems[i][@"key"] isEqualToString:key]) {
            [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            break;
        }
    }
}

- (void)present {
    [self reloadSidebar];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)buildUI {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;

    // 标题栏高度（全尺寸内容视图下，内容从窗口顶端开始，需要为红绿灯留出空间）
    CGFloat titlebar = NSHeight(self.window.frame) - NSHeight(self.window.contentLayoutRect);
    if (titlebar < 20 || titlebar > 60) titlebar = 28;

    // 原生侧边栏：毛玻璃材质，跟随窗口激活状态，自动适配深浅色
    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] init];
    sidebar.material = NSVisualEffectMaterialSidebar;
    sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebar.state = NSVisualEffectStateFollowsWindowActiveState;
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:sidebar];

    // 内容区顶部的空白条：让标题栏覆盖在内容一侧时保持与内容一致的底色，而不是透出桌面
    FWColorView *topFill = [FWColorView viewWithColor:[NSColor windowBackgroundColor]];
    topFill.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:topFill];

    _contentContainer = [[NSView alloc] init];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_contentContainer];

    // 内容区底色（语义色，深浅色切换自动跟随）
    FWColorView *contentFill = [FWColorView viewWithColor:[NSColor windowBackgroundColor]];
    contentFill.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentContainer addSubview:contentFill];
    [NSLayoutConstraint activateConstraints:@[
        [contentFill.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
        [contentFill.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
        [contentFill.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
        [contentFill.bottomAnchor constraintEqualToAnchor:_contentContainer.bottomAnchor]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:236],

        [topFill.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [topFill.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [topFill.topAnchor constraintEqualToAnchor:root.topAnchor],
        [topFill.bottomAnchor constraintEqualToAnchor:_contentContainer.topAnchor],

        [_contentContainer.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_contentContainer.topAnchor constraintEqualToAnchor:root.topAnchor constant:titlebar],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];

    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = [NSImage imageWithSystemSymbolName:@"sparkles.rectangle.stack.fill"
                           accessibilityDescription:@"流光壁纸"];
    icon.contentTintColor = [NSColor controlAccentColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:icon];

    NSTextField *name = FWLabel(@"流光壁纸", 14, NSFontWeightSemibold, [NSColor labelColor]);
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:name];

    NSTextField *sub = FWLabel(@"动态桌面引擎", 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:sub];

    _sidebarTable = [[NSTableView alloc] init];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"sidebar"];
    col.width = 210;
    [_sidebarTable addTableColumn:col];
    _sidebarTable.headerView = nil;
    _sidebarTable.rowHeight = 42;
    _sidebarTable.style = NSTableViewStyleSourceList;
    _sidebarTable.backgroundColor = [NSColor clearColor];
    _sidebarTable.dataSource = self;
    _sidebarTable.delegate = self;
    _sidebarTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sidebarTable.allowsEmptySelection = NO;

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = _sidebarTable;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:scroll];

    NSTextField *footer = FWLabel(@"", 10.5, NSFontWeightRegular, [NSColor tertiaryLabelColor]);
    footer.identifier = @"footer";
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [icon.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:titlebar + 18],
        [icon.widthAnchor constraintEqualToConstant:22],
        [icon.heightAnchor constraintEqualToConstant:22],

        [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9],
        [name.topAnchor constraintEqualToAnchor:icon.topAnchor constant:-2],
        [name.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.trailingAnchor constant:-10],

        [sub.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:1],

        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],

        [footer.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [footer.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-12],
        [footer.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.trailingAnchor constant:-10]
    ]];

    [self updateFooter];
}

- (void)updateFooter {
    for (NSView *v in self.window.contentView.subviews) {
        [self findFooterIn:v andUpdate:YES];
    }
}

- (void)findFooterIn:(NSView *)view andUpdate:(BOOL)update {
    if ([view.identifier isEqualToString:@"footer"] && [view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        field.stringValue = [NSString stringWithFormat:@"v1.0 · %@", _engine.paused ? @"轮换已暂停" : @"运行中"];
        return;
    }
    for (NSView *sub in view.subviews) [self findFooterIn:sub andUpdate:update];
}

#pragma mark 侧边栏

- (void)reloadSidebar {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *screen in _engine.screens) {
        [items addObject:@{@"kind": @"display",
                           @"key": screen[@"key"],
                           @"name": screen[@"name"],
                           @"info": screen}];
    }
    [items addObject:@{@"kind": @"general", @"key": @"__general__", @"name": @"通用设置"}];
    _sidebarItems = items;

    NSInteger previous = _sidebarTable.selectedRow;
    [_sidebarTable reloadData];
    if (previous < 0 || previous >= (NSInteger)_sidebarItems.count) {
        [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    } else {
        [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:previous] byExtendingSelection:NO];
    }
    [self showPaneForRow:_sidebarTable.selectedRow];
    [self updateFooter];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_sidebarItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return nil;
    NSDictionary *entry = _sidebarItems[row];
    FWSidebarCell *cell = [tableView makeViewWithIdentifier:@"side" owner:self];
    if (!cell) {
        cell = [[FWSidebarCell alloc] initWithFrame:NSMakeRect(0, 0, 210, 42)];
        cell.identifier = @"side";
    }
    BOOL isGeneral = [entry[@"kind"] isEqualToString:@"general"];
    if (isGeneral) {
        cell.iconView.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
        cell.titleLabel.stringValue = @"通用设置";
        cell.subLabel.stringValue = @"启动项 · 性能 · 维护";
        cell.subLabel.hidden = NO;
        cell.titleLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    } else {
        NSDictionary *info = entry[@"info"];
        BOOL isMain = [info[@"isMain"] boolValue];
        cell.iconView.image = [NSImage imageWithSystemSymbolName:(isMain ? @"laptopcomputer" : @"display")
                                          accessibilityDescription:nil];
        cell.titleLabel.stringValue = entry[@"name"];
        NSUInteger count = [_store itemsForDisplay:entry[@"key"]].count;
        cell.subLabel.stringValue = [NSString stringWithFormat:@"%.0f × %.0f · %lu 项",
                                     [info[@"width"] doubleValue], [info[@"height"] doubleValue],
                                     (unsigned long)count];
        cell.subLabel.hidden = NO;
        cell.titleLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == _sidebarTable) {
        [self showPaneForRow:_sidebarTable.selectedRow];
    }
}

- (void)showPaneForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return;
    NSDictionary *entry = _sidebarItems[row];
    [_currentPane removeFromSuperview];

    NSView *pane = nil;
    if ([entry[@"kind"] isEqualToString:@"general"]) {
        pane = [[FWGeneralPane alloc] initWithStore:_store engine:_engine];
    } else {
        pane = [[FWDisplayPane alloc] initWithStore:_store
                                             engine:_engine
                                                key:entry[@"key"]
                                         screenInfo:entry[@"info"]];
    }
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentContainer addSubview:pane];
    [NSLayoutConstraint activateConstraints:@[
        [pane.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:_contentContainer.bottomAnchor]
    ]];
    _currentPane = pane;
}

#pragma mark 通知

- (void)handleConfigChange:(NSNotification *)note {
    if (!self.window.isVisible) return;
    if ([_currentPane respondsToSelector:@selector(reload)]) {
        [(id)_currentPane reload];
    }
    [_sidebarTable reloadData];
    [self updateFooter];
}

- (void)handleScreenChange:(NSNotification *)note {
    if (!self.window.isVisible) return;
    [self reloadSidebar];
}

@end
