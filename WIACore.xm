#include "WIA.h"

static void WIAAppendMemoryBrief(NSMutableString *tpl, NSString *chatID);   // 前置声明：生成 prompt 注入相处笔记
NSString *WIASinceLast(NSString *chatID);                                    // 前置声明：距该会话上一条消息的可读间隔
static NSString *WIAWithTimeContext(NSString *chatID);                       // 前置声明：时间坐标+记忆时效段


// ================= 运行时可覆盖 =================
// 下方常量是默认值；如果你不想改代码重编译，可在微信里设置（或 Filza 改
// /var/mobile/Library/Preferences/com.local.wia.plist 的对应键）：
//   判断层：wiaJudgeBase / wiaJudgeKey / wiaJudgeModel
//   生成层：wiaGenBase / wiaGenKey / wiaGenModel / wiaGenKind
// 每个键填了就用填的值，没填就用上方常量。
NSString *WIACfgString(NSString *key, NSString *def) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return (v.length) ? v : (def ?: @"");
}
NSString *WIAJudgeBase(void)  { return WIACfgString(@"wiaJudgeBase",  kWIACfgJudgeBase); }
NSString *WIAJudgeKey(void)   { return WIACfgString(@"wiaJudgeKey",   kWIACfgJudgeKey); }
NSString *WIAJudgeModel(void) { return WIACfgString(@"wiaJudgeModel", kWIACfgJudgeModel); }
NSString *WIAGenBase(void)    { return WIACfgString(@"wiaGenBase",    kWIACfgGenBase); }
NSString *WIAGenKey(void)     { return WIACfgString(@"wiaGenKey",     kWIACfgGenKey); }
NSString *WIAGenModel(void)   { return WIACfgString(@"wiaGenModel",   kWIACfgGenModel); }
NSString *WIAGenKind(void)    { return WIACfgString(@"wiaGenKind",    kWIACfgGenKind); }



// 全部可选回复方式（设置页「回复方式」列出，可多选勾选）
NSArray *WIAToneList(void)
{
    return @[ @"高情商话术", @"贴吧老哥 v1.0", @"拒绝加班", @"卑微乙方",
              @"稳如老狗", @"已读乱回", @"鱼塘主", @"职场黑话",
              @"阴阳怪气", @"情绪价值", @"夸夸", @"讨好型人格",
              @"狗头军师", @"狗头军师·会撩", @"狗头军师·抽离" ];
}

// 用户勾选的回复方式（默认前两种：情绪价值 + 讨好型人格，共 4 条）
NSArray *wiaSelectedTones = nil;
BOOL wiaToneRealEnabled = YES;   // 话术模式：开=话术当底子+真实口吻；关=纯真实角度

// 每个话术的人设指令（喂给生成层）。
NSDictionary *WIAToneInstructions(void)
{
    return @{
        @"高情商话术" : @"像公司里那个谁都说好的老同事：先接住对方情绪（「我理解」「确实」），再说事实和下一步，拒绝也带替代方案加一个具体时间点。不说教、不绕圈子、句尾不堆「呢/哦/啦」。",
        @"贴吧老哥 v1.0" : @"贴吧老哥：一口网感口语，「有一说一」「绷不住了」「搁这」「这就去整」随手就来，自称我、管对方叫「哥/兄弟」，可以自嘲玩梗甚至摆烂，但不骂人。禁止「您好」「感谢」这类书面客套。",
        @"拒绝加班" : @"态度平和但把话说死：明确今天做不完，不给「我尽量」「看情况」这种会被继续压的口子；必须给一个具体替代时间（比如「明早九点前」），并说清不用等今晚。道歉不超过一句，理由不超过一句。",
        @"卑微乙方" : @"极度卑微的乙方：「好的好的」「收到收到」「实在抱歉」「麻烦您了」张口就来，全程称「您」，任何问题先认在自己头上，随叫随到。夸张到一眼看出是梗，但整句仍然能直接发出去。",
        @"稳如老狗" : @"十年老工程师那种稳：不解释、不铺垫、不道歉，只给结论加一个时间点，句子短、主语是事不是情绪（「三点前给你」「已确认，没问题」），让对方觉得事情已经稳了。",
        @"已读乱回" : @"敷衍但不失礼：一到六个字把对方接住（「在忙，你说」「嗯嗯」「好」），不承诺、不展开、不给时间点，让对方觉得回了又没法接着追问。",
        @"鱼塘主" : @"海王海后式的推拉。每条回复里都要有一推一拉：先用一句淡淡的调侃把距离拉开，紧接着给一点真心的甜头，让人想再追问一句；对方提要求时先接住、再讲条件，事情不说死，收尾留个悬念。惜字如金，不解释、不道歉、不讨好，不揽活不背锅，嘴甜心硬。推是让对方多想一步，不是把人推开：不冷嘲热讽、不居高临下、不连环追问；对方好好说话时就别用推拉。不油腻、不露骨，整句要能直接发出去。不要照抄这段话里的任何措辞。",
        @"职场黑话" : @"把简单的事说得很专业：对齐、抓手、闭环、颗粒度、拉通、复盘、赋能、沉淀、打法轮着用，一句话里至少两个；但整句要能看懂，不要堆到不知所云。",
        @"阴阳怪气" : @"表面客气、话里带刺：多用「哦」「呢」「那就」「辛苦你了」配反问或夸张的客气，让对方不好发作又不能说你没礼貌。不要升级成直接骂人或人身攻击。",
        @"情绪价值" : @"情绪价值为先。认同的是对方的感受和处境（累、委屈、烦），不是对方话里的结论——绝不顺着别人对 ta 的否定说话（「你妈说得对」这种最伤人）；对方和别人有冲突时站到对方这边，不评判谁对谁错。对方没问「怎么办」就别急着给方案、别总结、别讲道理，也绝不说「别想太多」「这没什么」「想开点」。认同要具体（点出对方做的哪一点），但不空泛吹捧、不说教、不写小作文；不知道关系就别加「宝贝」「亲爱的」，也不堆 emoji。整句要能直接发出去，不要照抄这段话里的任何措辞。",
        @"夸夸" : @"像夸夸群里的金牌群友：夸人夸具体——抓住对方消息里的细节往高了夸（眼光、效率、品位都行），语气真诚热络，「绝了」「这也太强了」「服了」随手就来，可以带感叹号；夸完顺势把正事接住（该答应的答应、该给时间的给时间）。不空泛、不谄媚、不连用三个感叹号，别把夸说成阴阳怪气。",
        @"讨好型人格" : @"把对方的心情放在自己前面：先问清需求再表态顺从（「都听你的」「你说怎样就怎样」），习惯性先自贬一句（「是我笨」「我反应慢」），末尾爱追一句「这样行吗」「你没生气吧」。答应得比能做到的快，宁可自己加班也不想让对方失望。语气软、句尾带语气词，但不卖惨、不写小作文、不真把自己说成一无是处，整句仍然要能直接发出去。",
        @"狗头军师" : @"清醒的恋爱军师·稳健版：先接住对方的情绪或话头（累了先心疼、分享先接住），再把关系往前推一小步——一个具体的问题或低压力的邀约，一句话只做一件事。像个真实清醒的朋友：不舔不跪、不查户口式追问、不写小作文，邀约给对方能拒绝的台阶。",
        @"狗头军师·会撩" : @"清醒的恋爱军师·会撩版：带一点张力——用调侃、反差或画面感先轻轻推一下，再把球抛回去留个对方能接的出口；欣赏就夸具体的细节，不空夸。分寸在敢推进但不油腻：不忽冷忽热玩套路、不贬低、不硬撩，对方不接就自然收。",
        @"狗头军师·抽离" : @"清醒的恋爱军师·抽离版：对方冷淡、敷衍或只回「哈哈」时，不追问、不解释、不二次挽尊——一句话体面收住当轮（「先去忙，想聊再找我」），把主动权留给下次。不阴阳怪气、不赌气、不发小作文式告别，收得干脆但留得住体面。",
    };
}

void WIASendReply(NSString *toUser, NSString *fromUser, NSString *text);   // 前置声明（定义在文件后部）

