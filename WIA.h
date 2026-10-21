#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <UserNotifications/UserNotifications.h>

#pragma mark - 接口声明

@interface CMessageWrap : NSObject
@property (nonatomic, retain) NSString *m_nsContent;
@property (nonatomic, retain) NSString *m_nsFromUsr;
@property (nonatomic, retain) NSString *m_nsToUsr;
@property (nonatomic, assign) unsigned int m_uiCreateTime;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiStatus;
- (instancetype)initWithMsgType:(long long)type;
@end

@interface CMessageMgr : NSObject
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap;
- (void)AddLocalMsg:(NSString *)session MsgWrap:(CMessageWrap *)wrap fixTime:(BOOL)time NewMsgArriveNotify:(BOOL)notify;
@end

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)service;
@end

@interface TextMessageCellView : UIView
- (void)layoutContentView;
- (void)layoutSubviews;
- (void)prepareForReuse;
- (id)getCurrentMessageWrap;
- (id)getRichTextView;
@end

@interface TextMessageViewModel : NSObject
- (double)rowHeight;
@end

@interface NewSettingViewController : UIViewController @end
@interface WIAXiaoweiVC : UIViewController @end


@interface NewSettingViewController (WIAUI)
- (void)openXiaoweiPage:(id)sender;
@end

#pragma mark - 布局常量

static const CGFloat kWILineHeight = 17.0;   // 每行文本高（12pt 字体）
static const CGFloat kWIAPadH = 10.0;        // 容器水平内边距
static const CGFloat kWIAPadV = 6.0;         // 容器垂直内边距
static const CGFloat kWIABtnH = 24.0;        // 每条建议回复按钮高度
static const CGFloat kWIASpacing = 3.0;      // 建议回复行间距
static const CGFloat kWIA_BTN_SZ = 18.0;      // 建议回复发送按钮尺寸
static const CGFloat kWIAExtraGap = 4.0;     // 容器与气泡的间距

// 结果就绪通知名：判断/起草完成后触发 cell 重新布局。
static NSString * const kWIAIntentReadyNotification = @"com.local.wia.IntentReady";

#pragma mark - 配置（已填：判断层 bocha-jev-v1 + 生成层 deepseek-chat）

static NSString * const kWIACfgJudgeBase  = @"";   // 判断层默认地址：空，设置页自填
static NSString * const kWIACfgJudgeKey   = @"";   // 判断层默认 key：空，设置页自填
static NSString * const kWIACfgJudgeModel = @"";   // 判断层默认模型：空，设置页自填

static NSString * const kWIACfgGenBase  = @"";   // 生成层默认地址：空，设置页自填
static NSString * const kWIACfgGenKey   = @"";   // 生成层默认 key：空，设置页自填
static NSString * const kWIACfgGenModel = @"";   // 生成层默认模型：空，设置页自填
static NSString * const kWIACfgGenKind  = @"openai"; // openai | anthropic
@interface WIATonePickerVC : UITableViewController
@property (nonatomic, strong) NSMutableArray *selectedTones;
@end
// 读取其他功能开关（默认开，可用 NSUserDefaults 关）
static NSArray * const kWIACfgTones = @[ @"情绪价值", @"讨好型人格", @"高情商话术", @"夸夸" ];   // 默认恰好 4 个话术
static const NSInteger kWIARepliesPerTone = 1;   // 每个话术 1 条 → 建议回复固定 4 条

@interface WIAJudgeResult : NSObject
@property (nonatomic, copy) NSString *intentQuestion;   // 当前真实意图
@property (nonatomic, copy) NSArray *intentOptions;     // 按概率降序
@property (nonatomic, copy) NSString *intent;           // 选中的意图（最高概率）
@property (nonatomic) double risk;                      // 0-10
@property (nonatomic, copy) NSArray *riskOptions;       // @[{label,prob}]（等级）
@property (nonatomic, copy) NSString *actionQuestion;   // 最佳动作
@property (nonatomic, copy) NSArray *actionOptions;     // 按概率降序
@property (nonatomic, copy) NSString *action;           // 选中动作
@property (nonatomic, copy) NSString *strategy;         // 本轮行动策略（承接/降压/调侃/轻推/约见/澄清/收线）
// 自适应多段问题块：@{@"question":..., @"options":[{label,prob}], @"note":...}，按提问顺序。
@property (nonatomic, copy) NSArray *blocks;
@property (nonatomic, copy) NSString *humanRead;   // 真人读心：像懂人心的人一样，多角度的一句话判断
@property (nonatomic, copy) NSArray *replies;           // 有序候选回复（最多4条）
@property (nonatomic, copy) NSString *status;           // nil=成功；否则提示文案
@property (nonatomic, copy) NSString *detail;           // 失败原因
@property (nonatomic, assign) BOOL usedLocalJudge;      // 是否用了本地规则判断（无 key/失败）
@end

