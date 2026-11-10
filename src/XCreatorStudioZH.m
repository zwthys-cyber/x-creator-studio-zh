#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>

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


static NSUInteger NativeChanges;
static NSUInteger WebChanges;
static NSUInteger WebViewsSeen;
static BOOL ShowedLoaded;
static char BannerKey;
static char WebBusyKey;

static NSString *Normalize(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSArray *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}
static NSString *Replacement(NSString *text) {
    NSString *key = Normalize(text);
    return key.length ? Translations()[key] : nil;
}
static NSAttributedString *TranslateAttributed(NSAttributedString *text) {
    if (![text isKindOfClass:NSAttributedString.class]) return nil;
    NSString *replacement = Replacement(text.string);
    if (!replacement) return nil;
    NSDictionary *attributes = text.length ? [text attributesAtIndex:0 effectiveRange:NULL] : @{};
    return [[NSAttributedString alloc] initWithString:replacement attributes:attributes];
}
static id ObjectGetter(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL ObjectSetter(id object, SEL selector, id value) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        [signature getArgumentTypeAtIndex:2][0] != '@') return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    return YES;
}
static id DisplayNode(UIView *view) {
    // Texture exposes its owning node through the backing view.
    return ObjectGetter(view, NSSelectorFromString(@"asyncdisplaykit_node"));
}
static void Collect(UIView *view, NSMutableArray<UIView *> *result) {
    if (view.hidden || view.alpha < 0.01 || objc_getAssociatedObject(view, &BannerKey)) return;
    [result addObject:view];
    for (UIView *child in view.subviews) Collect(child, result);
}
static void GatherObject(id object, NSMutableSet *texts) {
    for (NSString *selector in @[@"text", @"attributedText", @"currentTitle"]) {
        id value = ObjectGetter(object, NSSelectorFromString(selector));
        if ([value isKindOfClass:NSAttributedString.class]) value = [value string];
        if ([value isKindOfClass:NSString.class]) [texts addObject:Normalize(value)];
    }
}
static void GatherLayer(CALayer *layer, NSMutableSet *texts) {
    if ([layer isKindOfClass:CATextLayer.class]) {
        id value = ((CATextLayer *)layer).string;
        if ([value isKindOfClass:NSAttributedString.class]) value = [value string];
        if ([value isKindOfClass:NSString.class]) [texts addObject:Normalize(value)];
    }
    for (CALayer *child in layer.sublayers) GatherLayer(child, texts);
}
static BOOL HasText(NSSet *texts, NSString *english) {
    return [texts containsObject:english] || [texts containsObject:Translations()[english]];
}
static void TranslateObject(id object) {
    id attributed = ObjectGetter(object, @selector(attributedText));
    NSAttributedString *translated = TranslateAttributed(attributed);
    if (translated && ObjectSetter(object, @selector(setAttributedText:), translated)) {
        NativeChanges++;
        return;
    }
    id plain = ObjectGetter(object, @selector(text));
    if (![plain isKindOfClass:NSString.class]) return;
    NSString *replacement = Replacement(plain);
    if (replacement && ObjectSetter(object, @selector(setText:), replacement)) NativeChanges++;
}
static void TranslateLayer(CALayer *layer) {
    if ([layer isKindOfClass:CATextLayer.class]) {
        CATextLayer *textLayer = (CATextLayer *)layer;
        id value = textLayer.string;
        id replacement = [value isKindOfClass:NSAttributedString.class] ?
            TranslateAttributed(value) : Replacement(value);
        if (replacement) { textLayer.string = replacement; NativeChanges++; }
    }
    for (CALayer *child in layer.sublayers) TranslateLayer(child);
}
static NSString *JavaScript(void) {
    static NSString *script;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:Translations() options:0 error:NULL];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        script = [@"(() => {\nconst map = __XCSZH_MAP__;\nconst norm = s => (s || '').replace(/\\s+/g, ' ').trim();\nconst body = document.body;\nif (!body) return 0;\nconst text = norm(body.innerText);\nconst has = s => text.includes(s) || text.includes(map[s]);\nif (!has('Creator Studio') || !(has('Creator Academy') || has('Original Content Rewards'))) return 0;\nlet count = 0;\nconst walk = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);\nconst nodes = [];\nwhile (walk.nextNode()) nodes.push(walk.currentNode);\nfor (const node of nodes) {\n  const parent = node.parentElement;\n  if (!parent || parent.closest('script,style,textarea,input,[contenteditable=\"true\"]')) continue;\n  const key = norm(node.nodeValue);\n  if (!Object.prototype.hasOwnProperty.call(map, key)) continue;\n  node.nodeValue = node.nodeValue.replace(key, map[key]);\n  count++;\n}\nfor (const element of body.querySelectorAll('[aria-label]')) {\n  const key = norm(element.getAttribute('aria-label'));\n  if (Object.prototype.hasOwnProperty.call(map, key)) element.setAttribute('aria-label', map[key]);\n}\nreturn count;\n})()" stringByReplacingOccurrencesOfString:@"__XCSZH_MAP__" withString:json];
    });
    return script;
}
static UIViewController *TopController(UIViewController *controller) {
    if (controller.presentedViewController) return TopController(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class])
        return TopController(((UINavigationController *)controller).visibleViewController);
    if ([controller isKindOfClass:UITabBarController.class])
        return TopController(((UITabBarController *)controller).selectedViewController);
    return controller;
}
static void LocalizeWindow(UIWindow *window) {
    if (window.hidden || !window.rootViewController) return;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    Collect(window, views);
    NSMutableSet *texts = [NSMutableSet set];
    UIViewController *controller = TopController(window.rootViewController);
    if (controller.title) [texts addObject:Normalize(controller.title)];
    if (controller.navigationItem.title) [texts addObject:Normalize(controller.navigationItem.title)];
    for (UIView *view in views) {
        GatherObject(view, texts);
        GatherObject(DisplayNode(view), texts);
        if ([view isKindOfClass:WKWebView.class]) {
            WebViewsSeen++;
            if (objc_getAssociatedObject(view, &WebBusyKey)) continue;
            objc_setAssociatedObject(view, &WebBusyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak WKWebView *web = (WKWebView *)view;
            [web evaluateJavaScript:JavaScript() completionHandler:^(id result, NSError *error) {
                if (!error && [result isKindOfClass:NSNumber.class]) WebChanges += [result unsignedIntegerValue];
                if (web) objc_setAssociatedObject(web, &WebBusyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
        }
    }
    GatherLayer(window.layer, texts);
    // Title plus one distinctive menu anchor tolerates virtualized/offscreen rows.
    if (!HasText(texts, @"Creator Studio") ||
        !(HasText(texts, @"Original Content Rewards") || HasText(texts, @"Creator Academy"))) return;
    for (UIView *view in views) {
        // Leave user-editable text untouched.
        if ([view isKindOfClass:UITextView.class] || [view isKindOfClass:UITextField.class]) continue;
        NSUInteger before = NativeChanges;
        TranslateObject(view);
        TranslateObject(DisplayNode(view));
        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted),
                                      @(UIControlStateSelected), @(UIControlStateDisabled)]) {
                NSString *replacement = Replacement([button titleForState:state.unsignedIntegerValue]);
                if (replacement) { [button setTitle:replacement forState:state.unsignedIntegerValue]; NativeChanges++; }
            }
        }
        NSString *accessible = Replacement(view.accessibilityLabel);
        if (accessible) view.accessibilityLabel = accessible;
        if (NativeChanges != before) {
            [view invalidateIntrinsicContentSize];
            [view setNeedsLayout];
        }
    }
    TranslateLayer(window.layer);
    NSString *title = Replacement(controller.title);
    if (title) controller.title = title;
    title = Replacement(controller.navigationItem.title);
    if (title) controller.navigationItem.title = title;
}
@interface XCSZHDriver : NSObject
+ (void)tick;
+ (void)diagnose:(UILongPressGestureRecognizer *)gesture;
@end
@implementation XCSZHDriver
+ (void)diagnose:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIWindow *window = gesture.view.window;
    UIViewController *controller = TopController(window.rootViewController);
    if (!controller || [controller isKindOfClass:UIAlertController.class]) return;
    NSString *message = [NSString stringWithFormat:
        @"版本：0.2\n已加载：是\nBundle ID：%@\n原生替换：%lu\n网页替换：%lu\n发现网页累计：%lu\n页面类型：%@",
        NSBundle.mainBundle.bundleIdentifier, (unsigned long)NativeChanges,
        (unsigned long)WebChanges, (unsigned long)WebViewsSeen, NSStringFromClass(controller.class)];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"中文插件诊断"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
