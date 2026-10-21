#include "WIA.h"
#include <notify.h>

NSInteger wiaEntryMode = 0;   // 插件入口位置：0=仅微信设置 1=仅插件 2=两者


static void WIASetupGradient(UIView *view) {
    if (!view) return;
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.frame = view.bounds;
    UIColor *top = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleDark)
            ? [UIColor colorWithRed:0.09 green:0.09 blue:0.12 alpha:1.0]
            : [UIColor colorWithRed:0.82 green:0.92 blue:1.0 alpha:1.0];
    }];
    UIColor *bot = [UIColor systemGroupedBackgroundColor];
    layer.colors = @[(id)top.CGColor, (id)bot.CGColor];
    layer.locations = @[@0.0, @0.9];
    layer.startPoint = CGPointMake(0.5, 0.0);
    layer.endPoint = CGPointMake(0.5, 1.0);
    [view.layer insertSublayer:layer atIndex:0];
}


@interface WIAMainVC : UIViewController
@end

#pragma mark ==================== 设置页 ====================

%hook NewSettingViewController

- (void)reloadTableData {
    %orig;
    @try {
        if (wiaEntryMode == 1) return;   // 仅插件入口：微信设置页不显示「Jev Chat」
        id tableViewMgr = MSHookIvar<id>(self, "m_tableViewMgr");
        if (!tableViewMgr) return;

        id sectionMgr = ((id(*)(id, SEL))objc_msgSend)(NSClassFromString(@"WCTableViewSectionManager"), @selector(sectionInfoDefaut));
        Class cellClass = NSClassFromString(@"WCTableViewNormalCellManager");
        id xiaoweiCell = ((id(*)(id, SEL, SEL, id, NSString *))objc_msgSend)(
            cellClass, @selector(normalCellForSel:target:title:), @selector(openXiaoweiPage:), self, @"Jev Chat");
        if (xiaoweiCell && [sectionMgr respondsToSelector:@selector(addCell:)]) {
            ((void(*)(id, SEL, id))objc_msgSend)(sectionMgr, @selector(addCell:), xiaoweiCell);
        }
        if ([tableViewMgr respondsToSelector:@selector(insertSection:At:)]) {
            ((void(*)(id, SEL, id, NSInteger))objc_msgSend)(tableViewMgr, @selector(insertSection:At:), sectionMgr, 0);
        }
        id tableView = ((id(*)(id, SEL))objc_msgSend)(tableViewMgr, @selector(getTableView));
        if (tableView && [tableView respondsToSelector:@selector(reloadData)]) {
            ((void(*)(id, SEL))objc_msgSend)(tableView, @selector(reloadData));
        }
    } @catch (NSException *e) {}
}

%new
- (void)openXiaoweiPage:(id)sender {
    WIAMainVC *vc = [[WIAMainVC alloc] init];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(pushViewController:animated:)]) {
        ((void(*)(id, SEL, id, BOOL))objc_msgSend)(navController, @selector(pushViewController:animated:), vc, YES);
    }
}



%end


