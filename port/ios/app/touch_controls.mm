// On-screen N64 controller, tray and gyro (see touch_controls.h). Carried over from
// sote-ios's touch_controls.mm, without SotE's own extras (photos, cheats, level select,
// its menus), and fed into CBFD-Recompiled's input instead of SotE-Recomp's.

#import "touch_controls.h"

#import <CoreMotion/CoreMotion.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <unordered_map>
#include <vector>

#include "conker_ios_game.h"
#include "recompinput/input_state.h"

namespace {
    // N64 controller button bits, as CBFD-Recompiled's frontend uses them.
    constexpr uint16_t N64A = 0x8000;
    constexpr uint16_t N64B = 0x4000;
    constexpr uint16_t N64Z = 0x2000;
    constexpr uint16_t N64Start = 0x1000;
    constexpr uint16_t N64DUp = 0x0800;
    constexpr uint16_t N64DDown = 0x0400;
    constexpr uint16_t N64DLeft = 0x0200;
    constexpr uint16_t N64DRight = 0x0100;
    constexpr uint16_t N64L = 0x0020;
    constexpr uint16_t N64R = 0x0010;
    constexpr uint16_t N64CUp = 0x0008;
    constexpr uint16_t N64CDown = 0x0004;
    constexpr uint16_t N64CLeft = 0x0002;
    constexpr uint16_t N64CRight = 0x0001;

    // Values shared with the other ports' touch controls.
    constexpr CGFloat IdleAlpha = 0.65;
    constexpr CGFloat TouchSlop = 6.0;
    constexpr CGFloat StickRadius = 60.0;
    constexpr CGFloat StickKnob = 24.0;
    constexpr CGFloat StickDeadZone = 0.15;
    constexpr CGFloat StickAreaFraction = 0.42;
    // The right stick: touches that start between the left stick's area and the buttons.
    constexpr CGFloat RightStickRadius = 50.0;
    constexpr CGFloat RightStickAreaEnd = 0.74;
    // Mouse pixels a second at full tilt, times SENS (150 degrees a second at 1x).
    constexpr double RightStickPixelsPerSecond = 1500.0;
    constexpr double MenuHold = 0.45;
    constexpr double StartPulse = 0.15;
    constexpr double TapTime = 0.35;
    constexpr CGFloat HoldMoveLimit = 12.0;
    constexpr CGFloat TrayRadius = 20.0;
    constexpr CGFloat TrayStep = 80.0;
    constexpr double ToastTime = 1.6;

    // Look: mouse pixels per point dragged, and per degree the phone turns, both times SENS.
    // CBFD-Recompiled turns 0.1 degrees per mouse pixel at 100% Mouse: Sensitivity (the iOS
    // build's default).
    constexpr CGFloat LookPixelsPerPoint = 3.0;
    constexpr double GyroPixelsPerDegree = 7.0;
    constexpr double GyroDeadZone = 1.5;
    constexpr double LookSens[] = { 1.0, 1.5, 2.0, 3.0, 4.0 };
    constexpr int LookSensCount = 5;

    enum class Kind { N64, Menu, Tray };
    enum class TrayItem { None, Gyro, Sens, Opacity, Dpad, Fps };
    enum class GyroMode { Off = 0, Touch = 1, Always = 2 };
    enum class Role { None, Stick, RightStick, Look, Control };

    struct Control {
        Kind kind;
        uint16_t bit;
        TrayItem tray;
        NSString *label;
        UIColor *accent;
        CGFloat radius;
        bool pill;
        CGPoint center;
        bool visible;
        CALayer *group;
        CAShapeLayer *shape;
        CATextLayer *text;
        CAShapeLayer *ring;
    };

    struct TouchState {
        Role role = Role::None;
        int control = -1;
        CGPoint start = CGPointZero;
        CGPoint last = CGPointZero;
        CFTimeInterval down = 0;
        bool moved = false;
        bool fired = false;
    };

    CGFloat distance(CGPoint a, CGPoint b) {
        return std::hypot(a.x - b.x, a.y - b.y);
    }

    UIColor *Gold() {
        return [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95];
    }

    UIColor *RingBlue() {
        return [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95];
    }

    // Read by the gyro's queue.
    std::atomic<int> gyroMode{0};
    std::atomic<int> gyroSensIndex{1};
    std::atomic<bool> gyroThumbDown{false};
    std::atomic<bool> gyroSuppressed{false};
    std::atomic<int> gyroLandscapeSign{1};
    // The controls are showing (the game runs, no menu is up).
    std::atomic<bool> controlsShowing{false};

    void addLook(double pixelsX, double pixelsY) {
        if (controlsShowing.load()) {
            recompinput::add_mouse_deltas(float(pixelsX), float(pixelsY));
        }
    }
}