+ (void)tick {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    // Older app lifecycle may not register UIWindowScene instances.
    id delegateWindow = ObjectGetter(UIApplication.sharedApplication.delegate, @selector(window));
    if ([delegateWindow isKindOfClass:UIWindow.class]) [windows addObject:delegateWindow];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    for (UIWindow *window in windows) {
        LocalizeWindow(window);
        if (window.hidden || !window.isKeyWindow || !window.rootViewController) continue;
        static char GestureKey;
        if (!objc_getAssociatedObject(window, &GestureKey)) {
            UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(diagnose:)];
            gesture.numberOfTouchesRequired = 3;
            gesture.minimumPressDuration = 1.2;
            gesture.cancelsTouchesInView = NO;
            [window addGestureRecognizer:gesture];
            objc_setAssociatedObject(window, &GestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (ShowedLoaded) continue;
        ShowedLoaded = YES;
        UILabel *banner = [[UILabel alloc] initWithFrame:CGRectMake(16, window.safeAreaInsets.top + 8,
            MAX(120, window.bounds.size.width - 32), 40)];
        objc_setAssociatedObject(banner, &BannerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        banner.text = @"中文插件 v0.2 已加载";
        banner.textAlignment = NSTextAlignmentCenter;
        banner.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        banner.backgroundColor = UIColor.systemBlueColor;
        banner.textColor = UIColor.whiteColor;
        banner.layer.cornerRadius = 10;
        banner.clipsToBounds = YES;
        banner.userInteractionEnabled = NO;
        [window addSubview:banner];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [banner removeFromSuperview];
        });
    }
}
@end

#ifndef XCSZH_FIXTURE
__attribute__((constructor)) static void XCSZHStart(void) {
    @autoreleasepool {
        // An explicitly injected clone must work even after its bundle ID changes.
        // App extensions have no UIApplication lifecycle and are excluded.
        if ([NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer *timer = [NSTimer timerWithTimeInterval:0.75 target:XCSZHDriver.class
                selector:@selector(tick) userInfo:nil repeats:YES];
            [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
        });
    }
}
#endif
