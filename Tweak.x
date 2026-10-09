/*
 * CameraButtonSwap - iOS 17 / 17.3.1 深度重构强化版 (v2.1.0)
 *
 * 核心升级：
 *   1. 注入感知强反馈：
 *      - 触感震动反馈：AudioServicesPlaySystemSound 硬件级物理震动。
 *      - 顶层系统弹窗：UIAlertController 直接弹窗（自动 2.5 秒淡出或点击关闭），绝对无法被相机预览层遮挡。
 *      - 浮动胶囊 HUD 与本地双通道日志 (/var/mobile/Library/Logs/CameraButtonSwap.log 及 /tmp/camerabuttonswap.log)。
 *   2. 双模容器与视图移动引擎：
 *      - 若元素直接位于大容器（全屏取景器/底部栏），直接调整其 frame 与 center。
 *      - 若元素被嵌套在小容器中（如 VKCActionInfoView / 小容器），自动上溯冒泡到该容器整体左移。
 *   3. 精准 Hook 与多重防回弹：
 *      - CAMImageAnalysisButton / VKImageAnalysisButton / VKCCornerLookupButton 的 setFrame: 与 setCenter:。
 *      - CAMFullscreenViewfinder 与 CAMBottomBar 的 layoutSubviews。
 *      - Trailing 约束解绑 + Leading 约束施加 + CGAffineTransform 物理平移兜底。
 *   4. 微距按钮智能避让。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

#define CBS_TAG @"[CameraButtonSwap-v2.4]"

// ============================================================================
// 前向接口声明
// ============================================================================

@interface CAMImageAnalysisButton : UIButton
@end

@interface VKImageAnalysisButton : UIButton
@end

@interface VKCCornerLookupButton : UIView
@end

@interface CAMFullscreenViewfinder : UIView
@end

@interface CAMBottomBar : UIView
@end

// ============================================================================
// 多通道日志与震动反馈
// ============================================================================

static void writeCBSLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"%@ %@", CBS_TAG, msg);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];
    
    NSMutableArray *paths = [NSMutableArray arrayWithObjects:
        @"/var/mobile/Library/Logs/CameraButtonSwap.log",
        @"/tmp/camerabuttonswap.log",
        @"/var/jb/tmp/camerabuttonswap.log",
        @"/var/mobile/Media/camerabuttonswap.log",
        nil];
    
    NSString *tmpDir = NSTemporaryDirectory();
    if (tmpDir.length > 0) {
        [paths addObject:[tmpDir stringByAppendingPathComponent:@"camerabuttonswap.log"]];
    }
    NSArray *docDirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docDirs.count > 0) {
        [paths addObject:[docDirs.firstObject stringByAppendingPathComponent:@"camerabuttonswap.log"]];
    }
    
    for (NSString *path in paths) {
        @try {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            } else {
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        } @catch (id e) {}
    }
}

// 硬件触感震动反馈
static void triggerHapticFeedback(void) {
    AudioServicesPlaySystemSound(1519); // Peek / 强触感震动
}

// 安全获取对象 ivar
static UIView *getIvarView(id obj, const char *ivarName) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), ivarName);
    if (iv) {
        return object_getIvar(obj, iv);
    }
    return nil;
}

// ============================================================================
// 元素识别辅助函数
// ============================================================================

static BOOL isLiveTextElement(UIView *view) {
    if (!view) return NO;
    
    NSString *className = NSStringFromClass([view class]);
    
    // 1. 类名特征匹配
    if ([className containsString:@"ImageAnalysis"] ||
        [className containsString:@"CornerLookup"] ||
        [className containsString:@"ActionInfo"] ||
        [className containsString:@"LiveText"] ||
        [className containsString:@"ScanText"] ||
        [className containsString:@"TextRecognition"] ||
        [className containsString:@"DataScanner"]) {
        return YES;
    }
    
    // 2. 检查按钮是否带有 text.viewfinder 图标
    if ([view isKindOfClass:[UIButton class]] || [view isKindOfClass:[UIControl class]]) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)view;
            UIImage *img = [b currentImage] ?: [b imageForState:UIControlStateNormal];
            if (img && [[img description] containsString:@"viewfinder"]) {
                return YES;
            }
        }
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UIImageView class]]) {
                UIImage *img = [(UIImageView *)sub image];
                if (img && [[img description] containsString:@"viewfinder"]) {
                    return YES;
                }
            }
        }
    }
    
    // 3. Accessibility 标识特征
    NSString *aid = view.accessibilityIdentifier;
    if (aid && ([aid localizedCaseInsensitiveContainsString:@"analysis"] ||
                [aid localizedCaseInsensitiveContainsString:@"lookup"] ||
                [aid localizedCaseInsensitiveContainsString:@"live-text"] ||
                [aid localizedCaseInsensitiveContainsString:@"scantext"])) {
        return YES;
    }
    
    return NO;
}

static BOOL isMacroElement(UIView *view) {
    if (!view) return NO;
    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"AutoMacro"] ||
           [className containsString:@"MacroButton"] ||
           [className containsString:@"MacroControl"];
}

// ============================================================================
// 统一重定位引擎：智能处理直接视图与嵌套容器
// ============================================================================

static void relocateElementAndContainer(UIView *element) {
    if (!element) return;
    UIView *superview = element.superview;
    if (!superview) return;
    
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    if (screenW <= 0 || screenW > 2000.0) screenW = 390.0;
    
    UIWindow *window = element.window ?: superview.window;
    
    // 1. 容器冒泡：如果当前元素包裹在一个靠右侧的小容器中（宽度 < 屏幕 70%），上溯到最外层小容器
    UIView *target = element;
    while (target.superview &&
           target.superview != window &&
           target.superview.bounds.size.width > 0 &&
           target.superview.bounds.size.width < screenW * 0.7) {
        target = target.superview;
    }
    
    UIView *parent = target.superview ?: superview;
    CGFloat parentW = parent.bounds.size.width > 0 ? parent.bounds.size.width : screenW;
    
    // 计算 target 在 window 中的中轴坐标
    CGRect winRect = window ? [parent convertRect:target.frame toView:window] : target.frame;
    CGFloat winMidX = CGRectGetMidX(winRect);
    
    // 如果已经在左侧，跳过
    if (winMidX > 0 && winMidX < screenW * 0.45) {
        return;
    }
    
    writeCBSLog(@"[Relocate] 正在将目标移动至左侧: %@ (WinMidX=%.1f)", NSStringFromClass([target class]), winMidX);
    
    // 2. 解除 Auto Layout 右侧约束，添加左侧 Leading 约束
    NSMutableArray<NSLayoutConstraint *> *trailingConstraints = [NSMutableArray array];
    for (NSLayoutConstraint *c in parent.constraints) {
        if (c.firstItem == target || c.secondItem == target) {
            if (c.firstAttribute == NSLayoutAttributeTrailing ||
                c.firstAttribute == NSLayoutAttributeRight ||
                c.secondAttribute == NSLayoutAttributeTrailing ||
                c.secondAttribute == NSLayoutAttributeRight) {
                [trailingConstraints addObject:c];
            }
        }
    }
    if (trailingConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:trailingConstraints];
        NSLayoutConstraint *leading = [target.leadingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.leadingAnchor constant:16.0];
        leading.priority = UILayoutPriorityRequired;
        leading.active = YES;
        [parent setNeedsLayout];
    }
    
    // 3. 计算左侧 frame
    CGRect f = target.frame;
    if (f.origin.x > parentW / 2.0) {
        CGFloat rightMargin = parentW - (f.origin.x + f.size.width);
        if (rightMargin < 12.0) rightMargin = 16.0;
        if (rightMargin > 80.0) rightMargin = 20.0;
        f.origin.x = rightMargin;
        target.frame = f;
    }
    
    // 4. 计算左侧 center
    CGPoint c = target.center;
    if (c.x > parentW / 2.0) {
        CGFloat rightMargin = parentW - c.x;
        if (rightMargin < 20.0) rightMargin = 36.0;
        c.x = rightMargin;
        target.center = c;
    }
    
    // 5. 智能避让微距按钮
    for (UIView *sibling in parent.subviews) {
        if (sibling != target && isMacroElement(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
            if (sibling.frame.origin.x < parentW / 2.0) {
                if (CGRectIntersectsRect(target.frame, CGRectInset(sibling.frame, -10, -10))) {
                    CGRect tf = target.frame;
                    tf.origin.y = sibling.frame.origin.y - tf.size.height - 12.0;
                    target.frame = tf;
                    
                    CGPoint tc = target.center;
                    tc.y = tf.origin.y + tf.size.height / 2.0;
                    target.center = tc;
                }
            }
            break;
        }
    }
    
    // 6. CGAffineTransform 物理平移兜底
    CGRect currentWinRect = window ? [parent convertRect:target.frame toView:window] : target.frame;
    if (CGRectGetMidX(currentWinRect) > screenW / 2.0) {
        CGFloat currentX = CGRectGetMidX(currentWinRect);
        CGFloat targetX = 42.0;
        CGFloat deltaX = targetX - currentX;
        target.transform = CGAffineTransformMakeTranslation(deltaX, 0);
        writeCBSLog(@"[Relocate] 激活 CGAffineTransform 强制平移 deltaX=%.1f", deltaX);
    }
}

// 递归扫描整棵视图树
static void scanAndRelocateHierarchy(UIView *root) {
    if (!root) return;
    
    if (isLiveTextElement(root)) {
        relocateElementAndContainer(root);
        return;
    }
    
    for (UIView *sub in root.subviews) {
        scanAndRelocateHierarchy(sub);
    }
}

// ============================================================================
// 可视化注入反馈：物理震动 + 系统 Alert 弹窗 + 胶囊 HUD
// ============================================================================

static void showInjectionFeedback(UIViewController *vc) {
    static BOOL feedbackTriggered = NO;
    if (feedbackTriggered) return;
    feedbackTriggered = YES;
    
    // 1. 物理触感震动
    triggerHapticFeedback();
    writeCBSLog(@"[Feedback] 触发触感震动反馈与注入通知");
    
    // 2. 弹出系统级 UIAlertController (无法被任何取景器遮挡)
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = vc;
        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }
        if (!presenter) {
            presenter = [UIApplication sharedApplication].keyWindow.rootViewController;
        }
        
        if (presenter) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚡️ CameraButtonSwap"
                                                                           message:@"插件已成功注入相机进程！\n实况文本按钮已切换至左侧 (v2.4)"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            
            [presenter presentViewController:alert animated:YES completion:^{
                // 2.5 秒后自动淡出关闭，不干扰拍照
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [alert dismissViewControllerAnimated:YES completion:nil];
                });
            }];
        }
    });
    
    // 3. 在活跃 UIWindow 上挂载黑金胶囊 HUD
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = nil;
        if (@available(iOS 15.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                        if (w.isKeyWindow || [NSStringFromClass([w class]) containsString:@"Camera"]) {
                            targetWindow = w;
                            break;
                        }
                    }
                }
                if (targetWindow) break;
            }
        }
        if (!targetWindow) {
            targetWindow = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        }
        if (!targetWindow) return;
        
        UILabel *toast = [[UILabel alloc] init];
        toast.text = @" ⚡️ CameraButtonSwap 已注入 (左侧模式) ";
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        toast.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.layer.cornerRadius = 14.0;
        toast.clipsToBounds = YES;
        toast.layer.borderColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.8].CGColor;
        toast.layer.borderWidth = 1.0;
        [toast sizeToFit];
        
        CGRect frame = toast.frame;
        frame.size.width += 24.0;
        frame.size.height = 28.0;
        frame.origin.x = (targetWindow.bounds.size.width - frame.size.width) / 2.0;
        frame.origin.y = 56.0;
        toast.frame = frame;
        toast.alpha = 0.0;
        [targetWindow addSubview:toast];
        [targetWindow bringSubviewToFront:toast];
        
        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.4 animations:^{
                    toast.alpha = 0.0;
                } completion:^(BOOL fin) {
                    [toast removeFromSuperview];
                }];
            });
        }];
    });
}

// ============================================================================
// 精准类级 Hooks (拦截 setFrame 与 setCenter)
// ============================================================================

%hook CAMImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

%end

%hook VKImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

%end

%hook VKCCornerLookupButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateElementAndContainer((UIView *)self);
}

%end

// ============================================================================
// 宿主容器布局 Hooks (CAMFullscreenViewfinder & CAMBottomBar)
// ============================================================================

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = nil;
    @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
    if (!btn) {
        btn = getIvarView(self, "_imageAnalysisButton");
    }
    if (btn && !btn.hidden && btn.alpha > 0.01) {
        relocateElementAndContainer(btn);
    }
    
    scanAndRelocateHierarchy((UIView *)self);
}

%end

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = nil;
    @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
    if (!btn) {
        btn = getIvarView(self, "_imageAnalysisButton");
    }
    if (btn && !btn.hidden && btn.alpha > 0.01) {
        relocateElementAndContainer(btn);
    }
    
    scanAndRelocateHierarchy((UIView *)self);
}

%end

// ============================================================================
// 控制器生命周期与动态视图监听
// ============================================================================

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Camera"] || [clsName containsString:@"Viewfinder"] || [clsName hasPrefix:@"CAM"]) {
        showInjectionFeedback(self);
        
        // 启动高频看门狗定时器（每 0.25 秒扫描一次）
        static NSTimer *watchdogTimer = nil;
        if (!watchdogTimer) {
            __weak UIViewController *weakSelf = self;
            watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer * _Nonnull timer) {
                UIViewController *strongSelf = weakSelf;
                if (strongSelf && strongSelf.view) {
                    scanAndRelocateHierarchy(strongSelf.view);
                }
            }];
        }
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Camera"] || [clsName containsString:@"Viewfinder"] || [clsName hasPrefix:@"CAM"]) {
        UIView *v = [(UIViewController *)self view];
        if (v) {
            scanAndRelocateHierarchy(v);
        }
    }
}

%end

%hook UIView

- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (isLiveTextElement(subview)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            relocateElementAndContainer(subview);
        });
    }
}

%end

// ============================================================================
// 构造函数与初始化
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        writeCBSLog(@"[Ctor] 插件初始化启动, Bundle: %@", bundleID);
        
        // 硬件触感震动感知
        triggerHapticFeedback();
        
        // 预加载系统私有框架
        dlopen("/System/Library/PrivateFrameworks/CameraUI.framework/CameraUI", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/VisionKitCore.framework/VisionKitCore", RTLD_NOW);
        dlopen("/System/Library/Frameworks/VisionKit.framework/VisionKit", RTLD_NOW);
        
        %init;
        writeCBSLog(@"[Ctor] Hooks 注册完毕");
        
        // 监听应用进入前台唤醒
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            writeCBSLog(@"[App] UIApplicationDidBecomeActiveNotification 触发");
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            showInjectionFeedback(rootVC);
        }];
    }
}
