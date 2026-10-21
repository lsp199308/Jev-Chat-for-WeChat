#include "WIA.h"

BOOL WIAAnalyzable(id wrap)
{
    return WIAIsTextMessage(wrap)
        && !WIAIsOutgoingMessage(wrap)
        && !WIAIsGroupMessage(wrap);
}

BOOL WIAShouldReserveHeight(id wrap)
{
    if (!WIAAnalyzable(wrap)) return NO;
    NSString *key = WIAMessageKey(wrap);
    return WIACachedIntentForKey(key) != nil || WIAInflightForKey(key);
}

UIColor *WIAThemeTextColor(void);
NSAttributedString *WIAAttributedText(WIAJudgeResult *r);
id WIAGetTapTarget(void);
@class WIATapTarget;

// 确定性预留：按完整分析结果的「最坏排版」量出总高度，分析中即预留到底。
// 这样消息到达时微信就把这条消息的 cell 高度定死（含整块分析空间），
// 结果到达只是填充内容，不改变高度 → 不依赖微信刷新、不挡消息、完整可见。
CGFloat WIAFullBlockHeight(void)
{
    UIFont *body = [UIFont systemFontOfSize:10.0];
    UIFont *bold = [UIFont boldSystemFontOfSize:10.0];
    UIColor *tc = WIAThemeTextColor();
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    void (^ln)(NSString *, UIFont *) = ^(NSString *str, UIFont *f) {
        [as appendAttributedString:
            [[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:str]
                attributes:@{ NSFontAttributeName : f,
                              NSForegroundColorAttributeName : tc }]];
    };
    // 预留高度按当前开关只算「实际会显示」的那一层：
    // 意图文本高（判断层）+ 建议回复区固定高（生成层）。
    if (wiaJudgeEnabled) {
        ln(@"- 意图 -", bold);
        ln(@"分析　她可能不只是表面生气，更是在表达被忽视的委屈，语气越重越说明她在乎这段关系，需要先安抚情绪再谈事情。", body);
        for (int i = 0; i < 5; i++) {
            ln(@"当前真实意图是什么", bold);
            for (int k = 0; k < 3; k++) {
                ln(@"　- 在表达委屈需要被倾听：72%", body);
            }
        }
    }
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2.0;
    [as addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, as.length)];
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 60.0;
    w = MIN(MAX(w, 280.0), 420.0);
    CGFloat textW = w - kWIAPadH * 2.0;
    CGRect tr = [as boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  context:nil];
    CGFloat intentH = ceil(tr.size.height);
    CGFloat replyH = 0.0;
    if (wiaGenEnabled) {
        UIFont *hf0 = [UIFont boldSystemFontOfSize:10.0];
        UIFont *rf0 = [UIFont systemFontOfSize:15.0];
        CGFloat lh0 = ceil(rf0.lineHeight);
        replyH += ceil(hf0.lineHeight) + kWIASpacing;   // 标题行
        for (int i = 0; i < 4; i++) {
            replyH += (2 * lh0 + 6.0) + kWIASpacing;    // 每行按最长 2 行预留
        }
    }
    return MAX(30.0, intentH + replyH) + kWIAPadV * 2.0 + 1.0;
}

// 结果已就绪时的「贴合高度」：按真实内容量高，结果到达后 cell 缩到此高度，
// 分析块下面不再留白，下一条消息紧贴。
CGFloat WIAFitBlockHeight(WIAJudgeResult *r)
{
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 60.0;
    w = MIN(MAX(w, 280.0), 420.0);
    CGFloat textW = w - kWIAPadH * 2.0;
    CGFloat intentH = 14.0;
    NSAttributedString *ats = WIAAttributedText(r);
    if (ats) {
        CGRect tr = [ats boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
            context:nil];
        intentH = MAX(intentH, ceil(tr.size.height));
    }
    UIFont *hf = [UIFont boldSystemFontOfSize:10.0];
    UIFont *rf = [UIFont systemFontOfSize:15.0];
    CGFloat lineH = ceil(rf.lineHeight);
    CGFloat replyH = 0.0;
    BOOL showReply = (wiaGenEnabled && r.replies.count > 0);
    if (showReply) {
        replyH += ceil(hf.lineHeight) + kWIASpacing;
        NSUInteger cnt = MIN(r.replies.count, 4u);
        for (NSUInteger i = 0; i < cnt; i++) {
            NSString *tt = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(i + 1), r.replies[i]];
            CGRect ts = [tt boundingRectWithSize:CGSizeMake(textW - kWIA_BTN_SZ - 10.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                attributes:@{ NSFontAttributeName : rf } context:nil];
            NSInteger rows = MAX(1, (NSInteger)ceil(ts.size.height / lineH));
            replyH += rows * lineH + 6.0 + kWIASpacing;
        }
    }
    return kWIAPadV * 2.0 + intentH + replyH;
}

// 消息只要有分析（分析中或已有结果），就预留完整高度；否则不预留。
CGFloat WIAEstimatedBlockHeight(id wrap)
{
    NSString *key = WIAMessageKey(wrap);
    WIAJudgeResult *r = WIACachedIntentForKey(key);
    BOOL pending = WIAInflightForKey(key);
    if (!r && !pending) return 0.0;
    if (r) return WIAFitBlockHeight(r);   // 结果已就绪：贴合实际内容高
    return WIAFullBlockHeight();           // 分析中：先按完整预留占位，结果到达再缩小贴合，避免挡住消息
}