@implementation WIAXiaoweiVC {
    NSInteger wiaCategory;   // 详情页分类：0=基础功能 1=意图判断 2=建议回复 3=分析记录
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Jev Chat";
    self.view.backgroundColor = [UIColor clearColor];
    WIASetupGradient(self.view);
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor = [UIColor clearColor];
    [self.view addSubview:scroll];
    objc_setAssociatedObject(self, "wiaScroll", scroll, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    switch (wiaCategory) {
        case 1: [self wiaBuildJudge:scroll]; break;
        case 2: [self wiaBuildReply:scroll]; break;
        case 3: [self wiaBuildHistory:scroll]; break;
        default: [self wiaBuildBasic:scroll]; break;
    }
}

- (UILabel *)wiaRowLabel:(NSString *)t {
    UILabel *l = [[UILabel alloc] init];
    l.text = t;
    l.font = [UIFont systemFontOfSize:17];
    l.textColor = [UIColor labelColor];
    return l;
}

- (void)wiaAddSwitchRow:(UIView *)group title:(NSString *)t on:(BOOL)on action:(SEL)sel y:(CGFloat *)y w:(CGFloat)w {
    CGFloat h = 56;
    UILabel *l = [self wiaRowLabel:t];
    l.frame = CGRectMake(15, *y, w - 100, h);
    [group addSubview:l];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(w - 15 - 51, *y + (h - 31) / 2.0, 51, 31)];
    s.on = on;
    [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [group addSubview:s];
    *y += h;
}

- (void)wiaAddTapRow:(UIView *)group title:(NSString *)t value:(NSString *)v key:(NSString *)key action:(SEL)sel y:(CGFloat *)y w:(CGFloat)w {
    CGFloat h = 56;
    UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0, *y, w, h)];
    row.backgroundColor = [UIColor clearColor];
    [row addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    if (key) objc_setAssociatedObject(row, "wiaCfgKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(row, "wiaCfgTitle", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *tl = [self wiaRowLabel:t];
    tl.frame = CGRectMake(15, 0, w * 0.42, h);
    [row addSubview:tl];

    UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(w * 0.42, 0, w - w * 0.42 - 34, h)];
    BOOL secret = (key.length && [key.lowercaseString containsString:@"key"]);
    vl.text = (secret && v.length) ? @"••••••••" : ((v.length) ? v : @"设置");
    vl.font = [UIFont systemFontOfSize:14];
    vl.textColor = [UIColor secondaryLabelColor];
    vl.textAlignment = NSTextAlignmentRight;
    vl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [row addSubview:vl];

    UILabel *chev = [[UILabel alloc] initWithFrame:CGRectMake(w - 30, 0, 20, h)];
    chev.text = @"›";
    chev.font = [UIFont systemFontOfSize:22];
    chev.textColor = [UIColor systemGray3Color];
    chev.textAlignment = NSTextAlignmentCenter;
    [row addSubview:chev];

    [group addSubview:row];
    *y += h;
}

- (void)wiaBuildBasic:(UIScrollView *)scroll {
    for (UIView *v in [scroll.subviews copy]) [v removeFromSuperview];
    CGFloat w = scroll.frame.size.width;
    CGFloat mx = 16, gw = w - mx * 2;
    __block CGFloat y = 10;
    void (^section)(NSString *) = ^(NSString *t) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(mx + 4, y, gw - 8, 30)];
        h.text = t; h.font = [UIFont boldSystemFontOfSize:14];
        h.textColor = [UIColor secondaryLabelColor];
        [scroll addSubview:h]; y += 30;
    };
    __block CGFloat gy = 0;
    UIView *(^card)(void) = ^UIView * {
        UIView *g = [[UIView alloc] initWithFrame:CGRectMake(mx, y, gw, 0)];
        g.backgroundColor = [UIColor systemBackgroundColor];
        g.layer.cornerRadius = 14; g.clipsToBounds = YES;
        [scroll addSubview:g]; gy = 0; return g;
    };
    void (^cardDone)(UIView *) = ^(UIView *g) {
        CGRect f = g.frame; f.size.height = gy; g.frame = f; y += gy + 16;
    };
    void (^sep)(UIView *) = ^(UIView *g) {
        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(15, gy - 0.5, gw - 30, 0.5)];
        l.backgroundColor = [UIColor systemGray4Color]; [g addSubview:l];
    };
    section(@"基础功能");
    UIView *g1 = card();
    [self wiaAddSwitchRow:g1 title:@"后台运行" on:keepAliveEnabled action:@selector(toggleKeepAlive:) y:&gy w:gw];
    sep(g1);
    [self wiaAddSwitchRow:g1 title:@"消息防撤" on:preventRevokeEnabled action:@selector(togglePreventRevoke:) y:&gy w:gw];
    sep(g1);
    [self wiaAddSwitchRow:g1 title:@"微信运动" on:stepSpoofEnabled action:@selector(toggleStepSpoof:) y:&gy w:gw];
    if (stepSpoofEnabled) {
        sep(g1);
        [self wiaAddTapRow:g1 title:@"总步数" value:[NSString stringWithFormat:@"%ld", (long)stepTarget] key:nil action:@selector(editStepTarget:) y:&gy w:gw];
    }
    sep(g1);
    [self wiaAddTapRow:g1 title:@"插件入口位置" value:(wiaEntryMode==0?@"仅微信设置":(wiaEntryMode==1?@"仅插件":@"微信设置+插件")) key:nil action:@selector(wiaChooseEntry:) y:&gy w:gw];
    cardDone(g1);
    scroll.contentSize = CGSizeMake(w, y + 20);
}

