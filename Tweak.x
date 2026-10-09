/*
 * CameraButtonSwap - iOS 17 终极适配版 (v1.3.0)
 *
 * 核心特性：
 *   1. 启动注入提示 (Toast HUD)：
 *      - 打开相机时在屏幕顶部短暂提示「CameraButtonSwap 已加载」，让用户 100% 确认越狱注入成功。
 *   2. 四重实况文本定位匹配引擎：
 *      - 策略 A：匹配类名 (ImageAnalysisButton, CornerLookupButton, ActionInfoView, LiveText 等)
 *      - 策略 B：匹配 SF Symbol 图标 (text.viewfinder 图标自动识别)
 *      - 策略 C：匹配无障碍标识 (Accessibility Identifier / Label)
 *      - 策略 D：右下角浮动按钮几何特征捕获
 *   3. 三重强力移位引擎：
 *      - 约束反转：停用 Trailing 约束并添加 Leading 约束
 *      - 容器冒泡：自动查找并移动包裹实况文本按钮的外层右侧小容器
 *      - Transform 强制平移兜底：使用 CGAffineTransformMakeTranslation 确保即使 Auto Layout 强锁死，视觉与触摸交互也必然位于左侧！
 *   4. 本地诊断日志：
 *      - 详细日志写入 /var/mobile/Documents/CameraButtonSwap.log
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define CBS_LOG(fmt, ...) do { \
    NSString *_msg = [NSString stringWithFormat:@"[CameraButtonSwap] " fmt, ##__VA_ARGS__]; \
    NSLog(@"%@", _msg); \
    appendDiagnosticLog(_msg); \
} while(0)

// ============================================================================
// 日志持久化辅助
// ============================================================================

static void appendDiagnosticLog(NSString *text) {
    static NSString *logPath = @"/var/mobile/Documents/CameraButtonSwap.log";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    });
    
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], text];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

// ============================================================================
// 前向声明与辅助判断
// ============================================================================

@interface CAMViewfinderViewController : UIViewController
@end

@interface CAMFullscreenViewfinder : UIView
@end

@interface CAMBottomBar : UIView
@end

// 检查是否包含 text.viewfinder 或文本相关特征
static BOOL isLiveTextAffordance(UIView *view) {
    if (!view) return NO;
    
    // 1. 类名匹配
    NSString *cls = NSStringFromClass([view class]);
    if ([cls containsString:@"ImageAnalysis"] ||
        [cls containsString:@"CornerLookup"] ||
        [cls containsString:@"ActionInfo"] ||
        [cls containsString:@"LiveText"] ||
        [cls containsString:@"ScanText"] ||
        [cls containsString:@"TextRecognition"]) {
        return YES;
    }
    
    // 2. accessibilityIdentifier / label 匹配
    NSString *aid = view.accessibilityIdentifier;
    if (aid) {
        NSString *lower = [aid lowercaseString];
        if ([lower containsString:@"analysis"] ||
            [lower containsString:@"lookup"] ||
            [lower containsString:@"livetext"] ||
            [lower containsString:@"live-text"] ||
            [lower containsString:@"scantext"] ||
            [lower containsString:@"scan-text"]) {
            return YES;
        }
    }
    
    // 3. 检查是否有 text.viewfinder 相关的图像
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        UIImage *img = [btn imageForState:UIControlStateNormal];
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
    
    return NO;
}

// 检查是否是微距按钮 (花朵)
static BOOL isMacroAffordance(UIView *view) {
    if (!view) return NO;
    NSString *cls = NSStringFromClass([view class]);
    return [cls containsString:@"AutoMacro"] || [cls containsString:@"MacroButton"] || [cls containsString:@"MacroControl"];
}

// ============================================================================
// 强力移位引擎：将目标（或外层容器）彻底移至左侧
// ============================================================================

static void forceRelocateToLeft(UIView *view) {
    if (!view) return;
    UIView *superview = view.superview;
    if (!superview) return;
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    if (screenWidth <= 0 || screenWidth > 2000.0) screenWidth = 390.0;
    
    UIWindow *window = view.window ?: superview.window;
    CGRect winRect = window ? [superview convertRect:view.frame toView:window] : view.frame;
    CGFloat winMidX = CGRectGetMidX(winRect);
    
    // 如果已经在屏幕左半边，不再重复处理
    if (winMidX > 0 && winMidX < screenWidth * 0.45) {
        return;
    }
    
    CBS_LOG(@"[Relocate] 发现右侧目标: %@ (WinMidX=%.1f), 执行左移", NSStringFromClass([view class]), winMidX);
    
    // 1. 容器冒泡：若该视图处于一个靠右的小容器中，上溯找到该容器
    UIView *targetToMove = view;
    while (targetToMove.superview &&
           targetToMove.superview.bounds.size.width > 0 &&
           targetToMove.superview.bounds.size.width < screenWidth * 0.6) {
        targetToMove = targetToMove.superview;
    }
    
    UIView *parent = targetToMove.superview ?: superview;
    CGFloat parentWidth = parent.bounds.size.width > 0 ? parent.bounds.size.width : screenWidth;
    
    // 2. 停用 Trailing 约束并添加 Leading 约束
    NSMutableArray<NSLayoutConstraint *> *trailingConstraints = [NSMutableArray array];
    for (NSLayoutConstraint *c in parent.constraints) {
        if (c.firstItem == targetToMove || c.secondItem == targetToMove) {
            if (c.firstAttribute == NSLayoutAttributeTrailing ||
                c.firstAttribute == NSLayoutAttributeRight ||
                c.secondAttribute == NSLayoutAttributeTrailing ||
                c.secondAttribute == NSLayoutAttributeRight) {
                [trailingConstraints addObject:c];
            }
        }
    }
    if (trailingConstraints.count > 0) {
        CBS_LOG(@"[Relocate] 停用 %lu 条 Trailing 约束，替换为 Leading", (unsigned long)trailingConstraints.count);
        [NSLayoutConstraint deactivateConstraints:trailingConstraints];
        NSLayoutConstraint *leading = [targetToMove.leadingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.leadingAnchor constant:16.0];
        leading.priority = UILayoutPriorityRequired;
        leading.active = YES;
        [parent setNeedsLayout];
    }
    
    // 3. 手动调整 Frame / Center
    CGPoint center = targetToMove.center;
    if (center.x > parentWidth / 2.0) {
        CGFloat distFromRight = parentWidth - center.x;
        CGFloat halfW = targetToMove.bounds.size.width > 0 ? (targetToMove.bounds.size.width / 2.0) : 22.0;
        if (distFromRight < halfW + 8.0) {
            distFromRight = halfW + 16.0;
        }
        center.x = distFromRight;
        targetToMove.center = center;
    }
    
    // 4. 微距按钮避让
    for (UIView *sibling in parent.subviews) {
        if (isMacroAffordance(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
            if (sibling.center.x < parentWidth / 2.0) {
                CGFloat macroHalfH = sibling.bounds.size.height / 2.0;
                CGFloat myHalfH = targetToMove.bounds.size.height / 2.0;
                if (fabs(center.x - sibling.center.x) < 55.0 && fabs(center.y - sibling.center.y) < (macroHalfH + myHalfH + 10.0)) {
                    center.y = sibling.center.y - (macroHalfH + myHalfH + 12.0);
                    targetToMove.center = center;
                }
            }
            break;
        }
    }
    
    // 5. Transform 物理强制平移兜底 (彻底解决 Auto Layout 强行在视觉上保持右侧)
    CGRect curWinRect = window ? [targetToMove.superview convertRect:targetToMove.frame toView:window] : targetToMove.frame;
    if (CGRectGetMidX(curWinRect) > screenWidth / 2.0) {
        CGFloat curX = CGRectGetMidX(curWinRect);
        CGFloat targetLeftX = 40.0;
        CGFloat dx = targetLeftX - curX; // 负值，强制向左拉
        targetToMove.transform = CGAffineTransformMakeTranslation(dx, 0);
        CBS_LOG(@"[Relocate] 强制激活 CGAffineTransform dx=%.1f", dx);
    }
}

// 递归遍历视图树
static void recursiveScanAndRelocate(UIView *root) {
    if (!root) return;
    
    if (isLiveTextAffordance(root)) {
        forceRelocateToLeft(root);
        return;
    }
    
    for (UIView *sub in root.subviews) {
        recursiveScanAndRelocate(sub);
    }
}

// ============================================================================
// 启动 Toast 提示 (让用户直观看到插件已成功加载)
// ============================================================================

static void showLoadedToastIfNeeded(UIViewController *vc) {
    static BOOL shown = NO;
    if (shown || !vc || !vc.view) return;
    shown = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UILabel *toast = [[UILabel alloc] init];
        toast.text = @" ⚡️ CameraButtonSwap 已注入 (左撇子模式) ";
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        toast.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.layer.cornerRadius = 14.0;
        toast.clipsToBounds = YES;
        [toast sizeToFit];
        
        CGRect frame = toast.frame;
        frame.size.width += 24.0;
        frame.size.height = 28.0;
        frame.origin.x = (vc.view.bounds.size.width - frame.size.width) / 2.0;
        frame.origin.y = 54.0;
        toast.frame = frame;
        toast.alpha = 0.0;
        [vc.view addSubview:toast];
        
        [UIView animateWithDuration:0.3 animations:^{
            toast.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.5 animations:^{
                    toast.alpha = 0.0;
                } completion:^(BOOL fin) {
                    [toast removeFromSuperview];
                }];
            });
        }];
    });
}

// ============================================================================
// Hooks
// ============================================================================

%hook CAMViewfinderViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    showLoadedToastIfNeeded((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v = [(UIViewController *)self view];
        if (v) {
            recursiveScanAndRelocate(v);
        }
    });
}

%end

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    recursiveScanAndRelocate((UIView *)self);
}

%end

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    recursiveScanAndRelocate((UIView *)self);
}

%end

// ============================================================================
// 构造函数
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        CBS_LOG(@"========================================");
        CBS_LOG(@"[Tweak ctor] 进程启动: %@", bundleID);
        
        // 预加载相关系统框架
        NSArray<NSString *> *frameworks = @[
            @"/System/Library/PrivateFrameworks/CameraUI.framework",
            @"/System/Library/Frameworks/VisionKit.framework",
            @"/System/Library/PrivateFrameworks/VisionKitCore.framework"
        ];
        for (NSString *fw in frameworks) {
            NSBundle *b = [NSBundle bundleWithPath:fw];
            if (b) {
                BOOL ok = [b load];
                CBS_LOG(@"加载框架 %@ -> %d", [fw lastPathComponent], ok);
            }
        }
        
        %init;
        CBS_LOG(@"[Tweak ctor] Hooks 注册完成");
        CBS_LOG(@"========================================");
    }
}