// 从任意节点（cellData / viewModel / wrap）健壮地取出 CMessageWrap，逐级 fallback。
id WIAExtractWrap(id obj)
{
    if (!obj) return nil;
    id wrap = nil;
    @try { wrap = [obj valueForKey:@"messageWrap"]; } @catch (NSException *e) {}
    if (!wrap) @try { wrap = [obj valueForKey:@"m_messageWrap"]; } @catch (NSException *e) {}
    if (!wrap) @try {
        id vm = [obj valueForKey:@"viewModel"];
        if (vm) {
            wrap = [vm valueForKey:@"messageWrap"];
            if (!wrap) wrap = [vm valueForKey:@"m_messageWrap"];
        }
    } @catch (NSException *e) {}
    if (!wrap) @try {
        SEL s = NSSelectorFromString(@"getMessageWrap");
        if ([obj respondsToSelector:s]) wrap = ((id (*)(id, SEL))objc_msgSend)(obj, s);
    } @catch (NSException *e) {}
    return wrap;
}

// 判断 viewModel 是否是"长消息拆分的最后一段子 cell"。
// 普通消息（非 TextMessageSubViewModel）或无父模型 → 视为单条，返回 YES。
// 拆分消息：仅最后一个子段返回 YES（分析块只显示在长消息末尾，前面子段正常显示）。
BOOL WIAIsLastSubViewModel(id viewModel)
{
    if (!viewModel) return YES;   // 取不到模型时按单条处理，避免分析块被永久隐藏
    NSString *cls = [NSString stringWithUTF8String:object_getClassName(viewModel)];
    if (![cls hasPrefix:@"TextMessageSubViewModel"]) return YES;

    id parent = nil;
    @try { parent = [viewModel valueForKey:@"parentModel"]; } @catch (NSException *e) {}
    if (!parent) return YES;

    id subs = nil;
    @try { subs = [parent valueForKey:@"subViewModels"]; } @catch (NSException *e) {}
    if ([subs isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)subs;
        if (arr.count > 0) return [arr lastObject] == viewModel;
    }
    return YES;
}

#pragma mark - UI：多行展示容器（Jev 风格，排版美观）

static char kWIA_CONTAINER_KEY;
static char kWIA_LABEL_KEY;
static char kWIA_REPLIES_KEY;
static char kWIA_SESSION_KEY;
static char kWIA_BTNS_KEY;
static char kWIA_SELF_KEY;
static char kWIA_HEAD_KEY;
static char kWIA_TXTS_KEY;