- (void)wiaBuildJudge:(UIScrollView *)scroll {
    for (UIView *v in [scroll.subviews copy]) [v removeFromSuperview];
    CGFloat w = scroll.frame.size.width;
    CGFloat mx = 16, gw = w - mx * 2;
    __block CGFloat y = 10;
    void (^section)(NSString *) = ^(NSString *t) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(mx + 4, y, gw - 8, 30)];
        h.text = t; h.font = [UIFont boldSystemFontOfSize:14];
        h.textColor = [UIColor secondaryLabelColor];
        [scroll addSubview:h]; y += 30;
    };
    __block CGFloat gy = 0;
    UIView *(^card)(void) = ^UIView * {
        UIView *g = [[UIView alloc] initWithFrame:CGRectMake(mx, y, gw, 0)];
        g.backgroundColor = [UIColor systemBackgroundColor];
        g.layer.cornerRadius = 14; g.clipsToBounds = YES;
        [scroll addSubview:g]; gy = 0; return g;
    };
    void (^cardDone)(UIView *) = ^(UIView *g) {
        CGRect f = g.frame; f.size.height = gy; g.frame = f; y += gy + 16;
    };
    void (^sep)(UIView *) = ^(UIView *g) {
        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(15, gy - 0.5, gw - 30, 0.5)];
        l.backgroundColor = [UIColor systemGray4Color]; [g addSubview:l];
    };
    section(@"意图判断");
    UIView *g2 = card();
    [self wiaAddSwitchRow:g2 title:@"意图判断" on:wiaJudgeEnabled action:@selector(toggleJudgeEnabled:) y:&gy w:gw];
    if (wiaJudgeEnabled) {
        sep(g2);
        [self wiaAddTapRow:g2 title:@"关联上下文"
                     value:(wiaJudgeContextLines > 0 ? [NSString stringWithFormat:@"最近 %ld 条", (long)wiaJudgeContextLines] : @"不关联")
                      key:@"judge" action:@selector(wiaChooseContext:) y:&gy w:gw];
        sep(g2);
        [self wiaAddTapRow:g2 title:@"服务地址" value:WIACfgString(@"wiaJudgeBase",  kWIACfgJudgeBase)  key:@"wiaJudgeBase"  action:@selector(wiaTapConfigRow:) y:&gy w:gw];
        sep(g2);
        [self wiaAddTapRow:g2 title:@"Key密钥" value:WIACfgString(@"wiaJudgeKey",   kWIACfgJudgeKey)   key:@"wiaJudgeKey"   action:@selector(wiaTapConfigRow:) y:&gy w:gw];
        sep(g2);
        [self wiaAddTapRow:g2 title:@"模型" value:WIACfgString(@"wiaJudgeModel", kWIACfgJudgeModel) key:@"wiaJudgeModel" action:@selector(wiaTapConfigRow:) y:&gy w:gw];
    }
    cardDone(g2);
    scroll.contentSize = CGSizeMake(w, y + 20);
}

