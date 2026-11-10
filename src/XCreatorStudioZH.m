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
static NSInteger LastWebError;
static BOOL LastPageMatched;
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
static id DisplayNode(id view) {
    // Texture exposes its owning node through the backing view.
    return ObjectGetter(view, NSSelectorFromString(@"asyncdisplaykit_node"));
}
static void Collect(UIView *view, NSMutableArray<UIView *> *result) {
    if (view.hidden || view.alpha < 0.01 || objc_getAssociatedObject(view, &BannerKey)) return;
    [result addObject:view];
    for (UIView *child in view.subviews) Collect(child, result);
}

static void CollectNodeTree(id node, NSMutableArray *nodes, NSHashTable *seen, NSUInteger depth) {
    if (!node || depth > 64 || nodes.count >= 4096 || [seen containsObject:node]) return;
    [seen addObject:node];
    [nodes addObject:node];
    id children = ObjectGetter(node, NSSelectorFromString(@"subnodes"));
    if ([children isKindOfClass:NSArray.class]) {
        for (id child in children) CollectNodeTree(child, nodes, seen, depth + 1);
    }
}
static void CollectLayerNodes(CALayer *layer, NSMutableArray *nodes, NSHashTable *seen, NSUInteger depth) {
    if (!layer || layer.hidden || layer.opacity < 0.01 || depth > 128) return;
    CollectNodeTree(DisplayNode(layer), nodes, seen, 0);
    for (CALayer *child in layer.sublayers) CollectLayerNodes(child, nodes, seen, depth + 1);
}
static NSArray *NodesForWindow(UIWindow *window, NSArray<UIView *> *views) {
    NSMutableArray *nodes = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (UIView *view in views) CollectNodeTree(DisplayNode(view), nodes, seen, 0);
    CollectLayerNodes(window.layer, nodes, seen, 0);
    return nodes;
}