static UIView *WIAGetContainer(UIView *cell)
{
    if (!cell) return nil;
    UIView *c = objc_getAssociatedObject(cell, &kWIA_CONTAINER_KEY);
    if (![c isKindOfClass:[UIView class]]) {
        c = [[UIView alloc] initWithFrame:CGRectZero];
        // 分析块不要气泡：背景透明、无圆角、不裁剪（原气泡样式已注释保留，需要可随时恢复）
        // c.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        //     return t.userInterfaceStyle == UIUserInterfaceStyleDark
        //         ? [UIColor colorWithWhite:0.16 alpha:0.96]
        //         : [UIColor colorWithWhite:0.93 alpha:0.96];
        // }];
        // c.layer.cornerRadius = 8.0;
        // c.clipsToBounds = YES;
        c.userInteractionEnabled = YES;
        objc_setAssociatedObject(cell, &kWIA_CONTAINER_KEY, c,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.userInteractionEnabled = NO;
        [c addSubview:label];
        objc_setAssociatedObject(c, &kWIA_LABEL_KEY, label,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 建议回复：标题 + 4 行（透明按钮整行点击 + 文字 label 左对齐 + 发送图标对齐文字末尾）
        UILabel *head = [[UILabel alloc] initWithFrame:CGRectZero];
        head.text = @"- 建议回复 -";
        head.font = [UIFont boldSystemFontOfSize:10.0];
        head.userInteractionEnabled = NO;
        [c addSubview:head];
        objc_setAssociatedObject(c, &kWIA_HEAD_KEY, head, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 每条回复：左侧圆形发送按钮（纸飞机，可点）+ 文字（不可点，避免误触）
        NSMutableArray *btns = [NSMutableArray array];
        NSMutableArray *txts = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = i;
            b.userInteractionEnabled = YES;
            b.layer.cornerRadius = kWIA_BTN_SZ / 2.0;
            b.layer.masksToBounds = YES;
            b.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
            [b setTitle:@"➤" forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:15.0];
            [b setTitleColor:WIAThemeTextColor() forState:UIControlStateNormal];
            [b addTarget:WIAGetTapTarget() action:@selector(wiaReplyTapped:)
                forControlEvents:UIControlEventTouchUpInside];
            [c addSubview:b];

            UILabel *tx = [[UILabel alloc] initWithFrame:CGRectZero];
            tx.font = [UIFont systemFontOfSize:15.0];
            tx.numberOfLines = 2;
            tx.userInteractionEnabled = NO;
            [c addSubview:tx];

            [btns addObject:b];
            [txts addObject:tx];
        }
        objc_setAssociatedObject(c, &kWIA_BTNS_KEY, btns, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(c, &kWIA_TXTS_KEY, txts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (c.superview != cell) {
        [c removeFromSuperview];
        [cell addSubview:c];
    }
    return c;
}

static UILabel *WIAContainerLabel(UIView *container)
{
    return objc_getAssociatedObject(container, &kWIA_LABEL_KEY);
}

// 富文本辅助：新起一行 / 追加一段同行程。
static void WIAStartLine(NSMutableAttributedString *as)
{
    if (as.length > 0) {
        [as appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"]];
    }
}

static void WIAAddRun(NSMutableAttributedString *as, NSString *text,
                      UIFont *font, UIColor *color)
{
    [as appendAttributedString:
        [[NSAttributedString alloc] initWithString:text
            attributes:@{ NSFontAttributeName : font,
                          NSForegroundColorAttributeName : color }]];
}

// 追加一行「- 标签：概率%」，概率用更小的字并靠前（贴近截图的逐项小字）。
static void WIAAppendOption(NSMutableAttributedString *as, NSDictionary *option,
                            UIFont *labelFont, UIFont *pctFont,
                            UIColor *labelColor, UIColor *pctColor)
{
    double p = [option[@"prob"] doubleValue];
    WIAStartLine(as);
    WIAAddRun(as, @"　- ", labelFont, labelColor);
    WIAAddRun(as, [NSString stringWithFormat:@"%@：", option[@"label"]],
              labelFont, labelColor);
    WIAAddRun(as, [NSString stringWithFormat:@"%.0f%%", p * 100.0],
              pctFont, pctColor);
}

// 分析块主题色：浅色模式黑色，深色模式白色（随微信外观）
UIColor *WIAThemeTextColor(void) {
    if (@available(iOS 13.0, *)) {
        if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor whiteColor];
        }
    }
    return [UIColor blackColor];
}

// Jev 风格富文本：按「自适应多段问题块」逐段渲染，小字概率 + 序号回复。
NSAttributedString *WIAAttributedText(WIAJudgeResult *r)
{
    // 小一号、颜色随主题（浅色黑 / 深色白）
    UIFont *body = [UIFont systemFontOfSize:10.0];
    UIFont *small = [UIFont systemFontOfSize:8.0];
    UIFont *bold = [UIFont boldSystemFontOfSize:10.0];
    UIColor *title = WIAThemeTextColor();
    UIColor *normal = WIAThemeTextColor();
    UIColor *pctColor = WIAThemeTextColor();

    if (r.status && r.replies.count == 0) {
        return [[NSAttributedString alloc] initWithString:
            [NSString stringWithFormat:@"[WIA] %@：%@", r.status, (r.detail ?: @"")]
            attributes:@{ NSFontAttributeName : body,
                          NSForegroundColorAttributeName : WIAThemeTextColor() }];
    }

    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];

    // —— 意图部分：仅判断层开启时渲染 ——
    if (wiaJudgeEnabled) {
        WIAStartLine(as);
        WIAAddRun(as, @"- 意图 -", bold, title);

        // 真人读心：像懂人心的人聊天一样，多角度判断，放在最上方。
        if (r.humanRead.length) {
            WIAStartLine(as);
            WIAAddRun(as, @"分析　", bold, WIAThemeTextColor());
            WIAAddRun(as, r.humanRead, body, normal);
        }

        // 逐段渲染判断层问题块（保留提问顺序，贴近截图的连续追问）。
        NSArray *blocks = r.blocks ?: @[];
        for (NSDictionary *b in blocks) {
            NSString *q = b[@"question"];
            NSArray *opts = b[@"options"];
            NSString *note = b[@"note"];
            if (q.length) {
                WIAStartLine(as);
                WIAAddRun(as, q, bold, normal);
            }
            if (opts.count) {
                NSInteger n = 0;
                for (NSDictionary *o in opts) {
                    if (n++ >= 3) break;   // 每块最多展示 3 项，控制块高
                    WIAAppendOption(as, o, body, small, normal, pctColor);
                }
            } else if (note.length) {
                WIAStartLine(as);
                WIAAddRun(as, note, body, normal);
            }
        }
    }

    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2.0;
    [as addAttribute:NSParagraphStyleAttributeName value:ps
               range:NSMakeRange(0, as.length)];
    return as;
}

void WIAUpdateCellLabel(UIView *cell)
{
    id wrap = nil;
    SEL wrapSel = NSSelectorFromString(@"getCurrentMessageWrap");
    if ([cell respondsToSelector:wrapSel]) {
        @try {
            wrap = ((id (*)(id, SEL))objc_msgSend)(cell, wrapSel);
        } @catch (NSException *exception) { }
    }

    NSString *key = WIAMessageKey(wrap);
    WIAJudgeResult *r = WIACachedIntentForKey(key);
    BOOL pending = WIAInflightForKey(key);

    if (!r && !pending) {
        // 没有分析结果时不创建整套子视图，只把复用的旧容器隐藏
        UIView *existing = objc_getAssociatedObject(cell, &kWIA_CONTAINER_KEY);
        if ([existing isKindOfClass:[UIView class]]) existing.hidden = YES;
        return;
    }
    UIView *container = WIAGetContainer(cell);

    // 长消息拆分的多个子 cell 共享同一 key：只有最后一段子 cell 显示分析块，
    // 前面的子段正常显示消息、不挂分析。
    id vm = nil;
    @try { vm = [cell valueForKey:@"viewModel"]; } @catch (NSException *e) {}
    if (!WIAIsLastSubViewModel(vm)) {
        container.hidden = YES;
        return;
    }

    CGFloat cellWidth = CGRectGetWidth(cell.bounds);
    CGFloat cellHeight = CGRectGetHeight(cell.bounds);
    if (cellWidth < 40.0 || cellHeight < 1.0) {
        container.hidden = YES;
        return;
    }

    // 统一宽度：与 WIAFullBlockHeight / WIAFitBlockHeight 完全一致，避免贴合高度与实际渲染偏差
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 60.0;
    w = MIN(MAX(w, 280.0), 420.0);
    CGFloat textW = w - kWIAPadH * 2.0;

    // 意图文本（判断层）或"分析中…"
    NSAttributedString *ats = nil;
    if (r) {
        ats = WIAAttributedText(r);
    } else {
        ats = [[NSAttributedString alloc] initWithString:@"[WIA] 分析中…"
            attributes:@{
                NSFontAttributeName : [UIFont systemFontOfSize:10.0],
                NSForegroundColorAttributeName : WIAThemeTextColor(),
            }];
    }
    CGFloat intentH = 14.0;
    if (ats) {
        CGRect tr = [ats boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      context:nil];
        intentH = MAX(intentH, ceil(tr.size.height));
    }

    NSArray *replies = (r ? r.replies : @[]);
    UIFont *hf = [UIFont boldSystemFontOfSize:10.0];
    UIFont *rf = [UIFont systemFontOfSize:15.0];
    CGFloat lineH = ceil(rf.lineHeight);
    BOOL showReply = (wiaGenEnabled && replies.count > 0);

    // 先按内容算建议回复区实际高（标题 + 每行自适应），用于容器高度
    CGFloat replyH = 0.0;
    if (showReply) {
        replyH += ceil(hf.lineHeight) + kWIASpacing;   // 标题行
        NSUInteger cnt = MIN(replies.count, 4u);
        for (NSUInteger i = 0; i < cnt; i++) {
            NSString *tt = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(i + 1), replies[i]];
            CGRect ts = [tt boundingRectWithSize:CGSizeMake(textW - kWIA_BTN_SZ - 10.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                attributes:@{ NSFontAttributeName : rf } context:nil];
            NSInteger rows = MAX(1, (NSInteger)ceil(ts.size.height / lineH));
            replyH += rows * lineH + 6.0 + kWIASpacing;
        }
    }
    CGFloat h;
    if (r) {
        h = kWIAPadV * 2.0 + intentH + replyH;   // 结果已就绪：贴合实际内容高
    } else {
        h = MAX(kWIAPadV * 2.0 + intentH + replyH, WIAFullBlockHeight());   // 分析中：按完整预留，容器贴消息不挡
    }

    // 容器锚定在 cell 底部上方（cell 已按贴合高度增高，结果渲染在增高完成后进行）
    CGFloat y = MAX(0.0, cellHeight - h);
    container.frame = CGRectMake(8.0, y, w, h);

    // 意图文本标签：顶部对齐
    UILabel *clabel = WIAContainerLabel(container);
    clabel.frame = CGRectMake(kWIAPadH, kWIAPadV, textW, intentH);
    clabel.attributedText = ats;

    // 供点击发送：存会话 id 与发件人
    @try {
        objc_setAssociatedObject(clabel, &kWIA_REPLIES_KEY, replies, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *sess = @"";
        @try { sess = [wrap valueForKey:@"m_nsFromUsr"] ?: @""; } @catch (NSException *e) {}
        objc_setAssociatedObject(clabel, &kWIA_SESSION_KEY, sess, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *selfId = @"";
        @try { selfId = [wrap valueForKey:@"m_nsToUsr"] ?: @""; } @catch (NSException *e) {}
        objc_setAssociatedObject(clabel, &kWIA_SELF_KEY, selfId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *e) {}

    // 建议回复：标题 + 每行（左侧圆形发送按钮可点 + 文字不可点，避免误触）
    UIColor *tc = WIAThemeTextColor();
    NSArray *btns = objc_getAssociatedObject(container, &kWIA_BTNS_KEY);
    NSArray *txts = objc_getAssociatedObject(container, &kWIA_TXTS_KEY);
    UILabel *head = objc_getAssociatedObject(container, &kWIA_HEAD_KEY);

    CGFloat headY = kWIAPadV + intentH;
    CGFloat areaTop = headY;
    if (showReply && head) {
        head.hidden = NO;
        head.frame = CGRectMake(kWIAPadH + 2, headY, textW - 4, ceil(hf.lineHeight));
        head.textColor = tc;
        areaTop = headY + ceil(hf.lineHeight) + kWIASpacing;
    } else if (head) {
        head.hidden = YES;
    }

    CGFloat cursor = areaTop;
    // 建议回复只在生成层开启时渲染；关掉后即使缓存里有回复也全部隐藏
    NSUInteger cnt2 = showReply ? MIN(replies.count, (NSUInteger)btns.count) : 0;
    for (NSUInteger i = 0; i < cnt2; i++) {
        UIButton *b = btns[i];
        UILabel *tx = (i < txts.count) ? txts[i] : nil;
        NSString *text = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(i + 1), replies[i]];   // 带序号
        CGFloat tw = textW - kWIA_BTN_SZ - 10.0;
        CGRect ts = [text boundingRectWithSize:CGSizeMake(tw, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
            attributes:@{ NSFontAttributeName : rf } context:nil];
        NSInteger rows = MAX(1, (NSInteger)ceil(ts.size.height / lineH));
        CGFloat rowH = rows * lineH + 6.0;   // 上下各 3

        CGFloat btnSize = kWIA_BTN_SZ;
        BOOL showBtn = wiaQuickReplyEnabled;
        b.hidden = !showBtn;
        if (showBtn) {
            // 发送按钮放末尾：右对齐，垂直居中文字行
            b.frame = CGRectMake(kWIAPadH + textW - btnSize, cursor + (rowH - btnSize) / 2.0, btnSize, btnSize);
            b.tintColor = tc;
            [b setTitleColor:tc forState:UIControlStateNormal];
            // 浅色模式用黑底、深色模式用白底，两种模式都能看清背景
            BOOL dark = (cell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
            b.backgroundColor = dark ? [[UIColor whiteColor] colorWithAlphaComponent:0.20]
                                     : [[UIColor blackColor] colorWithAlphaComponent:0.10];
        }
        if (tx) {
            tx.hidden = NO;
            tx.frame = CGRectMake(kWIAPadH + 4.0, cursor, tw, rowH);
            tx.text = text;
            tx.textColor = tc;
        }
        cursor += rowH + kWIASpacing;
    }
    for (NSUInteger i = cnt2; i < btns.count; i++) {
        [btns[i] setHidden:YES];
        if (i < txts.count) [txts[i] setHidden:YES];
    }

    container.hidden = NO;
    [cell bringSubviewToFront:container];
}

#pragma mark - 工具：递归找 cell / 结果就绪刷新

static void WIAFindSubviews(UIView *view, Class cls, NSMutableArray *out)
{
    for (UIView *s in view.subviews) {
        if ([s isKindOfClass:cls]) [out addObject:s];
        WIAFindSubviews(s, cls, out);
    }
}

void WIARefreshVisibleCells(void)
{
    NSMutableArray *cells = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in [(UIWindowScene *)scene windows]) {
            WIAFindSubviews(w, NSClassFromString(@"TextMessageCellView"), cells);
        }
    }
    for (UIView *c in cells) {
        [c setNeedsLayout];
    }
}

// 开关切换后：强制刷新「可见且带分析块」的消息 cell 高度，
// 让微信按新的预留高度重算 rowHeight，避免分析块压住消息。
void WIARefreshHeightsAfterSwitch(void)
{
    @try {
        NSMutableArray *cells = [NSMutableArray array];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                WIAFindSubviews(w, NSClassFromString(@"TextMessageCellView"), cells);
            }
        }
        NSMutableDictionary *cvMap = [NSMutableDictionary dictionary]; // NSValue(cv) -> indexPaths
        for (UIView *c in cells) {
            @try {
                UIView *cv = c.superview;
                while (cv && ![cv isKindOfClass:[UICollectionView class]]) cv = cv.superview;
                if (!cv) continue;
                UIView *container = objc_getAssociatedObject(c, &kWIA_CONTAINER_KEY);
                if (![container isKindOfClass:[UIView class]] || container.hidden) continue;
                id ip = ((id(*)(id, SEL, id))objc_msgSend)(cv, @selector(indexPathForCell:), c);
                if (!ip) continue;
                NSValue *k = [NSValue valueWithNonretainedObject:cv];
                NSMutableArray *ips = cvMap[k] ?: [NSMutableArray array];
                [ips addObject:ip];
                cvMap[k] = ips;
            } @catch (NSException *e) {}
        }
        for (NSValue *k in cvMap) {
            @try {
                UICollectionView *cv = [k nonretainedObjectValue];
                ((void(*)(id, SEL, id))objc_msgSend)(cv, @selector(reloadItemsAtIndexPaths:), cvMap[k]);
            } @catch (NSException *e) {}
        }
    } @catch (NSException *e) {}
}

// 结果就绪：让消息列表重新测量行高，并确保底部那条消息的分析块完整可见（可滚动/自动滚到）。
void WIARelayoutLists(void)
{
    // 结果就绪：重算「带结果」消息 cell 的高度，让分析块贴合实际内容、下一条消息紧贴。
    WIARefreshHeightsAfterSwitch();
}

// 直接从当前屏幕上的消息列表抓最近上下文（含会话里已加载的历史），
// 不再只依赖 tweak 加载后才收到的内存记录。
// excludeContent 用于剔除"本条要分析的当前消息"，避免把自己算进去。
NSString *WIAOnScreenThread(NSString *excludeContent, NSInteger lines)
{
    Class cellCls = NSClassFromString(@"TextMessageCellView");
    if (!cellCls) return @"";
    if (lines <= 0) return @""; // 不关联

    NSMutableArray *rows = [NSMutableArray array]; // @{y, text}
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in [(UIWindowScene *)scene windows]) {
            NSMutableArray *cells = [NSMutableArray array];
            WIAFindSubviews(w, cellCls, cells);
            for (UIView *cell in cells) {
                id wrap = nil;
                SEL sel = NSSelectorFromString(@"getCurrentMessageWrap");
                if ([cell respondsToSelector:sel]) {
                    @try {
                        wrap = ((id (*)(id, SEL))objc_msgSend)(cell, sel);
                    } @catch (NSException *exception) { }
                }
                NSString *content = WIAReadString(wrap, @"m_nsContent");
                if (content.length == 0) continue;
                if (excludeContent.length && [content isEqualToString:excludeContent]) {
                    continue; // 跳过本条当前消息
                }
                NSString *role = (WIAReadUInt(wrap, @"m_uiIsSenderStatus") != 0) ? @"我" : @"对方";
                [rows addObject:@{
                    @"y"    : @(CGRectGetMinY(cell.frame)),
                    @"text" : [NSString stringWithFormat:@"[%@] %@", role, content],
                }];
            }
        }
    }

    if (rows.count == 0) return @"";
    [rows sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [a[@"y"] compare:b[@"y"]];
    }];
    NSMutableArray *lineArr = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [lineArr addObject:row[@"text"]];
        if ((NSInteger)lineArr.count >= lines) break;   // 关联最近 N 条（用户可选）
    }
    return [lineArr componentsJoinedByString:@"\n"];
}