@implementation ConkerTouchControlsView {
    std::vector<Control> _controls;
    std::unordered_map<void *, TouchState> _touches;
    CADisplayLink *_displayLink;
    CMMotionManager *_motion;
    NSOperationQueue *_motionQueue;

    // Stick.
    UITouch *_stickTouch;
    CGPoint _stickHome;
    CGPoint _stickOrigin;
    CGPoint _stickKnob;
    CAShapeLayer *_stickBase;
    CAShapeLayer *_stickKnobLayer;

    // Right stick (the camera).
    UITouch *_rightTouch;
    CGPoint _rightHome;
    CGPoint _rightOrigin;
    CGPoint _rightKnob;
    CGFloat _rightX;
    CGFloat _rightY;
    CAShapeLayer *_rightBase;
    CAShapeLayer *_rightKnobLayer;
    CFTimeInterval _lastTick;

    // Frame rate readout.
    UILabel *_fpsLabel;
    bool _showFps;
    CFTimeInterval _fpsTime;
    uint64_t _fpsPresented;
    uint64_t _fpsGame;

    // Frame rate asked for (60 or 120, the tray's FPS held), and the log's frame time.
    int _maxFps;
    bool _maxFpsApplied;
    CFTimeInterval _logTime;
    uint64_t _logPresented;
    uint64_t _logGame;

    // Tray, opacity row, toast.
    bool _trayOpen;
    UIView *_trayBacking;
    UILabel *_versionLabel;
    UIView *_opacityRow;
    UISlider *_opacitySlider;
    UILabel *_toast;
    CFTimeInterval _toastUntil;
    CGFloat _toastTop;

    // State.
    CFTimeInterval _startUntil;
    bool _stickShown;
    bool _rightShown;
    bool _showing;
    uint16_t _pressed;
    CGFloat _opacity;
    bool _showDpad;
}

// "build 80 · Nov 9", from the keys the cloud build writes into Info.plist; "build dev" without them.
static NSString *appVersionText(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    id number = info[@"SWBuildNumber"], date = info[@"SWBuildDate"];
    static NSArray<NSString *> *const months = @[ @"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun",
                                                  @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec" ];
    if ([number isKindOfClass:NSString.class] && [date isKindOfClass:NSString.class] && [number length]) {
        NSArray<NSString *> *ymd = [date componentsSeparatedByString:@"-"];
        NSInteger month = ymd.count == 3 ? ymd[1].integerValue : 0, day = ymd.count == 3 ? ymd[2].integerValue : 0;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31)
            return [NSString stringWithFormat:@"build %@ \u00B7 %@ %ld", number, months[month - 1], (long)day];
    }
    return @"build dev";
}

#pragma mark - Setup

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self loadSettings];

    UIColor *white = [UIColor colorWithWhite:1.0 alpha:0.4];
    UIColor *green = [UIColor colorWithRed:0.35 green:0.9 blue:0.45 alpha:0.6];
    UIColor *blue = [UIColor colorWithRed:0.45 green:0.65 blue:1.0 alpha:0.6];
    UIColor *yellow = [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.6];
    UIColor *red = [UIColor colorWithRed:1.0 green:0.45 blue:0.4 alpha:0.6];
    _controls = {
        { Kind::N64, N64A, TrayItem::None, @"A", green, 40, false },
        { Kind::N64, N64B, TrayItem::None, @"B", blue, 32, false },
        { Kind::N64, N64CUp, TrayItem::None, @"▲", yellow, 19, false },
        { Kind::N64, N64CDown, TrayItem::None, @"▼", yellow, 19, false },
        { Kind::N64, N64CLeft, TrayItem::None, @"◀", yellow, 19, false },
        { Kind::N64, N64CRight, TrayItem::None, @"▶", yellow, 19, false },
        { Kind::N64, N64Z, TrayItem::None, @"Z", white, 30, false },
        { Kind::N64, N64L, TrayItem::None, @"L", white, 22, true },
        { Kind::N64, N64R, TrayItem::None, @"R", white, 22, true },
        { Kind::N64, N64DUp, TrayItem::None, @"↑", white, 17, false },
        { Kind::N64, N64DDown, TrayItem::None, @"↓", white, 17, false },
        { Kind::N64, N64DLeft, TrayItem::None, @"←", white, 17, false },
        { Kind::N64, N64DRight, TrayItem::None, @"→", white, 17, false },
        { Kind::Menu, 0, TrayItem::None, @"START", red, 22, true },
        { Kind::Tray, 0, TrayItem::Gyro, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Sens, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Opacity, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Dpad, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Fps, @"", white, TrayRadius, true },
    };

    _trayBacking = [[UIView alloc] init];
    _trayBacking.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _trayBacking.layer.cornerRadius = 26;
    _trayBacking.layer.borderWidth = 1.5;
    _trayBacking.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _trayBacking.userInteractionEnabled = NO;
    _trayBacking.hidden = YES;
    [self addSubview:_trayBacking];

    // The build stamp, shown with the tray (not a button).
    _versionLabel = [[UILabel alloc] init];
    _versionLabel.text = appVersionText();
    _versionLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _versionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _versionLabel.textAlignment = NSTextAlignmentCenter;
    _versionLabel.userInteractionEnabled = NO;
    _versionLabel.hidden = YES;
    [self addSubview:_versionLabel];

    _stickBase = [CAShapeLayer layer];
    _stickBase.fillColor = [UIColor colorWithWhite:0.0 alpha:0.22].CGColor;
    _stickBase.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _stickBase.lineWidth = 1.5;
    [self.layer addSublayer:_stickBase];
    _stickKnobLayer = [CAShapeLayer layer];
    _stickKnobLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _stickKnobLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    _stickKnobLayer.lineWidth = 1.5;
    [self.layer addSublayer:_stickKnobLayer];
    _rightBase = [CAShapeLayer layer];
    _rightBase.fillColor = [UIColor colorWithWhite:0.0 alpha:0.22].CGColor;
    _rightBase.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _rightBase.lineWidth = 1.5;
    [self.layer addSublayer:_rightBase];
    _rightKnobLayer = [CAShapeLayer layer];
    _rightKnobLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _rightKnobLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    _rightKnobLayer.lineWidth = 1.5;
    [self.layer addSublayer:_rightKnobLayer];

    for (Control &control : _controls) {
        [self buildControl:control];
    }

    [self buildOpacityRow];
    _toast = [[UILabel alloc] init];
    _toast.font = [UIFont boldSystemFontOfSize:14];
    _toast.textColor = UIColor.whiteColor;
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    _toast.layer.cornerRadius = 12;
    _toast.layer.masksToBounds = YES;
    _toast.hidden = YES;
    [self addSubview:_toast];

    // FPS: frames presented to the screen a second; Game: frames the game made (up to 30).
    _fpsLabel = [[UILabel alloc] init];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _fpsLabel.textColor = UIColor.whiteColor;
    _fpsLabel.textAlignment = NSTextAlignmentCenter;
    _fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    _fpsLabel.layer.cornerRadius = 8;
    _fpsLabel.layer.masksToBounds = YES;
    _fpsLabel.userInteractionEnabled = NO;
    _fpsLabel.hidden = YES;
    [self addSubview:_fpsLabel];

    self.hidden = YES;
    [self startGyro];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_displayLink invalidate];
    _displayLink = nil;
    if (self.window != nil) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [self applyScreenRate];
    }
}