void WIALoadFeatureDefaults(void) {
    // 清理历史调试日志 wia-long.log（旧版本生成，现不再写）
    [[NSFileManager defaultManager] removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/wia-long.log"] error:nil];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"keepAliveEnabled"])      keepAliveEnabled = [d boolForKey:@"keepAliveEnabled"];
    if ([d objectForKey:@"preventRevokeEnabled"])  preventRevokeEnabled = [d boolForKey:@"preventRevokeEnabled"];
    if ([d objectForKey:@"stepSpoofEnabled"])      stepSpoofEnabled = [d boolForKey:@"stepSpoofEnabled"];
    if ([d objectForKey:@"instantStep88888Enabled"]) instantStep88888Enabled = [d boolForKey:@"instantStep88888Enabled"];
    if ([d objectForKey:@"stepTarget"])            stepTarget = [d integerForKey:@"stepTarget"];
    lastInstantStepDate = [d objectForKey:@"lastInstantStepDate"];
    if ([d objectForKey:@"wiaJudgeEnabled"])       wiaJudgeEnabled = [d boolForKey:@"wiaJudgeEnabled"];
    if ([d objectForKey:@"wiaGenEnabled"])         wiaGenEnabled = [d boolForKey:@"wiaGenEnabled"];
    if ([d objectForKey:@"wiaQuickReplyEnabled"])  wiaQuickReplyEnabled = [d boolForKey:@"wiaQuickReplyEnabled"];
    if ([d objectForKey:@"wiaAutoReplyEnabled"])   wiaAutoReplyEnabled  = [d boolForKey:@"wiaAutoReplyEnabled"];
    if ([d objectForKey:@"wiaAutoReplyIndex"])     wiaAutoReplyIndex    = [d integerForKey:@"wiaAutoReplyIndex"];
    wiaAutoReplyIndex = MIN(MAX(wiaAutoReplyIndex, 1), 4);
    // 话术模式：开=话术当底子+真实口吻；关=纯真实角度（未设置过则默认开）
    if ([d objectForKey:@"wiaToneRealEnabled"])    wiaToneRealEnabled   = [d boolForKey:@"wiaToneRealEnabled"];
    // 兼容旧键 wiaContextLines
    NSInteger oldCtx = -1;
    if ([d objectForKey:@"wiaContextLines"]) oldCtx = [d integerForKey:@"wiaContextLines"];
    if ([d objectForKey:@"wiaJudgeContextLines"]) wiaJudgeContextLines = [d integerForKey:@"wiaJudgeContextLines"];
    else if (oldCtx >= 0) wiaJudgeContextLines = oldCtx;
    if ([d objectForKey:@"wiaGenContextLines"]) wiaGenContextLines = [d integerForKey:@"wiaGenContextLines"];
    else if (oldCtx >= 0) wiaGenContextLines = oldCtx;
    wiaJudgeContextLines = MIN(MAX(wiaJudgeContextLines, 0), 20);
    wiaGenContextLines   = MIN(MAX(wiaGenContextLines, 0), 20);
    if ([d objectForKey:@"wiaEntryMode"]) wiaEntryMode = [d integerForKey:@"wiaEntryMode"];
    // 用户勾选的回复方式（缺省默认前两种）
    if ([d objectForKey:@"wiaSelectedTones"]) {
        NSArray *sel = [d arrayForKey:@"wiaSelectedTones"];
        NSMutableArray *valid = [NSMutableArray array];
        for (NSString *t in sel) {
            if ([WIAToneList() containsObject:t] && ![valid containsObject:t]) [valid addObject:t];
        }
        wiaSelectedTones = valid;
    } else {
        wiaSelectedTones = kWIACfgTones;
    }
    // 话术固定 4 个：超了截断，不足用默认补
    if (wiaSelectedTones.count > 4) {
        wiaSelectedTones = [wiaSelectedTones subarrayWithRange:NSMakeRange(0, 4)];
    } else {
        NSMutableArray *m = [NSMutableArray arrayWithArray:wiaSelectedTones];
        for (NSString *t in kWIACfgTones) {
            if (m.count >= 4) break;
            if (![m containsObject:t]) [m addObject:t];
        }
        wiaSelectedTones = m;
    }
    // 建议回复关闭时，快捷回复 / 自动回复一并关闭
    if (!wiaGenEnabled) {
        wiaQuickReplyEnabled = NO;
        wiaAutoReplyEnabled = NO;
    }
    // 分析结果不持久化：只显示当前最新消息，重启即无
    if ([d objectForKey:@"wiaMemoryEnabled"])  wiaMemoryEnabled  = [d boolForKey:@"wiaMemoryEnabled"];
    WIAReadMemory();   // 记忆档案：与关系档案一样，默认加载存盘（不受持久化开关管）
}

#pragma mark - 判断层数据（移植自 JevPrompts.swift）

static NSArray *WIARiskLevels(void)
{
    return @[
        @"完全没风险", @"基本没风险", @"平淡正常回",
        @"稍微留神", @"有点敏感", @"需要谨慎",
        @"比较危险", @"很危险", @"非常危险", @"极度危险先别回",
    ];
}

// 人性化意图：问"人的心态"而不是"工作任务标签"（贴近截图 Jev 的问法）。
static NSDictionary *WIAHumanIntents(void)
{
    return @{
        @"想确认你在不在乎" : @"需要你证明你在意、不被敷衍",
        @"带着情绪想发作"   : @"憋着不满，想让你先安抚或接住",
        @"要个说法交代"     : @"需要你解释清楚、给个交代",
        @"求回应求陪伴"     : @"主要是想有人接住、陪聊",
        @"随口闲聊分享"     : @"没要求，就是聊天分享",
        @"实际有事要办"     : @"有具体事要你处理",
    };
}

static NSDictionary *WIAActionMap(void)
{
    return @{
        @"派活"   : @"先接下，问清交付标准和期限，给个时间点",
        @"催进度" : @"先给当前状态，给明确完成时间，别解释太多",
        @"问进度" : @"直接说事实，给下个节点，有卡点就说卡点",
        @"批评"   : @"先认下来，别急着辩解，给补救方案",
        @"要解释" : @"说清原因，别找借口，给改进措施",
        @"闲聊"   : @"轻松回应，可以互动，不用当真",
        @"邀约" : @"确认时间，说清议程，准备好材料",
        @"夸奖"   : @"接住并感谢，别过度谦虚，可以顺带提下一步",
    };
}

// 通用「最佳动作」候选（判断层 choice 题 criteria）。
static NSDictionary *WIAActionCandidates(void)
{
    return @{
        @"接住情绪回应情感" : @"对方在表达想念/情绪/想要回应，先接住并回应情感（承接/情绪价值），不转话题、不讲理、不急着给方案",
        @"安抚情绪再回"     : @"对方带着不满或委屈，先安抚情绪再讲事",
        @"先确认再回"       : @"信息不够，先确认/搜索再回复，别硬猜",
        @"直接给回应"       : @"对方要的是明确回应或答案，直接给，不绕",
        @"约个时间详聊"     : @"事情复杂，约时间说清楚",
        @"表示感谢"         : @"对方在肯定/表达好感，接住并感谢、回应",
        @"认错并给补救"     : @"是我的问题，先认下来再给补救方案",
        @"先别急着回"       : @"危险度高，想清楚再回或先不回",
    };
}

// 本轮行动策略（决定回复方向：推进/退让/等待/追问）。与意图（对方什么心态）互补。
static NSDictionary *WIAStrategies(void)
{
    return @{
        @"承接" : @"接住对方情绪或分享，先倾听，不急着解决或升级",
        @"降压" : @"对方忙、累、犹豫或被反复追问时，减压、暂停追求，不把一次模糊回复当拒绝",
        @"调侃" : @"对方明显在开玩笑时，轻松尊重地逗趣，不嘲笑脆弱、不忽视不适",
        @"轻推" : @"双方都有投入但对话停滞时，推进一小步，不索要承诺",
        @"约见" : @"双方互惠有兴趣且有可信时间/活动窗口时，给具体、低压力的邀约",
        @"澄清" : @"有一个关键未知或矛盾阻止负责任下一步时，问一个关键问题，不臆测",
        @"收线" : @"对方明确拒绝/划清边界，或反复单向投入、取消后，停止追求；单次忙不构成此模式",
    };
}

// 本地规则兜底：按判断出的动作给一个策略默认值。
static NSString *WIARuleStrategy(NSString *action)
{
    if ([action isEqualToString:@"约个时间详聊"]) return @"约见";
    if ([action isEqualToString:@"先确认再回"]) return @"澄清";
    if ([action isEqualToString:@"先别急着回"]) return @"降压";
    if ([action isEqualToString:@"转移话题"]) return @"调侃";
    if ([action isEqualToString:@"安抚情绪再回"] ||
        [action isEqualToString:@"认错并给补救"] ||
        [action isEqualToString:@"表示感谢"] ||
        [action isEqualToString:@"接住情绪回应情感"] ||
        [action isEqualToString:@"直接给回应"]) return @"承接";
    if ([action isEqualToString:@"直接回事实"]) return @"轻推";
    return @"承接";
}

static NSString *WIARiskLabel(double score)
{
    int idx = (int)lround(score);
    NSArray *levels = WIARiskLevels();
    idx = MAX(0, MIN(idx, (int)levels.count - 1));
    return levels[idx];
}

// 截断到前 max 个字符（用于把消息嵌进追问问题文本，避免过长）。
static NSString *WIATrim(NSString *s, NSUInteger max)
{
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return s ?: @"";
    if (s.length <= max) return s;
    NSString *cut = [s substringToIndex:max];
    return [cut stringByAppendingString:@"…"];
}

#pragma mark - 消息字段读取（防御性 KVC）

NSString *WIAReadString(id obj, NSString *key)
{
    if (!obj) return nil;
    @try {
        id v = [obj valueForKey:key];
        if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    } @catch (NSException *exception) { }
    return nil;
}

unsigned int WIAReadUInt(id obj, NSString *key)
{
    if (!obj) return 0;
    @try {
        return [[obj valueForKey:key] unsignedIntValue];
    } @catch (NSException *exception) { return 0; }
}

long long WIAReadInt64(id obj, NSString *key)
{
    if (!obj) return 0;
    @try {
        return [[obj valueForKey:key] longLongValue];
    } @catch (NSException *exception) { return 0; }
}

NSString *WIAMessageKey(id wrap)
{
    NSString *from = WIAReadString(wrap, @"m_nsFromUsr") ?: @"";
    NSString *content = WIAReadString(wrap, @"m_nsContent") ?: @"";
    long long svrId = WIAReadInt64(wrap, @"m_n64MesSvrID");
    return [NSString stringWithFormat:@"%@|%@|%lld", from, content, svrId];
}

BOOL WIAIsTextMessage(id wrap)
{
    NSString *content = WIAReadString(wrap, @"m_nsContent");
    if (![content isKindOfClass:[NSString class]] || content.length == 0) return NO;
    if (WIAReadUInt(wrap, @"m_uiMessageType") != 1) return NO;
    return YES;
}

BOOL WIAIsOutgoingMessage(id wrap)
{
    if (!wrap) return NO;
    if (WIAReadUInt(wrap, @"m_uiIsSenderStatus") != 0) return YES;

    static BOOL triedSenderMethod = NO;
    static BOOL senderMethodAvailable = NO;
    if (!triedSenderMethod) {
        triedSenderMethod = YES;
        Class cls = NSClassFromString(@"CMessageWrap");
        senderMethodAvailable =
            (cls != nil) &&
            [cls respondsToSelector:NSSelectorFromString(@"isSenderFromMsgWrap:")];
    }
    if (senderMethodAvailable) {
        @try {
            Class cls = NSClassFromString(@"CMessageWrap");
            BOOL isSender =
                ((BOOL (*)(Class, SEL, id))objc_msgSend)(
                    cls, NSSelectorFromString(@"isSenderFromMsgWrap:"), wrap);
            if (isSender) return YES;
        } @catch (NSException *exception) { }
    }
    return NO;
}

BOOL WIAIsGroupMessage(id wrap)
{
    if (!wrap) return NO;
    NSString *from = WIAReadString(wrap, @"m_nsFromUsr");
    if ([from containsString:@"@chatroom"]) return YES;

    static BOOL triedChatRoom = NO;
    static BOOL chatRoomAvailable = NO;
    if (!triedChatRoom) {
        triedChatRoom = YES;
        chatRoomAvailable =
            [wrap respondsToSelector:NSSelectorFromString(@"IsChatRoomMessage")];
    }
    if (chatRoomAvailable) {
        @try {
            return ((BOOL (*)(id, SEL))objc_msgSend)(
                wrap, NSSelectorFromString(@"IsChatRoomMessage"));
        } @catch (NSException *exception) { }
    }
    return NO;
}

#pragma mark - 网络传输（预算制超时 + 容错）

static NSURLSession *WIASession(void)
{
    static NSURLSession *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *c =
            [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForRequest = 60;
        s = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

static NSDictionary *WIAPostJSON(NSString *url, NSDictionary *body,
                                 NSDictionary *headers,
                                 NSTimeInterval budget, NSError **err)
{
    if (!url || !body) return nil;

    NSMutableURLRequest *req =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = budget;
    for (NSString *k in headers) {
        [req setValue:headers[k] forHTTPHeaderField:k];
    }
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!payload) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-1
                                        userInfo:@{NSLocalizedDescriptionKey:@"JSON 序列化失败"}];
        return nil;
    }
    req.HTTPBody = payload;

    __block NSDictionary *outObj = nil;
    __block NSError *outErr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [WIASession()
        dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
            if (!error && hr.statusCode == 200 && data) {
                id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([obj isKindOfClass:[NSDictionary class]]) outObj = obj;
                else outErr = [NSError errorWithDomain:@"WIA" code:-2
                                              userInfo:@{NSLocalizedDescriptionKey:@"返回格式不对"}];
            } else {
                NSInteger code = hr ? hr.statusCode : 0;
                NSString *msg = error ? error.localizedDescription
                                      : [NSString stringWithFormat:@"HTTP %ld", (long)code];
                outErr = [NSError errorWithDomain:@"WIA" code:(int)code
                                         userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            dispatch_semaphore_signal(sem);
        }];
    [task resume];

    long rc = dispatch_semaphore_wait(
        sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(budget * NSEC_PER_SEC)));
    if (rc != 0) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-3
                                        userInfo:@{NSLocalizedDescriptionKey:@"请求超时"}];
        return nil;
    }
    if (outErr) {
        if (err) *err = outErr;
        return nil;
    }
    return outObj;
}

static NSString *WIAJudgeURL(NSString *base)
{
    NSString *b = [base stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    NSArray *segs = [b componentsSeparatedByString:@"/"];
    NSString *last = [segs.lastObject lowercaseString];
    NSSet *actions = [NSSet setWithArray:@[@"systemone", @"evaluate", @"decisions"]];
    if ([actions containsObject:last]) return b;
    NSRegularExpression *ver =
        [NSRegularExpression regularExpressionWithPattern:@"^v\\d+$" options:0 error:nil];
    if ([ver numberOfMatchesInString:last options:0
                               range:NSMakeRange(0, last.length)] > 0) {
        return [b stringByAppendingString:@"/systemone"];
    }
    return [b stringByAppendingString:@"/v1/systemone"];
}

static NSString *WIAChatURL(NSString *base, NSString *kind)
{
    NSString *b = [base stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    NSArray *segs = [b componentsSeparatedByString:@"/"];
    NSString *last = [segs.lastObject lowercaseString];

    if ([kind isEqualToString:@"anthropic"]) {
        if ([last isEqualToString:@"messages"]) return b;
        NSRegularExpression *ver =
            [NSRegularExpression regularExpressionWithPattern:@"^v\\d+$" options:0 error:nil];
        if ([ver numberOfMatchesInString:last options:0
                                   range:NSMakeRange(0, last.length)] > 0) {
            return [b stringByAppendingString:@"/messages"];
        }
        return [b stringByAppendingString:@"/v1/messages"];
    }
    if ([last isEqualToString:@"completions"]) return b;
    return [b stringByAppendingString:@"/chat/completions"];
}

#pragma mark - 判断结果模型

@implementation WIAJudgeResult
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.reframeQuestion forKey:@"rq"];
    [coder encodeObject:self.reframeOptions forKey:@"ro"];
    [coder encodeObject:self.intentQuestion forKey:@"iq"];
    [coder encodeObject:self.intentOptions forKey:@"io"];
    [coder encodeObject:self.intent forKey:@"it"];
    [coder encodeDouble:self.risk forKey:@"rk"];
    [coder encodeObject:self.riskOptions forKey:@"rko"];
    [coder encodeObject:self.actionQuestion forKey:@"aq"];
    [coder encodeObject:self.actionOptions forKey:@"ao"];
    [coder encodeObject:self.action forKey:@"ac"];
    [coder encodeObject:self.strategy forKey:@"sg"];
    [coder encodeObject:self.blocks forKey:@"bk"];
    [coder encodeObject:self.humanRead forKey:@"hr"];
    [coder encodeObject:self.replies forKey:@"rp"];
    [coder encodeObject:self.status forKey:@"st"];
    [coder encodeObject:self.detail forKey:@"dt"];
    [coder encodeBool:self.usedLocalJudge forKey:@"ul"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.reframeQuestion = [coder decodeObjectForKey:@"rq"];
        self.reframeOptions = [coder decodeObjectForKey:@"ro"];
        self.intentQuestion = [coder decodeObjectForKey:@"iq"];
        self.intentOptions = [coder decodeObjectForKey:@"io"];
        self.intent = [coder decodeObjectForKey:@"it"];
        self.risk = [coder decodeDoubleForKey:@"rk"];
        self.riskOptions = [coder decodeObjectForKey:@"rko"];
        self.actionQuestion = [coder decodeObjectForKey:@"aq"];
        self.actionOptions = [coder decodeObjectForKey:@"ao"];
        self.action = [coder decodeObjectForKey:@"ac"];
        self.strategy = [coder decodeObjectForKey:@"sg"];
        self.blocks = [coder decodeObjectForKey:@"bk"];
        self.humanRead = [coder decodeObjectForKey:@"hr"];
        self.replies = [coder decodeObjectForKey:@"rp"];
        self.status = [coder decodeObjectForKey:@"st"];
        self.detail = [coder decodeObjectForKey:@"dt"];
        self.usedLocalJudge = [coder decodeBoolForKey:@"ul"];
    }
    return self;
}
@end

#pragma mark - 概率解析（answers.*.probabilities 兼容 dict / array）

static NSArray *WIAProbabilities(NSDictionary *answer)
{
    id probs = [answer objectForKey:@"probabilities"];
    if ([probs isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *out = [NSMutableArray array];
        [(NSDictionary *)probs enumerateKeysAndObjectsUsingBlock:
            ^(id key, id val, BOOL *stop) {
                if ([key isKindOfClass:[NSString class]] &&
                    [val respondsToSelector:@selector(doubleValue)]) {
                    [out addObject:@{ @"label" : key,
                                      @"prob" : @([val doubleValue]) }];
                }
            }];
        [out sortUsingDescriptors:
            @[[NSSortDescriptor sortDescriptorWithKey:@"prob" ascending:NO]]];
        return out;
    }
    if ([probs isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in probs) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *label = [item objectForKey:@"label"] ?:
                              [item objectForKey:@"name"] ?:
                              [item objectForKey:@"choice"];
            id val = [item objectForKey:@"prob"] ?:
                     [item objectForKey:@"probability"] ?:
                     [item objectForKey:@"score"];
            if ([label isKindOfClass:[NSString class]] &&
                [val respondsToSelector:@selector(doubleValue)]) {
                [out addObject:@{ @"label" : label,
                                  @"prob" : @([val doubleValue]) }];
            }
        }
        [out sortUsingDescriptors:
            @[[NSSortDescriptor sortDescriptorWithKey:@"prob" ascending:NO]]];
        return out;
    }
    return nil;
}

static NSString *WIAChoice(NSDictionary *answer)
{
    id c = [answer objectForKey:@"choice"];
    if ([c isKindOfClass:[NSString class]] && [(NSString *)c length] > 0) return c;
    return nil;
}

