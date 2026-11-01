// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import <Cocoa/Cocoa.h>
#import "FWCore.h"
#import "FWDisplay.h"

@interface FWSettingsWindowController : NSWindowController
- (instancetype)initWithStore:(FWConfigStore *)store engine:(FWEngine *)engine;
- (void)present;
- (void)selectPaneWithKey:(NSString *)key;
@end