- (void)wiaBuildReply:(UIScrollView *)scroll {
    for (UIView *v in [scroll.subviews copy]) [v removeFromSuperview];
    CGFloat w = scroll.frame.size.width;
    CGFloat mx = 16, gw = w - mx * 2;
    __block CGFloat y = 10;
    void (^section)(NSString *) = ^(NSString *t) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(mx + 4, y, gw - 8, 30)];
        h.text = t; h.font = [UIFont boldSystemFontOfSize:14];
        h.textColor = [UIColor secondaryLabelColor];
        [scroll addSubview:h]; y += 30;
    };
    __block CGFloat gy = 0;
    UIView *(^card)(void) = ^UIView * {
        UIView *g = [[UIView alloc] initWithFrame:CGRectMake(mx, y, gw, 0)];
        g.backgroundColor = [UIColor systemBackgroundColor];
        g.layer.cornerRadius = 14; g.clipsToBounds = YES;
        [scroll addSubview:g]; gy = 0; return g;
    };
    void (^cardDone)(UIView *) = ^(UIView *g) {
        CGRect f = g.frame; f.size.height = gy; g.frame = f; y += gy + 16;
    };
    void (^sep)(UIView *) = ^(UIView *g) {
        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(15, gy - 0.5, gw - 30, 0.5)];
        l.backgroundColor = [UIColor systemGray4Color]; [g addSubview:l];
    };
    section(@"建议回复");
    UIView *g3 = card();
    [self wiaAddSwitchRow:g3 title:@"建议消息" on:wiaGenEnabled action:@selector(toggleGenEnabled:) y:&gy w:gw];
    if (wiaGenEnabled) {
        sep(g3);
        [self wiaAddSwitchRow:g3 title:@"快捷回复" on:wiaQuickReplyEnabled action:@selector(toggleQuickReply:) y:&gy w:gw];
        sep(g3);
        [self wiaAddSwitchRow:g3 title:@"自动回复" on:wiaAutoReplyEnabled action:@selector(toggleAutoReply:) y:&gy w:gw];
        if (wiaAutoReplyEnabled) {
            sep(g3);
            [self wiaAddTapRow:g3 title:@"自动回复第几条"
                         value:[NSString stringWithFormat:@"第 %ld 条", (long)wiaAutoReplyIndex]
                          key:nil action:@selector(wiaChooseAutoReply:) y:&gy w:gw];
        }
        sep(g3);
        [self wiaAddTapRow:g3 title:@"关联上下文"
                     value:(wiaGenContextLines > 0 ? [NSString stringWithFormat:@"最近 %ld 条", (long)wiaGenContextLines] : @"不关联")
                      key:@"gen" action:@selector(wiaChooseContext:) y:&gy w:gw];
        sep(g3);
        [self wiaAddTapRow:g3 title:@"服务地址" value:WIACfgString(@"wiaGenBase",  kWIACfgGenBase)  key:@"wiaGenBase"  action:@selector(wiaTapConfigRow:) y:&gy w:gw];
        sep(g3);
        [self wiaAddTapRow:g3 title:@"Key密钥" value:WIACfgString(@"wiaGenKey",   kWIACfgGenKey)   key:@"wiaGenKey"   action:@selector(wiaTapConfigRow:) y:&gy w:gw];
        sep(g3);
        [self wiaAddTapRow:g3 title:@"模型" value:WIACfgString(@"wiaGenModel", kWIACfgGenModel) key:@"wiaGenModel" action:@selector(wiaTapConfigRow:) y:&gy w:gw];
        sep(g3);
        [self wiaAddSwitchRow:g3 title:@"话术模式（真实口吻）" on:wiaToneRealEnabled action:@selector(toggleToneRealMode:) y:&gy w:gw];
        if (wiaToneRealEnabled) {
            sep(g3);
            {
                NSArray *sel = (wiaSelectedTones ?: kWIACfgTones);
                NSString *joined = [sel componentsJoinedByString:@"、"];
                if (joined.length > 18) joined = [[joined substringToIndex:18] stringByAppendingString:@"…"];
                [self wiaAddTapRow:g3 title:@"话术选择" value:joined key:nil action:@selector(wiaChooseTones:) y:&gy w:gw];
            }
        }
    }
    cardDone(g3);
    scroll.contentSize = CGSizeMake(w, y + 20);
}