#pragma mark - 意图识别放入正确的位置：消息接收数据层

// 超长消息会被微信拆成多条（分段几乎同时到达）。同会话极短窗口(3s)内的连续消息
// 只分析第一条，其余跳过，避免一条超长消息下方堆出多个分析块、互相重叠挡住。
#define kWIAMergeSeconds 3.0
// 延迟合并状态按会话隔离：不同会话的消息互不覆盖。旧实现共用一组全局变量，
// B 会话来消息会把 A 会话的 token 顶掉，A 的 inflight 永远没人清理（一直显示"分析中…"）。
static NSMutableDictionary *gWIAMergeStates;   // chatID -> {key,content,judgeCtx,genCtx,last,token}
static NSMutableDictionary *gWIALastSelfSend;  // chatID -> 我最后发消息的时间（CFAbsoluteTime）
static NSMutableDictionary *gWIALastInbound;   // chatID -> 最后收到该会话消息的时间
static NSMutableDictionary *gWIALatestKey;     // chatID -> 最新一条消息的 key，用于丢弃迟到的旧分析结果

// 纯应付/收尾消息（哈哈、嗯、好的、ok、行、表情语气词等）真人不回，自动回复也应跳过。
// 保守判定：去掉语气词、标点、空白后一个实字都不剩，且原文很短，才算应付。
static BOOL WIAIsFillerMessage(NSString *text)
{
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *t = [text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0 || t.length > 6) return NO;
    static NSCharacterSet *fillerChars;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *cs = [NSMutableCharacterSet punctuationCharacterSet];
        [cs formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 常见应付字：语气词/笑/应答。注意只收"单独用没有信息量"的字，
        // 实义字（吃、走、在、忙……）不收，避免误伤"在吗""走吧"这类真消息。
        [cs addCharactersInString:@"嗯哦啊呀哈嘿唉诶噢喔嘻呜呵好的行对okOK好吧嘛呢啦咯呗了"];
        fillerChars = cs;
    });
    NSString *stripped = [[t componentsSeparatedByCharactersInSet:fillerChars]
                          componentsJoinedByString:@""];
    return stripped.length == 0;
}

