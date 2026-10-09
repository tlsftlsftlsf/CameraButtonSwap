/*
 * CameraButtonSwap - iOS 15.0 ~ 17.3.1 (v2.5.0 正式纯净版)
 *
 * 核心优化：
 *   1. 深度保护 VisionKit 文本交互与选择系统：
 *      - 严格限定仅 Hook 独立按钮实体（CAMImageAnalysisButton / VKImageAnalysisButton / VKCCornerLookupButton），
 *        尺寸严格限制在 90x90 pt 以内。
 *      - 严格排除 VKCImageAnalysisBaseView / VKCImageAnalysisView / VKCTextSelectionView / VKCActionInfoView 等
 *        文本分析画布与交互选择视图，彻底解决「点击实况文本按钮后无法选中文字」的问题！
 *   2. 纯净无干扰体验：
 *      - 移除高频扫描看门狗定时器与全局递归视图扫描；
 *      - 移除侵入式 UIAlert 弹窗与黑金胶囊 HUD（即开即拍零干扰）；
 *      - 保留智能避让微距按钮逻辑。
 *   3. 零 Substrate 依赖：纯原生 Objective-C runtime 交换，Ad-hoc 签名强化，原生 iOS 17.3.1 SDK 编译。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

#define CBS_TAG @"[CameraButtonSwap-v2.5]"

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
// 多通道日志与辅助函数
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

// 硬件触感震动反馈（注入提示，轻触感）
static void triggerHapticFeedback(void) {
    AudioServicesPlaySystemSound(1519);
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
// 元素识别函数（精细白名单 + 严格尺寸限制，彻底保护文本选择交互层）
// ============================================================================

static BOOL isMacroElement(UIView *view) {
    if (!view) return NO;
    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"AutoMacro"] ||
           [className containsString:@"MacroButton"] ||
           [className containsString:@"MacroControl"];
}

static BOOL isLiveTextButton(UIView *view) {
    if (!view) return NO;
    
    // 1. 严格尺寸保护：按钮绝对不能超过 90x90 pt（文本分析与选择交互层通常覆盖整个取景画面，宽度远大于 100 pt）
    CGSize bSize = view.bounds.size;
    if (bSize.width > 90.0 || bSize.height > 90.0) return NO;
    CGSize fSize = view.frame.size;
    if (fSize.width > 90.0 || fSize.height > 90.0) return NO;
    
    NSString *className = NSStringFromClass([view class]);
    
    // 2. 绝对黑名单：坚决不碰 VisionKit 的文本分析画布、遮罩层、交互层及选择视图
    if ([className containsString:@"BaseView"] ||
        [className containsString:@"Overlay"] ||
        [className containsString:@"Selection"] ||
        [className containsString:@"Interaction"] ||
        [className containsString:@"ActionInfo"] ||
        [className containsString:@"Analyzer"] ||
        [className containsString:@"Detector"] ||
        [className containsString:@"Highlight"] ||
        [className containsString:@"Result"] ||
        [className containsString:@"Scanner"] ||
        [className containsString:@"VisualSearch"]) {
        return NO;
    }
    
    // 3. 必须是明确的按钮类（CAMImageAnalysisButton / VKImageAnalysisButton / VKCCornerLookupButton）
    if ([className isEqualToString:@"CAMImageAnalysisButton"] ||
        [className isEqualToString:@"VKImageAnalysisButton"] ||
        [className isEqualToString:@"VKCCornerLookupButton"] ||
        [className hasSuffix:@"ImageAnalysisButton"]) {
        return YES;
    }
    
    // 4. 辅助特征：带有 viewfinder 图标的微型 UIButton/UIControl
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        UIImage *img = [b currentImage] ?: [b imageForState:UIControlStateNormal];
        if (img && [[img description] containsString:@"viewfinder"]) {
            return YES;
        }
    }
    
    return NO;
}

// ============================================================================
// 精准重定位函数：只移动按钮本身，绝不牵连父容器或交互层
// ============================================================================

static void relocateLiveTextButton(UIView *button) {
    if (!button || !button.superview) return;
    if (!isLiveTextButton(button)) return;
    
    UIView *parent = button.superview;
    CGFloat parentW = parent.bounds.size.width;
    if (parentW <= 0) {
        parentW = [UIScreen mainScreen].bounds.size.width;
    }
    if (parentW <= 0) parentW = 390.0;
    
    // 如果已经在屏幕左半侧（origin.x < parentW * 0.45），说明已经位于左侧，不需要重复移动
    if (button.frame.origin.x < parentW * 0.45 && button.center.x < parentW * 0.45) {
        return;
    }
    
    writeCBSLog(@"[Relocate] 移动实况文本按钮到左侧: %@ (原 x=%.1f)", NSStringFromClass([button class]), button.frame.origin.x);
    
    CGRect f = button.frame;
    CGFloat rightMargin = parentW - (f.origin.x + f.size.width);
    if (rightMargin < 12.0) rightMargin = 16.0;
    if (rightMargin > 80.0) rightMargin = 20.0;
    
    f.origin.x = rightMargin;
    
    // 智能避让微距按钮（如果在左下角同时显示微距按钮）
    for (UIView *sibling in parent.subviews) {
        if (sibling != button && isMacroElement(sibling) && !sibling.hidden && sibling.alpha > 0.05) {
            if (sibling.frame.origin.x < parentW / 2.0) {
                if (CGRectIntersectsRect(f, CGRectInset(sibling.frame, -10, -10))) {
                    f.origin.y = sibling.frame.origin.y - f.size.height - 12.0;
                }
            }
            break;
        }
    }
    
    button.frame = f;
    button.center = CGPointMake(f.origin.x + f.size.width / 2.0, f.origin.y + f.size.height / 2.0);
}

// ============================================================================
// 精准类级 Hooks (拦截 setFrame 与 setCenter)
// ============================================================================

%hook CAMImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

%end

%hook VKImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

%end

%hook VKCCornerLookupButton

- (void)setFrame:(CGRect)frame {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    relocateLiveTextButton((UIView *)self);
}

%end

// ============================================================================
// 宿主容器布局 Hooks (CAMFullscreenViewfinder & CAMBottomBar)
// ============================================================================

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = getIvarView(self, "_imageAnalysisButton");
    if (!btn) {
        @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
    }
    if (btn && !btn.hidden && btn.alpha > 0.01) {
        relocateLiveTextButton(btn);
    }
}

%end

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    
    UIView *btn = getIvarView(self, "_imageAnalysisButton");
    if (!btn) {
        @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
    }
    if (btn && !btn.hidden && btn.alpha > 0.01) {
        relocateLiveTextButton(btn);
    }
}

%end

// ============================================================================
// 视图动态挂载监听（仅对符合严格按钮特征的子视图响应）
// ============================================================================

%hook UIView

- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (isLiveTextButton(subview)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            relocateLiveTextButton(subview);
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
        
        // 预加载系统私有框架
        dlopen("/System/Library/PrivateFrameworks/CameraUI.framework/CameraUI", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/VisionKitCore.framework/VisionKitCore", RTLD_NOW);
        dlopen("/System/Library/Frameworks/VisionKit.framework/VisionKit", RTLD_NOW);
        
        %init;
        writeCBSLog(@"[Ctor] Hooks 注册完毕");
    }
}