- (void)wiaBuildHistory:(UIScrollView *)scroll {
    for (UIView *v in [scroll.subviews copy]) [v removeFromSuperview];
    CGFloat w = scroll.frame.size.width;
    CGFloat mx = 16, gw = w - mx * 2;
    __block CGFloat y = 10;
    void (^section)(NSString *) = ^(NSString *t) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(mx + 4, y, gw - 8, 30)];
        h.text = t; h.font = [UIFont boldSystemFontOfSize:14];
        h.textColor = [UIColor secondaryLabelColor];
        [scroll addSubview:h]; y += 30;
    };
    __block CGFloat gy = 0;
    UIView *(^card)(void) = ^UIView * {
        UIView *g = [[UIView alloc] initWithFrame:CGRectMake(mx, y, gw, 0)];
        g.backgroundColor = [UIColor systemBackgroundColor];
        g.layer.cornerRadius = 14; g.clipsToBounds = YES;
        [scroll addSubview:g]; gy = 0; return g;
    };
    void (^cardDone)(UIView *) = ^(UIView *g) {
        CGRect f = g.frame; f.size.height = gy; g.frame = f; y += gy + 16;
    };
    void (^sep)(UIView *) = ^(UIView *g) {
        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(15, gy - 0.5, gw - 30, 0.5)];
        l.backgroundColor = [UIColor systemGray4Color]; [g addSubview:l];
    };
    section(@"记忆档案");
    UIView *g4 = card();
    [self wiaAddSwitchRow:g4 title:@"记忆档案" on:wiaMemoryEnabled action:@selector(toggleMemory:) y:&gy w:gw];
    sep(g4);
    [self wiaAddTapRow:g4 title:@"清除记忆档案" value:@"" key:nil action:@selector(wiaClearMemory:) y:&gy w:gw];
    cardDone(g4);
    scroll.contentSize = CGSizeMake(w, y + 20);
}
- (void)wiaRebuildCurrent:(UIScrollView *)scroll {
    CGPoint off = scroll.contentOffset;
    switch (wiaCategory) {
        case 1: [self wiaBuildJudge:scroll]; break;
        case 2: [self wiaBuildReply:scroll]; break;
        case 3: [self wiaBuildHistory:scroll]; break;
        default: [self wiaBuildBasic:scroll]; break;
    }
    // 重建后保持滚动位置，避免每切一个开关就跳回顶部
    CGFloat maxY = MAX(0, scroll.contentSize.height - scroll.bounds.size.height);
    scroll.contentOffset = CGPointMake(off.x, MIN(off.y, maxY));
}



- (void)wiaChooseContext:(id)sender {
    NSString *which = objc_getAssociatedObject(sender, "wiaCfgKey"); // judge / gen
    if (![which isEqualToString:@"judge"] && ![which isEqualToString:@"gen"]) which = @"judge";
    NSInteger cur = [which isEqualToString:@"judge"] ? wiaJudgeContextLines : wiaGenContextLines;
    NSString *cfgKey = [which isEqualToString:@"judge"] ? @"wiaJudgeContextLines" : @"wiaGenContextLines";
    NSString *title = [which isEqualToString:@"judge"] ? @"判断层关联上下文" : @"生成层关联上下文";

    NSArray *opts = @[
        @{@"label" : @"不关联",        @"v" : @0},
        @{@"label" : @"最近 3 条",     @"v" : @3},
        @{@"label" : @"最近 5 条",     @"v" : @5},
        @{@"label" : @"最近 8 条",     @"v" : @8},
        @{@"label" : @"最近 12 条",    @"v" : @12},
        @{@"label" : @"最近 20 条",    @"v" : @20},
    ];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"分析时参考最近几条对话"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *o in opts) {
        NSInteger v = [o[@"v"] integerValue];
        NSString *label = o[@"label"];
        if (v == cur) label = [label stringByAppendingString:@" ✓"];
        [alert addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if ([which isEqualToString:@"judge"]) wiaJudgeContextLines = v;
            else wiaGenContextLines = v;
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setInteger:v forKey:cfgKey];
            [d synchronize];
            UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
            if (s) [self wiaRebuildCurrent:s];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), alert, YES, nil);
    }
}

- (void)wiaChooseTones:(id)sender {
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (!navController) return;
    id vc = [[WIATonePickerVC alloc] initWithStyle:UITableViewStyleGrouped];
    ((void(*)(id, SEL, id, BOOL))objc_msgSend)(navController, @selector(pushViewController:animated:), vc, YES);
}

