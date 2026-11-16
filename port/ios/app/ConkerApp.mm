// iOS shell for the Conker's Bad Fur Day port.
//
// For now it runs two checks on the device and shows the results:
//  - can librecomp's rdram reservation be made (memory_probe.cpp)?
//  - does plume's Metal backend present through the UIKit glue (plume_clear.cpp)?
// The screen is cleared green if both pass, amber if only rendering works.
// Every step is written to Documents/conker-log.txt (Files app > Conker), so if
// the app crashes, the log's last line shows where.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <sys/utsname.h>

#include <memory>
#include <string>

#include "memory_probe.h"
#include "plume_clear.h"
#include "conker_log.h"

@interface ConkerMetalView : UIView
@end

@implementation ConkerMetalView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

@interface ConkerViewController : UIViewController
@end

@implementation ConkerViewController {
    ConkerMetalView *_metalView;
    UILabel *_statusLabel;
    CADisplayLink *_displayLink;
    std::unique_ptr<conker::PlumeClear> _renderer;
    bool _memoryOk;
    bool _started;
}

- (void)loadView {
    _metalView = [[ConkerMetalView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    _metalView.contentScaleFactor = UIScreen.mainScreen.nativeScale;
    self.view = _metalView;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.numberOfLines = 0;
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    [_metalView addSubview:_statusLabel];
    UILayoutGuide *safe = _metalView.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_statusLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_started) {
        return;
    }

    _started = true;
    _statusLabel.text = @"Conker's Bad Fur Day (iOS shell)\nrunning checks...";
    conker::log("view appeared, %.0fx%.0f points, scale %.1f",
        _metalView.bounds.size.width, _metalView.bounds.size.height, _metalView.contentScaleFactor);

    // Let the status text reach the screen before the checks run.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runChecks];
    });
}

- (void)runChecks {
    conker::log("memory probe: start");
    std::string memoryReport = conker::probe_rdram_reservation(_memoryOk);
    conker::log("%s", memoryReport.c_str());
    _statusLabel.text = [NSString stringWithFormat:@"Conker's Bad Fur Day (iOS shell)\n%s\nplume: starting...",
        memoryReport.c_str()];

    _renderer = conker::PlumeClear::create((__bridge void *)_metalView, (__bridge void *)_metalView.layer);
    const char *renderReport = _renderer ? "plume: Metal swap chain OK" : "plume: Metal setup failed";
    conker::log("%s", renderReport);

    _statusLabel.text = [NSString stringWithFormat:@"Conker's Bad Fur Day (iOS shell)\n%s\n%s",
        memoryReport.c_str(), renderReport];

    if (_renderer) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_renderer) {
        _renderer->resize();
    }
}

- (void)renderFrame:(CADisplayLink *)link {
    if (_memoryOk) {
        _renderer->render(0.05f, 0.35f, 0.10f);
    } else {
        _renderer->render(0.45f, 0.30f, 0.0f);
    }
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
@end

@interface ConkerSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation ConkerSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[ConkerViewController alloc] init];
    [self.window makeKeyAndVisible];
}
@end

@interface ConkerAppDelegate : UIResponder <UIApplicationDelegate>
@end

static void logUncaughtException(NSException *exception) {
    conker::log("uncaught exception: %s: %s", exception.name.UTF8String, exception.reason.UTF8String);
}

@implementation ConkerAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSSetUncaughtExceptionHandler(&logUncaughtException);
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    conker::log("Conker %s launched on %s, %s %s", version.UTF8String, systemInfo.machine,
        UIDevice.currentDevice.systemName.UTF8String, UIDevice.currentDevice.systemVersion.UTF8String);
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = [ConkerSceneDelegate class];
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ConkerAppDelegate class]));
    }
}
