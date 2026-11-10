#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSDictionary<NSString *, NSString *> *Translations(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"Creator Studio": @"创作者工作室",
            @"Programs": @"创作者计划",
            @"Original Content Rewards": @"原创内容奖励",
            @"Earn from your posts": @"通过发布内容赚取收益",
            @"Ineligible": @"暂不符合资格",
            @"Subscriptions": @"订阅",
            @"Tools": @"工具",
            @"Analytics": @"数据分析",
            @"Inspiration": @"创作灵感",
            @"Top posts by engagement": @"按互动量排序的热门帖子",
            @"Creator Academy": @"创作者学院",
            @"Tips and guides for creators": @"创作者实用技巧与指南",
            @"New": @"新",
            @"Support": @"支持",
            @"Contact support": @"联系支持",
            @"Learn more": @"了解更多"
        };
    });
    return map;
}

static void Collect(UIView *view, NSMutableArray<UIView *> *result) {
    if (view.hidden || view.alpha < 0.01) return;
    [result addObject:view];
    for (UIView *child in view.subviews) Collect(child, result);
}

static NSString *VisibleText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    if ([view isKindOfClass:UIButton.class]) return ((UIButton *)view).currentTitle;
    return nil;
}

static BOOL HasText(NSSet *texts, NSString *english) {
    return [texts containsObject:english] || [texts containsObject:Translations()[english]];
}

static void TranslateLabel(UILabel *label) {
    NSString *old = label.text;
    NSString *replacement = Translations()[old];
    if (!replacement) return;
    NSAttributedString *attributed = label.attributedText;
    if (attributed.length) {
        // Retain font, color and paragraph attributes instead of flattening styled text.
        NSDictionary *attributes = [attributed attributesAtIndex:0 effectiveRange:NULL];
        label.attributedText = [[NSAttributedString alloc] initWithString:replacement attributes:attributes];
    } else {
        label.text = replacement;
    }
    [label invalidateIntrinsicContentSize];
}

static void LocalizeWindow(UIWindow *window) {
    if (window.hidden || !window.rootViewController) return;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    Collect(window, views);
    NSMutableSet *texts = [NSMutableSet set];
    for (UIView *view in views) {
        NSString *value = VisibleText(view);
        if (value) [texts addObject:value];
    }
    // Require the page title and multiple unique menu anchors. Never translate timelines
    // merely because a post happens to contain a common word such as "Support".
    if (!HasText(texts, @"Creator Studio") ||
        !HasText(texts, @"Original Content Rewards") ||
        !HasText(texts, @"Creator Academy") ||
        !HasText(texts, @"Tools")) return;

    for (UIView *view in views) {
        if ([view isKindOfClass:UILabel.class]) TranslateLabel((UILabel *)view);
        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted),
                                      @(UIControlStateSelected), @(UIControlStateDisabled)]) {
                NSString *old = [button titleForState:state.unsignedIntegerValue];
                NSString *replacement = Translations()[old];
                if (replacement) [button setTitle:replacement forState:state.unsignedIntegerValue];
            }
        }
        NSString *accessible = view.accessibilityLabel;
        if (accessible && Translations()[accessible])
            view.accessibilityLabel = Translations()[accessible];
    }
}

@interface XCSZHDriver : NSObject
+ (void)tick;
@end
@implementation XCSZHDriver
+ (void)tick {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) LocalizeWindow(window);
    }
}
@end

__attribute__((constructor)) static void XCSZHStart(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.atebits.Tweetie2"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Timer handles menus constructed after network completion and reused cells.
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:XCSZHDriver.class
                selector:@selector(tick) userInfo:nil repeats:YES];
        });
    }
}