static double WIAScoreValue(NSDictionary *answer)
{
    id s = [answer objectForKey:@"score"];
    if ([s respondsToSelector:@selector(doubleValue)]) return [s doubleValue];
    return 0.0;
}

#pragma mark - 判断层：SystemOne 多题调用（reframe / intent / risk / action）

static WIAJudgeResult *WIAJudgeSystemOne(NSString *message, NSString *chatID, NSString *context,
                                         NSError **err)
{
    NSString *wiaRel = WIAMemoryRelationForUser(chatID);
    NSString *state = message;
    // 时间坐标 + 记忆时效放在最前：判断层先感知"现在几点、隔了多久"，不把很久前的旧事当当下语境
    state = [WIAWithTimeContext(chatID) stringByAppendingString:state];
    if (context.length) {
        state = [NSString stringWithFormat:@"%@\n[现在收到]：%@", context, message];
    }
    if (wiaRel.length) {
        state = [NSString stringWithFormat:@"[与对方的关系记录]：%@\n%@", wiaRel, state];
    }
    // 记忆档案：把相处笔记摘要也喂给判断层，让它判断时参考这段真实关系/相处史（判断关系/意图更准）
    if (wiaMemoryEnabled) {
        NSString *memBrief = WIAMemoryBrief(chatID);
        if (memBrief.length) {
            state = [NSString stringWithFormat:@"[相处笔记（记住的这些，供你判断时参考）]：%@\n%@", memBrief, state];
        }
    }
    NSString *relInst = wiaRel.length
        ? [NSString stringWithFormat:@"当前记录的关系是「%@」。关系是长期稳定的画像：一起出去玩、约饭、看电影、聊日常、有来有往等共同活动【都不改变】关系类型；称呼亲昵（老公/想你/宝贝）就继续维持原关系。只有出现明确转折信号（正式确立关系、表白、分手、绝交、身份剧变）才调整，否则【一律保持原关系】。", wiaRel]
        : @"根据最近对话（称呼、话题、语气、频率），判断我和对方大致的关系类型。";
    NSDictionary *body = @{
        @"model" : WIAJudgeModel(),
        @"state" : state,
        @"questions" : @{
            @"intent" : @{
                @"type" : @"choice",
                @"instructions" : @"对方这句话背后，更接近哪一种心态（不是工作任务类型）？注意：如果这句话和很久前已完成的事字面相近（如早上的约定、下午又问“到了吗”），但时间/语境已变，别默认关联旧事，按当下新的意图判断。",
                @"criteria" : WIAHumanIntents(),
            },
            @"risk" : @{
                @"type" : @"score",
                @"instructions" : @"如果直接回复这句话，风险有多大（0-10）？",
                @"criteria" : WIARiskLevels(),
            },
            @"should_reply" : @{
                @"type" : @"choice",
                @"instructions" : @"我应该立刻给出具体回复吗？",
                @"criteria" : @{
                    @"立刻回"         : @"信息足够、风险可控，直接回",
                    @"先想清楚再回"   : @"需要谨慎、先确认或搜上下文再回",
                },
            },
            @"action" : @{
                @"type" : @"choice",
                @"instructions" : @"面对这句话，最佳行动是什么？",
                @"criteria" : WIAActionCandidates(),
            },
            @"strategy" : @{
                @"type" : @"choice",
                @"instructions" : @"这一轮我该用哪种行动策略？它决定回复的方向（推进/退让/等待/追问）。",
                @"criteria" : WIAStrategies(),
            },
            @"relation" : @{
                @"type" : @"choice",
                @"instructions" : relInst,
                @"criteria" : WIARelationTypes(),
            },
        },
    };
    NSDictionary *headers = @{
        @"Content-Type" : @"application/json",
        @"Authorization" : [@"Bearer " stringByAppendingString:WIAJudgeKey()],
    };

    NSDictionary *data = WIAPostJSON(WIAJudgeURL(WIAJudgeBase()),
                                     body, headers, 20, err);
    if (!data) return nil;

    NSDictionary *answers = [data objectForKey:@"answers"];
    NSDictionary *intentAns = [answers objectForKey:@"intent"];
    NSDictionary *riskAns = [answers objectForKey:@"risk"];
    NSDictionary *shouldAns = [answers objectForKey:@"should_reply"];
    NSDictionary *actionAns = [answers objectForKey:@"action"];

    WIAJudgeResult *r = [WIAJudgeResult new];
    r.intentQuestion = @"当前真实意图";
    r.intentOptions = WIAProbabilities(intentAns);
    r.intent = WIAChoice(intentAns);
    if (![WIAHumanIntents() objectForKey:r.intent]) {
        r.intent = @"随口闲聊分享";
        for (NSDictionary *opt in r.intentOptions) {
            if ([WIAHumanIntents() objectForKey:opt[@"label"]]) { r.intent = opt[@"label"]; break; }
        }
    }
    r.risk = WIAScoreValue(riskAns);
    r.riskOptions = WIAProbabilities(riskAns);
    r.actionQuestion = @"最佳动作";
    r.actionOptions = WIAProbabilities(actionAns);
    r.action = WIAChoice(actionAns);
    if (r.actionOptions.count) {
        r.action = r.actionOptions[0][@"label"];
    }

    // 策略：本轮该"做什么"。优先用 SystemOne 选出的，非法值则用动作映射兜底。
    NSDictionary *strategyAns = [answers objectForKey:@"strategy"];
    r.strategy = WIAChoice(strategyAns);
    if (![WIAStrategies() objectForKey:r.strategy]) {
        r.strategy = WIARuleStrategy(r.action);
    }

    // 关系：判一次 → 渐进更新关系档案（初判 / 增量 + 防跳变）
    NSDictionary *relationAns = [answers objectForKey:@"relation"];
    NSString *rel = WIAChoice(relationAns);
    if (rel && [WIARelationTypes() objectForKey:rel]) {
        double p = 0;
        for (NSDictionary *o in (WIAProbabilities(relationAns) ?: @[])) {
            if ([o[@"label"] isEqualToString:rel]) { p = [o[@"prob"] doubleValue]; break; }
        }
        // 关系档案已废弃：关系由记忆笔记维护，这里不再写关系档案
    }

    // —— 自适应多段：根据第一段的意图/风险，决定追加哪些追问 ——
    NSMutableArray *blocks = [NSMutableArray array];
    [blocks addObject:@{ @"question" : @"本轮策略",
                         @"note" : [NSString stringWithFormat:@"%@（%@）",
                                    r.strategy ?: @"承接",
                                    (WIAStrategies()[r.strategy] ?: @"")] }];
    [blocks addObject:@{ @"question" : @"当前真实意图",
                         @"options" : r.intentOptions ?: @[] }];
    [blocks addObject:@{ @"question" : @"",
                         @"note" : [NSString stringWithFormat:@"关系：%@",
                                    (wiaRel.length ? wiaRel : @"暂未判断")] }];
    [blocks addObject:@{ @"question" : @"",
                         @"note" : [NSString stringWithFormat:@"危险等级：%.0f/10（%@）",
                                    r.risk, WIARiskLabel(r.risk)] }];
    [blocks addObject:@{ @"question" : @"是否应该立刻回复",
                         @"options" : WIAProbabilities(shouldAns) ?: @[] }];

    // 追问段：带情绪/高风险的意图 → 需要什么；高风险 → 是否紧急模式。
    NSMutableDictionary *followQ = [NSMutableDictionary dictionary];
    BOOL emotional = r.risk >= 5 ||
        [@[@"批评", @"要解释"] containsObject:(r.intent ?: @"")];
    if (emotional) {
        followQ[@"need"] = @{
            @"type" : @"choice",
            @"instructions" : @"她现在需要什么？",
            @"criteria" : @{
                @"道歉" : @"先低头认错",
                @"行动" : @"给实际方案/行动",
                @"解释" : @"讲清原因",
                @"倾听" : @"先听她说完",
                @"陪伴" : @"情绪上陪着",
            },
        };
    }
    if (r.risk >= 6) {
        followQ[@"emergency"] = @{
            @"type" : @"choice",
            @"instructions" : @"是否进入紧急模式？",
            @"criteria" : @{ @"是" : @"谨慎措辞、别乱说", @"否" : @"正常回" },
        };
    }
    if (followQ.count) {
        NSDictionary *bodyB = @{
            @"model" : WIAJudgeModel(),
            @"state" : state,
            @"questions" : followQ,
        };
        NSDictionary *dataB = WIAPostJSON(WIAJudgeURL(WIAJudgeBase()),
                                          bodyB, headers, 20, err);
        if (dataB) {
            NSDictionary *answersB = [dataB objectForKey:@"answers"];
            NSDictionary *need = [answersB objectForKey:@"need"];
            if (need) {
                [blocks addObject:@{ @"question" : @"她现在需要什么？",
                                     @"options" : WIAProbabilities(need) ?: @[] }];
            }
            NSDictionary *emergency = [answersB objectForKey:@"emergency"];
            if (emergency) {
                [blocks addObject:@{ @"question" : @"是否进入紧急模式？",
                                     @"options" : WIAProbabilities(emergency) ?: @[] }];
            }
        }
    }

    [blocks addObject:@{ @"question" : @"最佳动作",
                         @"options" : r.actionOptions ?: @[] }];
    r.blocks = blocks;
    return r;
}


#pragma mark - 判断层：普通聊天模型（用户改了「判断地址」为普通 chat 接口时走这条，model 真正生效）

// 用户是否在设置里显式填过判断层配置（填了就严格：失败不静默降级）
static BOOL WIAJudgeOverridden(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:@"wiaJudgeBase"] ||
           [d objectForKey:@"wiaJudgeKey"] ||
           [d objectForKey:@"wiaJudgeModel"];
}

// 从模型文本里抠出 JSON 对象（容忍 ``` 围栏、前后废话）
static NSDictionary *WIAJSONFromText(NSString *text) {
    if (!text.length) return nil;
    NSString *s = text;
    NSError *re = nil;
    NSRegularExpression *fence =
        [NSRegularExpression regularExpressionWithPattern:@"```[a-zA-Z]*\\s*([\\s\\S]*?)```"
                                                  options:0 error:&re];
    NSTextCheckingResult *m = [fence firstMatchInString:s options:0
                                                  range:NSMakeRange(0, s.length)];
    if (m && m.numberOfRanges > 1) s = [s substringWithRange:[m rangeAtIndex:1]];
    NSRange b = [s rangeOfString:@"{"];
    NSRange e = [s rangeOfString:@"}" options:NSBackwardsSearch];
    if (b.location == NSNotFound || e.location == NSNotFound || e.location <= b.location) return nil;
    NSString *sub = [s substringWithRange:NSMakeRange(b.location, e.location - b.location + 1)];
    NSData *d = [sub dataUsingEncoding:NSUTF8StringEncoding];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static WIAJudgeResult *WIAJudgeChat(NSString *message, NSString *context, NSError **err)
{
    NSString *userMsg = message;
    if (context.length) {
        userMsg = [NSString stringWithFormat:@"最近对话：\n%@\n\n现在对方发来：「%@」", context, message];
    }
    NSString *sys =
        @"你是一个特别懂人心的聊天军师。根据对方发来的这句话（以及历史对话），像真人一样判断："
        @"2)这句话背后接近哪种心态（从下面列表选，可给多个带概率）；"
        @"3)直接回复这句话的风险（0-10 一个数）；4)该立刻回复还是先想清楚；5)最佳行动是什么；"
        @"6)一句话人性化读心。\n"
        @"心态列表：想确认你在不在乎 / 带着情绪想发作 / 要个说法交代 / 求回应求陪伴 / 随口闲聊分享 / 实际有事要办\n"
        @"动作列表：派活 / 催进度 / 问进度 / 批评 / 要解释 / 闲聊 / 邀约 / 夸奖\n"
        @"只输出一个 JSON 对象，不要任何其他文字、不要 markdown。格式："
        @"{\"intent\":{\"想确认你在不在乎\":0.5,\"实际有事要办\":0.5},"
        @"\"risk\":3,\"should_reply\":\"立刻回\",\"action\":\"闲聊\",\"human_read\":\"一句话读心\"}";

    NSDictionary *body = @{
        @"model" : WIAJudgeModel(),
        @"messages" : @[
            @{ @"role" : @"system", @"content" : sys },
            @{ @"role" : @"user",   @"content" : userMsg },
        ],
        @"max_tokens" : @400,
        @"temperature" : @0.2,
        @"stream" : @NO,
    };
    NSDictionary *headers = @{
        @"Content-Type" : @"application/json",
        @"Authorization" : [@"Bearer " stringByAppendingString:WIAJudgeKey()],
    };
    NSDictionary *data = WIAPostJSON(WIAChatURL(WIAJudgeBase(), @"openai"),
                                     body, headers, 30, err);
    if (!data) return nil;
    NSArray *choices = [data objectForKey:@"choices"];
    NSDictionary *msg = [[choices firstObject] objectForKey:@"message"];
    NSString *content = [msg objectForKey:@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) return nil;
    NSDictionary *j = WIAJSONFromText(content);
    if (!j) return nil;

    NSDictionary *intent = [j objectForKey:@"intent"];
    id riskVal = [j objectForKey:@"risk"];
    double risk = 0;
    if ([riskVal respondsToSelector:@selector(doubleValue)]) risk = [riskVal doubleValue];
    NSString *should = [j objectForKey:@"should_reply"];
    NSString *action = [j objectForKey:@"action"];
    NSString *human = [j objectForKey:@"human_read"];
    if (![human isKindOfClass:[NSString class]]) human = @"";

    WIAJudgeResult *r = [WIAJudgeResult new];
    r.intentQuestion = @"当前真实意图";
    r.intentOptions = WIAProbabilities(@{ @"probabilities" : (intent ?: @{}) });
    r.intent = (intent.allKeys.count) ? intent.allKeys[0] : @"随口闲聊分享";
    if (![WIAHumanIntents() objectForKey:r.intent]) {
        r.intent = @"随口闲聊分享";
        for (NSDictionary *opt in r.intentOptions) {
            if ([WIAHumanIntents() objectForKey:opt[@"label"]]) { r.intent = opt[@"label"]; break; }
        }
    }
    r.risk = risk;
    r.actionQuestion = @"最佳动作";
    r.actionOptions = WIAProbabilities(@{ @"probabilities" : @{ (action ?: @"闲聊") : @1.0 } });
    r.action = (r.actionOptions.count) ? r.actionOptions[0][@"label"] : action;
    r.humanRead = human;
    r.strategy = WIARuleStrategy(r.action);

    NSMutableArray *blocks = [NSMutableArray array];
    [blocks addObject:@{ @"question" : @"本轮策略",
                         @"note" : [NSString stringWithFormat:@"%@（%@）",
                                    r.strategy ?: @"承接",
                                    (WIAStrategies()[r.strategy] ?: @"")] }];
    [blocks addObject:@{ @"question" : @"当前真实意图", @"options" : r.intentOptions ?: @[] }];
    [blocks addObject:@{ @"question" : @"危险等级",
                         @"note" : [NSString stringWithFormat:@"危险等级：%.0f/10（%@）", risk, WIARiskLabel(risk)] }];
    [blocks addObject:@{ @"question" : @"是否应该立刻回复",
                         @"options" : WIAProbabilities(@{@"probabilities" : @{(should ?: @"立刻回") : @1.0}}) ?: @[] }];
    [blocks addObject:@{ @"question" : @"最佳动作", @"options" : r.actionOptions ?: @[] }];
    r.blocks = blocks;
    return r;
}

#pragma mark - 本地规则判断（无 key / 判断层失败时的兜底，概率为启发式估算）

static NSArray *WIARuleKeywords(void)
{
    return @[
        @{ @"intent" : @"派活",
           @"words" : @[@"你帮我", @"帮我", @"麻烦你", @"请你", @"给我", @"搞一下",
                        @"弄一下", @"做一下", @"处理一下", @"安排一下", @"跟进",
                        @"搞定", @"弄好", @"做好", @"写个", @"整一个"] },
        @{ @"intent" : @"催进度",
           @"words" : @[@"还没", @"好了吗", @"到哪了", @"进展", @"进度", @"怎么还没",
                        @"卡住", @"多久", @"什么时候能", @"催", @"等很久", @"拖"] },
        @{ @"intent" : @"问进度",
           @"words" : @[@"怎么样了", @"如何了", @"到哪", @"进展如何", @"什么时候",
                        @"几点能", @"情况", @"结果呢", @"有结果"] },
        @{ @"intent" : @"批评",
           @"words" : @[@"你不行", @"你怎么搞的", @"垃圾", @"差劲", @"都是你的错",
                        @"太差", @"不满意", @"又搞砸", @"怎么回事你", @"你居然"] },
        @{ @"intent" : @"要解释",
           @"words" : @[@"为什么", @"凭什么", @"解释", @"理由", @"原因", @"怎么回事",
                        @"你说说看", @"讲清楚", @"说清楚"] },
        @{ @"intent" : @"邀约",
           @"words" : @[@"开会", @"会议", @"约个时间", @"聊一下", @"通个话", @"视频",
                        @"见一面", @"商量", @"时间方便"] },
        @{ @"intent" : @"夸奖",
           @"words" : @[@"不错", @"厉害", @"好棒", @"真棒", @"谢谢", @"辛苦了",
                        @"赞", @"很好", @"满意", @"厉害啊", @"牛逼"] },
        @{ @"intent" : @"闲聊",
           @"words" : @[@"哈哈", @"今天", @"天气", @"吃饭了吗", @"在干嘛", @"累",
                        @"开心", @"分享", @"听说", @"在吗", @"嗯嗯", @"嘿嘿"] },
    ];
}

static BOOL WIARhetoricalKeyword(NSString *msg)
{
    static NSArray *words;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        words = @[@"是不是", @"难道", @"你说", @"在乎", @"你忘", @"有没有", @"当真", @"你心里"];
    });
    for (NSString *w in words) {
        if ([msg containsString:w]) return YES;
    }
    return NO;
}