// ==================== 跨文件共享符号（由 _split.py 生成，勿手改） ====================
#pragma mark - 共享全局变量（extern）
extern BOOL keepAliveEnabled;
extern BOOL preventRevokeEnabled;
extern id gWIAMsgMgr;
extern BOOL stepSpoofEnabled;
extern BOOL instantStep88888Enabled;
extern NSInteger stepTarget;
extern NSDate *lastInstantStepDate;
extern BOOL wiaJudgeEnabled;
extern BOOL wiaGenEnabled;
extern BOOL wiaToneRealEnabled;   // 话术模式：开=话术当底子+真实口吻；关=纯真实角度（无话术标签）
extern BOOL wiaQuickReplyEnabled;
extern BOOL wiaAutoReplyEnabled;
extern BOOL wiaMemoryEnabled;      // 记忆档案开关：开=判断层/生成层读取+更新相处笔记；关=完全不用（默认开）
extern NSInteger wiaAutoReplyIndex;
extern NSInteger wiaJudgeContextLines;
extern NSInteger wiaGenContextLines;
extern NSArray *wiaSelectedTones;
extern NSMutableDictionary *gWIAHistory;
extern NSMutableDictionary *gWIAIntentCache;
extern NSMutableDictionary *gWIAInflight;
extern NSInteger wiaEntryMode;   // 插件入口位置：0=仅微信设置 1=仅插件 2=两者

#pragma mark - 共享函数（extern）
extern NSString *WIACfgString(NSString *key, NSString *def);
extern NSString *WIAJudgeBase(void);
extern NSString *WIAJudgeKey(void);
extern NSString *WIAJudgeModel(void);
extern NSString *WIAGenBase(void);
extern NSString *WIAGenKey(void);
extern NSString *WIAGenModel(void);
extern NSString *WIAGenKind(void);
extern NSArray *WIAToneList(void);
extern NSDictionary *WIAToneInstructions(void);
extern void WIALoadFeatureDefaults(void);
extern WIAJudgeResult *WIARunAnalysis(NSString *message, NSString *chatID, NSString *judgeCtx, NSString *genCtx);
extern NSMutableDictionary *WIAIntentCache(void);
extern WIAJudgeResult *WIACachedIntentForKey(NSString *key);
extern BOOL WIAInflightForKey(NSString *key);
extern BOOL WIAAnalyzable(id wrap);
extern BOOL WIAShouldReserveHeight(id wrap);
extern CGFloat WIAFullBlockHeight(void);
extern CGFloat WIAFitBlockHeight(WIAJudgeResult *r);
extern CGFloat WIAEstimatedBlockHeight(id wrap);
extern id WIAExtractWrap(id obj);
extern BOOL WIAIsLastSubViewModel(id viewModel);
extern UIColor *WIAThemeTextColor(void);
extern NSAttributedString *WIAAttributedText(WIAJudgeResult *r);
extern id WIAGetTapTarget(void);
extern void WIARefreshVisibleCells(void);
extern void WIARefreshHeightsAfterSwitch(void);
extern void WIARelayoutLists(void);
extern NSString *WIAOnScreenThread(NSString *excludeContent, NSInteger lines);
extern void WIAUpdateCellLabel(UIView *cell);
extern void WIASendReply(NSString *toUser, NSString *fromUser, NSString *text);
extern id WIAGetMsgMgr(void);
extern void WIAHistoryAppend(NSString *chatID, NSString *role, NSString *content);
extern NSString *WIAHistoryThread(NSString *chatID, NSInteger lines);
extern NSDictionary *WIARelationTypes(void);
extern NSMutableDictionary *gWIAMemory;   // 记忆档案：chatID -> 相处笔记 dict（"这是TA/我们之间/聊过什么/长期话题/TA最近/待办承诺/画像小结"）
extern NSString *WIAMemoryPath(void);
extern NSString *WIAMemoryBackupPath(void);
extern void WIAWriteMemory(void);
extern void WIAReadMemory(void);
extern void WIAClearMemory(void);
extern NSDictionary *WIAMemoryForUser(NSString *chatID);
extern NSString *WIAMemoryRelationForUser(NSString *chatID);   // 从记忆读"我们关系"（关系档案已废弃）
extern NSString *WIAMemoryBrief(NSString *chatID);
extern void WIAUpdateMemoryForNote(NSString *chatID, NSDictionary *note, NSString *msgKey);   // 合并新笔记（缺失节用旧笔记补）并落盘；msgKey 记来源消息 id（可 nil）
extern void WIACapIntentCache(NSString *from, NSString *key);   // 分析结果每会话限 20 条，超出淘汰最旧
// 消息字段读取（Core 定义，UI/设置共用）
extern NSString *WIAReadString(id obj, NSString *key);
extern unsigned int WIAReadUInt(id obj, NSString *key);
extern long long WIAReadInt64(id obj, NSString *key);
extern NSString *WIAMessageKey(id wrap);
extern BOOL WIAIsTextMessage(id wrap);
extern BOOL WIAIsOutgoingMessage(id wrap);
extern BOOL WIAIsGroupMessage(id wrap);
// 防撤回：就地替换被撤回消息后刷新对应 cell（显示在原位置）

