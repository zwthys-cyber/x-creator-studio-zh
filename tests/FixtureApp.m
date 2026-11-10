#define XCSZH_FIXTURE 1
#import "../src/XCreatorStudioZH.m"

@interface FixtureNode : NSObject
@property(nonatomic, copy) NSAttributedString *attributedText;
@end
@implementation FixtureNode
@end
@interface FixtureView : UIView
@property(nonatomic, strong) FixtureNode *asyncdisplaykit_node;
@end
@implementation FixtureView
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
    NSString *setup = @"document.body.innerHTML='<h1>Creator Studio</h1><span>Creator Academy</span>"
        "<p id=target>Tips and guides for creators</p><input value=Support><textarea>Support</textarea>';";
    [self.web evaluateJavaScript:setup completionHandler:^(id value, NSError *error) {
        (void)value;
        [self check:!error name:@"web fixture setup"];
        [self.web evaluateJavaScript:JavaScript() completionHandler:^(id count, NSError *translationError) {
            [self check:!translationError && [count integerValue] >= 3 name:@"web text nodes translated"];
            [self.web evaluateJavaScript:@"document.getElementById('target').textContent === '创作者实用技巧与指南' && document.querySelector('textarea').value === 'Support'"
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
