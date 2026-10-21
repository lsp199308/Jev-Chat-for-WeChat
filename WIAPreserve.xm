/*
  Jev-Chat 后台保活（移植自 ImmortalizerJailed，GPL-3.0，作者 Serge Alagon）
  原理：hook FBSWorkspaceScenesClient sceneID:updateWithSettingsDiff:，吞掉把 foreground 置 No 的
  「退后台」指令 → 系统始终认为微信在前台，永不挂起；辅以 UIApplication applicationState 谎报、
  通知强制弹出、悬浮按钮 + base64 静音音频 + toast。
  开关与设置页「后台运行」keepAliveEnabled 共用。
*/

#include "WIA.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UserNotifications/UserNotifications.h>
#import <notify.h>
#import "FloatingButtonWindow.h"

#define kWIAKeepAliveNotifyKey "com.jevchat.keepalive"

static BOOL isPhysicallyInBackground = NO;

// ============ 保持前台核心：吞掉「退后台」的 scene 更新 ============
static void (*orig_sceneID_updateWithSettingsDiff_transitionContext_completion)(id, SEL, id, id, id, id);

void new_sceneID_updateWithSettingsDiff_transitionContext_completion(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!keepAliveEnabled) {
        if (orig_sceneID_updateWithSettingsDiff_transitionContext_completion) {
            orig_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
        }
        return;
    }

    NSString *diffDescription = [arg2 description];

    // 系统要把本 scene 切去后台（foreground=No）→ 直接吞掉，不让 App 收到「退后台」指令
    if ([diffDescription containsString:@"foreground = NotSet"] ||
        [diffDescription containsString:@"foreground = No"] ||
        [diffDescription containsString:@"foreground = BSSettingFlagNo"] ||
        [diffDescription containsString:@"foreground = NO"]) {
        return;
    }
    if ([diffDescription containsString:@"hostContextIdentifierForSnapshotting = 0"] ||
        [diffDescription containsString:@"scenePresenterRenderIdentifierForSnapshotting = 0"] ||
        [diffDescription containsString:@"targetOfEventDeferringEnvironments = (empty)"]) {
        return;
    }
    if ([diffDescription containsString:@"FBSceneSnapshotAction:"]) {
        return;
    }

    if (orig_sceneID_updateWithSettingsDiff_transitionContext_completion) {
        orig_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
    }
}

// ============ applicationState 谎报 ============
static UIApplicationState (*orig_applicationState)(id, SEL);
static UIApplicationState hook_applicationState(id self, SEL _cmd) {
    if (keepAliveEnabled && isPhysicallyInBackground) {
        void *returnAddress = __builtin_extract_return_addr(__builtin_return_address(0));
        Dl_info info;
        if (dladdr(returnAddress, &info) && info.dli_fname) {
            NSString *imageName = [NSString stringWithUTF8String:info.dli_fname];
            if ([imageName containsString:@"UserNotifications"] || [imageName containsString:@"PushKit"]) {
                return UIApplicationStateBackground; // 让通知系统正常弹
            }
        }
        return UIApplicationStateActive;
    }
    return orig_applicationState ? orig_applicationState(self, _cmd) : UIApplicationStateActive;
}

// ============ 前台态也强制弹通知（否则系统以为在前台，通知默认不弹） ============
static void (*orig_willPresent)(id, SEL, UNUserNotificationCenter *, UNNotification *, void (^)(UNNotificationPresentationOptions));
static void hook_willPresent(id self, SEL _cmd, UNUserNotificationCenter *center, UNNotification *notification, void (^completionHandler)(UNNotificationPresentationOptions options)) {
    if (keepAliveEnabled && isPhysicallyInBackground) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
    } else if (orig_willPresent) {
        orig_willPresent(self, _cmd, center, notification, completionHandler);
    }
}

static void (*orig_setDelegate)(id, SEL, id<UNUserNotificationCenterDelegate>);
static void hook_setDelegate(id self, SEL _cmd, id<UNUserNotificationCenterDelegate> delegate) {
    if (orig_setDelegate) orig_setDelegate(self, _cmd, delegate);
    if (delegate) {
        Class delegateClass = [delegate class];
        SEL sel = @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:);
        Method method = class_getInstanceMethod(delegateClass, sel);
        if (method) {
            IMP currentIMP = method_getImplementation(method);
            if (currentIMP != (IMP)hook_willPresent) {
                orig_willPresent = (void (*)(id, SEL, UNUserNotificationCenter *, UNNotification *, void (^)(UNNotificationPresentationOptions)))currentIMP;
                method_setImplementation(method, (IMP)hook_willPresent);
            }
        }
    }
}

// ============ 开关变化（设置页 / 悬浮按钮）→ 刷新按钮 ============
static void prefsChanged() {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FloatingButtonWindow sharedInstance] syncWithPrefs];
    });
}

// ============ setup：装 hooks + 跟踪进出后台 + 监听开关通知 + 显示按钮 ============
static void setup() {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. Scene Hook：保持前台核心
        Class targetClass = objc_getClass("FBSWorkspaceScenesClient");
        SEL originalSelector = @selector(sceneID:updateWithSettingsDiff:transitionContext:completion:);
        Method originalMethod = targetClass ? class_getInstanceMethod(targetClass, originalSelector) : NULL;
        if (originalMethod) {
            orig_sceneID_updateWithSettingsDiff_transitionContext_completion =
                (void (*)(id, SEL, id, id, id, id))method_getImplementation(originalMethod);
            method_setImplementation(originalMethod, (IMP)new_sceneID_updateWithSettingsDiff_transitionContext_completion);
        }

        // 2. Application State Hook
        Class uiAppClass = objc_getClass("UIApplication");
        Method appStateMethod = class_getInstanceMethod(uiAppClass, @selector(applicationState));
        if (appStateMethod) {
            orig_applicationState = (UIApplicationState (*)(id, SEL))method_getImplementation(appStateMethod);
            method_setImplementation(appStateMethod, (IMP)hook_applicationState);
        }

        // 3. Notification Delegate Hook
        Class unCenterClass = objc_getClass("UNUserNotificationCenter");
        Method setDelegateMethod = class_getInstanceMethod(unCenterClass, @selector(setDelegate:));
        if (setDelegateMethod) {
            orig_setDelegate = (void (*)(id, SEL, id<UNUserNotificationCenterDelegate>))method_getImplementation(setDelegateMethod);
            method_setImplementation(setDelegateMethod, (IMP)hook_setDelegate);
        }

        // 4. 跟踪物理进出后台
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            isPhysicallyInBackground = YES;
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            isPhysicallyInBackground = NO;
        }];

        // 5. 开关通知（设置页 / 悬浮按钮改动都走这里刷新）
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        (CFNotificationCallback)prefsChanged,
                                        CFSTR(kWIAKeepAliveNotifyKey), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // 6. 悬浮按钮（按当前开关显示/隐藏）
        FloatingButtonWindow *btn = [FloatingButtonWindow sharedInstance];
        if (keepAliveEnabled) [btn showButton]; else [btn hideButton];
    });
}

%ctor
{
    @autoreleasepool {
        // 兜底再读一次开关（构造顺序不保证，幂等）
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if ([d objectForKey:@"keepAliveEnabled"]) keepAliveEnabled = [d boolForKey:@"keepAliveEnabled"];
        setup();
    }
}