static NSArray *WIARuleReframe(NSString *message)
{
    double pNot = WIARhetoricalKeyword(message) ? 0.85 : 0.25;
    return @[
        @{ @"label" : @"是", @"prob" : @(1.0 - pNot) },
        @{ @"label" : @"不是", @"prob" : @(pNot) },
    ];
}

// 返回按概率降序的意图选项（含选中意图）。
static NSArray *WIARuleIntentOptions(NSString *message, NSString **chosenOut)
{
    NSArray *rules = WIARuleKeywords();
    NSMutableArray *scores = [NSMutableArray array];
    long long total = 0;
    for (NSDictionary *rule in rules) {
        long long s = 0;
        for (NSString *w in rule[@"words"]) {
            if ([message containsString:w]) s++;
        }
        [scores addObject:@(s)];
        total += s;
    }
    if (total == 0) {
        // 全不命中 → 闲聊兜底
        total = 4;
        for (NSInteger i = 0; i < scores.count; i++) {
            if ([(NSString *)rules[i][@"intent"] isEqualToString:@"闲聊"]) {
                scores[i] = @4;
            } else {
                scores[i] = @0;
            }
        }
    }
    NSMutableArray *opts = [NSMutableArray array];
    for (NSInteger i = 0; i < scores.count; i++) {
        double p = (double)[scores[i] longLongValue] / (double)total;
        if (p < 0.001) continue;
        [opts addObject:@{ @"label" : rules[i][@"intent"],
                           @"prob" : @(p) }];
    }
    [opts sortUsingDescriptors:
        @[[NSSortDescriptor sortDescriptorWithKey:@"prob" ascending:NO]]];
    if (chosenOut && opts.count) *chosenOut = opts[0][@"label"];
    return opts;
}

static double WIARuleRisk(NSString *intent, NSString *message)
{
    static NSDictionary *base;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        base = @{ @"批评" : @8, @"催进度" : @5, @"要解释" : @4, @"问进度" : @3,
                  @"派活" : @3, @"邀约" : @2, @"闲聊" : @0, @"夸奖" : @1 };
    });
    double risk = [[base objectForKey:intent] doubleValue];
    static NSArray *boost;
    static dispatch_once_t t2;
    dispatch_once(&t2, ^{
        boost = @[@"立刻", @"马上", @"必须", @"再这样", @"别怪", @"后果", @"你看着办",
                  @"不要", @"还不行", @"都是你"];
    });
    for (NSString *w in boost) {
        if ([message containsString:w]) risk += 1.0;
    }
    return MIN(10.0, MAX(0.0, risk));
}

static NSArray *WIARuleActionOptions(NSString *intent)
{
    NSString *chosen = [[WIAActionMap() objectForKey:intent] ?: @"" copy];
    // 动作候选 → 概率：选中的最高，其余摊低。
    NSArray *cands = [WIAActionCandidates() allKeys];
    NSMutableArray *opts = [NSMutableArray array];
    double chosenProb = 0.55;
    double rest = (1.0 - chosenProb) / MAX((double)cands.count - 1, 1.0);
    for (NSString *c in cands) {
        double p = [c isEqualToString:chosen] ? chosenProb : rest;
        [opts addObject:@{ @"label" : c, @"prob" : @(p) }];
    }
    [opts sortUsingDescriptors:
        @[[NSSortDescriptor sortDescriptorWithKey:@"prob" ascending:NO]]];
    return opts;
}

static NSArray *WIARuleShouldReply(NSString *intent)
{
    double yes;
    if ([@[@"夸奖", @"闲聊", @"问进度"] containsObject:(intent ?: @"")]) yes = 0.82;
    else if ([@[@"批评", @"要解释"] containsObject:(intent ?: @"")]) yes = 0.22;
    else yes = 0.6;
    return @[
        @{ @"label" : @"立刻回", @"prob" : @(yes) },
        @{ @"label" : @"先想清楚再回", @"prob" : @(1.0 - yes) },
    ];
}

static NSArray *WIARuleNeed(NSString *intent)
{
    static NSDictionary *base;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        base = @{ @"批评" : @"道歉", @"要解释" : @"解释", @"催进度" : @"行动",
                  @"派活" : @"行动", @"问进度" : @"行动", @"邀约" : @"行动",
                  @"闲聊" : @"倾听", @"夸奖" : @"倾听" };
    });
    NSString *chosen = [base objectForKey:intent] ?: @"倾听";
    NSArray *cands = @[@"道歉", @"行动", @"解释", @"倾听", @"陪伴"];
    NSMutableArray *opts = [NSMutableArray array];
    double chosenProb = 0.68;
    double rest = (1.0 - chosenProb) / MAX((double)cands.count - 1, 1.0);
    for (NSString *c in cands) {
        double p = [c isEqualToString:chosen] ? chosenProb : rest;
        [opts addObject:@{ @"label" : c, @"prob" : @(p) }];
    }
    [opts sortUsingDescriptors:
        @[[NSSortDescriptor sortDescriptorWithKey:@"prob" ascending:NO]]];
    return opts;
}

static NSArray *WIARuleEmergency(double risk)
{
    double yes = risk >= 6 ? 0.85 : 0.12;
    return @[
        @{ @"label" : @"是", @"prob" : @(yes) },
        @{ @"label" : @"否", @"prob" : @(1.0 - yes) },
    ];
}

static WIAJudgeResult *WIAJudgeLocal(NSString *message)
{
    WIAJudgeResult *r = [WIAJudgeResult new];
    r.usedLocalJudge = YES;
    r.intentQuestion = @"当前真实意图";
    NSString *intent = nil;
    r.intentOptions = WIARuleIntentOptions(message, &intent);
    r.intent = intent;
    r.risk = WIARuleRisk(r.intent, message);
    r.riskOptions = nil;
    r.actionQuestion = @"最佳动作";
    r.actionOptions = WIARuleActionOptions(r.intent);
    r.action = r.actionOptions.count ? r.actionOptions[0][@"label"] : nil;
    r.strategy = WIARuleStrategy(r.action);

    // 自适应多段（本地规则版），与 SystemOne 对齐的块结构。
    NSMutableArray *blocks = [NSMutableArray array];
    [blocks addObject:@{ @"question" : @"本轮策略",
                         @"note" : [NSString stringWithFormat:@"%@（%@）",
                                    r.strategy ?: @"承接",
                                    (WIAStrategies()[r.strategy] ?: @"")] }];
    [blocks addObject:@{ @"question" : @"当前真实意图",
                         @"options" : r.intentOptions }];
    [blocks addObject:@{ @"question" : @"危险等级",
                         @"note" : [NSString stringWithFormat:@"危险等级：%.0f/10（%@）",
                                    r.risk, WIARiskLabel(r.risk)] }];
    [blocks addObject:@{ @"question" : @"是否应该立刻回复",
                         @"options" : WIARuleShouldReply(r.intent) }];
    if (r.risk >= 5 || [@[@"批评", @"要解释"] containsObject:(r.intent ?: @"")]) {
        [blocks addObject:@{ @"question" : @"她现在需要什么？",
                             @"options" : WIARuleNeed(r.intent) }];
    }
    if (r.risk >= 6) {
        [blocks addObject:@{ @"question" : @"是否进入紧急模式？",
                             @"options" : WIARuleEmergency(r.risk) }];
    }
    [blocks addObject:@{ @"question" : @"最佳动作",
                         @"options" : r.actionOptions }];
    r.blocks = blocks;
    return r;
}

#pragma mark - 起草 prompt（判断结果注入 + PROMPT_ONE 风格）

static NSString *WIAJudgeSummary(WIAJudgeResult *j)
{
    NSMutableArray *parts = [NSMutableArray array];
    if (j.intent) {
        double ip = 0.0;
        for (NSDictionary *o in j.intentOptions) {
            if ([o[@"label"] isEqualToString:j.intent]) { ip = [o[@"prob"] doubleValue]; break; }
        }
        [parts addObject:[NSString stringWithFormat:@"意图=%@(%.0f%%)",
                          j.intent, ip * 100.0]];
    }
    [parts addObject:[NSString stringWithFormat:@"风险=%d/10(%@)",
                      (int)lround(j.risk), WIARiskLabel(j.risk)]];
    if (j.action) [parts addObject:[NSString stringWithFormat:@"建议动作=%@", j.action]];
    if (j.strategy) [parts addObject:[NSString stringWithFormat:@"策略=%@", j.strategy]];
    return [parts componentsJoinedByString:@"，"];
}

static NSString *WIABuildDraftPrompt(NSString *message, NSString *context, NSString *chatID,
                                     WIAJudgeResult *j,
                                     NSString *tone, NSString *instruction,
                                     NSInteger n)
{
    NSString *summary = j ? WIAJudgeSummary(j) : @"（未判断）";
    NSMutableString *tpl =
        [NSMutableString stringWithString:@"刚收到一条聊天消息，你要帮我回。\n"];
    NSString *wiaRel = WIAMemoryRelationForUser(chatID);
    if (wiaRel.length) {
        [tpl appendFormat:@"和对方的关系：%@。回复口吻要贴合这个关系（家人别太客套、领导要尊重、伴侣可亲昵、陌生人保持分寸）。\n", wiaRel];
    }
    WIAAppendMemoryBrief(tpl, chatID);
    if (context.length) {
        [tpl appendFormat:@"最近对话（越靠后越新）：\n%@\n", context];
    }
    NSDateFormatter *wiaNowFmt = [[NSDateFormatter alloc] init];
    [wiaNowFmt setDateFormat:@"yyyy-MM-dd HH:mm EEEE"];
    [tpl appendString:WIAWithTimeContext(chatID)];
    [tpl appendFormat:@"现在收到（当前时间 %@）：「%@」\n",
     [wiaNowFmt stringFromDate:[NSDate date]], message];
    [tpl appendFormat:@"判断结果：%@\n", summary];
    if (j.strategy.length) {
        [tpl appendFormat:@"本轮策略：%@（%@）。回复的方向要服从这个策略：该推进就推进，该退让、等待或追问就按策略来，不要违背它。\n",
         j.strategy, (WIAStrategies()[j.strategy] ?: @"")];
    }
    [tpl appendFormat:
        @"请写 %ld 条回复候选，语气统一成下面这一种，但两条的胆量要有差别：\n"
        @"「%@」%@\n"
        @"硬性要求：\n"
        @"- 结合最近对话的上下文来回，别答非所问\n"
        @"- 别老盯一件事：对方这句若是新进展/新话题，或上一件事已经办完（已到/已吃完/已谈定），就顺着当前这句+最新进展回，别再回头催/重复提旧事；只有旧事还没办完、对方还在等结果时才继续跟进\n"
        @"- 4 条候选必须在内容/角度/胆量上真有差异：一条稳妥、一条更皮、一条更具体、一条先接情绪，都可以；\n"
        @"  禁止用同一句话只换语气词、感叹号或标点来凑数，也不要每条只是换个开头词。\n"
        @"- 前一条稳妥、可以直接发出去；后一条把这个语气做足，更皮、更夸张一点也行\n"
        @"- 每条不超过 30 个字，像日常聊天时打字的语气，不要客套话、不要解释\n"
        @"- 只输出 %ld 行，每行一条，不要编号、不要引号、不要任何前后缀\n"
        @"- 不要写出语气名称（不要写「%@：」这类前缀），直接从回复内容开始\n",
        (long)n, tone, (instruction ?: @""), (long)n, tone];

    return tpl;
}

