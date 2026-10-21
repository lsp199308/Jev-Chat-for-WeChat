#include "WIA.h"

#pragma mark - 其他功能开关（后台保活 / 防止撤回 / 微信运动步数）

BOOL keepAliveEnabled = YES;       // 后台保活
BOOL preventRevokeEnabled = YES;   // 防止撤回
id gWIAMsgMgr = nil;              // 缓存的 CMessageMgr 实例（在 AsyncOnAddMsg 里赋值）
BOOL stepSpoofEnabled = YES;       // 步数
BOOL instantStep88888Enabled = NO; // 瞬间 88888
NSInteger stepTarget = 88888;      // 目标总步数
NSDate *lastInstantStepDate = nil;

BOOL wiaJudgeEnabled = YES; // 意图分析-判断层开关
BOOL wiaGenEnabled = YES;   // 意图分析-生成层开关
BOOL wiaQuickReplyEnabled = YES; // 快捷回复：开启显示并可直接点发送按钮
BOOL wiaAutoReplyEnabled = NO;   // 自动回复：开启后不点选也自动发送建议回复
BOOL wiaMemoryEnabled = YES;     // 记忆档案：判断层/生成层读取并更新「相处笔记」（默认开；不受持久化开关管，始终存盘，只能点「清除记忆档案」重建）
NSInteger wiaAutoReplyIndex = 1; // 自动回复用第几条建议（1-4）
NSInteger wiaJudgeContextLines = 12; // 判断层关联上下文条数（0=不关联）
NSInteger wiaGenContextLines = 16;   // 生成层关联上下文条数（0=不关联；放宽到16条保稳妥接话）

#pragma mark ==================== 其他功能（防撤回 / 步数）====================

#pragma mark - 防止撤回
// 获取 CMessageMgr 实例：MMServiceCenter 的单例名在头文件里未暴露，用运行时探测常见 selector；
// 拿不到再从 CMessageMgr 自身探测单例。
id WIAGetMsgMgr(void)
{
    return gWIAMsgMgr;
}

// 获取当前登录用户自己的微信 ID（官方头文件 MMContext +currentUserName 最可靠，getSelfContact 兜底）
static NSString *WIASelfUsrName(void)
{
    NSString *r = @"";
    @try {
        Class ctx = NSClassFromString(@"MMContext");
        if (ctx && [ctx respondsToSelector:@selector(currentUserName)]) {
            id u = ((id(*)(id, SEL))objc_msgSend)(ctx, @selector(currentUserName));
            if (u && [u isKindOfClass:[NSString class]] && [u length]) return u;
        }
    } @catch (NSException *e) {}
    @try {
        Class sc = NSClassFromString(@"MMServiceCenter");
        if (!sc) return r;
        id center = ((id(*)(id, SEL))objc_msgSend)(sc, @selector(defaultCenter));
        if (!center) return r;
        id cm = ((id(*)(id, SEL, id))objc_msgSend)(center, @selector(getService:), NSClassFromString(@"CContactMgr"));
        if (!cm) return r;
        id selfC = ((id(*)(id, SEL))objc_msgSend)(cm, @selector(getSelfContact));
        if (selfC) {
            id u = [selfC valueForKey:@"m_nsUsrName"];
            if (u && [u isKindOfClass:[NSString class]] && [u length]) r = u;
        }
    } @catch (NSException *e) {}
    return r;
}

// 原文件 WIAIsOutgoingMessage 的完整逻辑：判断一条消息是否是我发送的
static BOOL WIARevokedIsSelf(id wrap)
{
    if (!wrap) return NO;
    @try {
        int ss = [[wrap valueForKey:@"m_uiIsSenderStatus"] intValue];
        if (ss != 0) return YES;
    } @catch (NSException *e) {}
    @try {
        Class cls = NSClassFromString(@"CMessageWrap");
        if (cls && [cls respondsToSelector:NSSelectorFromString(@"isSenderFromMsgWrap:")]) {
            BOOL is = ((BOOL(*)(Class, SEL, id))objc_msgSend)(cls, NSSelectorFromString(@"isSenderFromMsgWrap:"), wrap);
            if (is) return YES;
        }
    } @catch (NSException *e) {}
    return NO;
}