// The rate asked of the screen (Info.plist's CADisableMinimumFrameDurationOnPhone lets an iPhone
// go above 60). RT64 presents from its own thread; this display link tells iOS what to expect.
- (void)applyScreenRate {
    const float rate = float(_maxFps);
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(_maxFps == 120 ? 80.0f : 60.0f, rate, rate);
    std::fprintf(stderr, "[ios] asked the screen for %d Hz (it can do %ld; Low Power Mode %s)\n", _maxFps,
        (long)UIScreen.mainScreen.maximumFramesPerSecond,
        NSProcessInfo.processInfo.lowPowerModeEnabled ? "on: 60 at most" : "off");
}

// The screen and RT64 both follow the choice.
- (void)applyMaxFps {
    [self applyScreenRate];
    conker::ios::set_max_fps(_maxFps);
    _maxFpsApplied = true;
    _logTime = 0;
}

- (void)loadSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{
        @"iosTouchGyroMode": @0,
        @"iosTouchGyroSens": @1,
        @"iosTouchOpacity": @1.0,
        @"iosTouchShowDpad": @NO,
        @"iosTouchShowFps": @NO,
        @"iosTouchMaxFps": @60,
    }];
    gyroMode.store(int([defaults integerForKey:@"iosTouchGyroMode"]) % 3);
    gyroSensIndex.store(int([defaults integerForKey:@"iosTouchGyroSens"]) % LookSensCount);
    _opacity = std::clamp(CGFloat([defaults doubleForKey:@"iosTouchOpacity"]), CGFloat(0.2), CGFloat(1.0));
    _showDpad = [defaults boolForKey:@"iosTouchShowDpad"];
    _showFps = [defaults boolForKey:@"iosTouchShowFps"];
    _maxFps = ([defaults integerForKey:@"iosTouchMaxFps"] == 120) ? 120 : 60;
}

- (void)saveSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:gyroMode.load() forKey:@"iosTouchGyroMode"];
    [defaults setInteger:gyroSensIndex.load() forKey:@"iosTouchGyroSens"];
    [defaults setDouble:_opacity forKey:@"iosTouchOpacity"];
    [defaults setBool:_showDpad forKey:@"iosTouchShowDpad"];
    [defaults setBool:_showFps forKey:@"iosTouchShowFps"];
    [defaults setInteger:_maxFps forKey:@"iosTouchMaxFps"];
}

- (CATextLayer *)textLayer:(CGFloat)size {
    CATextLayer *text = [CATextLayer layer];
    text.fontSize = size;
    text.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:size].fontName;
    text.foregroundColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    text.alignmentMode = kCAAlignmentCenter;
    text.contentsScale = UIScreen.mainScreen.scale;
    return text;
}

- (void)buildControl:(Control &)control {
    control.group = [CALayer layer];
    control.shape = [CAShapeLayer layer];
    control.shape.lineWidth = 1.5;
    [control.group addSublayer:control.shape];
    const CGFloat size = (control.radius >= 30) ? 16 : (control.radius >= 20 ? 13 : 10);
    control.text = [self textLayer:(control.kind == Kind::Tray ? 10 : size)];
    control.text.string = control.label;
    [control.group addSublayer:control.text];
    control.ring = [CAShapeLayer layer];
    control.ring.fillColor = UIColor.clearColor.CGColor;
    control.ring.strokeColor = RingBlue().CGColor;
    control.ring.lineWidth = 3.0;
    control.ring.strokeEnd = 0.0;
    [control.group addSublayer:control.ring];
    [self.layer addSublayer:control.group];
}