#pragma mark - 候选清洗（移植自 JevPrompts.swift CandidateParser）

static NSString *WIAStripRegexPrefix(NSString *s, NSRegularExpression *re)
{
    NSTextCheckingResult *m = [re firstMatchInString:s options:0
                                              range:NSMakeRange(0, s.length)];
    if (m && m.range.location != NSNotFound) {
        return [s substringFromIndex:NSMaxRange(m.range)];
    }
    return s;
}

static NSString *WIAStripQuotes(NSString *s)
{
    NSArray *pairs = @[
        @[@"\"", @"\""], @[@"'", @"'"], @[@"“", @"”"],
        @[@"‘", @"’"], @[@"「", @"」"], @[@"『", @"』"],
    ];
    for (NSArray *p in pairs) {
        NSString *open = p[0], *close = p[1];
        if ([s hasPrefix:open] && [s hasSuffix:close] && s.length >= 2) {
            s = [s substringFromIndex:1];
            s = [s substringToIndex:s.length - 1];
        }
    }
    return s;
}

static NSRegularExpression *WIANumberingRe(void)
{
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\d+[.、)．]\\s*"
                                                       options:0 error:nil];
    });
    return re;
}

static NSRegularExpression *WIAStyleLabelRe(void)
{
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^[\\*_#\\s]*(稳妥|轻松|简短|简洁)[^，。！？；、,.!?;：:]{0,5}[\\*_#\\s]*[:：]\\s*"
              options:0 error:nil];
    });
    return re;
}

static NSString *WIAParseCandidateLine(NSString *raw)
{
    NSString *s = [raw stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if (s.length == 0) return nil;
    s = WIAStripRegexPrefix(s, WIANumberingRe());
    s = WIAStripQuotes(s);
    s = WIAStripRegexPrefix(s, WIAStyleLabelRe());
    s = WIAStripQuotes(s);
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return s.length ? s : nil;
}

static NSArray *WIAParseCandidates(NSString *content, NSInteger limit)
{
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *c = WIAParseCandidateLine(line);
        if (c && ![out containsObject:c]) {
            [out addObject:c];
            if (out.count >= limit) break;
        }
    }
    return out;
}

#pragma mark - 生成层：LLM 起草（判断结果注入）

// 真人读心：像懂人心的人聊天一样，多角度简短判断（状态/语气/潜台词/分寸/该避的雷）。
// 注入记忆（关系+相处笔记），让读心知道对面是谁，判断更准。
static NSString *WIAGenHumanRead(NSString *message, NSString *context, NSString *chatID)
{
    if (WIAGenKey().length == 0) return nil;

    NSMutableString *prompt =
        [NSMutableString stringWithString:@"你是很懂人心的真人，正在微信里看一段对话。\n"];
    NSString *wiaRel = WIAMemoryRelationForUser(chatID);
    if (wiaRel.length) {
        [prompt appendFormat:@"和对方的关系：%@。读懂对方时一定带上这层关系来看（亲人/伴侣/领导/陌生人，分寸完全不同）。\n", wiaRel];
    }
    WIAAppendMemoryBrief(prompt, chatID);
    if (context.length) {
        [prompt appendFormat:@"最近对话：\n%@\n", context];
    }
    [prompt appendString:WIAWithTimeContext(chatID)];
    [prompt appendFormat:@"现在对方发来：「%@」\n", message];
    [prompt appendString:
        @"请像真人一样、从多个方面判断后，给我几句「读心」，不要说教、不要客套、不要评价我。\n"
        @"直接从「对方…」开头，讲清：ta 此刻的状态和语气、这句话的潜台词、我们之间该拿捏的分寸、"
        @"最适合怎么回、最不该踩的雷。总共 3 句话以内，像朋友私下分析。\n"];

    NSDictionary *body = @{
        @"model" : WIAGenModel(),
        @"messages" : @[ @{ @"role" : @"user", @"content" : prompt } ],
        @"max_tokens" : @160,
        @"temperature" : @0.6,
        @"stream" : @NO,
        @"thinking" : @{ @"type" : @"disabled" },   // 读心也非思考：整体更快
    };
    NSDictionary *headers = @{
        @"Content-Type" : @"application/json",
        @"Authorization" : [@"Bearer " stringByAppendingString:WIAGenKey()],
    };
    NSError *err = nil;
    NSDictionary *data = WIAPostJSON(WIAChatURL(WIAGenBase(), WIAGenKind()),
                                     body, headers, 30, &err);
    if (!data) return nil;
    NSArray *choices = [data objectForKey:@"choices"];
    NSDictionary *msg = [[choices firstObject] objectForKey:@"message"];
    NSString *content = [msg objectForKey:@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) return nil;
    content = [content stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([content hasPrefix:@"对方"] == NO && content.length > 3) {
        // 尽量以"对方"开头，保持读心口吻
        content = [@"对方" stringByAppendingString:content];
    }
    return content.length ? content : nil;
}

static NSString *WIAGenRequest(NSString *prompt, NSError **err)
{
    if (WIAGenKey().length == 0) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-11
                                        userInfo:@{NSLocalizedDescriptionKey:@"生成层未配置"}];
        return nil;
    }

    NSDictionary *body;
    NSDictionary *headers = @{ @"Content-Type" : @"application/json" };

    if ([WIAGenKind() isEqualToString:@"anthropic"]) {
        body = @{
            @"model" : WIAGenModel(),
            @"max_tokens" : @400,
            @"temperature" : @0.9,
            @"messages" : @[ @{ @"role" : @"user", @"content" : prompt } ],
        };
        NSMutableDictionary *h = [headers mutableCopy];
        h[@"x-api-key"] = WIAGenKey();
        h[@"anthropic-version"] = @"2023-06-01";
        headers = h;
    } else {
        body = @{
            @"model" : WIAGenModel(),
            @"messages" : @[ @{ @"role" : @"user", @"content" : prompt } ],
            @"max_tokens" : @400,
            @"temperature" : @0.9,
            @"stream" : @NO,
            @"thinking" : @{ @"type" : @"disabled" },   // OpenAI 兼容：生成回复非思考，更快更像随手打字
        };
        NSMutableDictionary *h = [headers mutableCopy];
        h[@"Authorization"] = [@"Bearer " stringByAppendingString:WIAGenKey()];
        headers = h;
    }

    NSDictionary *data = WIAPostJSON(WIAChatURL(WIAGenBase(), WIAGenKind()),
                                     body, headers, 35, err);
    if (!data) return nil;

    NSString *content = nil;
    if ([WIAGenKind() isEqualToString:@"anthropic"]) {
        NSArray *carr = [data objectForKey:@"content"];
        NSMutableString *s = [NSMutableString string];
        for (NSDictionary *item in carr) {
            if ([[item objectForKey:@"text"] isKindOfClass:[NSString class]]) {
                [s appendString:[item objectForKey:@"text"]];
            }
        }
        content = s.length ? s : nil;
    } else {
        NSArray *choices = [data objectForKey:@"choices"];
        NSDictionary *msg = [[choices firstObject] objectForKey:@"message"];
        content = [msg objectForKey:@"content"];
        if (![content isKindOfClass:[NSString class]]) {
            id reasoning = [msg objectForKey:@"reasoning_content"];
            if (!reasoning) reasoning = [msg objectForKey:@"reasoning"];
            if ([reasoning isKindOfClass:[NSString class]] && [reasoning length] > 0) {
                if (err) *err = [NSError errorWithDomain:@"WIA" code:-12
                                                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"「%@」是思考型模型：思考占满额度、正文 0 条；请换非思考模型", WIAGenModel()]}];
                return nil;
            }
        }
    }

    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-13
                                        userInfo:@{NSLocalizedDescriptionKey:@"模型返回空内容"}];
        return nil;
    }
    return content;
}

static NSArray *WIAGenDraft(NSString *message, NSString *context, NSString *chatID,
                            WIAJudgeResult *j,
                            NSString *tone, NSString *instruction,
                            NSInteger n, NSError **err)
{
    if (WIAGenKey().length == 0) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-11
                                        userInfo:@{NSLocalizedDescriptionKey:@"生成层未配置"}];
        return @[];
    }

    NSString *prompt = WIABuildDraftPrompt(message, context, chatID, j, tone, instruction, n);
    NSString *content = WIAGenRequest(prompt, err);
    if (!content) return @[];
    return WIAParseCandidates(content, n);
}

#pragma mark - 记忆更新：让生成层模型基于「旧笔记 + 本轮对话 + 时间」重写相处笔记

