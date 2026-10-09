/*
 * CameraButtonSwap - iOS 17 / 17.3.1 深度重构版 (v2.0.0)
 *
 * 核心架构设计：
 *   1. 多维度注入验证与可视化反馈：
 *      - 进程唤醒即在顶层 UIWindow 弹出黑金胶囊 HUD 提示："⚡️ CameraButtonSwap 已注入 (iOS 17 适配版)"。
 *      - 双通道日志：同时输出至 NSLog 与 /var/mobile/Library/Logs/CameraButtonSwap.log（及 /tmp/camerabuttonswap.log），方便排查。
 *   2. 类级 setFrame: / setCenter: 精准拦截：
 *      - 直接 Hook CAMImageAnalysisButton、VKImageAnalysisButton、VKCCornerLookupButton 的坐标赋值方法，
 *        在任何布局引擎（手动或 Auto Layout）将其置于右侧时，即刻计算并重定向至左下侧。
 *   3. 宿主容器布局 Hook (CAMFullscreenViewfinder & CAMBottomBar)：
 *      - 拦截 layoutSubviews，直接获取 _imageAnalysisButton 实例并矫正 frame，
 *        同时检测微距按钮 (_autoMacroButton)，若微距激活则自动将文本按钮上移避让。
 *   4. 顶级容器冒泡与约束反转 (Container Bubbling & Auto Layout Inversion)：
 *      - iOS 17 将实况文本组件包装于独立容器中，插件自动向上追溯容器并解除 Trailing 约束、施加 Leading 约束。
 *      - 物理图层平移兜底 (CGAffineTransformMakeTranslation) 确保绝对不被回弹。
 *   5. 高频看门狗与动态感知 (Watchdog + didAddSubview)：
 *      - 确保文本被识别并弹出的毫秒级时间内被拉至左侧。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#define CBS_TAG @"[CameraButtonSwap-v2]"

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
// 双通道日志输出
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
    
    NSArray *paths = @[
        @"/var/mobile/Library/Logs/CameraButtonSwap.log",
        @"/tmp/camerabuttonswap.log"
    ];
    for (NSString *path in paths) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } else {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

// ============================================================================
// 元素识别辅助函数
// ============================================================================

// 识别实况文本按钮与容器
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

// 识别微距模式花朵按钮
static BOOL isMacroElement(UIView *view) {
    if (!view) return NO;
    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"AutoMacro"] ||
           [className containsString:@"MacroButton"] ||
           [className containsString:@"MacroControl"];
}

// ============================================================================
// 坐标与避让计算核心
// ============================================================================

static CGRect computeLeftFrame(UIView *view, CGRect origFrame) {
    UIView *superview = view.superview;
    CGFloat superW = superview ? superview.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    if (superW <= 0) superW = 390.0;
    
    CGRect f = origFrame;
    // 如果已经在左侧，直接返回
    if (f.origin.x < superW * 0.45 && f.origin.x >= 0) {
        return f;
    }
    
    // 计算离左侧的安全边距（保持与原右侧边距对称，默认 16~20pt）
    CGFloat rightMargin = superW - (origFrame.origin.x + origFrame.size.width);
    if (rightMargin < 12.0) rightMargin = 16.0;
    if (rightMargin > 80.0) rightMargin = 20.0;
    
    f.origin.x = rightMargin;
    
    // 智能避让微距按钮
    if (superview) {
        for (UIView *sibling in superview.subviews) {
            if (sibling != view && isMacroElement(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
                if (sibling.frame.origin.x < superW / 2.0) {
                    CGRect macroRect = sibling.frame;
                    if (CGRectIntersectsRect(f, CGRectInset(macroRect, -8, -8))) {
                        f.origin.y = macroRect.origin.y - f.size.height - 12.0;
                    }
                }
                break;
            }
        }
    }
    
    return f;
}

static CGPoint computeLeftCenter(UIView *view, CGPoint origCenter) {
    UIView *superview = view.superview;
    CGFloat superW = superview ? superview.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    if (superW <= 0) superW = 390.0;
    
    CGPoint c = origCenter;
    if (c.x < superW * 0.45 && c.x >= 0) {
        return c;
    }
    
    CGFloat rightMargin = superW - origCenter.x;
    if (rightMargin < 20.0) rightMargin = 36.0;
    c.x = rightMargin;
    
    if (superview) {
        for (UIView *sibling in superview.subviews) {
            if (sibling != view && isMacroElement(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
                if (sibling.center.x < superW / 2.0) {
                    CGFloat dist = fabs(c.y - sibling.center.y);
                    if (dist < 55.0) {
                        c.y = sibling.center.y - 55.0;
                    }
                }
                break;
            }
        }
    }
    
    return c;
}

// ============================================================================
// 容器冒泡与重定位引擎
// ============================================================================

static void relocateLiveTextToLeft(UIView *element) {
    if (!element) return;
    UIView *superview = element.superview;
    if (!superview) return;
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    if (screenWidth <= 0 || screenWidth > 2000.0) screenWidth = 390.0;
    
    UIWindow *window = element.window ?: superview.window;
    CGRect winRect = window ? [superview convertRect:element.frame toView:window] : element.frame;
    CGFloat winMidX = CGRectGetMidX(winRect);
    
    // 如果已经在屏幕左半边，无需重复处理
    if (winMidX > 0 && winMidX < screenWidth * 0.45) {
        return;
    }
    
    writeCBSLog(@"[Relocate] 捕获右侧目标: %@ (WinMidX=%.1f)", NSStringFromClass([element class]), winMidX);
    
    // 容器冒泡：若该元素被包含在靠右侧的小容器中（宽度小于屏幕 65%），移动最顶层小容器
    UIView *viewToMove = element;
    while (viewToMove.superview &&
           viewToMove.superview != window &&
           viewToMove.superview.bounds.size.width > 0 &&
           viewToMove.superview.bounds.size.width < screenWidth * 0.65) {
        viewToMove = viewToMove.superview;
    }
    
    UIView *parent = viewToMove.superview ?: superview;
    
    // 处理 Auto Layout 约束：移除 Trailing / Right 约束，添加 Leading 约束
    NSMutableArray<NSLayoutConstraint *> *trailingConstraints = [NSMutableArray array];
    for (NSLayoutConstraint *c in parent.constraints) {
        if (c.firstItem == viewToMove || c.secondItem == viewToMove) {
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
        NSLayoutConstraint *leading = [viewToMove.leadingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.leadingAnchor constant:16.0];
        leading.priority = UILayoutPriorityRequired;
        leading.active = YES;
        [parent setNeedsLayout];
    }
    
    // 手动调整 frame 与 center
    viewToMove.frame = computeLeftFrame(viewToMove, viewToMove.frame);
    viewToMove.center = computeLeftCenter(viewToMove, viewToMove.center);
    
    // CGAffineTransform 物理平移兜底 (防止被系统未公开布局周期强制回弹)
    CGRect currentWinRect = window ? [viewToMove.superview convertRect:viewToMove.frame toView:window] : viewToMove.frame;
    if (CGRectGetMidX(currentWinRect) > screenWidth / 2.0) {
        CGFloat currentX = CGRectGetMidX(currentWinRect);
        CGFloat targetX = 40.0;
        CGFloat deltaX = targetX - currentX;
        viewToMove.transform = CGAffineTransformMakeTranslation(deltaX, 0);
        writeCBSLog(@"[Relocate] 激活 CGAffineTransform 强制平移 deltaX=%.1f", deltaX);
    }
}

// 递归扫描整棵视图树
static void scanAndRelocateHierarchy(UIView *root) {
    if (!root) return;
    
    if (isLiveTextElement(root)) {
        relocateLiveTextToLeft(root);
        return;
    }
    
    for (UIView *sub in root.subviews) {
        scanAndRelocateHierarchy(sub);
    }
}

// ============================================================================
// 可视化注入 HUD 提示
// ============================================================================

static void showGlobalInjectionToast(void) {
    static BOOL shown = NO;
    if (shown) return;
    
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
    
    shown = YES;
    writeCBSLog(@"[Toast] 成功挂载 HUD 到窗口: %@", NSStringFromClass([targetWindow class]));
    
    UILabel *toast = [[UILabel alloc] init];
    toast.text = @" ⚡️ CameraButtonSwap 已注入 (iOS 17 适配版) ";
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.4 animations:^{
                toast.alpha = 0.0;
            } completion:^(BOOL fin) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

// ============================================================================
// 精准类级 Hooks (setFrame & setCenter 拦截)
// ============================================================================

%hook CAMImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig(computeLeftFrame((UIView *)self, frame));
}

- (void)setCenter:(CGPoint)center {
    %orig(computeLeftCenter((UIView *)self, center));
}

%end

%hook VKImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig(computeLeftFrame((UIView *)self, frame));
}

- (void)setCenter:(CGPoint)center {
    %orig(computeLeftCenter((UIView *)self, center));
}

%end

%hook VKCCornerLookupButton

- (void)setFrame:(CGRect)frame {
    %orig(computeLeftFrame((UIView *)self, frame));
}

- (void)setCenter:(CGPoint)center {
    %orig(computeLeftCenter((UIView *)self, center));
}

%end

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
        btn.frame = computeLeftFrame(btn, btn.frame);
        btn.center = computeLeftCenter(btn, btn.center);
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
        btn.frame = computeLeftFrame(btn, btn.frame);
        btn.center = computeLeftCenter(btn, btn.center);
    }
    
    scanAndRelocateHierarchy((UIView *)self);
}

%end

// ============================================================================
// 控制器生命周期与动态视图 Hook
// ============================================================================

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Camera"] || [clsName containsString:@"Viewfinder"] || [clsName hasPrefix:@"CAM"]) {
        showGlobalInjectionToast();
        
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
            relocateLiveTextToLeft(subview);
        });
    }
}

%end

// ============================================================================
// 构造函数与动态框架加载
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        writeCBSLog(@"[Ctor] 插件加载成功, Bundle: %@", bundleID);
        
        // 预加载相关系统框架
        dlopen("/System/Library/PrivateFrameworks/CameraUI.framework/CameraUI", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/VisionKitCore.framework/VisionKitCore", RTLD_NOW);
        dlopen("/System/Library/Frameworks/VisionKit.framework/VisionKit", RTLD_NOW);
        
        %init;
        writeCBSLog(@"[Ctor] Hooks 注册完毕");
        
        // 监听应用唤醒事件，弹出提示并初始化
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            writeCBSLog(@"[App] UIApplicationDidBecomeActiveNotification 触发");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showGlobalInjectionToast();
            });
        }];
    }
}