%hook CMessageMgr

- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap
{
    @try { gWIAMsgMgr = self; } @catch (NSException *e) {}
    %orig;

    @try {
        // 仅处理普通文本消息。
        if (!WIAIsTextMessage(wrap)) return;

        NSString *content = WIAReadString(wrap, @"m_nsContent");
        NSString *from = WIAReadString(wrap, @"m_nsFromUsr") ?: @"";
        NSString *selfId = WIAReadString(wrap, @"m_nsToUsr") ?: @"";   // 自己（登录账号），自动回复发送方
        BOOL isOutgoing = WIAIsOutgoingMessage(wrap);
        BOOL isGroup = WIAIsGroupMessage(wrap);

        // 无论收发都记入该会话历史，供后续建议回复关联上下文。
        // 自己发的不做分析/展示，只进历史（会话 ID 用对方，否则进错会话）。
        if (isOutgoing) {
            NSString *peer = (selfId.length ? selfId : from);
            WIAHistoryAppend(peer, @"assistant", content);
            @synchronized (WIAIntentCache()) {
                if (!gWIALastSelfSend) gWIALastSelfSend = [NSMutableDictionary dictionary];
                gWIALastSelfSend[peer] = @(CFAbsoluteTimeGetCurrent());
            }
            return;
        }
        // 判断层、生成层都关闭 → 只记历史，不分析、不显示（也不出现"分析中"）
        if (!wiaJudgeEnabled && !wiaGenEnabled) {
            WIAHistoryAppend(from, @"user", content);
            return;
        }
        // 分析前先取「不含本条」的上下文：优先抓屏幕上的会话历史（含已加载），
        // 屏幕没有则退回内存积累。判断层、生成层各自按所选条数取。
        NSString *judgeCtx = WIAHistoryThread(from, wiaJudgeContextLines);
        if (judgeCtx.length == 0) judgeCtx = WIAOnScreenThread(content, wiaJudgeContextLines);
        NSString *genCtx = WIAHistoryThread(from, wiaGenContextLines);
        if (genCtx.length == 0) genCtx = WIAOnScreenThread(content, wiaGenContextLines);
        WIAHistoryAppend(from, @"user", content);
        if (isGroup) return; // 群聊不分析、不展示

        NSString *key = WIAMessageKey(wrap);
        CFAbsoluteTime nowT = CFAbsoluteTimeGetCurrent();

        // 延迟合并：同会话 3s 内连续到达的分段消息，只分析「最后一条」。
        // 前面的分段成为中间段：清除其分析块（inflight/cache），保留预留空位。
        NSInteger myToken = 0;
        @synchronized (WIAIntentCache()) {
            if (!gWIAMergeStates) gWIAMergeStates = [NSMutableDictionary dictionary];
            if (!gWIALastInbound) gWIALastInbound = [NSMutableDictionary dictionary];
            if (!gWIALatestKey) gWIALatestKey = [NSMutableDictionary dictionary];
            gWIALastInbound[from] = @(nowT);
            gWIALatestKey[from] = key;

            NSMutableDictionary *st = gWIAMergeStates[from];
            NSString *prevKey = nil;
            BOOL sameWin = (st != nil && (nowT - [st[@"last"] doubleValue]) < kWIAMergeSeconds);
            if (sameWin) prevKey = st[@"key"];
            myToken = [st[@"token"] integerValue] + 1;
            gWIAMergeStates[from] = [@{
                @"key" : key,
                @"content" : content ?: @"",
                @"judgeCtx" : judgeCtx ?: @"",
                @"genCtx" : genCtx ?: @"",
                @"last" : @(nowT),
                @"token" : @(myToken)
            } mutableCopy];
            // 前一候选成为中间段：不再显示分析块
            if (prevKey.length) {
                [gWIAInflight removeObjectForKey:prevKey];
                [gWIAIntentCache removeObjectForKey:prevKey];
            }
            if (!gWIAInflight[key]) gWIAInflight[key] = @1; // 当前最后候选：预留+分析中
        }

        // 3 秒后若无新消息，分析当前最后一条候选；期间有新的则改分析新的一条。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kWIAMergeSeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSString *msgContent = nil, *msgJudgeCtx = nil, *msgGenCtx = nil;
            @synchronized (WIAIntentCache()) {
                NSMutableDictionary *st = gWIAMergeStates[from];
                if (!st || [st[@"token"] integerValue] != myToken ||
                    ![st[@"key"] isEqualToString:key]) {
                    // 本会话已有更新的候选：清掉自己的 inflight，交给新消息处理
                    [gWIAInflight removeObjectForKey:key];
                    return;
                }
                msgContent = st[@"content"];
                msgJudgeCtx = st[@"judgeCtx"];
                msgGenCtx = st[@"genCtx"];
                [gWIAMergeStates removeObjectForKey:from];
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                WIAJudgeResult *r = nil;
                @try {
                    r = WIARunAnalysis(msgContent, from, msgJudgeCtx, msgGenCtx);
                } @catch (NSException *e) {
                    NSLog(@"[WIA] analysis exception: %@", e);
                }
                @synchronized (WIAIntentCache()) {
                    // 分析期间又来了新消息：丢弃迟到的旧结果，避免把最新结果挤掉
                    BOOL latest = (!gWIALatestKey[from] ||
                                   [gWIALatestKey[from] isEqualToString:key]);
                    if (latest) {
                        gWIAIntentCache[key] = r;
                        WIACapIntentCache(from, key);   // 只保留当前最新1条，旧分析即弃
                    }
                    [gWIAInflight removeObjectForKey:key];
                }
                NSLog(@"[WIA] done from=%@ intent=%@ risk=%.0f action=%@ replies=%ld status=%@ detail=%@",
                      from, r.intent, r.risk, r.action,
                      (long)r.replies.count, r.status, r.detail);
                // 自动回复：开启且生成了建议回复 → 自动发送选定的那一条（无需手动点选）。
                // 发送前确认：分析期间我没有手动回复，也没有收到该会话的新消息。
                // 真人不会句句都回：收线策略（该结束话题）或纯应付消息（哈哈/嗯/好的…）不回。
                if (wiaAutoReplyEnabled && r.replies.count > 0) {
                    BOOL stale = NO;
                    @synchronized (WIAIntentCache()) {
                        stale = ([gWIALastSelfSend[from] doubleValue] > nowT + 0.01 ||
                                 [gWIALastInbound[from] doubleValue] > nowT + 0.01);
                    }
                    BOOL noReply = [r.strategy isEqualToString:@"收线"] ||
                                   WIAIsFillerMessage(msgContent);
                    if (!stale && !noReply) {
                        NSInteger idx = wiaAutoReplyIndex - 1;
                        if (idx < 0) idx = 0;
                        if (idx >= (NSInteger)r.replies.count) idx = (NSInteger)r.replies.count - 1;
                        WIASendReply(from, selfId, r.replies[idx]);
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kWIAIntentReadyNotification object:nil];
                });
            });
        });
    }
    @catch (NSException *exception) {
        NSLog(@"[WIA] AsyncOnAddMsg exception: %@", exception);
    }
}