static NSString *WIAMemoryJSONString(id obj) {
    if (!obj) return @"";
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return @"";
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static NSString *WIAMemoryUpdatePrompt(NSString *chatID, NSString *message, NSString *context) {
    NSDictionary *old = WIAMemoryForUser(chatID);
    NSMutableString *p =
        [NSMutableString stringWithString:
         @"你是一个\"人际记忆笔记员\"。我在微信里和 TA 聊天，需要维护一份关于 TA 的相处笔记。\n"];
    if (old && old.count) {
        [p appendFormat:@"【旧笔记】\n%@\n", WIAMemoryJSONString(old)];
    } else {
        [p appendString:@"【旧笔记】\n（还没有笔记，这是第一次，从零建立）\n"];
    }
    if (context.length) {
        [p appendFormat:@"【最近对话（越靠后越新）】\n%@\n", context];
    }
    NSDateFormatter *wiaMemNow = [[NSDateFormatter alloc] init];
    [wiaMemNow setDateFormat:@"yyyy-MM-dd HH:mm EEEE"];
    [p appendFormat:@"【本轮对方发来】（当前时间 %@）「%@」\n",
     [wiaMemNow stringFromDate:[NSDate date]], message];
    [p appendString:
        @"请输出一份【更新后】的相处笔记，固定 JSON 结构（不要解释、不要 markdown 围栏）：\n"
        @"{\n"
        @"\"这是TA\":{\"身份背景\":\"\",\"圈子\":\"\",\"关系网络\":\"\"},\n"
        @"\"我们之间\":{\"我们关系\":\"\",\"里程碑\":\"\",\"一起做过\":\"\",\"互动模式\":\"\"},\n"
        @"\"长期话题\":[{\"主题\":\"\",\"聊过要点\":\"\",\"最近时间\":\"\",\"次数\":\"\"}],\n"
        @"\"近期动态\":[{\"时间\":\"\",\"话题\":\"\"}],\n"
        @"\"TA最近\":{\"处境情绪\":\"\",\"压力点\":\"\",\"偏好雷区\":\"\"},\n"
        @"\"待办承诺\":{\"约定\":\"\",\"承诺\":\"\"},\n"
        @"\"画像小结\":{\"一句话\":\"\"}\n"
        @"}\n"
        @"硬性要求：\n"
        @"- 逐节对照旧笔记：没变的信息【原样保留】，变了才改，新增才加，别把旧信息删掉\n"
        @"- 计数类要累积：旧\"约过2次\"+这次=\"约过3次\"；\"长期话题\"里次数也要累加，别覆盖成1\n"
        @"- 长期话题【按主题聚合】：把聊过的事归成主题（如\"工作\"\"感情\"\"工资/钱\"\"约见面\"\"家人\"），每个主题一条；本轮若属于已有主题就更新那一条（补要点、更新最近时间、次数+1），新主题才新增；最多10条，别一条消息开一条\n"
        @"- 近期动态【只写最近5条】带时间，用来接话；旧的被顶掉即可，别堆长列表\n"
        @"- 里程碑记关系大事：怎么认识的、表白/确定关系、约过几次/看过几部电影/一起做过的事、重要吵架和好、绝交复合等转折\n"
        @"- 时间线带时间（昨天/上周五/几月几号）\n"
        @"- 追踪进行中的事：带东西/送东西/约见面等正在推进的事，要把『当前进行到哪一步、是否已结束』写进『近期动态』最新一条和『待办承诺』；对方一有进展就同步更新，已结束/完成的事不得再当进行中\n"
        @"- 关系稳定：『我们关系』是长期画像，一起出去玩/约饭/看电影/日常聊等共同活动【不改变】关系；称呼亲昵（老公/想你）继续保持；只有出现明确转折（正式确立、分手、绝交、身份剧变）才调整\n"
        @"- 作息可变不固化：对方作息/生活习惯（上夜班、自由职业、周末带娃等）是会变的，不要写死成永久身份；观察到就记进『近期动态』并带时间，别固化到『身份背景』里\n"
        @"- 每一节没内容就留空，禁止编造；拿不准的写\"可能是\"\n"
        @"- 互动模式/亲疏边界能看出就记（谁主动、到什么程度、别碰什么）\n"
        @"- 全篇≤700字，超了先压缩合并再补新的\n"
        @"- 只输出 JSON，不要任何其他文字\n"];
    return p;
}

// 调生成层模型写记忆，成功返回新笔记 dict，失败返回 nil（不阻塞主流程）
static NSDictionary *WIAGenMemoryUpdate(NSString *chatID, NSString *message, NSString *context, NSError **err) {
    if (WIAGenKey().length == 0) {
        if (err) *err = [NSError errorWithDomain:@"WIA" code:-11
                                        userInfo:@{NSLocalizedDescriptionKey:@"生成层未配置"}];
        return nil;
    }
    NSString *prompt = WIAMemoryUpdatePrompt(chatID, message, context);
    NSString *content = WIAGenRequest(prompt, err);
    if (!content) return nil;
    return WIAJSONFromText(content);
}

// 生成层 prompt 注入相处笔记摘要：作背景参考，回复主体始终围绕对方刚说的话
static void WIAAppendMemoryBrief(NSMutableString *tpl, NSString *chatID) {
    if (!wiaMemoryEnabled) return;
    NSString *memBrief = WIAMemoryBrief(chatID);
    if (memBrief.length) {
        [tpl appendFormat:@"关于TA的相处笔记（作背景参考，帮你知道怎么接话、什么分寸；别复述它，回复主体始终围绕TA刚说的话）：\n%@\n", memBrief];
    }
}




static NSString *WIABuildCombinedDraftPrompt(NSString *message, NSString *context,
                                                 NSString *chatID,
                                                 WIAJudgeResult *j,
                                                 NSArray *tones, NSArray *instructions,
                                                 NSInteger n)
{
    NSString *summary = j ? WIAJudgeSummary(j) : @"（未判断）";
    NSMutableString *tpl =
        [NSMutableString stringWithString:@"刚收到一条聊天消息，你要帮我回。\n"];
    NSString *wiaRel = WIAMemoryRelationForUser(chatID);
    if (wiaRel.length) {
        [tpl appendFormat:@"和对方的关系：%@。回复口吻要贴合这个关系（家人别太客套、领导要尊重、伴侣可亲昵、陌生人保持分寸）。\n", wiaRel];
    }
    WIAAppendMemoryBrief(tpl, chatID);
    if (context.length) {
        [tpl appendFormat:@"最近对话（越靠后越新）：\n%@\n", context];
    }
    NSDateFormatter *wiaNowFmt = [[NSDateFormatter alloc] init];
    [wiaNowFmt setDateFormat:@"yyyy-MM-dd HH:mm EEEE"];
    [tpl appendString:WIAWithTimeContext(chatID)];
    [tpl appendFormat:@"现在收到（当前时间 %@）：「%@」\n",
     [wiaNowFmt stringFromDate:[NSDate date]], message];
    [tpl appendString:@"【时序事实】上面的『最近对话』是当下正在进行的真实对话（越靠后越新），是判断现在情况的最新事实；『相处笔记』只是长期背景、可能滞后于对话。回复前先想清楚：对方说的这件事现在进行到哪一步了（比如带早餐——还在路上、已经到了、还是已经吃完了），别照过时的承诺或旧状态回话。\n"];
    [tpl appendString:@"【时间与生活常识】如果对方这句话和很久前已完成的事字面很像（比如早上约定去某地、下午又问“到了吗”），但时间已过去、那件事已办完、人也已回家，就别再把它接到那件旧事上——这多半是新的意思（约饭、问你现在到哪、或对方自己到了某地）。顺着当下真实情境回，别自作主张去报旧约定的位置或进度。\n"];
    [tpl appendFormat:@"判断结果：%@\n", summary];
    if (j.strategy.length) {
        [tpl appendFormat:@"本轮策略：%@（%@）。回复的方向要服从这个策略：该推进就推进，该退让、等待或追问就按策略来，不要违背它。\n",
         j.strategy, (WIAStrategies()[j.strategy] ?: @"")];
    }
    if (j.humanRead.length) {
        [tpl appendFormat:@"读心（只用来帮你理解局面、定方向，别复述它的话，也别让 4 条都顺着读心往一处写）：\n%@\n", j.humanRead];
    }
    [tpl appendFormat:@"请一次写出 %ld 条回复候选，每条分别用下面一个话术的风格（共 %ld 条）：\n",
     (long)n, (long)n];
    for (NSInteger i = 0; i < (NSInteger)tones.count && i < n; i++) {
        NSString *tone = tones[i];
        NSString *inst = (i < instructions.count) ? instructions[i] : @"";
        [tpl appendFormat:@"%ld. 话术「%@」：%@\n", (long)(i + 1), tone, (inst ?: @"")];
    }
    [tpl appendFormat:
        @"先在心里想好：这条消息最该回应的一个点（贴合对方刚说的话，别发散）。\n"
        @"硬性要求：\n"
        @"- 内容贴题第一：%ld 条都针对对方刚说的事、表达同一个回应重点，只用不同话术换口吻措辞；禁止为凑话术风格编造对方没提的情节（奶茶、请客、赔偿、担保都不许加）\n"
        @"- 话术只用来定口吻底子（撒娇/安慰/直给/抬高），别背出「鱼塘主」「高情商」那种套路腔\n"
        @"- 立场边界：无论对方说的事是什么（公司、工作、家庭、感情、生活、钱……），你只是他的聊天对象，不是他生活里能替他办事的角色；除非对方明确请你帮忙、或这事本来就与你相关，否则不要写「我去帮你问/我去处理/我去搞定/我来解决」这类越界动作，只接情绪、问清楚、陪着说一句，最多留一句「要不要我帮你出出主意」的余地\n"
        @"- 读心只用来理解局面定方向，别复述它的话，也别让 4 条都顺着读心挤成同一种口吻\n"
        @"- 结合最近对话的上下文来回，别答非所问\n"
        @"- 别老盯一件事：对方这句若是新进展/新话题，或上一件事已经办完（已到/已吃完/已谈定），就顺着当前这句+最新进展回，别再回头催/重复提旧事；只有旧事还没办完、对方还在等结果时才继续跟进\n"
        @"- 每条不超过 30 个字，口语短句、别书面客套、别油腻、别套话\n"
        @"- 严格按上面话术顺序输出：第 1 行对第 1 个话术、第 2 行对第 2 个话术……共 %ld 行\n"
        @"- 只输出 %ld 行，每行一条，不要编号、不要引号、不要任何前后缀，也不要写出话术名，直接从回复内容开始\n",
        (long)n, (long)n, (long)n];
    return tpl;
}

static NSArray *WIAGenDraftsCombined(NSString *message, NSString *context, NSString *chatID,
                                     WIAJudgeResult *j,
                                     NSArray *tones, NSArray *instructions,
                                     NSInteger n, NSError **err)
{
    NSString *prompt = WIABuildCombinedDraftPrompt(message, context, chatID, j, tones, instructions, n);
    NSString *content = WIAGenRequest(prompt, err);
    if (!content) return @[];
    return WIAParseCandidates(content, n);
}

// 真实角度模式（话术开关关闭时）：不带话术标签，按 4 个真实角度/胆量出候选，更接近真人随手打字
static NSString *WIABuildRealDraftPrompt(NSString *message, NSString *context,
                                         NSString *chatID, WIAJudgeResult *j,
                                         NSInteger n)
{
    NSString *summary = j ? WIAJudgeSummary(j) : @"（未判断）";
    NSMutableString *tpl =
        [NSMutableString stringWithString:@"刚收到一条聊天消息，你要帮我回。\n"];
    NSString *wiaRel = WIAMemoryRelationForUser(chatID);
    if (wiaRel.length) {
        [tpl appendFormat:@"和对方的关系：%@。回复口吻要贴合这个关系（家人别太客套、领导要尊重、伴侣可亲昵、陌生人保持分寸）。\n", wiaRel];
    }
    WIAAppendMemoryBrief(tpl, chatID);
    if (context.length) {
        [tpl appendFormat:@"最近对话（越靠后越新）：\n%@\n", context];
    }
    NSDateFormatter *wiaNowFmt = [[NSDateFormatter alloc] init];
    [wiaNowFmt setDateFormat:@"yyyy-MM-dd HH:mm EEEE"];
    [tpl appendString:WIAWithTimeContext(chatID)];
    [tpl appendFormat:@"现在收到（当前时间 %@）：「%@」\n",
     [wiaNowFmt stringFromDate:[NSDate date]], message];
    [tpl appendString:@"【时序事实】上面的『最近对话』是当下正在进行的真实对话（越靠后越新），是判断现在情况的最新事实；『相处笔记』只是长期背景、可能滞后于对话。回复前先想清楚：对方说的这件事现在进行到哪一步了（比如带早餐——还在路上、已经到了、还是已经吃完了），别照过时的承诺或旧状态回话。\n"];
    [tpl appendString:@"【时间与生活常识】如果对方这句话和很久前已完成的事字面很像（比如早上约定去某地、下午又问“到了吗”），但时间已过去、那件事已办完、人也已回家，就别再把它接到那件旧事上——这多半是新的意思（约饭、问你现在到哪、或对方自己到了某地）。顺着当下真实情境回，别自作主张去报旧约定的位置或进度。\n"];
    [tpl appendFormat:@"判断结果：%@\n", summary];
    if (j.strategy.length) {
        [tpl appendFormat:@"本轮策略：%@（%@）。回复的方向要服从这个策略：该推进就推进，该退让、等待或追问就按策略来，不要违背它。\n",
         j.strategy, (WIAStrategies()[j.strategy] ?: @"")];
    }
    if (j.humanRead.length) {
        [tpl appendFormat:@"读心（只用来帮你理解局面、定方向，别复述它的话）：\n%@\n", j.humanRead];
    }
    [tpl appendFormat:
        @"请一次写出 %ld 条回复候选，都像你（微信里的真人）随手打出来的，4 条在角度和胆量上要有差别：\n"
        @"第 1 条：最稳妥，接住对方情绪或话头，正常往前说一句\n"
        @"第 2 条：最敢，带点俏皮或调侃，胆子放大一点，但不油腻\n"
        @"第 3 条：最贴，认同对方当下的感受，不评价对方这个人\n"
        @"第 4 条：最活，轻松带点画面感或幽默，留个对方能接的口\n"
        @"硬性要求：\n"
        @"- 服从本轮主策略，一句话只推进一个重点，别把接情绪、邀约、追问、解释全塞进一句\n"
        @"- %ld 条从角度、内容和句式都要真正不同，禁止同一句只换语气词/标点凑数\n"
        @"- 像熟人微信随手打字：口语、短句、别书面客套、别油腻、别套话、别写小作文\n"
        @"- 话术只是参考不是台词，别背出「鱼塘主」「高情商」那种套路腔\n"
        @"- 结合最近对话，别答非所问\n"
        @"- 每条不超过 30 个字，像日常聊天时打字的语气\n"
        @"- 只输出 %ld 行，每行一条，不要编号、不要引号、不要任何前后缀，直接从回复内容开始\n",
        (long)n, (long)n, (long)n];
    return tpl;
}

static NSArray *WIAGenDraftsReal(NSString *message, NSString *context, NSString *chatID,
                                 WIAJudgeResult *j, NSInteger n, NSError **err)
{
    NSString *prompt = WIABuildRealDraftPrompt(message, context, chatID, j, n);
    NSString *content = WIAGenRequest(prompt, err);
    if (!content) return @[];
    return WIAParseCandidates(content, n);
}

#pragma mark - 生成层：本地模板起草（无 key 兜底，按判断结果选模板）

static NSDictionary *WIATemplates(void)
{
    static NSDictionary *t;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        t = @{
            @"派活" : @{
                @"高情商话术" : @[@"收到，这就安排，先给你一版进度，节点我再同步你。",
                                  @"好的，我先接下，你确认下截止时间，我按节点推进。"],
                @"情绪价值"   : @[@"交给我你就放心吧，我处理好再跟你说。",
                                  @"你肯交给我，我肯定不让你失望，等我的消息。"],
            },
            @"催进度" : @{
                @"高情商话术" : @[@"正在收尾，卡点我直接同步你，不让你干等。",
                                  @"抱歉让你等了，我这就加急，最迟给你个准信。"],
                @"情绪价值"   : @[@"知道你着急，我理解，我马上给你个准信。",
                                  @"让你等这么久辛苦了，我尽快把进度给你。"],
            },
            @"问进度" : @{
                @"高情商话术" : @[@"目前已完成大半，接下来出结果，有新情况第一时间告诉你。",
                                  @"卡在一个环节，正在解决，好了马上给你下一步。"],
                @"情绪价值"   : @[@"关心进度就是关心我，给你实时同步，别担心。",
                                  @"正在推进，稳着呢，好了马上叫你。"],
            },
            @"批评" : @{
                @"高情商话术" : @[@"你说得对，这是我的问题，我马上补救，给你处理方案。",
                                  @"收到批评，我先认下来，不找借口，直接给改进。"],
                @"情绪价值"   : @[@"让你失望了，我挺难受，但更想把它做好给你看。",
                                  @"你的感受我收到了，是我没做好，我这就改。"],
            },
            @"要解释" : @{
                @"高情商话术" : @[@"原因是客观情况所致，我负主要责任，下一步这么补救。",
                                  @"说清楚：这个结果是我没把控好，我后续避免，给出改进。"],
                @"情绪价值"   : @[@"你想问清楚我完全理解，我把来龙去脉跟你讲明白。",
                                  @"是我没提前跟你说清楚，对不起，现在跟你讲透。"],
            },
            @"闲聊" : @{
                @"高情商话术" : @[@"哈哈，是，我最近也这样，回头一起聊聊。",
                                  @"嗯嗯，这话题有意思，我接着聊。"],
                @"情绪价值"   : @[@"你说得对，最近是有点累，但你一说我就不累了。",
                                  @"跟你聊两句，心情都好多了。"],
            },
            @"邀约" : @{
                @"高情商话术" : @[@"好，你定个方便的时间，我把要聊的整理好等你。",
                                  @"可以，我这会空，议题先发你，见面聊。"],
                @"情绪价值"   : @[@"行，咱约个时间好好聊聊，你想聊的都说出来。",
                                  @"你愿意跟我商量，我很重视，时间你挑。"],
            },
            @"夸奖" : @{
                @"高情商话术" : @[@"谢谢，能得到你认可我很开心，我继续加油。",
                                  @"过奖了，主要是大家配合，我顺手做的。"],
                @"情绪价值"   : @[@"被你夸我都有点飘了，嘿嘿，谢谢你。",
                                  @"你的肯定对我很重要，谢谢你愿意说出来。"],
            },
        };
    });
    return t;
}