- (void)wiaTapConfigRow:(UIControl *)sender {
    NSString *key = objc_getAssociatedObject(sender, "wiaCfgKey");
    if (!key.length) return;
    NSString *title = objc_getAssociatedObject(sender, "wiaCfgTitle");
    if (!title.length) title = key;
    NSString *cur = WIACfgString(key, @"");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"留空则用默认值"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    BOOL secret = [key.lowercaseString containsString:@"key"];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.secureTextEntry = secret;   // API Key 不回显明文
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *val = alert.textFields.firstObject.text ?: @"";
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:val forKey:key];
        [d synchronize];
        UIScrollView *scroll = objc_getAssociatedObject(self, "wiaScroll");
        if (scroll) [self wiaRebuildCurrent:scroll];
    }]];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), alert, YES, nil);
    }
}

- (void)toggleMemory:(UISwitch *)sender {
    wiaMemoryEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaMemoryEnabled forKey:@"wiaMemoryEnabled"];
    [d synchronize];
    // 关=暂停读写记忆档案（已存的笔记文件保留，重开可继续）；彻底删除走「清除记忆档案」
    // 该开关不改变页面结构，无需整页重建
}

- (void)wiaClearMemory:(id)sender {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清除记忆档案"
                                                                 message:@"将删除所有联系人的相处笔记，且不可恢复。确定清除吗？"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"确定清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        WIAClearMemory();
        UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
        if (s) [self wiaRebuildCurrent:s];
    }]];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), ac, YES, nil);
    }
}

- (void)toggleKeepAlive:(UISwitch *)sender {
    keepAliveEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:keepAliveEnabled forKey:@"keepAliveEnabled"];
    [d synchronize];
    notify_post("com.jevchat.keepalive");   // 通知保持前台模块刷新悬浮按钮
}

- (void)togglePreventRevoke:(UISwitch *)sender {
    preventRevokeEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:preventRevokeEnabled forKey:@"preventRevokeEnabled"];
    [d synchronize];
}

- (void)toggleJudgeEnabled:(UISwitch *)sender {
    wiaJudgeEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaJudgeEnabled forKey:@"wiaJudgeEnabled"];
    [d synchronize];
    WIARefreshHeightsAfterSwitch();   // 开关切换后重算已显示分析块的高度，避免压住消息
    UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
    if (s) [self wiaRebuildCurrent:s];
}

- (void)toggleGenEnabled:(UISwitch *)sender {
    wiaGenEnabled = sender.on;
    if (!wiaGenEnabled) {
        wiaQuickReplyEnabled = NO;   // 建议回复关闭 → 快捷回复一并关闭
        wiaAutoReplyEnabled = NO;    // 自动回复一并关闭
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaGenEnabled forKey:@"wiaGenEnabled"];
    [d setBool:wiaQuickReplyEnabled forKey:@"wiaQuickReplyEnabled"];
    [d setBool:wiaAutoReplyEnabled forKey:@"wiaAutoReplyEnabled"];
    [d synchronize];
    WIARefreshHeightsAfterSwitch();   // 开关切换后重算已显示分析块的高度，避免压住消息
    UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
    if (s) [self wiaRebuildCurrent:s];
}

- (void)toggleToneRealMode:(UISwitch *)sender {
    wiaToneRealEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaToneRealEnabled forKey:@"wiaToneRealEnabled"];
    [d synchronize];
    WIARefreshHeightsAfterSwitch();
    UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
    if (s) [self wiaRebuildCurrent:s];
}

- (void)toggleQuickReply:(UISwitch *)sender {
    wiaQuickReplyEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaQuickReplyEnabled forKey:@"wiaQuickReplyEnabled"];
    [d synchronize];
}

- (void)toggleAutoReply:(UISwitch *)sender {
    wiaAutoReplyEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:wiaAutoReplyEnabled forKey:@"wiaAutoReplyEnabled"];
    [d synchronize];
    UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
    if (s) [self wiaRebuildCurrent:s];
}

- (void)wiaChooseAutoReply:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自动回复用第几条"
                                                                  message:@"收到消息自动发送选定的那一条建议回复"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 1; i <= 4; i++) {
        NSString *label = [NSString stringWithFormat:@"第 %ld 条", (long)i];
        if (i == wiaAutoReplyIndex) label = [label stringByAppendingString:@" ✓"];
        [alert addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            wiaAutoReplyIndex = i;
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setInteger:i forKey:@"wiaAutoReplyIndex"];
            [d synchronize];
            UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
            if (s) [self wiaRebuildCurrent:s];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), alert, YES, nil);
    }
}

