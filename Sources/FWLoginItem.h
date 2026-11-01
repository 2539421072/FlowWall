// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import <Foundation/Foundation.h>

/// 开机自启（macOS 13+ 使用 SMAppService）
BOOL FWLoginItemIsEnabled(void);
BOOL FWLoginItemNeedsApproval(void);
/// 返回 nil 表示成功，否则为错误描述
NSString *FWLoginItemSetEnabled(BOOL enabled);
void FWLoginItemOpenSettings(void);