static NSArray *WIATemplateDraft(WIAJudgeResult *j, NSString *tone, NSInteger n)
{
    NSDictionary *byIntent = [WIATemplates() objectForKey:j.intent];
    NSArray *list = [byIntent objectForKey:tone];
    if (list.count == 0) {
        list = @[@"好的，收到，我会尽快处理并给你反馈。",
                 @"嗯，我明白了，马上安排。"];
    }
    NSMutableArray *out = [NSMutableArray array];
    NSInteger take = MIN(n, (NSInteger)list.count);
    for (NSInteger i = 0; i < take; i++) [out addObject:list[i]];
    return out;
}

#pragma mark - 会话上下文：按会话维护最近消息，供判断/起草关联

NSMutableDictionary *gWIAHistory;   // chatID -> NSMutableArray<@{role,content}>

NSMutableDictionary *WIAIntentCache(void); // 前置声明（定义在后）

void WIAHistoryAppend(NSString *chatID, NSString *role, NSString *content)
{
    if (!chatID || !content) return;
    @synchronized (WIAIntentCache()) {
        NSMutableArray *arr = gWIAHistory[chatID];
        if (!arr) {
            arr = [NSMutableArray array];
            gWIAHistory[chatID] = arr;
        }
        [arr addObject:@{ @"role" : role, @"content" : content,
                          @"t" : @((long long)[[NSDate date] timeIntervalSince1970]) }];
        // 内存只保留最近 20 条（够用；展示时按 wiaContextLines 截取）
        if (arr.count > 20) {
            [arr removeObjectsInRange:NSMakeRange(0, arr.count - 20)];
        }
    }
}

// 距该会话"上一条"消息的人类可读间隔（跳过刚 append 的当前条）
NSString *WIASinceLast(NSString *chatID)
{
    if (!chatID.length) return @"";
    NSArray *snapshot = nil;
    @synchronized (WIAIntentCache()) { snapshot = [gWIAHistory[chatID] copy]; }
    double now = [[NSDate date] timeIntervalSince1970];
    double last = 0;
    for (NSDictionary *m in snapshot.reverseObjectEnumerator) {
        NSNumber *t = m[@"t"];
        if (![t isKindOfClass:[NSNumber class]]) continue;
        double ts = [t doubleValue];
        if (now - ts < 30) continue;      // 跳过刚 append 的当前条
        last = ts;
        break;
    }
    if (last <= 0) return @"你们之前没有聊过（第一次对话）";
    double diff = now - last;
    if (diff < 60) return @"刚刚";
    if (diff < 3600) return [NSString stringWithFormat:@"%.0f分钟前", diff / 60.0];
    if (diff < 86400) return [NSString stringWithFormat:@"%.1f小时前", diff / 3600.0];
    return [NSString stringWithFormat:@"%.0f天前", diff / 86400.0];
}

// 时间坐标 + 记忆时效段：让判断/读心/生成感知"现在几点、隔了多久"，不把很久前的旧事当当下；
// 也告知作息这类可变信息按距今久远定权重、会过期。
static NSString *WIAWithTimeContext(NSString *chatID)
{
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yyyy-MM-dd HH:mm EEEE"];
    return [NSString stringWithFormat:
        @"【时间坐标】现在是 %@；这条消息距你们上一次对话约 %@。\n"
        @"请基于现在这个时间点（几点、星期几、隔了多久）和普通人生活节奏的常识，推断对方此刻大概处于什么状态、这条消息最可能是什么语境；你不清楚对方的真实作息时不要臆断，把它当作新语境处理，别拿很久以前的旧事套到当下。\n"
        @"【记忆时效】相处笔记里带时间的条目，请按『距今多久』定权重：最近几小时=当下语境；今天早些=参考；几天前=只作背景；很久前（尤其对方作息、临时状态这类会变的）=基本作废，除非对方主动重提。作息类信息若是很久前观察到的，别当当下事实，只当历史线索。\n",
        [f stringFromDate:[NSDate date]], WIASinceLast(chatID)];
}

// 拼出该会话最近对话文本（[对方]/[我] 交替），用于喂判断层与生成层。
NSString *WIAHistoryThread(NSString *chatID, NSInteger lines)
{
    if (!chatID) return @"";
    if (lines <= 0) return @""; // 不关联
    NSMutableArray *lineArr = [NSMutableArray array];
    @synchronized (WIAIntentCache()) {
        NSArray *arr = gWIAHistory[chatID];
        NSArray *recent = arr;
        if (arr.count > lines) {
            recent = [arr subarrayWithRange:
                      NSMakeRange(arr.count - lines, lines)];
        }
        for (NSDictionary *m in recent) {
            NSString *role = [m[@"role"] isEqualToString:@"assistant"] ? @"我" : @"对方";
            [lineArr addObject:[NSString stringWithFormat:@"[%@] %@", role, m[@"content"]]];
        }
    }
    return [lineArr componentsJoinedByString:@"\n"];
}

#pragma mark - 端到端：判断（SystemOne/本地兜底）→ 各话术起草（LLM/本地模板）

WIAJudgeResult *WIARunAnalysis(NSString *message, NSString *chatID, NSString *judgeCtx, NSString *genCtx)
{
    WIAJudgeResult *r = nil;

    // 判断层、生成层都关 → 整个功能不启动
    if (!wiaJudgeEnabled && !wiaGenEnabled) return nil;

    // —— 判断层：开 → 意图概率题 + 真人读心；关 → 生成层仍可单独工作 ——
    if (wiaJudgeEnabled) {
        NSError *judgeErr = nil;
        if (WIAJudgeKey().length > 0) {
            // 地址指向 Jev SystemOne 专用接口 → 走 SystemOne；其它地址走通用 chat
            NSString *bs = [WIAJudgeBase() stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (bs.length > 0) {
                if ([bs rangeOfString:@"systemone"].location != NSNotFound) {
                    r = WIAJudgeSystemOne(message, chatID, judgeCtx, &judgeErr);
                } else {
                    r = WIAJudgeChat(message, judgeCtx, &judgeErr);
                }
            }
        }
        if (!r) {
            if (WIAJudgeOverridden() && WIAJudgeKey().length > 0) {
                // 你自己填过判断层配置：失败必须露出，不静默降级
                r = [[WIAJudgeResult alloc] init];
                r.status = @"判断请求失败";
                r.detail = judgeErr ? judgeErr.localizedDescription
                                    : @"可能是 key / 模型 / 地址不对，请在设置里检查";
                r.humanRead = [NSString stringWithFormat:@"判断请求失败：%@", r.detail];
            } else {
                r = WIAJudgeLocal(message);
                if (judgeErr) {
                    r.status = @"判断层降级";
                    r.detail = judgeErr.localizedDescription;
                }
                // 真人读心：像懂人心的人聊天一样，多角度判断一句（失败则跳过，不影响结果）。
                r.humanRead = WIAGenHumanRead(message, genCtx, chatID);
            }
        } else {
            r.humanRead = WIAGenHumanRead(message, genCtx, chatID);
        }
    } else {
        // 判断层已关：给一个空判断，让生成层仅凭「消息 + 上下文」生成话术
        r = [[WIAJudgeResult alloc] init];
        r.status = @"判断层已关闭，仅生成";
    }

    NSMutableArray *replies = [NSMutableArray array];
    NSMutableArray *notes = [NSMutableArray array];

    // —— 记忆档案：判断层/读心跑完后，让生成层模型更新一份「相处笔记」（有变化才写，失败不影响回复）——
    if (wiaMemoryEnabled && WIAGenKey().length > 0 && chatID.length > 0 && message.length > 0) {
        NSError *me = nil;
        NSDictionary *note = WIAGenMemoryUpdate(chatID, message, genCtx, &me);
        if (note && note.count) {
            WIAUpdateMemoryForNote(chatID, note, nil);
        }
        // 失败静默：记忆更新是加分项，绝不阻塞回复
    }

    // —— 生成层：开 → 出 4 条建议回复；关 → 只显示判断层结果 ——
    if (wiaGenEnabled) {
        NSArray *tones = wiaSelectedTones ?: kWIACfgTones;
        NSMutableArray *insts = [NSMutableArray array];
        for (NSString *tone in tones) {
            NSString *instruction = [WIAToneInstructions() objectForKey:tone];
            if (!instruction) instruction = @"像真人聊天一样自然回复，让对方舒服，句子短能直接发出去。";
            [insts addObject:instruction];
        }

        NSInteger wantCount = wiaToneRealEnabled ? (NSInteger)tones.count : 4;
        NSArray *cands = nil;
        if (WIAGenKey().length > 0) {
            NSError *ce = nil;
            if (wiaToneRealEnabled) {
                // 话术当底子 + 真实口吻约束
                cands = WIAGenDraftsCombined(message, genCtx, chatID, r, tones, insts,
                                             (NSInteger)tones.count, &ce);
            } else {
                // 真实角度模式（4 条，不带话术标签）
                cands = WIAGenDraftsReal(message, genCtx, chatID, r, 4, &ce);
            }
        }
        if (cands.count == wantCount && cands.count > 0) {
            [replies addObjectsFromArray:cands];
        } else {
            // 合并失败 / 未配置 key → 逐个话术兜底（单话术生成或本地模板）
            for (NSUInteger i = 0; i < tones.count; i++) {
                NSString *tone = tones[i];
                NSString *instruction = insts[i];
                NSError *e = nil;
                NSArray *c2 = nil;
                if (WIAGenKey().length > 0) {
                    c2 = WIAGenDraft(message, genCtx, chatID, r, tone, instruction,
                                     kWIARepliesPerTone, &e);
                } else {
                    c2 = WIATemplateDraft(r, tone, kWIARepliesPerTone);
                }
                if (e) {
                    [notes addObject:[NSString stringWithFormat:@"「%@」失败：%@",
                                      tone, e.localizedDescription]];
                } else {
                    [replies addObjectsFromArray:c2];
                }
            }
        }
    }

    if (wiaGenEnabled && replies.count == 0) {
        // 兜底：本地模板必须能出，绝不空手
        if (!r.status) r.status = @"生成失败";
        r.detail = notes.count ? [notes componentsJoinedByString:@"；"]
                               : (r.detail ?: @"（无候选）");
    } else if (replies.count) {
        r.replies = replies;
        if (notes.count) {
            r.status = @"部分降级";
            r.detail = [notes componentsJoinedByString:@"；"];
        }
    }
    return r;
}

#pragma mark - 缓存

NSMutableDictionary *gWIAIntentCache;   // key -> WIAJudgeResult
NSMutableDictionary *gWIAInflight;      // key -> @1，避免重复请求

NSMutableDictionary *WIAIntentCache(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gWIAIntentCache = [NSMutableDictionary dictionary];
        gWIAInflight = [NSMutableDictionary dictionary];
        gWIAHistory = [NSMutableDictionary dictionary];
    });
    return gWIAIntentCache;
}

NSMutableDictionary *gWIAIntentOrder;   // from -> NSMutableArray<key>，用于分析结果每会话只留最新1条

// 分析结果：每个会话（from）只保留当前最新1条。旧分析在收到下一条新消息时即被淘汰（只显示当前最新消息、不保留历史）
void WIACapIntentCache(NSString *from, NSString *key) {
    if (!from.length || !key.length) return;
    @synchronized (WIAIntentCache()) {
        if (!gWIAIntentOrder) gWIAIntentOrder = [NSMutableDictionary dictionary];
        NSMutableArray *keys = gWIAIntentOrder[from];
        if (!keys) { keys = [NSMutableArray array]; gWIAIntentOrder[from] = keys; }
        if (![keys containsObject:key]) [keys addObject:key];
        while (keys.count > 1) {
            NSString *old = keys[0];
            [keys removeObjectAtIndex:0];
            [gWIAIntentCache removeObjectForKey:old];
        }
    }
}


// —— 历史持久化已移除：分析结果只显示当前最新消息，不落盘 ——

#pragma mark - 关系类型（判断层 relation 题 criteria；关系档案已废弃，仅保留判型用）

// 五类关系（判断层 relation 题的 criteria）
NSDictionary *WIARelationTypes(void)
{
    static NSDictionary *t;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        t = @{
            @"亲密伴侣"          : @"亲密、约会、想你、土味情话、深夜聊天、撒娇",
            @"家人亲属"          : @"父母长辈、兄弟姐妹、关心吃饭身体、催婚、安排事务、家常",
            @"亲密朋友"          : @"闺蜜死党、熟络、约局、开黑、借钱、互相吐槽玩笑",
            @"普通朋友/熟人"     : @"同学、邻居、同乡、客套但有来有往、话题偏日常事务",
            @"工作关系"          : @"事务、汇报、方案、加班、客气称呼（领导/老师/总）、谈进度交付",
            @"专业服务关系"      : @"师生、医患、客服、顾问、中介、一方给建议/服务、围绕需求",
            @"网络/陌生人"       : @"网友、代购、快递、极少历史、内容功能化、无生活交集",
        };
    });
    return t;
}


#pragma mark - 记忆档案：判断层模型自写「相处笔记」（仿关系档案，双写+隐蔽备份）

NSMutableDictionary *gWIAMemory;   // chatID -> 相处笔记 dict