- (void)buildOpacityRow {
    _opacityRow = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 44)];
    _opacityRow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _opacityRow.layer.cornerRadius = 22;
    _opacityRow.hidden = YES;
    _opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(30, 0, 240, 44)];
    _opacitySlider.minimumValue = 0.2f;
    _opacitySlider.maximumValue = 1.0f;
    _opacitySlider.value = float(_opacity);
    _opacitySlider.minimumTrackTintColor = RingBlue();
    [_opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [_opacitySlider addTarget:self action:@selector(opacityDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_opacityRow addSubview:_opacitySlider];
    [self addSubview:_opacityRow];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    const UIEdgeInsets insets = self.safeAreaInsets;
    const CGFloat left = insets.left + 20;
    const CGFloat right = self.bounds.size.width - insets.right - 20;
    const CGFloat top = insets.top + 14;
    const CGFloat bottom = self.bounds.size.height - insets.bottom - 14;
    const CGFloat midX = CGRectGetMidX(self.bounds);

    const CGPoint a = CGPointMake(right - 48, bottom - 56);
    const CGPoint c = CGPointMake(right - 70, bottom - 196);
    const CGPoint dpad = CGPointMake(left + 156, top + 84);
    const CGFloat trayY = bottom - 74;
    int trayIndex = 0;
    int trayCount = 0;
    for (const Control &control : _controls) {
        trayCount += (control.kind == Kind::Tray) ? 1 : 0;
    }

    for (Control &control : _controls) {
        switch (control.kind) {
            case Kind::N64:
                switch (control.bit) {
                    case N64A: control.center = a; break;
                    case N64B: control.center = CGPointMake(a.x - 82, a.y - 44); break;
                    case N64CUp: control.center = CGPointMake(c.x, c.y - 36); break;
                    case N64CDown: control.center = CGPointMake(c.x, c.y + 36); break;
                    case N64CLeft: control.center = CGPointMake(c.x - 36, c.y); break;
                    case N64CRight: control.center = CGPointMake(c.x + 36, c.y); break;
                    // Z sits under L like the N64's trigger.
                    case N64Z: control.center = CGPointMake(left + 44, top + 100); break;
                    case N64L: control.center = CGPointMake(left + 44, top + 30); break;
                    case N64R: control.center = CGPointMake(right - 44, top + 30); break;
                    case N64DUp: control.center = CGPointMake(dpad.x, dpad.y - 30); break;
                    case N64DDown: control.center = CGPointMake(dpad.x, dpad.y + 30); break;
                    case N64DLeft: control.center = CGPointMake(dpad.x - 30, dpad.y); break;
                    case N64DRight: control.center = CGPointMake(dpad.x + 30, dpad.y); break;
                    default: break;
                }
                break;
            case Kind::Menu: control.center = CGPointMake(midX, bottom - 16); break;
            case Kind::Tray:
                control.center = CGPointMake(midX + (trayIndex - (trayCount - 1) / 2.0) * TrayStep, trayY);
                trayIndex++;
                break;
        }

        [self shapeControl:control];
    }

    _trayBacking.frame = CGRectMake(midX - (trayCount * TrayStep) / 2.0 - 4, trayY - 26, trayCount * TrayStep + 8, 52);
    _opacityRow.center = CGPointMake(midX, trayY - 56);
    _versionLabel.frame = CGRectMake(midX - 100, trayY - 41, 200, 14);
    _toastTop = top + 50;
    [self sizeToast];
    _stickHome = CGPointMake(left + 100, bottom - 96);
    if (_stickTouch == nil) {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }
    // Left of B, clear of START.
    _rightHome = CGPointMake(right - 230, bottom - 90);
    if (_rightTouch == nil) {
        _rightOrigin = _rightHome;
        _rightKnob = _rightHome;
    }
    _fpsLabel.frame = CGRectMake(midX - 75, top, 150, 22);

    [self refresh];
}

- (CGRect)boundsForControl:(const Control &)control {
    const CGFloat r = control.radius;
    return control.pill ? CGRectMake(0, 0, r * 3.6, r * 1.6) : CGRectMake(0, 0, 2 * r, 2 * r);
}

- (void)shapeControl:(Control &)control {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    const CGRect bounds = [self boundsForControl:control];
    control.group.bounds = bounds;
    control.group.position = control.center;
    control.shape.path = (control.pill ?
        [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 0.75, 0.75) cornerRadius:bounds.size.height / 2] :
        [UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 0.75, 0.75)]).CGPath;
    // The hold indicator fills the button's own border, starting at the top.
    if (control.pill) {
        const CGRect r = CGRectInset(bounds, 0.75, 0.75);
        const CGFloat radius = r.size.height / 2;
        UIBezierPath *border = [UIBezierPath bezierPath];
        [border moveToPoint:CGPointMake(CGRectGetMidX(r), CGRectGetMinY(r))];
        [border addLineToPoint:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMinY(r))];
        [border addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMidY(r)) radius:radius startAngle:-M_PI_2 endAngle:M_PI_2 clockwise:YES];
        [border addLineToPoint:CGPointMake(CGRectGetMinX(r) + radius, CGRectGetMaxY(r))];
        [border addArcWithCenter:CGPointMake(CGRectGetMinX(r) + radius, CGRectGetMidY(r)) radius:radius startAngle:M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
        [border closePath];
        control.ring.path = border.CGPath;
    }
    else {
        control.ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            radius:control.radius - 0.75 startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    }
    const CGFloat textHeight = control.text.fontSize * 1.25;
    control.text.frame = CGRectMake(0, (bounds.size.height - textHeight) / 2, bounds.size.width, textHeight);
    [CATransaction commit];
}

#pragma mark - Looks

- (bool)controlVisible:(const Control &)control {
    switch (control.kind) {
        case Kind::N64:
            if ((control.bit & (N64DUp | N64DDown | N64DLeft | N64DRight)) != 0) {
                return _showDpad;
            }
            return true;
        case Kind::Menu: return true;
        case Kind::Tray: return _trayOpen;
    }

    return false;
}

- (bool)trayItemOn:(TrayItem)item {
    switch (item) {
        case TrayItem::Gyro: return gyroMode.load() != int(GyroMode::Off);
        case TrayItem::Dpad: return _showDpad;
        case TrayItem::Opacity: return !_opacityRow.hidden;
        case TrayItem::Fps: return _showFps;
        default: return false;
    }
}