static void GatherObject(id object, NSMutableSet *texts) {
    for (NSString *selector in @[@"text", @"attributedText", @"currentTitle", @"accessibilityLabel"]) {
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
static BOOL PageMatches(NSSet *texts) {
    BOOL rewards = HasText(texts, @"Original Content Rewards");
    BOOL academy = HasText(texts, @"Creator Academy");
    return (HasText(texts, @"Creator Studio") && (rewards || academy)) || (rewards && academy);
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

static char JetfuelStateKey;
static NSUInteger JetfuelChanges;
static NSHashTable<UIView *> *JetfuelHosts;

@interface XCSZHJetfuelState : NSObject
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *inkAlphas;
@property(nonatomic, copy) NSString *english;
@property(nonatomic, copy) NSString *originalAccessibility;
@end
@implementation XCSZHJetfuelState
@end

static BOOL IsJetfuelHost(UIView *view) {
    return [NSStringFromClass(view.class) isEqualToString:@"JetfuelSDK.TextDisplayView"];
}
static BOOL IsJetfuelInk(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"JetfuelSDK"] && [name containsString:@"TextInkView"];
}
static NSString *CanonicalMenuKey(NSString *value) {
    NSString *key = Normalize(value);
    if (!key.length) return nil;
    if (Translations()[key]) return key;
    for (NSString *english in Translations())
        if ([Translations()[english] isEqualToString:key]) return english;
    return nil;
}
static void FindInk(UIView *view, NSMutableArray<UIView *> *result, NSUInteger depth) {
    if (depth > 16) return;
    for (UIView *child in view.subviews) {
        if (objc_getAssociatedObject(child, &BannerKey)) continue;
        if (IsJetfuelInk(child)) [result addObject:child];
        else FindInk(child, result, depth + 1);
    }
}
static NSString *JetfuelMenuKey(UIView *view, NSArray<UIView *> *inks) {
    NSString *key = CanonicalMenuKey(view.accessibilityLabel);
    if (!key) key = CanonicalMenuKey(view.accessibilityAttributedLabel.string);
    if (key) return key;
    for (UIView *ink in inks) {
        key = CanonicalMenuKey(ink.accessibilityLabel);
        if (key) return key;
    }
    return nil;
}
static void RestoreJetfuel(UIView *view) {
    XCSZHJetfuelState *state = objc_getAssociatedObject(view, &JetfuelStateKey);
    if (!state) return;
    for (UIView *ink in state.inkAlphas) ink.alpha = [[state.inkAlphas objectForKey:ink] doubleValue];
    if ([view.accessibilityLabel isEqualToString:Translations()[state.english]])
        view.accessibilityLabel = state.originalAccessibility;
    [state.label removeFromSuperview];
    objc_setAssociatedObject(view, &JetfuelStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void CleanupJetfuel(UIWindow *window, NSSet<UIView *> *active) {
    for (UIView *host in JetfuelHosts.allObjects) {
        if ((!host.window || host.window == window) && ![active containsObject:host]) RestoreJetfuel(host);
    }
}
static BOOL TranslateJetfuel(UIView *view) {
    if (!IsJetfuelHost(view) || !view.window || CGRectIsEmpty(view.bounds)) return NO;
    CGRect visible = [view convertRect:view.bounds toView:view.window];
    if (!CGRectIntersectsRect(visible, view.window.bounds)) return NO;
    NSMutableArray<UIView *> *inks = [NSMutableArray array];
    FindInk(view, inks, 0);
    NSString *english = JetfuelMenuKey(view, inks);
    if (!english || !inks.count) { RestoreJetfuel(view); return NO; }
    XCSZHJetfuelState *state = objc_getAssociatedObject(view, &JetfuelStateKey);
    if (!state) {
        state = [XCSZHJetfuelState new];
        state.inkAlphas = [NSMapTable weakToStrongObjectsMapTable];
        state.originalAccessibility = view.accessibilityLabel;
        state.label = [[UILabel alloc] initWithFrame:view.bounds];
        state.label.userInteractionEnabled = NO;
        state.label.isAccessibilityElement = NO;
        state.label.backgroundColor = UIColor.clearColor;
        state.label.numberOfLines = 1;
        state.label.adjustsFontSizeToFitWidth = YES;
        state.label.minimumScaleFactor = 0.55;
        state.label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
        state.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        state.label.layer.zPosition = 10000;
        objc_setAssociatedObject(state.label, &BannerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &JetfuelStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!JetfuelHosts) JetfuelHosts = [NSHashTable weakObjectsHashTable];
        [JetfuelHosts addObject:view];
    }
    if (![state.english isEqualToString:english]) {
        if (state.english && ![view.accessibilityLabel isEqualToString:Translations()[state.english]])
            state.originalAccessibility = view.accessibilityLabel;
        state.english = english;
        state.label.text = Translations()[english];
        JetfuelChanges++;
        NativeChanges++;
    }
    CGRect frame = [inks.firstObject convertRect:inks.firstObject.bounds toView:view];
    frame = CGRectIntersection(view.bounds, frame);
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame)) frame = view.bounds;
    state.label.frame = frame;
    CGFloat size = MAX(10, MIN(22, frame.size.height * 0.78));
    BOOL heading = [@[@"Creator Studio", @"Programs", @"Tools", @"Support"] containsObject:english];
    BOOL badge = [english isEqualToString:@"New"] || [english isEqualToString:@"Ineligible"];
    BOOL secondary = [@[@"Earn from your posts", @"Top posts by engagement",
                         @"Tips and guides for creators"] containsObject:english];
    state.label.font = [UIFont systemFontOfSize:size weight:heading ? UIFontWeightBold : UIFontWeightRegular];
    state.label.textColor = secondary ? UIColor.secondaryLabelColor : UIColor.labelColor;
    if ([english isEqualToString:@"Ineligible"]) state.label.textColor = UIColor.tertiaryLabelColor;
    if ([english isEqualToString:@"New"]) state.label.textColor = UIColor.whiteColor;
    state.label.textAlignment = (badge || [english isEqualToString:@"Creator Studio"]) ?
        NSTextAlignmentCenter : NSTextAlignmentNatural;
    // Hide only the proven custom ink views. Never hide/replace the row, icon or tap target.
    for (UIView *ink in inks) {
        if (![state.inkAlphas objectForKey:ink]) [state.inkAlphas setObject:@(ink.alpha) forKey:ink];
        ink.alpha = 0;
    }
    if (state.label.superview != view) [view addSubview:state.label];
    [view bringSubviewToFront:state.label];
    view.accessibilityLabel = Translations()[english];
    return YES;
}

static NSString *JavaScript(void) {
    static NSString *script;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:Translations() options:0 error:NULL];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        script = [@"(() => {\nconst map = __XCSZH_MAP__;\nconst norm = s => (s || '').replace(/\\s+/g, ' ').trim();\nconst body = document.body;\nif (!body) return 0;\nconst text = norm(body.innerText);\nconst has = s => text.includes(s) || text.includes(map[s]);\nif (!((has('Creator Studio') && (has('Creator Academy') || has('Original Content Rewards'))) || (has('Creator Academy') && has('Original Content Rewards')))) return 0;\nlet count = 0;\nconst walk = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);\nconst nodes = [];\nwhile (walk.nextNode()) nodes.push(walk.currentNode);\nfor (const node of nodes) {\n  const parent = node.parentElement;\n  if (!parent || parent.closest('script,style,textarea,input,[contenteditable=\"true\"]')) continue;\n  const key = norm(node.nodeValue);\n  if (!Object.prototype.hasOwnProperty.call(map, key)) continue;\n  node.nodeValue = (node.nodeValue.match(/^\\s*/) || [''])[0] + map[key] + (node.nodeValue.match(/\\s*$/) || [''])[0];\n  count++;\n}\nfor (const element of body.querySelectorAll('[aria-label]')) {\n  const key = norm(element.getAttribute('aria-label'));\n  if (Object.prototype.hasOwnProperty.call(map, key)) element.setAttribute('aria-label', map[key]);\n}\nreturn count;\n})()" stringByReplacingOccurrencesOfString:@"__XCSZH_MAP__" withString:json];
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
    if (window.hidden || !window.rootViewController || objc_getAssociatedObject(window, &BannerKey)) return;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    Collect(window, views);
    NSArray *nodes = NodesForWindow(window, views);
    NSMutableSet *texts = [NSMutableSet set];
    UIViewController *controller = TopController(window.rootViewController);
    if (controller.title) [texts addObject:Normalize(controller.title)];
    if (controller.navigationItem.title) [texts addObject:Normalize(controller.navigationItem.title)];
    for (UIView *view in views) {
        GatherObject(view, texts);
        if ([view isKindOfClass:WKWebView.class]) {
            WebViewsSeen++;
            if (objc_getAssociatedObject(view, &WebBusyKey)) continue;
            objc_setAssociatedObject(view, &WebBusyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak WKWebView *web = (WKWebView *)view;
            [web evaluateJavaScript:JavaScript() completionHandler:^(id result, NSError *error) {
                LastWebError = error ? error.code : 0;
                if (!error && [result isKindOfClass:NSNumber.class]) WebChanges += [result unsignedIntegerValue];
                if (web) objc_setAssociatedObject(web, &WebBusyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
        }
    }
    for (id node in nodes) GatherObject(node, texts);
    GatherLayer(window.layer, texts);
    LastPageMatched = PageMatches(texts);
    if (!LastPageMatched) { CleanupJetfuel(window, [NSSet set]); return; }
    NSMutableSet<UIView *> *activeJetfuel = [NSMutableSet set];
    for (UIView *view in views) {
        if (IsJetfuelHost(view)) {
            if (TranslateJetfuel(view)) [activeJetfuel addObject:view];
            continue;
        }
        if (IsJetfuelInk(view)) continue;
        // Leave user-editable text untouched.
        if ([view isKindOfClass:UITextView.class] || [view isKindOfClass:UITextField.class]) continue;
        NSUInteger before = NativeChanges;
        TranslateObject(view);
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
    CleanupJetfuel(window, activeJetfuel);
    for (id node in nodes) TranslateObject(node);
    TranslateLayer(window.layer);
    NSString *title = Replacement(controller.title);
    if (title) controller.title = title;
    title = Replacement(controller.navigationItem.title);
    if (title) controller.navigationItem.title = title;
}

static NSArray<UIWindow *> *ApplicationWindows(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState == UISceneActivationStateForegroundActive)
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    id delegateWindow = ObjectGetter(UIApplication.sharedApplication.delegate, @selector(window));
    if ([delegateWindow isKindOfClass:UIWindow.class]) [windows addObject:delegateWindow];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    NSMutableArray *result = [NSMutableArray array];
    for (UIWindow *window in windows)
        if (!objc_getAssociatedObject(window, &BannerKey) && !window.hidden && window.rootViewController)
            [result addObject:window];
    return result;
}
static NSString *DiagnosticReport(UIWindow *window) {
    NSMutableArray *views = [NSMutableArray array];
    Collect(window, views);
    NSArray *nodes = NodesForWindow(window, views);
    NSMutableSet *texts = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *classes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, id> *samples = [NSMutableDictionary dictionary];
    NSUInteger webCount = 0;
    for (id object in [views arrayByAddingObjectsFromArray:nodes]) {
        GatherObject(object, texts);
        NSString *name = NSStringFromClass([object class]);
        classes[name] = @([classes[name] unsignedIntegerValue] + 1);
        samples[name] = object;
        if ([object isKindOfClass:WKWebView.class]) webCount++;
    }
    UIViewController *controller = TopController(window.rootViewController);
    if (controller.title) [texts addObject:Normalize(controller.title)];
    if (controller.navigationItem.title) [texts addObject:Normalize(controller.navigationItem.title)];
    GatherLayer(window.layer, texts);
    NSMutableArray *anchors = [NSMutableArray array];
    for (NSString *english in [[Translations() allKeys] sortedArrayUsingSelector:@selector(compare:)])
        if (HasText(texts, english)) [anchors addObject:english];
    NSMutableString *report = [NSMutableString stringWithFormat:
        @"版本 0.4 · 已加载\n页面匹配：%@\n原生替换：%lu / 网页替换：%lu\nJetfuel 自绘替换：%lu\n视图：%lu / 节点：%lu / 网页：%lu\n网页错误码：%ld\n页面类型：%@\n识别菜单项：%@\n\n控件类型（可向下滚动）：\n",
        PageMatches(texts) ? @"是" : @"否", (unsigned long)NativeChanges, (unsigned long)WebChanges, (unsigned long)JetfuelChanges,
        (unsigned long)views.count, (unsigned long)nodes.count, (unsigned long)webCount,
        (long)LastWebError, NSStringFromClass(controller.class),
        anchors.count ? [anchors componentsJoinedByString:@", "] : @"无"];
    NSArray *names = [[classes allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ca = [classes[a] unsignedIntegerValue], cb = [classes[b] unsignedIntegerValue];
        if (ca != cb) return ca > cb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    for (NSString *name in names) [report appendFormat:@"%@ × %@\n", name, classes[name]];
    [report appendString:@"\n文字相关接口（仅名称）：\n"];
    NSUInteger detailed = 0;
    for (NSString *name in names) {
        NSString *lower = name.lowercaseString;
        if (![lower containsString:@"text"] && ![lower containsString:@"label"] &&
            ![lower containsString:@"node"] && ![lower containsString:@"hosting"]) continue;
        if (detailed++ >= 20) break;
        NSMutableOrderedSet *selectors = [NSMutableOrderedSet orderedSet];
        Class cls = [samples[name] class];
        for (NSUInteger level = 0; cls && level < 3; level++, cls = class_getSuperclass(cls)) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            for (unsigned int i = 0; i < count; i++) {
                NSString *selector = NSStringFromSelector(method_getName(methods[i]));
                NSString *key = selector.lowercaseString;
                if ([key containsString:@"text"] || [key containsString:@"node"])
                    [selectors addObject:selector];
            }
            free(methods);
        }
        NSArray *limited = selectors.array;
        if (limited.count > 24) limited = [limited subarrayWithRange:NSMakeRange(0, 24)];
        [report appendFormat:@"%@: %@\n", name, [limited componentsJoinedByString:@", "]];
    }
    return report;
}

@interface XCSZHOverlayWindow : UIWindow
@end
@implementation XCSZHOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Outside the explicit controls, let X receive touches in its own window.
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end
@interface XCSZHOverlayController : UIViewController
@property(nonatomic, weak) UIWindow *sourceWindow;
@property(nonatomic, strong) UIButton *toggleButton;
@property(nonatomic, strong) UIButton *clipboardButton;
@property(nonatomic, strong) UIButton *refreshButton;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UITextView *reportView;
- (void)toggle;
- (void)refresh;
@end
@implementation XCSZHOverlayController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.toggleButton setTitle:@"中文诊断 v0.4" forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = UIColor.systemBlueColor;
    [self.toggleButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.toggleButton.layer.cornerRadius = 10;
    self.toggleButton.accessibilityIdentifier = @"xcszh.diagnostic.open";
    [self.toggleButton addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggleButton];
    self.panel = [UIView new];
    self.panel.backgroundColor = UIColor.systemBackgroundColor;
    self.panel.layer.cornerRadius = 12;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = UIColor.systemBlueColor.CGColor;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];
    self.clipboardButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clipboardButton setTitle:@"复制诊断" forState:UIControlStateNormal];
    [self.clipboardButton addTarget:self action:@selector(putReportOnClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.clipboardButton];
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.refreshButton setTitle:@"刷新" forState:UIControlStateNormal];
    [self.refreshButton addTarget:self action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.refreshButton];
    self.reportView = [UITextView new];
    self.reportView.editable = NO;
    self.reportView.selectable = YES;
    self.reportView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.reportView.accessibilityIdentifier = @"xcszh.diagnostic.report";
    [self.panel addSubview:self.reportView];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top + 54;
    self.toggleButton.frame = CGRectMake(MAX(8, width - 142), top, 134, 38);
    CGFloat panelTop = top + 44;
    self.panel.frame = CGRectMake(8, panelTop, MAX(100, width - 16),
        MAX(100, self.view.bounds.size.height - panelTop - self.view.safeAreaInsets.bottom - 12));
    self.clipboardButton.frame = CGRectMake(8, 4, 110, 40);
    self.refreshButton.frame = CGRectMake(120, 4, 70, 40);
    self.reportView.frame = CGRectMake(6, 46, self.panel.bounds.size.width - 12,
        MAX(40, self.panel.bounds.size.height - 52));
}
- (void)toggle {
    self.panel.hidden = !self.panel.hidden;
    [self.toggleButton setTitle:self.panel.hidden ? @"中文诊断 v0.4" : @"关闭诊断"
        forState:UIControlStateNormal];
    if (!self.panel.hidden) [self refresh];
}
- (void)refresh {
    UIWindow *source = self.sourceWindow;
    if (!source || source.hidden) source = ApplicationWindows().firstObject;
    if (!source) { self.reportView.text = @"暂未找到应用窗口，请返回 X 页面后刷新。"; return; }
    self.sourceWindow = source;
    LocalizeWindow(source);
    self.reportView.text = DiagnosticReport(source);
}
- (void)putReportOnClipboard {
    UIPasteboard.generalPasteboard.string = self.reportView.text ?: @"";
    [self.clipboardButton setTitle:@"已复制" forState:UIControlStateNormal];
}
@end
static XCSZHOverlayWindow *DiagnosticWindow;
static void EnsureDiagnosticWindow(UIWindow *source) {
    if (!source) return;
    if (DiagnosticWindow && DiagnosticWindow.windowScene != source.windowScene) {
        DiagnosticWindow.hidden = YES;
        DiagnosticWindow = nil;
    }
    if (!DiagnosticWindow) {
        DiagnosticWindow = source.windowScene ?
            [[XCSZHOverlayWindow alloc] initWithWindowScene:source.windowScene] :
            [[XCSZHOverlayWindow alloc] initWithFrame:source.bounds];
        DiagnosticWindow.frame = source.bounds;
        objc_setAssociatedObject(DiagnosticWindow, &BannerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DiagnosticWindow.windowLevel = UIWindowLevelAlert + 100;
        DiagnosticWindow.backgroundColor = UIColor.clearColor;
        DiagnosticWindow.rootViewController = [XCSZHOverlayController new];
    }
    ((XCSZHOverlayController *)DiagnosticWindow.rootViewController).sourceWindow = source;
    DiagnosticWindow.hidden = NO;
    // Do not makeKeyWindow: X retains keyboard and responder ownership.
}

@interface XCSZHDriver : NSObject
+ (void)tick;
@end
@implementation XCSZHDriver
+ (void)tick {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSArray<UIWindow *> *windows = ApplicationWindows();
    UIWindow *source = windows.firstObject;
    for (UIWindow *window in windows) {
        LocalizeWindow(window);
        if (window.isKeyWindow) source = window;
    }
    EnsureDiagnosticWindow(source);
    for (UIWindow *window in windows) {
        if (!window.isKeyWindow) continue;
        if (ShowedLoaded) continue;
        ShowedLoaded = YES;
        UILabel *banner = [[UILabel alloc] initWithFrame:CGRectMake(16, window.safeAreaInsets.top + 8,
            MAX(120, window.bounds.size.width - 32), 40)];
        objc_setAssociatedObject(banner, &BannerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        banner.text = @"中文插件 v0.4 已加载 · 右上角可诊断";
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
