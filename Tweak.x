/*
 * CameraButtonSwap - iOS 17 专门适配版 (兼容 iOS 15 ~ 17.x)
 * 功能：将系统相机 App 中的「扫描文本 / 实况文本」按钮移动到左侧，方便左撇子单手操作。
 *
 * iOS 17 深度适配要点：
 *   1. 覆盖 iOS 17 最新 VisionKitCore 真实类名：
 *      - VKCImageAnalysisButton
 *      - VKCCornerLookupButton
 *      - VKCActionInfoView / VKCActionInfoContainer
 *      - CAMImageAnalysisButton (CameraUI)
 *   2. Auto Layout 约束反转机制：
 *      - iOS 17 按钮采用 Auto Layout 强约束定位在 Trailing (右侧)
 *      - 仅修改 frame/center 会被系统布局引擎重置；本插件自动禁用 Trailing 约束并激活 Leading (左侧) 约束
 *   3. 容器冒泡检测：
 *      - 若按钮被包裹在右下角的小容器中，自动上溯找到顶级右侧容器并将其整体移至左侧
 *   4. 微距按钮智能避让：
 *      - 保持与左下角微距花朵按钮纵向间距，防止重叠
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define CBS_LOG(fmt, ...) NSLog(@"[CameraButtonSwap-iOS17] " fmt, ##__VA_ARGS__)

// ============================================================================
// 辅助判断函数：识别是否是实况文本/扫描按钮或其容器
// ============================================================================

static BOOL isLiveTextClass(Class cls) {
    if (!cls) return NO;
    const char *name = class_getName(cls);
    if (!name) return NO;
    
    // 匹配 iOS 15/16/17 所有已知及潜在相关类名
    if (strstr(name, "ImageAnalysisButton") != NULL) return YES;
    if (strstr(name, "CornerLookupButton") != NULL) return YES;
    if (strstr(name, "ActionInfoView") != NULL) return YES;
    if (strstr(name, "ActionInfoContainer") != NULL) return YES;
    if (strstr(name, "LiveText") != NULL) return YES;
    if (strstr(name, "ScanText") != NULL) return YES;
    if (strstr(name, "TextRecognition") != NULL) return YES;
    
    return NO;
}

static BOOL isLiveTextView(UIView *view) {
    if (!view) return NO;
    
    // 1. 类名匹配
    if (isLiveTextClass([view class])) return YES;
    
    // 2. accessibilityIdentifier 匹配
    NSString *aid = view.accessibilityIdentifier;
    if (aid) {
        NSString *lower = [aid lowercaseString];
        if ([lower containsString:@"image-analysis"] ||
            [lower containsString:@"corner-lookup"] ||
            [lower containsString:@"livetext"] ||
            [lower containsString:@"live-text"] ||
            [lower containsString:@"scantext"] ||
            [lower containsString:@"scan-text"]) {
            return YES;
        }
    }
    
    // 3. accessibilityLabel 匹配
    NSString *label = view.accessibilityLabel;
    if (label) {
        if ([label containsString:@"文本"] ||
            [label containsString:@"实况"] ||
            [label containsString:@"扫描"] ||
            [label localizedCaseInsensitiveContainsString:@"live text"] ||
            [label localizedCaseInsensitiveContainsString:@"scan text"]) {
            return YES;
        }
    }
    
    return NO;
}

static BOOL isMacroButton(UIView *view) {
    if (!view) return NO;
    const char *name = class_getName([view class]);
    if (name) {
        if (strstr(name, "AutoMacroButton") != NULL) return YES;
        if (strstr(name, "MacroButton") != NULL) return YES;
        if (strstr(name, "MacroControl") != NULL) return YES;
    }
    return NO;
}

// ============================================================================
// 核心定位引擎：将目标视图（或其父级右侧容器）移动到屏幕左侧
// ============================================================================

static void relocateViewToLeft(UIView *targetView) {
    if (!targetView) return;
    
    UIView *superview = targetView.superview;
    if (!superview) return;
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    if (screenWidth <= 0 || screenWidth > 2000.0) screenWidth = 390.0;
    
    // 获取在屏幕全局坐标系下的中心点
    UIWindow *window = targetView.window ?: superview.window;
    CGFloat midX = 0;
    if (window) {
        CGRect windowRect = [superview convertRect:targetView.frame toView:window];
        midX = CGRectGetMidX(windowRect);
    } else {
        midX = CGRectGetMidX(targetView.frame);
    }
    
    // 如果已经在屏幕左半边，无需重复调整
    if (midX > 0 && midX < screenWidth / 2.0) {
        return;
    }
    
    CBS_LOG(@"正在将 %@ 移动至屏幕左侧 (当前 Window X=%.1f)",
            NSStringFromClass([targetView class]), midX);
    
    // 1. 容器冒泡：如果当前视图被包裹在一个自身就靠右的小容器中，需要移动该外层容器
    UIView *viewToMove = targetView;
    while (viewToMove.superview &&
           viewToMove.superview.bounds.size.width > 0 &&
           viewToMove.superview.bounds.size.width < screenWidth * 0.65) {
        viewToMove = viewToMove.superview;
    }
    
    UIView *parent = viewToMove.superview;
    if (!parent) return;
    
    // 2. iOS 17 Auto Layout 约束处理：
    // 禁用所有 Trailing/Right 约束，替换为 Leading/Left 约束
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
    for (NSLayoutConstraint *c in viewToMove.constraints) {
        if (c.firstAttribute == NSLayoutAttributeTrailing ||
            c.firstAttribute == NSLayoutAttributeRight) {
            [trailingConstraints addObject:c];
        }
    }
    
    if (trailingConstraints.count > 0) {
        CBS_LOG(@"检测到 %lu 条 Trailing 约束，正在替换为 Leading 约束", (unsigned long)trailingConstraints.count);
        [NSLayoutConstraint deactivateConstraints:trailingConstraints];
        
        NSLayoutConstraint *leading = [viewToMove.leadingAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.leadingAnchor constant:16.0];
        leading.priority = UILayoutPriorityRequired;
        leading.active = YES;
        
        [parent setNeedsLayout];
        [parent layoutIfNeeded];
    }
    
    // 3. 手动 frame / center 调整（针对非 AutoLayout 或混合布局兜底）
    CGFloat parentWidth = parent.bounds.size.width;
    if (parentWidth <= 0 || parentWidth > 2000.0) parentWidth = screenWidth;
    
    CGPoint center = viewToMove.center;
    if (center.x > parentWidth / 2.0) {
        CGFloat distFromRight = parentWidth - center.x;
        CGFloat halfW = viewToMove.bounds.size.width > 0 ? (viewToMove.bounds.size.width / 2.0) : 22.0;
        if (distFromRight < halfW + 8.0) {
            distFromRight = halfW + 16.0;
        }
        center.x = distFromRight;
    }
    
    // 4. 微距按钮智能避让（若左下角有微距花朵按钮，上移避免重叠）
    UIView *macroView = nil;
    for (UIView *sibling in parent.subviews) {
        if (isMacroButton(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
            macroView = sibling;
            break;
        }
    }
    if (macroView) {
        CGFloat macroX = macroView.center.x;
        CGFloat macroY = macroView.center.y;
        CGFloat macroHalfH = macroView.bounds.size.height > 0 ? (macroView.bounds.size.height / 2.0) : 22.0;
        CGFloat myHalfH = viewToMove.bounds.size.height > 0 ? (viewToMove.bounds.size.height / 2.0) : 22.0;
        
        if (macroX < parentWidth / 2.0) {
            if (fabs(center.x - macroX) < 55.0 && fabs(center.y - macroY) < (macroHalfH + myHalfH + 10.0)) {
                center.y = macroY - (macroHalfH + myHalfH + 12.0);
            }
        }
    }
    
    viewToMove.center = center;
}

// 递归查找整个视图树中的实况文本元素
static void findAndRelocateAllLiveTextViews(UIView *root) {
    if (!root) return;
    
    if (isLiveTextView(root)) {
        relocateViewToLeft(root);
        return;
    }
    
    for (UIView *sub in root.subviews) {
        findAndRelocateAllLiveTextViews(sub);
    }
}

// ============================================================================
// 动态 Hook 宏：同时支持静态类名与运行时未知类
// ============================================================================

static void hookClassMethodsForRepositioning(Class targetClass) {
    if (!targetClass) return;
    
    CBS_LOG(@"正在为类 %@ 安装动态 Hook", NSStringFromClass(targetClass));
    
    // 1. Hook layoutSubviews
    SEL selLayout = @selector(layoutSubviews);
    Method mLayout = class_getInstanceMethod(targetClass, selLayout);
    if (mLayout) {
        void (*origLayout)(id, SEL) = (void (*)(id, SEL))method_getImplementation(mLayout);
        IMP newLayout = imp_implementationWithBlock(^(id selfObj) {
            origLayout(selfObj, selLayout);
            relocateViewToLeft((UIView *)selfObj);
        });
        class_replaceMethod(targetClass, selLayout, newLayout, method_getTypeEncoding(mLayout));
    }
    
    // 2. Hook didMoveToWindow
    SEL selWindow = @selector(didMoveToWindow);
    Method mWindow = class_getInstanceMethod(targetClass, selWindow);
    if (mWindow) {
        void (*origWindow)(id, SEL) = (void (*)(id, SEL))method_getImplementation(mWindow);
        IMP newWindow = imp_implementationWithBlock(^(id selfObj) {
            origWindow(selfObj, selWindow);
            dispatch_async(dispatch_get_main_queue(), ^{
                relocateViewToLeft((UIView *)selfObj);
            });
        });
        class_replaceMethod(targetClass, selWindow, newWindow, method_getTypeEncoding(mWindow));
    }
    
    // 3. Hook setHidden:
    SEL selHidden = @selector(setHidden:);
    Method mHidden = class_getInstanceMethod(targetClass, selHidden);
    if (mHidden) {
        void (*origHidden)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(mHidden);
        IMP newHidden = imp_implementationWithBlock(^(id selfObj, BOOL hidden) {
            origHidden(selfObj, selHidden, hidden);
            if (!hidden) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    relocateViewToLeft((UIView *)selfObj);
                });
            }
        });
        class_replaceMethod(targetClass, selHidden, newHidden, method_getTypeEncoding(mHidden));
    }
}

// ============================================================================
// Logos Hook: 取景器与视图控制器生命周期拦截 (全局兜底保障)
// ============================================================================

%hook CAMViewfinderViewController

- (void)viewDidLayoutSubviews {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v = [(UIViewController *)self view];
        if (v) {
            findAndRelocateAllLiveTextViews(v);
        }
    });
}

%end

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    findAndRelocateAllLiveTextViews((UIView *)self);
}

%end

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    findAndRelocateAllLiveTextViews((UIView *)self);
}

%end

// ============================================================================
// 构造函数：启动时自动扫描并注册所有匹配的类
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        CBS_LOG(@"====== 插件加载 ======");
        CBS_LOG(@"当前注入进程: %@", bundleID);
        
        // 强制预加载相关框架
        NSArray<NSString *> *frameworkPaths = @[
            @"/System/Library/PrivateFrameworks/CameraUI.framework",
            @"/System/Library/Frameworks/VisionKit.framework",
            @"/System/Library/PrivateFrameworks/VisionKitCore.framework"
        ];
        
        for (NSString *path in frameworkPaths) {
            NSBundle *b = [NSBundle bundleWithPath:path];
            if (b) {
                BOOL ok = [b load];
                CBS_LOG(@"加载框架 %@ -> %d", [path lastPathComponent], ok);
            }
        }
        
        // 初始化 Logos 声明的 Hooks
        %init;
        
        // 运行时扫描：自动匹配所有带有 ImageAnalysis / CornerLookup / ActionInfo 特征的类
        int numClasses = objc_getClassList(NULL, 0);
        if (numClasses > 0) {
            Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
            numClasses = objc_getClassList(classes, numClasses);
            
            for (int i = 0; i < numClasses; i++) {
                Class c = classes[i];
                if (isLiveTextClass(c) && [c isSubclassOfClass:[UIView class]]) {
                    hookClassMethodsForRepositioning(c);
                }
            }
            free(classes);
        }
        
        CBS_LOG(@"====== 插件初始化成功 (iOS 17 专属适配已启用) ======");
    }
}