- (NSString *)trayLabel:(TrayItem)item {
    static NSString *const gyroNames[] = { @"GYRO\nOFF", @"GYRO\nTOUCH", @"GYRO\nON" };
    switch (item) {
        case TrayItem::Gyro:
            return (_motion.deviceMotionAvailable ? gyroNames[gyroMode.load()] : @"NO\nGYRO");
        case TrayItem::Sens: return [NSString stringWithFormat:@"SENS\n%.1fx", LookSens[gyroSensIndex.load()]];
        case TrayItem::Opacity: return [NSString stringWithFormat:@"OPACITY\n%d%%", int(std::lround(_opacity * 100))];
        case TrayItem::Dpad: return _showDpad ? @"D-PAD\nON" : @"D-PAD\nOFF";
        case TrayItem::Fps: return [NSString stringWithFormat:@"FPS\n%d", _maxFps];
        default: return @"";
    }
}

- (void)refresh {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (Control &control : _controls) {
        control.visible = [self controlVisible:control];
        control.group.hidden = !control.visible;
        if (!control.visible) {
            control.ring.strokeEnd = 0.0;
            continue;
        }

        const bool held = [self controlHeld:control];
        UIColor *border = control.accent;
        CGFloat fillWhite = held ? 0.30 : 0.0;
        CGFloat fillAlpha = held ? 0.30 : 0.22;
        if (control.kind == Kind::Tray) {
            control.text.string = [self trayLabel:control.tray];
            control.text.fontSize = 10;
            control.text.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:10].fontName;
            const CGRect trayBounds = [self boundsForControl:control];
            const bool twoLines = [(NSString *)control.text.string containsString:@"\n"];
            control.text.frame = CGRectMake(0, (trayBounds.size.height - (twoLines ? 26 : 13)) / 2, trayBounds.size.width, twoLines ? 26 : 14);
            control.text.wrapped = YES;
            control.group.opacity = 1.0;
            if ([self trayItemOn:control.tray]) {
                border = Gold();
            }
        }
        else {
            const CGFloat alpha = (held ? 1.0 : IdleAlpha) * _opacity;
            control.group.opacity = float(alpha);
        }

        control.shape.fillColor = [UIColor colorWithWhite:fillWhite alpha:fillAlpha].CGColor;
        control.shape.strokeColor = border.CGColor;
    }

    _trayBacking.hidden = !_trayOpen;
    _versionLabel.hidden = !_trayOpen || !_opacityRow.hidden;
    // The stick shows under the thumb only.
    const CGFloat stickAlpha = (_stickTouch != nil ? 1.0 : 0.0) * _opacity;
    _stickShown = (_stickTouch != nil);
    _stickBase.opacity = float(stickAlpha);
    _stickKnobLayer.opacity = float(stickAlpha);
    _stickBase.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickOrigin.x - StickRadius, _stickOrigin.y - StickRadius, 2 * StickRadius, 2 * StickRadius)].CGPath;
    _stickKnobLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickKnob.x - StickKnob, _stickKnob.y - StickKnob, 2 * StickKnob, 2 * StickKnob)].CGPath;
    // The right stick shows under the thumb only, like the left one.
    const CGFloat rightAlpha = (_rightTouch != nil ? 1.0 : 0.0) * _opacity;
    _rightBase.opacity = float(rightAlpha);
    _rightKnobLayer.opacity = float(rightAlpha);
    _rightBase.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_rightOrigin.x - RightStickRadius, _rightOrigin.y - RightStickRadius, 2 * RightStickRadius, 2 * RightStickRadius)].CGPath;
    _rightKnobLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_rightKnob.x - StickKnob, _rightKnob.y - StickKnob, 2 * StickKnob, 2 * StickKnob)].CGPath;
    _fpsLabel.hidden = !_showFps;
    [CATransaction commit];
}

- (bool)controlHeld:(const Control &)control {
    const int index = int(&control - _controls.data());
    for (const auto &entry : _touches) {
        if ((entry.second.role == Role::Control) && (entry.second.control == index)) {
            return true;
        }
    }

    return (control.kind == Kind::N64) && ((_pressed & control.bit) != 0);
}

#pragma mark - Touches