%hook MessageRevokeMgr

- (void)onRevokeMsg:(CMessageWrap *)arg1 {
    if (!preventRevokeEnabled) { %orig; return; }

    // 判断是否自己撤回自己的消息（交给微信正常处理，不拦截）：
    // 1) arg1 本身是我发送的消息（senderStatus / isSenderFromMsgWrap）；
    // 2) 撤回发起者是我自己。
    BOOL selfRevoked = WIARevokedIsSelf(arg1);
    if (!selfRevoked) {
        @try {
            NSString *selfU = WIASelfUsrName();
            NSString *fromU = [arg1 valueForKey:@"m_nsFromUsr"] ?: @"";
            if (selfU.length && fromU.length && [fromU isEqualToString:selfU]) selfRevoked = YES;
        } @catch (NSException *e) {}
    }
    if (selfRevoked) { %orig; return; }

    @try {
        NSString *msgContent = arg1.m_nsContent ?: @"";
        NSString *fromUsrName = @"未知用户";

        NSRange cdataRange = [msgContent rangeOfString:@"<![CDATA["];
        if (cdataRange.location != NSNotFound) {
            NSUInteger start = cdataRange.location + cdataRange.length;
            NSRange endRange = [msgContent rangeOfString:@"撤回了一条消息"];
            if (endRange.location != NSNotFound && endRange.location > start) {
                fromUsrName = [msgContent substringWithRange:NSMakeRange(start, endRange.location - start)];
            }
        }

        NSString *(^parseSession)(void) = ^NSString *{
            NSRange start = [msgContent rangeOfString:@"<session>"];
            NSRange end   = [msgContent rangeOfString:@"</session>"];
            if (start.location != NSNotFound && end.location != NSNotFound && end.location > start.location) {
                return [msgContent substringWithRange:NSMakeRange(start.location + start.length, end.location - (start.location + start.length))];
            }
            return @"";
        };
        NSString *session = parseSession();
        // XML 里取不到 <session> 时，回退用撤回消息的 m_nsFromUsr 作为会话，保证提示能加上
        if (session.length == 0) {
            @try { session = arg1.m_nsFromUsr ?: @""; } @catch (NSException *e) { session = @""; }
        }
        if (session.length == 0) return;

        id msgMgr = WIAGetMsgMgr();
        if (!msgMgr) return;

        NSString *revokeTip = [NSString stringWithFormat:@"已拦截 %@ 撤回的消息", fromUsrName];
        id revokedWrap = nil;
        long long revokedSvr = 0;
        // 去掉时间戳；并尝试把被撤回的消息正文查出来附上（best-effort，查不到只显示拦截提示）
        @try {
            NSString *nid = @"";
            NSRange ns = [msgContent rangeOfString:@"<newmsgid>"];
            NSRange ne = [msgContent rangeOfString:@"</newmsgid>"];
            if (ns.location != NSNotFound && ne.location != NSNotFound && ne.location > ns.location) {
                nid = [msgContent substringWithRange:NSMakeRange(ns.location + ns.length, ne.location - (ns.location + ns.length))];
            }
            if (nid.length > 0) {
                revokedSvr = [nid longLongValue];
                revokedWrap = ((id (*)(id, SEL, id, long long))objc_msgSend)(msgMgr, sel_registerName("GetMsg:n64SvrID:"), session, revokedSvr);
                if (revokedWrap) {
                    // 只对被撤回的文字消息显示内容；图片/视频等非文字不显示
                    int mt = 0;
                    @try { mt = [[revokedWrap valueForKey:@"m_uiMessageType"] intValue]; } @catch (NSException *e) {}
                    if (mt == 1) {
                        NSString *rc = [revokedWrap valueForKey:@"m_nsContent"];
                        if ([rc length] > 0) {
                            revokeTip = [revokeTip stringByAppendingFormat:@"\n「%@」", rc];
                        }
                    }
                }
            }
        } @catch (NSException *e) {}
        // 判断被撤回消息是否是自己发送的：自己撤回自己的消息不拦截（交给微信正常处理）
        if (revokedWrap) {
            int senderStatus = 0;
            @try { senderStatus = [[revokedWrap valueForKey:@"m_uiIsSenderStatus"] intValue]; } @catch (NSException *e) {}
            if (senderStatus != 0) { %orig; return; }
        }
        // 用 AddLocalMsg 追加一条拦截提示；提示的创建时间设为被撤回消息的创建时间，
        // 让微信按时间排序把提示插到被撤回消息附近（而非列表末尾），位置即正确。
        CMessageWrap *tipWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:0x2710];
        tipWrap.m_nsFromUsr = arg1.m_nsFromUsr;
        tipWrap.m_nsToUsr   = arg1.m_nsToUsr;
        tipWrap.m_uiMessageType = 0x2710;
        tipWrap.m_uiStatus = 0x4;
        tipWrap.m_nsContent = revokeTip;
        unsigned int tipTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        if (revokedWrap) {
            @try { tipTime = [[revokedWrap valueForKey:@"m_uiCreateTime"] unsignedIntValue]; } @catch (NSException *e) {}
            tipTime += 1;   // 比被撤回消息晚 1 秒，提示排在被撤回消息下方
        }
        tipWrap.m_uiCreateTime = tipTime;
        // 优先用带显式时间的 AddLocalMsg:MsgWrap:Time:，确保按原消息时间插入；否则回退 fixTime:NO
        SEL addTimeSel = sel_registerName("AddLocalMsg:MsgWrap:Time:");
        if ([msgMgr respondsToSelector:addTimeSel]) {
            ((void(*)(id, SEL, id, id, unsigned int))objc_msgSend)(msgMgr, addTimeSel, session, tipWrap, tipTime);
        } else {
            [msgMgr AddLocalMsg:session MsgWrap:tipWrap fixTime:NO NewMsgArriveNotify:NO];
        }
    } @catch (NSException *e) {}

    return; // 阻止原撤回逻辑
}

