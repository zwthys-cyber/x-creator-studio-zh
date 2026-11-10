#define XCSZH_FIXTURE 1
#import "../src/XCreatorStudioZH.m"

@interface FixtureNode : NSObject
@property(nonatomic, copy) NSAttributedString *attributedText;
@property(nonatomic, copy) NSArray *subnodes;
@end
@implementation FixtureNode
@end
@interface FixtureView : UIView
@property(nonatomic, strong) FixtureNode *asyncdisplaykit_node;
@end
@implementation FixtureView
@end
@interface FixtureLayer : CALayer
@property(nonatomic, strong) FixtureNode *asyncdisplaykit_node;
@end
@implementation FixtureLayer
@end
@interface FixtureJetfuelInkBase : UIView
@property(nonatomic, copy) NSString *fixtureEnglish;
@end
@implementation FixtureJetfuelInkBase
- (void)drawRect:(CGRect)rect {
    [self.fixtureEnglish drawInRect:rect withAttributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:18],
        NSForegroundColorAttributeName: UIColor.redColor}];
}
@end
@interface FixtureApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) NSMutableArray<NSString *> *failures;
@end
@implementation FixtureApp
- (void)check:(BOOL)condition name:(NSString *)name {
    if (!condition) [self.failures addObject:name];
}
- (UILabel *)label:(NSString *)text y:(CGFloat)y {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, y, 350, 40)];
    label.text = text;
    [self.window.rootViewController.view addSubview:label];
    return label;
}
- (void)finish {
    NSDictionary *result = @{@"passed": @(self.failures.count == 0), @"failures": self.failures,
        @"nativeChanges": @(NativeChanges), @"webChanges": @(WebChanges)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.json"];
    [data writeToFile:path atomically:YES];
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.failures = [NSMutableArray array];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    UILabel *generic = [self label:@"Support" y:60];
    LocalizeWindow(self.window);
    [self check:[generic.text isEqualToString:@"Support"] name:@"unrelated native page unchanged"];
    UILabel *heading = [self label:@"Creator Studio" y:100];
    [self label:@"Original Content Rewards" y:140];
    UILabel *styled = [self label:@" Analytics \n" y:180];
    styled.attributedText = [[NSAttributedString alloc] initWithString:@" Analytics \n"
        attributes:@{NSForegroundColorAttributeName: UIColor.redColor}];
    FixtureView *nodeView = [[FixtureView alloc] initWithFrame:CGRectMake(10, 220, 300, 40)];
    nodeView.asyncdisplaykit_node = [FixtureNode new];
    nodeView.asyncdisplaykit_node.attributedText = [[NSAttributedString alloc] initWithString:@"Creator Academy"];
    [self.window.rootViewController.view addSubview:nodeView];
    CATextLayer *layer = [CATextLayer layer];
    layer.string = @"Ineligible";
    [self.window.layer addSublayer:layer];
    LocalizeWindow(self.window);
    [self check:[heading.text isEqualToString:@"创作者工作室"] name:@"native title"];
    [self check:[styled.text isEqualToString:@"数据分析"] name:@"whitespace normalized"];
    [self check:[[styled.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]
        isEqual:UIColor.redColor] name:@"text style preserved"];
    [self check:[nodeView.asyncdisplaykit_node.attributedText.string isEqualToString:@"创作者学院"]
        name:@"non UILabel node translated"];
    [self check:[layer.string isEqual:@"暂不符合资格"] name:@"CATextLayer translated"];
    NSUInteger before = NativeChanges;
    LocalizeWindow(self.window);
    [self check:NativeChanges == before name:@"repeat scan idempotent"];


    // Reproduce a page whose title and rewards exist only in a layer-backed node tree.
    for (UIView *view in [self.window.rootViewController.view.subviews copy]) [view removeFromSuperview];
    [layer removeFromSuperlayer];
    FixtureLayer *backing = [FixtureLayer layer];
    FixtureNode *root = [FixtureNode new];
    root.attributedText = [[NSAttributedString alloc] initWithString:@"Creator Studio"];
    FixtureNode *child = [FixtureNode new];
    child.attributedText = [[NSAttributedString alloc] initWithString:@"Original Content Rewards"];
    root.subnodes = @[child];
    // A cycle must not hang traversal.
    child.subnodes = @[root];
    backing.asyncdisplaykit_node = root;
    [self.window.layer addSublayer:backing];
    LocalizeWindow(self.window);
    [self check:[root.attributedText.string isEqualToString:@"创作者工作室"] name:@"layer-only title"];
    [self check:[child.attributedText.string isEqualToString:@"原创内容奖励"] name:@"rasterized child node"];
    [self label:@"PRIVATE_FIXTURE_POST_DO_NOT_REPORT" y:80];
    NSString *report = DiagnosticReport(self.window);
    [self check:![report containsString:@"PRIVATE_FIXTURE_POST_DO_NOT_REPORT"] name:@"diagnostic excludes post body"];
    EnsureDiagnosticWindow(self.window);
    XCSZHOverlayController *overlay = (XCSZHOverlayController *)DiagnosticWindow.rootViewController;
    [overlay loadViewIfNeeded];
    [overlay.view setNeedsLayout];
    [overlay.view layoutIfNeeded];
    CGPoint buttonPoint = [overlay.toggleButton convertPoint:
        CGPointMake(overlay.toggleButton.bounds.size.width / 2, overlay.toggleButton.bounds.size.height / 2)
        toView:DiagnosticWindow];
    UIView *hit = [DiagnosticWindow hitTest:buttonPoint withEvent:nil];
    [self check:hit == overlay.toggleButton || [hit isDescendantOfView:overlay.toggleButton]
        name:@"diagnostic button receives touches in separate window"];
    [overlay.toggleButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self check:!overlay.panel.hidden && [overlay.reportView.text containsString:@"版本 0.4"]
        name:@"tapping diagnostic button opens report without presentation"];
    [overlay.toggleButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self check:overlay.panel.hidden name:@"diagnostic button closes report"];
    [self check:[DiagnosticWindow hitTest:CGPointMake(2, self.window.bounds.size.height - 2) withEvent:nil] == nil
        name:@"outside diagnostic controls passes through"];
    [self check:self.window.isKeyWindow name:@"overlay preserves app key window"];
    DiagnosticWindow.hidden = YES;


    // Recreate the user's actual diagnostic: accessible menu text, no text setter,
    // no Texture nodes and no web views; custom glyphs live inside TextInkView.
    [backing removeFromSuperlayer];
    for (UIView *view in [self.window.rootViewController.view.subviews copy]) [view removeFromSuperview];
    self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
    Class displayClass = objc_allocateClassPair(UIView.class, "JetfuelSDK.TextDisplayView", 0);
    objc_registerClassPair(displayClass);
    Class inkClass = objc_allocateClassPair(FixtureJetfuelInkBase.class, "JetfuelSDK.FixtureTextInkView", 0);
    objc_registerClassPair(inkClass);
    NSArray *menu = @[@"Creator Studio", @"Programs", @"Original Content Rewards", @"Earn from your posts",
        @"Ineligible", @"Subscriptions", @"Ineligible", @"Tools", @"Analytics", @"Inspiration",
        @"Top posts by engagement", @"Creator Academy", @"Tips and guides for creators", @"New",
        @"Support", @"Contact support", @"Learn more"];
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    NSMutableArray<UIView *> *inkViews = [NSMutableArray array];
    NSUInteger countBefore = JetfuelChanges;
    for (NSUInteger index = 0; index < menu.count; index++) {
        UIView *host = [[displayClass alloc] initWithFrame:CGRectMake(20, 72 + index * 32, 310, 28)];
        host.accessibilityLabel = menu[index];
        FixtureJetfuelInkBase *ink = [[inkClass alloc] initWithFrame:host.bounds];
        ink.fixtureEnglish = menu[index];
        ink.alpha = 0.8;
        ink.userInteractionEnabled = NO;
        [host addSubview:ink];
        [self.window.rootViewController.view addSubview:host];
        [hosts addObject:host];
        [inkViews addObject:ink];
    }
    CGRect originalFrame = hosts.firstObject.frame;
    UITapGestureRecognizer *rowTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:NULL];
    [hosts.firstObject addGestureRecognizer:rowTap];
    [self check:![hosts.firstObject respondsToSelector:@selector(setText:)] &&
        ![hosts.firstObject respondsToSelector:@selector(setAttributedText:)] name:@"Jetfuel fixture has no UIKit text setters"];
    LocalizeWindow(self.window);
    [self check:JetfuelChanges == countBefore + menu.count name:@"all 17 self-drawn menu labels translated"];
    for (NSUInteger index = 0; index < hosts.count; index++) {
        XCSZHJetfuelState *state = objc_getAssociatedObject(hosts[index], &JetfuelStateKey);
        [self check:[state.label.text isEqualToString:Translations()[menu[index]]] name:@"Jetfuel visible Chinese label"];
        [self check:inkViews[index].alpha == 0 name:@"original English ink suppressed"];
        [self check:!state.label.userInteractionEnabled name:@"translated text does not capture menu touches"];
    }
    [self check:CGRectEqualToRect(originalFrame, hosts.firstObject.frame) &&
        [hosts.firstObject.gestureRecognizers containsObject:rowTap] name:@"host geometry and tap recognizer retained"];
    NSUInteger jetfuelBefore = JetfuelChanges;
    LocalizeWindow(self.window);
    [self check:JetfuelChanges == jetfuelBefore name:@"Jetfuel repeat scan idempotent"];
    [self.window layoutIfNeeded];
    for (UIView *host in hosts) {
        XCSZHJetfuelState *state = objc_getAssociatedObject(host, &JetfuelStateKey);
        [state.label.layer displayIfNeeded];
    }
    [CATransaction flush];
    UIImage *light = [[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [self.window.layer renderInContext:context.CGContext];
        }];
    [UIImagePNGRepresentation(light) writeToFile:[NSHomeDirectory()
        stringByAppendingPathComponent:@"Documents/JETFUEL_LIGHT.png"] atomically:YES];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    LocalizeWindow(self.window);
    [self.window layoutIfNeeded];
    for (UIView *host in hosts) {
        XCSZHJetfuelState *state = objc_getAssociatedObject(host, &JetfuelStateKey);
        [state.label setNeedsDisplay];
        [state.label.layer displayIfNeeded];
    }
    [CATransaction flush];
    UIImage *dark = [[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [self.window.layer renderInContext:context.CGContext];
        }];
    [UIImagePNGRepresentation(dark) writeToFile:[NSHomeDirectory()
        stringByAppendingPathComponent:@"Documents/JETFUEL_DARK.png"] atomically:YES];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    hosts.firstObject.accessibilityLabel = @"UNRELATED_REUSED_TEXT";
    LocalizeWindow(self.window);
    [self check:!objc_getAssociatedObject(hosts.firstObject, &JetfuelStateKey) &&
        fabs(inkViews.firstObject.alpha - 0.8) < 0.001 name:@"reused non-menu view restored"];
    [self check:[hosts.firstObject.accessibilityLabel isEqualToString:@"UNRELATED_REUSED_TEXT"]
        name:@"reused accessibility text preserved"];
    hosts.firstObject.accessibilityLabel = @"Inspiration";
    LocalizeWindow(self.window);
    XCSZHJetfuelState *reused = objc_getAssociatedObject(hosts.firstObject, &JetfuelStateKey);
    [self check:[reused.label.text isEqualToString:@"创作灵感"] name:@"reused menu view updates Chinese"];
    self.window.rootViewController = [UIViewController new];
    LocalizeWindow(self.window);
    for (NSUInteger index = 0; index < hosts.count; index++) {
        [self check:!objc_getAssociatedObject(hosts[index], &JetfuelStateKey) &&
            fabs(inkViews[index].alpha - 0.8) < 0.001 name:@"page exit restores custom ink and removes translation"];
    }

    self.web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 300, 350, 300)];
    [self.window.rootViewController.view addSubview:self.web];
    [self.web loadHTMLString:@"<html><body>Fixture</body></html>" baseURL:nil];
    [self waitForWeb:0];
    return YES;
}
- (void)waitForWeb:(NSUInteger)attempt {
    if (attempt > 40) {
        [self check:NO name:@"web fixture load timeout"];
        [self finish];
        return;
    }
    if (self.web.loading || !self.web.URL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
            [self waitForWeb:attempt + 1];
        });
        return;
    }
    NSString *setup = @"document.body.innerHTML='<h1>Original Content Rewards</h1><span>Creator Academy</span>"
        "<p id=target> Tips and   guides for creators </p><input value=Support><textarea>Support</textarea>';";
    [self.web evaluateJavaScript:setup completionHandler:^(id value, NSError *error) {
        (void)value;
        [self check:!error name:@"web fixture setup"];
        [self.web evaluateJavaScript:JavaScript() completionHandler:^(id count, NSError *translationError) {
            [self check:!translationError && [count integerValue] >= 3 name:@"web text nodes translated"];
            [self.web evaluateJavaScript:@"document.getElementById('target').textContent.trim() === '创作者实用技巧与指南' && document.querySelector('textarea').value === 'Support'"
                completionHandler:^(id ok, NSError *readError) {
                    [self check:!readError && [ok boolValue] name:@"web output and editable exclusion"];
                    [self.web evaluateJavaScript:@"document.body.innerHTML='<p>Support</p>'"
                        completionHandler:^(id reset, NSError *resetError) {
                            (void)reset; (void)resetError;
                            [self.web evaluateJavaScript:JavaScript() completionHandler:^(id changes, NSError *lastError) {
                                [self check:!lastError && [changes integerValue] == 0 name:@"unrelated web page unchanged"];
                                [self finish];
                            }];
                        }];
                }];
        }];
    }];
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FixtureApp.class)); }
}