// The visible control nearest a point, within its size plus the slop.
- (int)controlAt:(CGPoint)point {
    int best = -1;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (size_t i = 0; i < _controls.size(); i++) {
        const Control &control = _controls[i];
        if (!control.visible) {
            continue;
        }

        const CGRect bounds = CGRectInset([self boundsForControl:control], -TouchSlop, -TouchSlop);
        const CGRect frame = CGRectOffset(bounds, control.center.x - CGRectGetMidX(bounds), control.center.y - CGRectGetMidY(bounds));
        const CGFloat d = distance(point, control.center);
        const bool inside = control.pill ? CGRectContainsPoint(frame, point) : (d <= control.radius + TouchSlop);
        if (inside && (d < bestDistance)) {
            best = int(i);
            bestDistance = d;
        }
    }

    return best;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    const CFTimeInterval now = CACurrentMediaTime();
    for (UITouch *touch in touches) {
        const CGPoint p = [touch locationInView:self];
        TouchState state;
        state.start = p;
        state.last = p;
        state.down = now;
        const int index = [self controlAt:p];
        if (index >= 0) {
            state.role = Role::Control;
            state.control = index;
        }
        else if (_trayOpen) {
            // A touch anywhere else closes the tray.
            [self closeTray];
            continue;
        }
        else if ((_stickTouch == nil) && (p.x < self.bounds.size.width * StickAreaFraction) && (p.y > self.safeAreaInsets.top + 130)) {
            state.role = Role::Stick;
            _stickTouch = touch;
            _stickOrigin = p;
            _stickKnob = p;
        }
        else if ((_rightTouch == nil) && (p.x < self.bounds.size.width * RightStickAreaEnd) && (p.y > self.safeAreaInsets.top + 130)) {
            state.role = Role::RightStick;
            _rightTouch = touch;
            _rightOrigin = p;
            _rightKnob = p;
        }
        else {
            state.role = Role::Look;
        }

        _touches[(__bridge void *)touch] = state;
    }

    [self updateInput];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        auto it = _touches.find((__bridge void *)touch);
        if (it == _touches.end()) {
            continue;
        }

        TouchState &state = it->second;
        const CGPoint p = [touch locationInView:self];
        if (distance(p, state.start) > HoldMoveLimit) {
            state.moved = true;
        }

        if (state.role == Role::Look) {
            const double sens = LookSens[gyroSensIndex.load()];
            addLook((p.x - state.last.x) * LookPixelsPerPoint * sens, (p.y - state.last.y) * LookPixelsPerPoint * sens);
        }

        state.last = p;
    }

    [self updateInput];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        auto it = _touches.find((__bridge void *)touch);
        if (it == _touches.end()) {
            continue;
        }

        const TouchState state = it->second;
        _touches.erase(it);
        if (touch == _stickTouch) {
            _stickTouch = nil;
        }
        if (touch == _rightTouch) {
            _rightTouch = nil;
        }

        const bool tap = !state.moved && (event != nil) && (CACurrentMediaTime() - state.down < TapTime);
        if ((state.role == Role::Control) && !state.fired && !state.moved && (event != nil)) {
            [self tapControl:state.control];
        }
        else if (tap && ((state.role == Role::Look) || (state.role == Role::Stick) || (state.role == Role::RightStick))) {
            // A tap on the open screen skips the playing cutscene.
            conker::ios::request_skip();
            if (conker::ios::cutscene_playing()) {
                [self showToast:@"Skipping"];
            }
        }
    }

    [self updateInput];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:nil];
}

#pragma mark - Actions

- (void)tapControl:(int)index {
    Control &control = _controls[index];
    switch (control.kind) {
        case Kind::Menu:
            _startUntil = CACurrentMediaTime() + StartPulse;
            break;
        case Kind::Tray:
            [self useTray:control.tray];
            break;
        default:
            break;
    }
}

// Holds that complete while the finger is still down.
- (void)holdControl:(int)index {
    Control &control = _controls[index];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    switch (control.kind) {
        case Kind::Menu:
            [haptic impactOccurred];
            _trayOpen ? [self closeTray] : [self openTray];
            break;
        case Kind::Tray:
            if (control.tray == TrayItem::Opacity) {
                [haptic impactOccurred];
                _opacity = 1.0;
                _opacitySlider.value = 1.0f;
                [self saveSettings];
                [self showToast:@"Opacity 100%"];
            }
            else if (control.tray == TrayItem::Fps) {
                // FPS held: 60 or 120 frames a second (a tap still shows/hides the readout).
                [haptic impactOccurred];
                _maxFps = (_maxFps == 120) ? 60 : 120;
                [self saveSettings];
                [self applyMaxFps];
                [self showToast:(_maxFps == 120) ? @"120 FPS: smoother, uses more battery" : @"60 FPS: cooler, uses less battery"];
            }
            break;
        default:
            break;
    }
}

- (double)holdTimeFor:(const Control &)control {
    switch (control.kind) {
        case Kind::Menu: return MenuHold;
        case Kind::Tray: return ((control.tray == TrayItem::Opacity) || (control.tray == TrayItem::Fps)) ? MenuHold : 0.0;
        default: return 0.0;
    }
}

- (void)openTray {
    _trayOpen = YES;
    gyroSuppressed.store(true);
    [self refresh];
}

- (void)closeTray {
    _trayOpen = NO;
    _opacityRow.hidden = YES;
    gyroSuppressed.store(false);
    [self refresh];
}

- (void)useTray:(TrayItem)item {
    switch (item) {
        case TrayItem::Gyro:
            if (_motion.deviceMotionAvailable) {
                gyroMode.store((gyroMode.load() + 1) % 3);
            }
            break;
        case TrayItem::Sens:
            gyroSensIndex.store((gyroSensIndex.load() + 1) % LookSensCount);
            break;
        case TrayItem::Opacity:
            _opacityRow.hidden = !_opacityRow.hidden;
            break;
        case TrayItem::Dpad:
            _showDpad = !_showDpad;
            break;
        case TrayItem::Fps:
            _showFps = !_showFps;
            _fpsTime = 0;
            break;
        default:
            break;
    }

    [self saveSettings];
    [self refresh];
}

- (void)opacityChanged:(UISlider *)slider {
    _opacity = std::round(slider.value * 20.0f) / 20.0f;
    [self refresh];
}

- (void)opacityDone:(UISlider *)slider {
    [self saveSettings];
}