NSString *WIAMemoryPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/wia_memory.bin"];
}
NSString *WIAMemoryBackupPath(void) {
    // 备份放更隐蔽的 Library/Application Support，主文件被微信清掉时用它恢复
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"]
            stringByAppendingPathComponent:@"wia_memory.bak"];
}
// 记忆兜底备份：Application Support 写不进时落到 Documents（一定可写），保证备份始终存在
NSString *WIAMemoryFallbackPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/.wia_memory_bak.bin"];
}
void WIAWriteMemory(void) {
    @synchronized (WIAIntentCache()) {
        if (!gWIAMemory || gWIAMemory.count == 0) return;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:gWIAMemory];
        if (!data) return;
        [data writeToFile:WIAMemoryPath() atomically:YES];        // 主文件
        // 备份：先确保 Application Support 目录存在，再写；写不进则落到 Documents 兜底
        NSString *bk = WIAMemoryBackupPath();
        [[NSFileManager defaultManager] createDirectoryAtPath:[bk stringByDeletingLastPathComponent]
                                 withIntermediateDirectories:YES attributes:nil error:nil];
        if (![data writeToFile:bk atomically:YES]) {
            [data writeToFile:WIAMemoryFallbackPath() atomically:YES];
        }
    }
}
void WIAReadMemory(void) {
    NSData *data = [NSData dataWithContentsOfFile:WIAMemoryPath()];
    if (!data) data = [NSData dataWithContentsOfFile:WIAMemoryBackupPath()];  // 主文件被删则用 Application Support 备份
    if (!data) data = [NSData dataWithContentsOfFile:WIAMemoryFallbackPath()]; // 再不行用 Documents 兜底备份
    if (!data) return;
    @try {
        id loaded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if ([loaded isKindOfClass:[NSDictionary class]]) {
            @synchronized (WIAIntentCache()) {
                if (!gWIAMemory) gWIAMemory = [NSMutableDictionary dictionary];
                [gWIAMemory removeAllObjects];
                [gWIAMemory addEntriesFromDictionary:(NSDictionary *)loaded];
            }
        }
    } @catch (NSException *e) {}
}
void WIAClearMemory(void) {
    @synchronized (WIAIntentCache()) {
        if (!gWIAMemory) gWIAMemory = [NSMutableDictionary dictionary];
        [gWIAMemory removeAllObjects];
    }
    [[NSFileManager defaultManager] removeItemAtPath:WIAMemoryPath() error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:WIAMemoryBackupPath() error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:WIAMemoryFallbackPath() error:nil];
    // 兜底：删除可能失败（尤其隐蔽备份目录受限时），改写成空，确保重启后读到的一定是空
    NSData *empty = [NSKeyedArchiver archivedDataWithRootObject:@{}];
    if (empty) {
        [empty writeToFile:WIAMemoryPath() atomically:YES];
        [empty writeToFile:WIAMemoryBackupPath() atomically:YES];
        [empty writeToFile:WIAMemoryFallbackPath() atomically:YES];
    }
}
NSDictionary *WIAMemoryForUser(NSString *chatID) {
    if (!chatID.length) return nil;
    @synchronized (WIAIntentCache()) { return gWIAMemory[chatID]; }
}

// 从记忆读"我们关系"（关系档案已废弃，关系统一由记忆笔记维护）
NSString *WIAMemoryRelationForUser(NSString *chatID) {
    NSDictionary *m = WIAMemoryForUser(chatID);
    NSDictionary *us = m[@"我们之间"];
    NSString *rel = us[@"我们关系"];
    return ([rel isKindOfClass:[NSString class]] && rel.length) ? rel : @"";
}

// 相处笔记的分节骨架（供合并/校验用）
static NSArray *WIAMemorySectionKeys(void) {
    return @[ @"这是TA", @"我们之间", @"长期话题", @"近期动态", @"TA最近", @"待办承诺", @"画像小结" ];
}

// 长期话题去重聚合：按"主题"合并——同名主题只留最新一条（要点取更长的、次数取大的、时间取新的），限 limit 条
static NSArray *WIADedupLongTopics(NSArray *topics, NSInteger limit) {
    if (![topics isKindOfClass:[NSArray class]] || topics.count <= 1) return topics;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *t in topics) {
        if (![t isKindOfClass:[NSDictionary class]]) { [out addObject:t]; continue; }
        NSString *theme = t[@"主题"];
        if (![theme isKindOfClass:[NSString class]] || !theme.length) { [out addObject:t]; continue; }
        BOOL dup = NO;
        for (NSInteger i = 0; i < (NSInteger)out.count; i++) {
            NSDictionary *o = out[i];
            NSString *ot = o[@"主题"];
            if ([ot isKindOfClass:[NSString class]] && [ot isEqualToString:theme]) {
                NSMutableDictionary *merged = [o mutableCopy];
                NSString *a = t[@"聊过要点"], *b = o[@"聊过要点"];
                if ([a isKindOfClass:[NSString class]] && [b isKindOfClass:[NSString class]] && a.length > b.length) merged[@"聊过要点"] = a;
                NSNumber *na = t[@"次数"], *nb = o[@"次数"];
                if ([na isKindOfClass:[NSNumber class]] && [nb isKindOfClass:[NSNumber class]]) merged[@"次数"] = @(MAX(na.intValue, nb.intValue));
                if ([t[@"最近时间"] isKindOfClass:[NSString class]] && [t[@"最近时间"] length]) merged[@"最近时间"] = t[@"最近时间"];
                out[i] = merged;
                dup = YES;
                break;
            }
        }
        if (!dup) [out addObject:t];
    }
    if (out.count > limit) return [out subarrayWithRange:NSMakeRange(0, limit)];
    return out;
}

// 近期动态去重：新话题与已有某条高度相似（互相包含且都 >3 字）→ 更新该条而非新增，限 limit 条
static NSArray *WIADedupRecent(NSArray *topics, NSInteger limit) {
    if (![topics isKindOfClass:[NSArray class]] || topics.count <= 1) return topics;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *t in topics) {
        if (![t isKindOfClass:[NSDictionary class]]) { [out addObject:t]; continue; }
        NSString *topic = t[@"话题"];
        BOOL dup = NO;
        for (NSInteger i = 0; i < (NSInteger)out.count; i++) {
            NSDictionary *o = out[i];
            NSString *ot = o[@"话题"];
            if ([ot isKindOfClass:[NSString class]] && [topic isKindOfClass:[NSString class]]
                && ot.length > 3 && topic.length > 3
                && ([topic containsString:ot] || [ot containsString:topic])) {
                NSMutableDictionary *merged = [o mutableCopy];
                if ([topic length] > [ot length]) merged[@"话题"] = topic;   // 保留更详细的一条
                if ([t[@"时间"] isKindOfClass:[NSString class]] && [t[@"时间"] length]) merged[@"时间"] = t[@"时间"];
                out[i] = merged;
                dup = YES;
                break;
            }
        }
        if (!dup) [out addObject:t];
    }
    if (out.count > limit) return [out subarrayWithRange:NSMakeRange(0, limit)];
    return out;
}


// 把模型输出的新笔记合并进档案：新笔记缺失/为空的节用旧笔记补；长期话题按主题聚合限10条，近期动态只留最近3条
void WIAUpdateMemoryForNote(NSString *chatID, NSDictionary *note, NSString *msgKey) {
    if (!chatID.length || ![note isKindOfClass:[NSDictionary class]]) return;
    @synchronized (WIAIntentCache()) {
        if (!gWIAMemory) gWIAMemory = [NSMutableDictionary dictionary];
        NSMutableDictionary *rec = [gWIAMemory[chatID] mutableCopy];
        if (!rec) rec = [NSMutableDictionary dictionary];
        NSDictionary *old = gWIAMemory[chatID];
        for (NSString *key in WIAMemorySectionKeys()) {
            id newVal = note[key];
            // 模型没给/给空串/给空字典 → 用旧笔记的该节（防模型把历史弄丢）
            if (newVal == nil) newVal = old[key];
            if ([newVal isKindOfClass:[NSString class]] && [newVal length] == 0) newVal = old[key];
            if ([newVal isKindOfClass:[NSDictionary class]] && ((NSDictionary *)newVal).count == 0) newVal = old[key];
            if ([newVal isKindOfClass:[NSArray class]] && ((NSArray *)newVal).count == 0) newVal = old[key];
            if (newVal != nil) rec[key] = newVal;
        }
        // 长期话题：按主题聚合去重、限 10 条（模型守约时已是聚合好的，这里兜底防重复）
        NSArray *lt = WIADedupLongTopics(rec[@"长期话题"], 10);
        rec[@"长期话题"] = lt;
        // 近期动态：去重 + 只留最近 5 条（够接话就行）
        NSArray *recent = WIADedupRecent(rec[@"近期动态"], 5);
        rec[@"近期动态"] = recent;
        // 骨架兜底：确保 7 个键都在（模型漏输出某节时补默认空值，保证结构完整）
        NSDictionary *emptyDefaults = @{
            @"这是TA"   : @{},
            @"我们之间" : @{},
            @"长期话题" : @[],
            @"近期动态" : @[],
            @"TA最近"   : @{},
            @"待办承诺" : @{},
            @"画像小结" : @{},
        };
        for (NSString *k in emptyDefaults) {
            if (rec[k] == nil) rec[k] = emptyDefaults[k];
        }
        // 迁移清理：删除旧骨架残留键（聊过什么/关键事件），保证文件只有新骨架
        [rec removeObjectForKey:@"聊过什么"];
        [rec removeObjectForKey:@"关键事件"];
        NSDateFormatter *wiaMemFmt = [[NSDateFormatter alloc] init];
        [wiaMemFmt setDateFormat:@"yyyy-MM-dd HH:mm"];
        rec[@"updatedAt"] = [wiaMemFmt stringFromDate:[NSDate date]];
        rec[@"updatedByMsg"] = (msgKey.length ? msgKey : (rec[@"updatedByMsg"] ?: @""));
        gWIAMemory[chatID] = rec;
        WIAWriteMemory();
    }
}

// 记忆精简摘要（给判断层/生成层注入，控制长度）：圈子/关系/相处史/最近3条话题/待办
NSString *WIAMemoryBrief(NSString *chatID) {
    NSDictionary *m = WIAMemoryForUser(chatID);
    if (!m || !m.count) return @"";
    NSMutableArray *bits = [NSMutableArray array];
    NSDictionary *ta = m[@"这是TA"];
    if ([ta isKindOfClass:[NSDictionary class]]) {
        NSString *circle = ta[@"圈子"];
        if ([circle isKindOfClass:[NSString class]] && circle.length) [bits addObject:[NSString stringWithFormat:@"圈子：%@", circle]];
        NSString *net = ta[@"关系网络"];
        if ([net isKindOfClass:[NSString class]] && net.length) [bits addObject:[NSString stringWithFormat:@"关系网络：%@", net]];
    }
    NSDictionary *us = m[@"我们之间"];
    if ([us isKindOfClass:[NSDictionary class]]) {
        NSString *rel = us[@"我们关系"];
        if ([rel isKindOfClass:[NSString class]] && rel.length) [bits addObject:[NSString stringWithFormat:@"我们关系：%@", rel]];
        NSString *mile = us[@"里程碑"];
        if ([mile isKindOfClass:[NSString class]] && mile.length) [bits addObject:[NSString stringWithFormat:@"里程碑：%@", mile]];
        NSString *did = us[@"一起做过"];
        if ([did isKindOfClass:[NSString class]] && did.length) [bits addObject:[NSString stringWithFormat:@"相处史：%@", did]];
        NSString *mode = us[@"互动模式"];
        if ([mode isKindOfClass:[NSString class]] && mode.length) [bits addObject:[NSString stringWithFormat:@"互动：%@", mode]];
    }
    // 长期话题（按主题聚合）：取前 4 条（主题+次数）
    NSArray *ltArr = m[@"长期话题"];
    if ([ltArr isKindOfClass:[NSArray class]] && ltArr.count) {
        NSMutableArray *themes = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)ltArr.count && i < 4; i++) {
            NSDictionary *lt = ltArr[i];
            if (![lt isKindOfClass:[NSDictionary class]]) continue;
            NSString *theme = lt[@"主题"];
            if (![theme isKindOfClass:[NSString class]] || !theme.length) continue;
            id cnt = lt[@"次数"];
            NSString *cntS = ([cnt isKindOfClass:[NSNumber class]]) ? [cnt stringValue]
                          : ([cnt isKindOfClass:[NSString class]] ? cnt : nil);
            [themes addObject:(cntS.length ? [NSString stringWithFormat:@"%@(%@次)", theme, cntS] : theme)];
        }
        if (themes.count) [bits addObject:[NSString stringWithFormat:@"长期话题：%@", [themes componentsJoinedByString:@"、"]]];
    }
    // 近期动态（全部给，最多 5 条，带时间）
    NSArray *recent = m[@"近期动态"];
    if ([recent isKindOfClass:[NSArray class]] && recent.count) {
        NSMutableArray *topics = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)recent.count && i < 5; i++) {
            NSDictionary *t = recent[i];
            if (![t isKindOfClass:[NSDictionary class]]) continue;
            NSString *time = t[@"时间"], *topic = t[@"话题"];
            if ([topic isKindOfClass:[NSString class]] && topic.length) {
                [topics addObject:([time isKindOfClass:[NSString class]] && time.length)
                    ? [NSString stringWithFormat:@"%@：%@", time, topic] : topic];
            }
        }
        if (topics.count) [bits addObject:[NSString stringWithFormat:@"最近聊过：%@", [topics componentsJoinedByString:@"；"]]];
    }
    NSDictionary *todo = m[@"待办承诺"];
    if ([todo isKindOfClass:[NSDictionary class]]) {
        NSString *y = todo[@"约定"];
        if ([y isKindOfClass:[NSString class]] && y.length) [bits addObject:[NSString stringWithFormat:@"待办：%@", y]];
    }
    if (!bits.count) return @"";
    return [bits componentsJoinedByString:@"；"];
}
WIAJudgeResult *WIACachedIntentForKey(NSString *key)
{
    if (!key) return nil;
    @synchronized (WIAIntentCache()) {
        return gWIAIntentCache[key];
    }
}

BOOL WIAInflightForKey(NSString *key)
{
    if (!key) return NO;
    @synchronized (WIAIntentCache()) {
        return gWIAInflight[key] != nil;
    }
}

#pragma mark - 构造函数

%ctor
{
    @autoreleasepool {
        (void)WIAIntentCache();
        WIALoadFeatureDefaults(); // 读取保活/防撤回/步数开关

        [[NSNotificationCenter defaultCenter]
            addObserverForName:kWIAIntentReadyNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        WIARefreshVisibleCells();
                        WIARelayoutLists(); // 让列表重测行高，分析块贴合后下一条消息贴近
                    }];

        NSLog(@"[WIA] tweak loaded (judge:%@ gen:%@ tones=%@)",
              WIAJudgeKey().length ? @"on" : @"off",
              WIAGenKey().length ? @"on" : @"off",
              [(wiaSelectedTones ?: kWIACfgTones) componentsJoinedByString:@","]);
    }
}