%end

#pragma mark - 行高：为接收文本消息确定性预留整块高度，避免覆盖


#pragma mark - 行高：为接收文本消息确定性预留整块高度，避免覆盖
// 用健壮 WIAExtractWrap 取 messageWrap（此前 valueForKey 对长文本 viewModel 可能取不到，
// 导致长消息不预留、分析块盖住/切分消息）。

%hook BaseChatViewModel

- (double)rowHeight
{
    double h = %orig;

    @try {
        id wrap = WIAExtractWrap(self);
        if (WIAShouldReserveHeight(wrap) && WIAIsLastSubViewModel(self)) {
            return h + WIAEstimatedBlockHeight(wrap);
        }
    } @catch (NSException *exception) {
    }

    return h;
}

%end

// 微信对超长文本消息会拆分/折叠，其 cell 高度来自 contentHeight 而非 rowHeight。
// 短消息已由 rowHeight 预留；这里只对长文本（contentHeight 较大）再预留，避免双倍。
#pragma mark - UI 层仅展示缓存结果

%hook TextMessageCellView

- (void)layoutSubviews
{
    %orig;
    @try {
        WIAUpdateCellLabel((UIView *)self);
    } @catch (NSException *exception) {
        NSLog(@"[WIA] layoutSubviews exception: %@", exception);
    }
}

