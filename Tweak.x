/*
 * CameraButtonSwap - iOS 15.0 ~ 17.3.1 (v2.6.1 彻底解决重入死循环闪退版)
 *
 * 核心升级与修复：
 *   1. 彻底解决重入递归闪退 (Eliminate Re-entrancy Stack Overflow Crash)：
 *      - 增加全局重入安全锁 isRelocating 与坐标位移阈值比对，彻底杜绝 setFrame / setCenter 自身调用的死循环与栈溢出！
 *      - 拖动结束保存坐标后，平滑更新布局，相机绝对不再闪退。
 *   2. 屏幕长按自由拖拽与持久化记忆 (Custom Drag & Drop)：
 *      - 长按实况文本按钮 0.45 秒触发物理震动反馈，即可随心拖动到屏幕任意顺手位置；
 *      - 松开手指自动记忆该位置（自动保存至 NSUserDefaults），下次打开相机或任何时候均在专属位置；
 *      - 双击按钮或拖回左下角即可一键恢复默认推荐位置；
 *      - 拖动过程中带有顶部轻量胶囊提示。
 *   3. 深度保护 VisionKit 文本交互与选择系统：
 *      - 严格限定仅 Hook 独立按钮实体（CAMImageAnalysisButton / VKImageAnalysisButton / VKCCornerLookupButton），
 *        尺寸严格限制在 90x90 pt 以内。
 *      - 严格排除 VKCImageAnalysisBaseView / VKCImageAnalysisView / VKCTextSelectionView / VKCActionInfoView 等
 *        文本分析画布与交互选择视图，确保划词、选中文本 100% 灵敏顺畅！
 *   4. 零 Substrate 依赖：纯原生 Objective-C runtime 交换，Ad-hoc 签名强化，原生 iOS 17.3.1 SDK 直编。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

#define CBS_TAG @"[CameraButtonSwap-v2.6.1]"

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

// 硬件触感震动反馈（轻触感）
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

// 顶部轻量浮动提示胶囊
static void showTipToast(NSString *text, UIWindow *win) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *targetWin = win;
            if (!targetWin) {
                targetWin = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
            }
            if (!targetWin) return;
            
            static UILabel *activeToast = nil;
            if (activeToast) {
                [activeToast removeFromSuperview];
                activeToast = nil;
            }
            
            UILabel *toast = [[UILabel alloc] init];
            toast.text = [NSString stringWithFormat:@"  %@  ", text];
            toast.textColor = [UIColor whiteColor];
            toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
            toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            toast.textAlignment = NSTextAlignmentCenter;
            toast.layer.cornerRadius = 14.0;
            toast.layer.borderColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.6].CGColor;
            toast.layer.borderWidth = 0.8;
            toast.clipsToBounds = YES;
            [toast sizeToFit];
            
            CGRect f = toast.frame;
            f.size.width += 24.0;
            f.size.height = 28.0;
            f.origin.x = (targetWin.bounds.size.width - f.size.width) / 2.0;
            f.origin.y = 65.0; // 避开刘海/灵动岛
            toast.frame = f;
            toast.alpha = 0.0;
            
            activeToast = toast;
            [targetWin addSubview:toast];
            [targetWin bringSubviewToFront:toast];
            
            [UIView animateWithDuration:0.2 animations:^{
                toast.alpha = 1.0;
            } completion:^(BOOL finished) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        toast.alpha = 0.0;
                    } completion:^(BOOL fin) {
                        [toast removeFromSuperview];
                        if (activeToast == toast) activeToast = nil;
                    }];
                });
            }];
        } @catch (id e) {}
    });
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

// 关联对象 Key 与全局防重入锁
static char kCBSDraggingKey;
static char kCBSGestureAttachedKey;
static BOOL isRelocating = NO; // 核心防重入锁：杜绝 setFrame 递归死循环导致的闪退

static BOOL isButtonDragging(UIView *button) {
    NSNumber *val = objc_getAssociatedObject(button, &kCBSDraggingKey);
    return [val boolValue];
}

static void setButtonDragging(UIView *button, BOOL dragging) {
    objc_setAssociatedObject(button, &kCBSDraggingKey, @(dragging), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ============================================================================
// 手势管理器：负责长按自由拖拽与双击复位
// ============================================================================

static void relocateLiveTextButton(UIView *button);

@interface CBSDragManager : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedManager;
- (void)attachGesturesToButton:(UIView *)button;
@end

@implementation CBSDragManager

+ (instancetype)sharedManager {
    static CBSDragManager *mgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[CBSDragManager alloc] init];
    });
    return mgr;
}

- (void)attachGesturesToButton:(UIView *)button {
    if (!button) return;
    NSNumber *attached = objc_getAssociatedObject(button, &kCBSGestureAttachedKey);
    if ([attached boolValue]) return;
    objc_setAssociatedObject(button, &kCBSGestureAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    button.userInteractionEnabled = YES;
    
    // 1. 长按自由拖拽手势（0.45秒长按触发，避免与正常点击识别冲突）
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressDrag:)];
    longPress.minimumPressDuration = 0.45;
    longPress.allowableMovement = 1000.0; // 触发后允许大范围全屏平滑拖拽
    longPress.delegate = self;
    [button addGestureRecognizer:longPress];
    
    // 2. 双击复位手势（快速连击两次重置回默认推荐位置）
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapReset:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.delegate = self;
    [button addGestureRecognizer:doubleTap];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 拖动时独占手势，防止相机背景取景器滑动切换模式
    return NO;
}

- (void)handleLongPressDrag:(UILongPressGestureRecognizer *)gesture {
    UIView *btn = gesture.view;
    if (!btn || !btn.superview) return;
    UIView *parent = btn.superview;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        setButtonDragging(btn, YES);
        triggerHapticFeedback();
        
        // 放大并提升层级，显示选中反馈
        [parent bringSubviewToFront:btn];
        [UIView animateWithDuration:0.2 animations:^{
            btn.transform = CGAffineTransformMakeScale(1.18, 1.18);
            btn.alpha = 0.9;
        }];
        showTipToast(@"👆 拖动到顺手位置，松开即可保存", btn.window);
    }
    else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint location = [gesture locationInView:parent];
        CGFloat parentW = parent.bounds.size.width;
        CGFloat parentH = parent.bounds.size.height;
        if (parentW <= 100.0) parentW = [UIScreen mainScreen].bounds.size.width;
        if (parentH <= 100.0) parentH = [UIScreen mainScreen].bounds.size.height;
        
        // 边界限制，防止拖出屏幕可视区域
        CGFloat minX = btn.bounds.size.width / 2.0 + 8.0;
        CGFloat maxX = parentW - btn.bounds.size.width / 2.0 - 8.0;
        CGFloat minY = btn.bounds.size.height / 2.0 + 40.0;
        CGFloat maxY = parentH - btn.bounds.size.height / 2.0 - 15.0;
        
        location.x = MAX(minX, MIN(maxX, location.x));
        location.y = MAX(minY, MIN(maxY, location.y));
        
        btn.center = location;
    }
    else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        triggerHapticFeedback();
        
        [UIView animateWithDuration:0.25 animations:^{
            btn.transform = CGAffineTransformIdentity;
            btn.alpha = 1.0;
        }];
        
        CGFloat parentH = parent.bounds.size.height;
        if (parentH <= 100.0) parentH = [UIScreen mainScreen].bounds.size.height;
        
        // 计算坐标边距
        CGFloat marginX = btn.frame.origin.x;
        CGFloat marginYFromBottom = parentH - (btn.frame.origin.y + btn.frame.size.height);
        
        // 如果拖回了左下角极值区（距左边 <= 25 且距底 <= 80），自动恢复为自适应默认模式
        if (marginX <= 25.0 && marginYFromBottom <= 80.0) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_HasCustomPosition"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_CustomMarginX"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_CustomMarginYFromBottom"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            showTipToast(@"🔄 已恢复为默认自适应位置", btn.window);
        } else {
            [[NSUserDefaults standardUserDefaults] setFloat:marginX forKey:@"CBS_CustomMarginX"];
            [[NSUserDefaults standardUserDefaults] setFloat:marginYFromBottom forKey:@"CBS_CustomMarginYFromBottom"];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CBS_HasCustomPosition"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            writeCBSLog(@"[CustomPos] 成功保存自定义位置: marginX=%.1f, marginYFromBottom=%.1f", marginX, marginYFromBottom);
            showTipToast(@"✅ 已记住该位置，下次自动生效", btn.window);
        }
        
        // 关键：保存完成并稳定后再解除拖拽标记
        setButtonDragging(btn, NO);
    }
}

- (void)handleDoubleTapReset:(UITapGestureRecognizer *)gesture {
    UIView *btn = gesture.view;
    if (!btn || !btn.superview) return;
    
    triggerHapticFeedback();
    
    // 清除自定义位置
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_HasCustomPosition"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_CustomMarginX"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_CustomMarginYFromBottom"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    writeCBSLog(@"[CustomPos] 双击重置为默认位置");
    
    [UIView animateWithDuration:0.3 animations:^{
        relocateLiveTextButton(btn);
    }];
    showTipToast(@"🔄 已重置为默认左侧位置", btn.window);
}

@end

// ============================================================================
// 精准重定位函数：防重入安全锁 + 优先应用自定义位置
// ============================================================================

static void relocateLiveTextButton(UIView *button) {
    if (!button || !button.superview) return;
    if (isRelocating) return; // 核心防线：绝对防止递归重入
    if (isButtonDragging(button)) return; // 正在拖拽时不打断
    if (!isLiveTextButton(button)) return;
    
    isRelocating = YES;
    @try {
        // 挂载长按拖拽和双击复位手势
        [[CBSDragManager sharedManager] attachGesturesToButton:button];
        
        UIView *parent = button.superview;
        CGFloat parentW = parent.bounds.size.width;
        CGFloat parentH = parent.bounds.size.height;
        if (parentW <= 100.0) parentW = [UIScreen mainScreen].bounds.size.width;
        if (parentH <= 100.0) parentH = [UIScreen mainScreen].bounds.size.height;
        if (parentW <= 100.0) parentW = 390.0;
        
        // 1. 如果用户已保存自定义位置，直接优先定位到专属位置
        BOOL hasCustom = [[NSUserDefaults standardUserDefaults] boolForKey:@"CBS_HasCustomPosition"];
        if (hasCustom) {
            CGFloat customX = [[NSUserDefaults standardUserDefaults] floatForKey:@"CBS_CustomMarginX"];
            CGFloat customYFromBottom = [[NSUserDefaults standardUserDefaults] floatForKey:@"CBS_CustomMarginYFromBottom"];
            
            // 合法性校验：如果保存的值越界，则清除并回退到默认
            if (customX > 0 && customX < parentW - 20.0 && customYFromBottom > 0 && customYFromBottom < parentH - 50.0) {
                CGRect f = button.frame;
                f.origin.x = customX;
                f.origin.y = parentH - customYFromBottom - f.size.height;
                
                // 屏幕可视区域保护
                if (f.origin.x < 8.0) f.origin.x = 8.0;
                if (f.origin.x > parentW - f.size.width - 8.0) f.origin.x = parentW - f.size.width - 8.0;
                if (f.origin.y < 40.0) f.origin.y = 40.0;
                if (f.origin.y > parentH - f.size.height - 12.0) f.origin.y = parentH - f.size.height - 12.0;
                
                // 仅当坐标产生有效位移时才赋值，防止多余布局触发
                if (fabs(button.frame.origin.x - f.origin.x) > 1.0 || fabs(button.frame.origin.y - f.origin.y) > 1.0) {
                    button.frame = f;
                    button.center = CGPointMake(f.origin.x + f.size.width / 2.0, f.origin.y + f.size.height / 2.0);
                }
                return;
            } else {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CBS_HasCustomPosition"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
        
        // 2. 如果未自定义位置，执行默认推荐左置（避让微距按钮）
        if (button.frame.origin.x < parentW * 0.45 && button.center.x < parentW * 0.45) {
            return;
        }
        
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
        
        if (fabs(button.frame.origin.x - f.origin.x) > 1.0 || fabs(button.frame.origin.y - f.origin.y) > 1.0) {
            button.frame = f;
            button.center = CGPointMake(f.origin.x + f.size.width / 2.0, f.origin.y + f.size.height / 2.0);
        }
    } @finally {
        isRelocating = NO;
    }
}

// ============================================================================
// 精准类级 Hooks (防重入拦截 setFrame 与 setCenter)
// ============================================================================

%hook CAMImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

- (void)setCenter:(CGPoint)center {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

%end

%hook VKImageAnalysisButton

- (void)setFrame:(CGRect)frame {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

- (void)setCenter:(CGPoint)center {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

%end

%hook VKCCornerLookupButton

- (void)setFrame:(CGRect)frame {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

- (void)setCenter:(CGPoint)center {
    %orig;
    if (!isRelocating && !isButtonDragging((UIView *)self)) {
        relocateLiveTextButton((UIView *)self);
    }
}

%end

// ============================================================================
// 宿主容器布局 Hooks (CAMFullscreenViewfinder & CAMBottomBar)
// ============================================================================

%hook CAMFullscreenViewfinder

- (void)layoutSubviews {
    %orig;
    
    if (!isRelocating) {
        UIView *btn = getIvarView(self, "_imageAnalysisButton");
        if (!btn) {
            @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
        }
        if (btn && !btn.hidden && btn.alpha > 0.01) {
            relocateLiveTextButton(btn);
        }
    }
}

%end

%hook CAMBottomBar

- (void)layoutSubviews {
    %orig;
    
    if (!isRelocating) {
        UIView *btn = getIvarView(self, "_imageAnalysisButton");
        if (!btn) {
            @try { btn = [self valueForKey:@"imageAnalysisButton"]; } @catch (id e) {}
        }
        if (btn && !btn.hidden && btn.alpha > 0.01) {
            relocateLiveTextButton(btn);
        }
    }
}

%end

// ============================================================================
// 视图动态挂载监听（仅对符合严格按钮特征的子视图响应）
// ============================================================================

%hook UIView

- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (!isRelocating && isLiveTextButton(subview)) {
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