- (void)toggleStepSpoof:(UISwitch *)sender {
    stepSpoofEnabled = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:stepSpoofEnabled forKey:@"stepSpoofEnabled"];
    [d synchronize];
    UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
    if (s) [self wiaRebuildCurrent:s];
}

- (void)wiaChooseEntry:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"插件入口位置"
                                                                   message:@"选择Jev Chat设置从哪里进入"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    void (^pick)(NSInteger) = ^(NSInteger m) {
        wiaEntryMode = m;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setInteger:m forKey:@"wiaEntryMode"];
        [d synchronize];
        UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
        if (s) [self wiaRebuildCurrent:s];
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"仅微信设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ pick(0); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"仅插件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ pick(1); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"微信设置+插件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ pick(2); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), alert, YES, nil);
    }
}

- (void)editStepTarget:(id)sender {
    NSInteger maxStep = 98800;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改总步数"
                                                                   message:[NSString stringWithFormat:@"可输入步数（0~%ld），或点击下方按钮瞬间到 88888", (long)maxStep]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [NSString stringWithFormat:@"%ld", (long)stepTarget];
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSInteger value = [alert.textFields.firstObject.text integerValue];
        if (value < 0) value = 0;
        if (value > maxStep) value = maxStep;
        stepTarget = value;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setInteger:stepTarget forKey:@"stepTarget"];
        [d synchronize];
        UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
        if (s) [self wiaRebuildCurrent:s];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"瞬间到 88888 步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        stepTarget = 88888;
        instantStep88888Enabled = YES;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setInteger:stepTarget forKey:@"stepTarget"];
        [d setBool:YES forKey:@"instantStep88888Enabled"];
        [d setObject:[NSDate date] forKey:@"lastInstantStepDate"];
        [d synchronize];
        UIScrollView *s = objc_getAssociatedObject(self, "wiaScroll");
        if (s) [self wiaRebuildCurrent:s];
    }]];

    id navController = ((id(*)(id, SEL))objc_msgSend)(self, @selector(navigationController));
    if (navController && [navController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(navController, @selector(presentViewController:animated:completion:), alert, YES, nil);
    }
}

@end

@implementation WIAMainVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Jev Chat";
    self.view.backgroundColor = [UIColor clearColor];
    WIASetupGradient(self.view);
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor = [UIColor clearColor];
    [self.view addSubview:scroll];

    CGFloat w = scroll.frame.size.width;
    CGFloat mx = 16, gw = w - mx * 2;
    __block CGFloat y = 10;
    __block CGFloat gy = 0;
    UIView *(^card)(void) = ^UIView * {
        UIView *g = [[UIView alloc] initWithFrame:CGRectMake(mx, y, gw, 0)];
        g.backgroundColor = [UIColor systemBackgroundColor];
        g.layer.cornerRadius = 14; g.clipsToBounds = YES;
        [scroll addSubview:g]; gy = 0; return g;
    };
    void (^cardDone)(UIView *) = ^(UIView *g) {
        CGRect f = g.frame; f.size.height = gy; g.frame = f; y += gy + 16;
    };
    void (^sep)(UIView *) = ^(UIView *g) {
        UIView *l = [[UIView alloc] initWithFrame:CGRectMake(15, gy - 0.5, gw - 30, 0.5)];
        l.backgroundColor = [UIColor systemGray4Color]; [g addSubview:l];
    };
    void (^catRow)(UIView *, NSString *, NSInteger) = ^(UIView *g, NSString *t, NSInteger idx) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, gy, gw, 56)];
        row.userInteractionEnabled = YES;
        row.tag = idx;
        row.backgroundColor = [UIColor systemBackgroundColor];
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, gw - 70, 56)];
        lab.text = t; lab.font = [UIFont systemFontOfSize:17]; lab.textColor = [UIColor labelColor];
        [row addSubview:lab];
        UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(gw - 40, 0, 25, 56)];
        arrow.text = @"›"; arrow.font = [UIFont systemFontOfSize:24];
        arrow.textColor = [UIColor systemGray3Color];
        arrow.textAlignment = NSTextAlignmentCenter;
        [row addSubview:arrow];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wiaOpenCategory:)];
        [row addGestureRecognizer:tap];
        [g addSubview:row];
        gy += 56;
    };

    UIView *g = card();
    catRow(g, @"基础功能", 0);
    sep(g);
    catRow(g, @"意图判断", 1);
    sep(g);
    catRow(g, @"建议回复", 2);
    sep(g);
    catRow(g, @"分析记录", 3);
    cardDone(g);

    scroll.contentSize = CGSizeMake(w, y + 20);
}