// 让分析块区域能接收到触摸（微信 cell 默认拦截，长按/点击都被吞掉）：
// 触点在分析块容器内时直接返回容器内的控件，否则走微信原逻辑。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    @try {
        UIView *container = WIAGetContainer((UIView *)self);
        if (container && !container.hidden && container.superview == (UIView *)self) {
            CGPoint local = [container convertPoint:point fromView:(UIView *)self];
            if ([container pointInside:local withEvent:event]) {
                UIView *hit = [container hitTest:local withEvent:event];
                if (hit) return hit;
            }
        }
    } @catch (NSException *exception) {}
    return %orig;
}

- (void)layoutContentView
{
    %orig;
    @try {
        WIAUpdateCellLabel((UIView *)self);
    } @catch (NSException *exception) {
        NSLog(@"[WIA] layoutContentView exception: %@", exception);
    }
}

- (void)prepareForReuse
{
    %orig;
    @try {
        UIView *container = objc_getAssociatedObject(self, &kWIA_CONTAINER_KEY);
        if ([container isKindOfClass:[UIView class]]) {
            container.hidden = YES;
            UILabel *label = objc_getAssociatedObject(container, &kWIA_LABEL_KEY);
            if ([label isKindOfClass:[UILabel class]]) label.text = @"";
        }
    } @catch (NSException *exception) {
        NSLog(@"[WIA] prepareForReuse exception: %@", exception);
    }
}