%end

#pragma mark - 微信运动步数
%hook WCDeviceStepObject

- (NSInteger)m7StepCount {
    if (instantStep88888Enabled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDate *lastDate = [defaults objectForKey:@"lastInstantStepDate"];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        if (lastDate && [calendar isDateInToday:lastDate]) {
            return 88888;
        } else {
            instantStep88888Enabled = NO;
            [defaults setBool:NO forKey:@"instantStep88888Enabled"];
            [defaults synchronize];
        }
    }

    NSInteger originalSteps = %orig;
    if (!stepSpoofEnabled) return originalSteps;

    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger hour = [calendar component:NSCalendarUnitHour fromDate:now];
    NSInteger minute = [calendar component:NSCalendarUnitMinute fromDate:now];
    NSInteger second = [calendar component:NSCalendarUnitSecond fromDate:now];

    NSInteger totalSeconds = 21 * 3600;
    NSInteger currentSeconds = hour * 3600 + minute * 60 + second;
    if (currentSeconds > totalSeconds) currentSeconds = totalSeconds;

    double targetStepsCalc = stepTarget * ((double)currentSeconds / (double)totalSeconds);
    int randomOffset = arc4random_uniform(401) - 200;
    targetStepsCalc += randomOffset;
    if (targetStepsCalc < 0) targetStepsCalc = 0;

    NSInteger finalSteps = MAX(originalSteps, (NSInteger)targetStepsCalc);
    if (finalSteps > stepTarget) finalSteps = stepTarget;
    return finalSteps;
}

%end
