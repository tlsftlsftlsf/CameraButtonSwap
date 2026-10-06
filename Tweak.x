/*
 * CameraButtonSwap - iOS 15.4.1 越狱插件 (无根越狱支持)
 * 功能：将系统相机 App 中的「扫描文本 (Live Text / CAMImageAnalysisButton)」按钮移动到左侧，方便左撇子单手操作。
 * 
 * 核心类 (iOS 15 CameraUI.framework):
 *   - CAMImageAnalysisButton: 扫描文本/实况文本按钮 (真实私有类名)
 *   - CAMAutoMacroButton: 微距控制按钮
 *   - CAMFullscreenViewfinder: 全屏取景器容器
 *   - CAMBottomBar: 底部操作栏容器
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define CBS_LOG(fmt, ...) NSLog(@"[CameraButtonSwap] " fmt, ##__VA_ARGS__)

// ============================================================================
// 前向声明 CameraUI 私有类
// ============================================================================

@interface CAMAutoMacroButton : UIControl
@end

@interface CAMImageAnalysisButton : UIControl
@end

@interface CAMFullscreenViewfinder : UIView
@property(nonatomic, readonly) CAMAutoMacroButton *autoMacroButton;
@property(nonatomic, readonly) CAMImageAnalysisButton *imageAnalysisButton;
@end

@interface CAMBottomBar : UIView
@end

@interface CAMViewfinderViewController : UIViewController
@end

// ============================================================================
// 核心定位函数：将文本扫描按钮移动到屏幕左侧（并自动避让微距按钮）
// ============================================================================

static void adjustButtonToLeftSide(UIView *button, UIView *container) {
    if (!button) return;
    
    UIView *superview = container ?: button.superview;
    if (!superview) return;
    
    CGFloat superWidth = superview.bounds.size.width;
    if (superWidth <= 0 || superWidth > 2000.0) {
        superWidth = [UIScreen mainScreen].bounds.size.width;
    }
    
    CGPoint currentCenter = button.center;
    CGSize buttonSize = button.bounds.size;
    CGFloat halfW = (buttonSize.width > 0) ? (buttonSize.width / 2.0) : 22.0;
    CGFloat halfH = (buttonSize.height > 0) ? (buttonSize.height / 2.0) : 22.0;
    
    // 如果按钮在右半屏，则镜像计算左侧对应位置
    if (currentCenter.x > superWidth / 2.0) {
        CGFloat distFromRight = superWidth - currentCenter.x;
        if (distFromRight < halfW + 8.0) {
            distFromRight = halfW + 16.0;
        }
        currentCenter.x = distFromRight;
    } else {
        // 如果原本已经在左侧（可能已经调整过），确保至少有 16pt 左边距
        if (currentCenter.x < halfW + 8.0) {
            currentCenter.x = halfW + 16.0;
        }
    }
    
    // 检查同层级是否有显示的微距按钮 (CAMAutoMacroButton)
    // 如果微距按钮也在左侧并与文本按钮在 Y 轴靠近，将文本按钮向上移动避让
    UIView *macroView = nil;
    if ([superview respondsToSelector:@selector(autoMacroButton)]) {
        macroView = [superview performSelector:@selector(autoMacroButton)];
    }
    if (!macroView) {
        for (UIView *sub in superview.subviews) {
            if ([sub isKindOfClass:objc_getClass("CAMAutoMacroButton")]) {
                macroView = sub;
                break;
            }
        }
    }
    
    if (macroView && !macroView.hidden && macroView.alpha > 0.05) {
        CGFloat macroX = macroView.center.x;
        CGFloat macroY = macroView.center.y;
        CGFloat macroHalfH = (macroView.bounds.size.height > 0) ? (macroView.bounds.size.height / 2.0) : 22.0;
        
        // 微距按钮在左侧
        if (macroX < superWidth / 2.0) {
            // 如果两者中心距离太近（发生重叠）
            if (fabs(currentCenter.x - macroX) < 50.0 && fabs(currentCenter.y - macroY) < (macroHalfH + halfH + 8.0)) {
                // 移动到微距按钮正上方，保留 12pt 间距
                currentCenter.y = macroY - (macroHalfH + halfH + 12.0);
            }
        }
    }
    
    // 应用新位置
    button.center = currentCenter;
}

// 递归查找 CAMImageAnalysisButton
static UIView *findImageAnalysisButtonRecursive(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:objc_getClass("CAMImageAnalysisButton")]) {
        return root;
    }
    for (UIView *sub in root.subviews) {
        UIView *found = findImageAnalysisButtonRecursive(sub);
        if (found) return found;
    }
    return nil;
}

// ============================================================================
// Hook: CAMImageAnalysisButton 直接拦截位置变更
// ============================================================================

%hook CAMImageAnalysisButton

- (void)setCenter:(CGPoint)center {
    static BOOL isAdjusting = NO;
    if (!isAdjusting) {
        isAdjusting = YES;
        CGFloat superWidth = self.superview ? self.superview.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
        if (superWidth > 0 && center.x > superWidth / 2.0) {
            CGFloat distFromRight = superWidth - center.x;
            CGFloat halfW = self.bounds.size.width > 0 ? (self.bounds.size.width / 2.0) : 22.0;
            if (distFromRight < halfW + 8.0) {
                distFromRight = halfW + 16.0;
            }
            center.x = distFromRight;
        }
        %orig(center);
        
        // 避让微距按钮
        if (self.superview) {
            adjustButtonToLeftSide(self, self.superview);
        }
        isAdjusting = NO;
    } else {
        %orig(center);
    }
}

- (void)setFrame:(CGRect)frame {
    static BOOL isAdjusting = NO;
    if (!isAdjusting) {
        isAdjusting = YES;
        CGFloat superWidth = self.superview ? self.superview.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
        if (superWidth > 0 && frame.origin.x > superWidth / 2.0) {
            CGFloat rightMargin = superWidth - CGRectGetMaxX(frame);
            if (rightMargin < 8.0 || rightMargin > superWidth / 3.0) {
                rightMargin = 16.0;
            }
            frame.origin.x = rightMargin;
        }
        %orig(frame);
        
        if (self.superview) {
            adjustButtonToLeftSide(self, self.superview);
        }
        isAdjusting = NO;
    } else {
        %orig(frame);
    }
}

%end

// ============================================================================
// Hook: CAMFullscreenViewfinder (全屏取景器布局)
// ============================================================================

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = nil;
    @try {
        btn = [self valueForKey:@"_imageAnalysisButton"];
    } @catch (id e) {
        btn = nil;
    }
    
    if (!btn && [self respondsToSelector:@selector(imageAnalysisButton)]) {
        btn = [self imageAnalysisButton];
    }
    
    if (btn) {
        adjustButtonToLeftSide(btn, self);
    }
}

%end

// ============================================================================
// Hook: CAMBottomBar (底部栏布局)
// ============================================================================

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = nil;
    UIView *overlay = nil;
    @try {
        btn = [self valueForKey:@"_imageAnalysisButton"];
    } @catch (id e) {
        btn = nil;
    }
    @try {
        overlay = [self valueForKey:@"_imageAnalysisButtonBackgroundOverlay"];
    } @catch (id e) {
        overlay = nil;
    }
    
    if (btn) {
        adjustButtonToLeftSide(btn, self);
        if (overlay) {
            overlay.center = btn.center;
        }
    }
}

%end

// ============================================================================
// Hook: CAMViewfinderViewController (主控制器，兜底保障)
// ============================================================================

%hook CAMViewfinderViewController

- (void)viewDidLayoutSubviews {
    %orig;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *root = self.view;
        if (!root) return;
        
        UIView *btn = findImageAnalysisButtonRecursive(root);
        if (btn) {
            adjustButtonToLeftSide(btn, btn.superview);
        }
    });
}

%end

// ============================================================================
// 构造函数
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        CBS_LOG(@"正在加载... 当前进程: %@", bundleID);
        
        // 动态加载 CameraUI.framework，确保所有目标类在 %init 前注册入 ObjC 运行时
        NSBundle *cameraBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CameraUI.framework"];
        if (cameraBundle) {
            BOOL loaded = [cameraBundle load];
            CBS_LOG(@"CameraUI.framework 加载状态: %d", loaded);
        }
        
        %init;
        CBS_LOG(@"✅ 插件 Hook 初始化成功！扫描文本按钮将自动移至左侧");
    }
}