%end

#pragma mark - 建议回复：点击即发送

void WIASendReply(NSString *toUser, NSString *fromUser, NSString *text)
{
    if (toUser.length == 0 || fromUser.length == 0 || text.length == 0) return;
    @try {
        id msgMgr = WIAGetMsgMgr();
        if (!msgMgr) return;
        id wrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
        [wrap setValue:fromUser forKey:@"m_nsFromUsr"];
        [wrap setValue:text forKey:@"m_nsContent"];
        [wrap setValue:@((int)(10000 + (arc4random() % (99999 - 10000 + 1)))) forKey:@"m_uiMesLocalID"];
        [wrap setValue:toUser forKey:@"m_nsToUsr"];
        [wrap setValue:@((int)time(NULL)) forKey:@"m_uiCreateTime"];
        dispatch_async(dispatch_get_main_queue(), ^{
            ((void (*)(id, SEL, id, id))objc_msgSend)(msgMgr,
                sel_registerName("ResendMsg:MsgWrap:"), toUser, wrap);
        });
    } @catch (NSException *e) {}
}

@interface WIATapTarget : NSObject
@end

@implementation WIATapTarget

- (void)wiaReplyTapped:(UIButton *)btn
{
    @try {
        UIView *container = btn.superview;
        UILabel *label = WIAContainerLabel(container);
        NSArray *replies = objc_getAssociatedObject(label, &kWIA_REPLIES_KEY);
        NSString *session = objc_getAssociatedObject(label, &kWIA_SESSION_KEY);
        NSString *selfId = objc_getAssociatedObject(label, &kWIA_SELF_KEY);
        NSInteger idx = btn.tag;
        if (idx >= 0 && idx < (NSInteger)replies.count && session.length > 0 && selfId.length > 0) {
            WIASendReply(session, selfId, replies[idx]);
        }
    } @catch (NSException *e) {}
}

@end

id WIAGetTapTarget(void)
{
    static id t = nil;
    if (!t) t = [[WIATapTarget alloc] init];
    return t;
}
