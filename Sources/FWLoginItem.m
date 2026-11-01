// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 The FlowWall Authors

#import "FWLoginItem.h"
#import <ServiceManagement/ServiceManagement.h>

BOOL FWLoginItemIsEnabled(void) {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

BOOL FWLoginItemNeedsApproval(void) {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusRequiresApproval;
    }
    return NO;
}

NSString *FWLoginItemSetEnabled(BOOL enabled) {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *error = nil;
        BOOL ok = YES;
        if (enabled) {
            if (service.status != SMAppServiceStatusEnabled) {
                ok = [service registerAndReturnError:&error];
            }
        } else {
            if (service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval) {
                ok = [service unregisterAndReturnError:&error];
            }
        }
        if (!ok && error) {
            NSLog(@"[FlowWall] 登录项设置失败: %@", error.localizedDescription);
            return error.localizedDescription;
        }
        return nil;
    }
    return @"需要 macOS 13 及以上系统";
}

void FWLoginItemOpenSettings(void) {
    if (@available(macOS 13.0, *)) {
        [SMAppService openSystemSettingsLoginItems];
    }
}