- (void)showToast:(NSString *)text {
    _toast.text = text;
    [self sizeToast];
    _toast.hidden = NO;
    _toastUntil = CACurrentMediaTime() + ToastTime;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Hidden (RecompFrontend's menus), touches go to SDL's view below.
    if (self.hidden) {
        return nil;
    }

    if (!_opacityRow.hidden && CGRectContainsPoint(_opacityRow.frame, point)) {
        return [_opacityRow hitTest:[self convertPoint:point toView:_opacityRow] withEvent:event];
    }

    return [super hitTest:point withEvent:event] != nil ? self : nil;
}

// At least 280 points wide, wider for a longer line.
- (void)sizeToast {
    const CGFloat fit = [_toast sizeThatFits:CGSizeMake(CGFLOAT_MAX, 30)].width + 28;
    const CGFloat width = std::min(std::max(CGFloat(280), fit), self.bounds.size.width - 32);
    _toast.frame = CGRectMake(CGRectGetMidX(self.bounds) - width / 2, _toastTop, width, 30);
}

#pragma mark - Every frame

- (void)tick:(CADisplayLink *)link {
    // In front of SDL's Metal view, even one added later.
    if (self.superview.subviews.lastObject != self) {
        [self.superview bringSubviewToFront:self];
    }

    // Shown while the game runs and none of RecompFrontend's menus is up.
    const bool showing = conker::ios::controls_wanted();
    if (showing != _showing) {
        _showing = showing;
        controlsShowing.store(showing);
        self.hidden = !showing;
        if (!showing) {
            // Let go of everything held.
            _touches.clear();
            _stickTouch = nil;
            _rightTouch = nil;
            [self closeTray];
        }
        [self refresh];
    }

    const CFTimeInterval now = CACurrentMediaTime();
    const double dt = (_lastTick > 0) ? std::min(now - _lastTick, 0.1) : 0.0;
    _lastTick = now;
    // The right stick turns the camera as long as it's held over, faster the further it's
    // pushed (squared, for fine aiming near the middle).
    if ((_rightTouch != nil) && ((_rightX != 0) || (_rightY != 0))) {
        const double tilt = std::min(1.0, double(std::hypot(_rightX, _rightY)));
        const double speed = RightStickPixelsPerSecond * LookSens[gyroSensIndex.load()] * tilt * dt;
        addLook(_rightX * speed, -_rightY * speed);
    }
    if (_showing && !_maxFpsApplied) {
        // The remembered choice, once the game (and its settings) are up.
        [self applyMaxFps];
    }
    if (_showFps && _showing) {
        [self updateFps:now];
    }
    if (_showing) {
        [self logFrameTime:now];
    } else {
        _logTime = 0;
    }

    bool changed = false;
    for (auto &entry : _touches) {
        TouchState &state = entry.second;
        if (state.role != Role::Control) {
            continue;
        }

        Control &control = _controls[state.control];
        const double hold = [self holdTimeFor:control];
        if ((hold <= 0.0) || state.fired) {
            continue;
        }

        if (state.moved) {
            control.ring.strokeEnd = 0.0;
            continue;
        }

        const double progress = (now - state.down) / hold;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        control.ring.strokeEnd = std::min(1.0, progress);
        [CATransaction commit];
        if (progress >= 1.0) {
            state.fired = true;
            control.ring.strokeEnd = 0.0;
            [self holdControl:state.control];
            changed = true;
        }
    }

    for (Control &control : _controls) {
        bool holding = false;
        for (const auto &entry : _touches) {
            holding = holding || ((entry.second.role == Role::Control) && (&_controls[entry.second.control] == &control) && !entry.second.fired && !entry.second.moved);
        }

        if (!holding && (control.ring.strokeEnd != 0.0)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            control.ring.strokeEnd = 0.0;
            [CATransaction commit];
        }
    }

    if (!_toast.hidden && (now > _toastUntil)) {
        _toast.hidden = YES;
    }

    [self updateInput];
    if (changed) {
        [self refresh];
    }
}

- (void)updateFps:(CFTimeInterval)now {
    uint64_t presented = 0;
    uint64_t game = 0;
    conker::ios::frame_counts(&presented, &game);
    if (_fpsTime == 0) {
        _fpsTime = now;
        _fpsPresented = presented;
        _fpsGame = game;
        _fpsLabel.text = @"FPS …";
        return;
    }
    if (now - _fpsTime < 0.5) {
        return;
    }
    const double seconds = now - _fpsTime;
    _fpsLabel.text = [NSString stringWithFormat:@"%.0f FPS  |  Game %.0f",
        double(presented - _fpsPresented) / seconds, double(game - _fpsGame) / seconds];
    _fpsTime = now;
    _fpsPresented = presented;
    _fpsGame = game;
}

// The log: frames presented and the game's own, every 5 seconds of play.
- (void)logFrameTime:(CFTimeInterval)now {
    uint64_t presented = 0;
    uint64_t game = 0;
    conker::ios::frame_counts(&presented, &game);
    if (_logTime == 0) {
        _logTime = now;
        _logPresented = presented;
        _logGame = game;
        return;
    }
    const double seconds = now - _logTime;
    if (seconds < 5.0) {
        return;
    }
    const double fps = double(presented - _logPresented) / seconds;
    std::fprintf(stderr, "[ios] frames: %.1f FPS (%.1f ms a frame), game %.1f FPS, asked %d\n",
        fps, fps > 0 ? 1000.0 / fps : 0.0, double(game - _logGame) / seconds, _maxFps);
    _logTime = now;
    _logPresented = presented;
    _logGame = game;
}

// A stick's position for a touch: the knob (kept within the radius) and its tilt (-1 to 1,
// up positive), zero within the dead zone.
- (void)stickFor:(UITouch *)touch origin:(CGPoint)origin radius:(CGFloat)radius knob:(CGPoint *)knob x:(CGFloat *)x y:(CGFloat *)y {
    auto it = _touches.find((__bridge void *)touch);
    const CGPoint p = (it != _touches.end()) ? it->second.last : origin;
    CGFloat dx = p.x - origin.x;
    CGFloat dy = p.y - origin.y;
    const CGFloat length = std::hypot(dx, dy);
    if (length > radius) {
        dx *= radius / length;
        dy *= radius / length;
    }

    *knob = CGPointMake(origin.x + dx, origin.y + dy);
    *x = 0;
    *y = 0;
    if (std::hypot(dx, dy) / radius > StickDeadZone) {
        *x = dx / radius;
        *y = -dy / radius;
    }
}

- (void)updateInput {
    uint16_t bits = 0;
    bool thumb = (_stickTouch != nil);
    for (const auto &entry : _touches) {
        const TouchState &state = entry.second;
        if (state.role == Role::Look) {
            thumb = true;
        }
        else if ((state.role == Role::Control) && (_controls[state.control].kind == Kind::N64)) {
            // N64 buttons follow the finger, so a thumb can roll between them.
            const int index = [self controlAt:state.last];
            if ((index >= 0) && (_controls[index].kind == Kind::N64)) {
                bits |= _controls[index].bit;
            }

            thumb = true;
        }
    }

    if (CACurrentMediaTime() < _startUntil) {
        bits |= N64Start;
    }

    float x = 0.0f;
    float y = 0.0f;
    if (_stickTouch != nil) {
        CGFloat stickX = 0;
        CGFloat stickY = 0;
        [self stickFor:_stickTouch origin:_stickOrigin radius:StickRadius knob:&_stickKnob x:&stickX y:&stickY];
        x = float(stickX);
        y = float(stickY);
    }
    else {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }

    if (_rightTouch != nil) {
        [self stickFor:_rightTouch origin:_rightOrigin radius:RightStickRadius knob:&_rightKnob x:&_rightX y:&_rightY];
        thumb = true;
    }
    else {
        _rightOrigin = _rightHome;
        _rightKnob = _rightHome;
        _rightX = 0;
        _rightY = 0;
    }

    gyroThumbDown.store(thumb);
    const bool changed = (bits != _pressed);
    _pressed = bits;
    if (!_showing) {
        bits = 0;
        x = 0.0f;
        y = 0.0f;
    }

    conker::ios::set_touch_input(bits, x, y);
    // Redraw while the stick is held, and once more when it is let go, so it disappears
    // with the thumb.
    if (changed || (_stickTouch != nil) || _stickShown || (_rightTouch != nil) || _rightShown) {
        _rightShown = (_rightTouch != nil);
        [self refresh];
    }
}

#pragma mark - Gyro

- (void)startGyro {
    _motion = [[CMMotionManager alloc] init];
    if (!_motion.deviceMotionAvailable) {
        return;
    }

    _motionQueue = [[NSOperationQueue alloc] init];
    _motionQueue.maxConcurrentOperationCount = 1;
    _motion.deviceMotionUpdateInterval = 0.01;
    [self updateLandscapeSign];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateLandscapeSign)
        name:UIDeviceOrientationDidChangeNotification object:nil];

    __block CFTimeInterval lastTime = 0;
    __block CFTimeInterval quietUntil = 0;
    __block int lastSign = gyroLandscapeSign.load();
    [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
        toQueue:_motionQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (motion == nil) {
            return;
        }

        const CFTimeInterval now = motion.timestamp;
        const double dt = (lastTime > 0) ? (now - lastTime) : 0.0;
        lastTime = now;
        const int sign = gyroLandscapeSign.load();
        if (sign != lastSign) {
            // No aiming for a moment after the screen flips sides.
            lastSign = sign;
            quietUntil = now + 0.35;
        }

        const GyroMode mode = GyroMode(gyroMode.load());
        if ((mode == GyroMode::Off) || gyroSuppressed.load() || (dt <= 0.0) || (dt > 0.5) || (now < quietUntil) ||
            ((mode == GyroMode::Touch) && !gyroThumbDown.load())) {
            return;
        }

        // Yaw about gravity's up axis (degrees per second), and pitch about the screen's
        // horizontal axis, which is the device's y in landscape.
        const CMRotationRate rate = motion.rotationRate;
        const CMAcceleration g = motion.gravity;
        const double gLength = std::sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
        if (gLength < 0.1) {
            return;
        }

        double yaw = (rate.x * g.x + rate.y * g.y + rate.z * g.z) / gLength * (180.0 / M_PI);
        // Tilting the top of the phone away looks down, as with a camera.
        double pitch = rate.y * sign * (180.0 / M_PI);
        auto deadZone = [](double value) {
            const double magnitude = std::fabs(value);
            if (magnitude < GyroDeadZone) {
                return value * (magnitude / GyroDeadZone);
            }

            return value;
        };

        yaw = deadZone(yaw);
        pitch = deadZone(pitch);
        const double scale = GyroPixelsPerDegree * LookSens[gyroSensIndex.load()] * dt;
        addLook(yaw * scale, pitch * scale);
    }];
}

- (void)updateLandscapeSign {
    const UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (orientation == UIDeviceOrientationLandscapeLeft) {
        gyroLandscapeSign.store(1);
    }
    else if (orientation == UIDeviceOrientationLandscapeRight) {
        gyroLandscapeSign.store(-1);
    }
}

- (void)dealloc {
    [_motion stopDeviceMotionUpdates];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

void conker_touch_controls_install(void) {
    // SDL makes its window as the game starts up: look for it until it's there. The app has
    // no scenes of its own (SDL 2 keeps a window of its own), so the window may only be in
    // the application's list.
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    for (UIWindow *window in windows) {
        UIView *root = window.rootViewController.view;
        if (root != nil) {
            ConkerTouchControlsView *controls = [[ConkerTouchControlsView alloc] initWithFrame:root.bounds];
            [root addSubview:controls];
            return;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        conker_touch_controls_install();
    });
}