- (void)wiaOpenCategory:(UITapGestureRecognizer *)gesture {
    NSInteger idx = gesture.view.tag;
    WIAXiaoweiVC *vc = [[WIAXiaoweiVC alloc] init];
    [vc setValue:@(idx) forKey:@"wiaCategory"];
    id nav = [self navigationController];
    if (nav && [nav respondsToSelector:@selector(pushViewController:animated:)]) {
        [nav pushViewController:vc animated:YES];
    }
}
@end


#pragma mark - 回复方式选择器（全部列出，可多选勾选）



@implementation WIATonePickerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"回复方式";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"toneCell"];
    self.selectedTones = [NSMutableArray arrayWithArray:(wiaSelectedTones ?: kWIACfgTones)];
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(pressNav:)];
    cancel.tag = 0;
    self.navigationItem.leftBarButtonItem = cancel;
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(pressNav:)];
    done.tag = 1;
    self.navigationItem.rightBarButtonItem = done;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return WIAToneList().count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"toneCell" forIndexPath:indexPath];
    NSString *t = WIAToneList()[indexPath.row];
    c.textLabel.text = t;
    c.textLabel.font = [UIFont systemFontOfSize:15.0];
    c.textLabel.textColor = [UIColor labelColor];
    c.accessoryType = [self.selectedTones containsObject:t]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *t = WIAToneList()[indexPath.row];
    if ([self.selectedTones containsObject:t]) {
        [self.selectedTones removeObject:t];
    } else {
        if (self.selectedTones.count >= 4) return;   // 上限 4 个，不能多选
        [self.selectedTones addObject:t];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)pressNav:(UIBarButtonItem *)btn {
    if (btn.tag == 1) { // 完成：保存
        // 不足 4 个则用默认话术补足（不能少）
        NSMutableArray *addOn = [NSMutableArray arrayWithArray:self.selectedTones];
        for (NSString *t in kWIACfgTones) {
            if (addOn.count >= 4) break;
            if (![addOn containsObject:t]) [addOn addObject:t];
        }
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSString *t in WIAToneList()) {
            if ([addOn containsObject:t]) [ordered addObject:t];
        }
        if (ordered.count > 4) ordered = [[ordered subarrayWithRange:NSMakeRange(0, 4)] mutableCopy];
        wiaSelectedTones = ordered;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:ordered forKey:@"wiaSelectedTones"];
        [d synchronize];
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

// —— 微信「插件」入口：注册 WIAXiaoweiVC 到 WCPluginsMgr（WechatEnhance 第二种入口方式）——
%hook MinimizeViewController
- (void)viewDidLoad {
    %orig;
    static int wiaPluginReg = 0;
    if (wiaPluginReg) return;
    wiaPluginReg = 1;
    if (wiaEntryMode == 0) return;   // 仅微信设置：不注册插件入口
    @try {
        Class wc = objc_getClass("WCPluginsMgr");
        if (!wc) return;
        id inst = ((id(*)(id, SEL))objc_msgSend)(wc, @selector(sharedInstance));
        if (!inst) return;
        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        if (![inst respondsToSelector:reg]) return;
        ((void(*)(id, SEL, id, id, id))objc_msgSend)(inst, reg, @"Jev Chat", @"1.1.0", @"WIAMainVC");
    } @catch (NSException *e) {}
}
%end
