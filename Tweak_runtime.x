/*
 * CameraButtonSwap - 运行时动态版本 (Tweak_runtime.x)
 * 
 * 这个版本不依赖具体的类名，而是通过运行时遍历视图层次，
 * 结合类名匹配 + accessibilityIdentifier + 视觉特征来定位按钮。
 * 
 * 如果主版本 (Tweak.x) 中的 Hook 因为类名不完全匹配而无效，
 * 可以使用这个版本替代。
 * 
 * 使用方法：在 Makefile 中将 Tweak.x 替换为 Tweak_runtime.x
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================================
// 日志宏
// ============================================================================
#define CBS_LOG(fmt, ...) NSLog(@"[CameraButtonSwap] " fmt, ##__VA_ARGS__)

// ============================================================================
// 全局状态
// ============================================================================
static BOOL g_swapEnabled = YES;
static BOOL g_isSwapping = NO;

// ============================================================================
// 通过运行时遍历查找按钮
// ============================================================================

// 检查一个视图是否可能是微距控件
static BOOL isMacroControl(UIView *view) {
    NSString *className = NSStringFromClass([view class]);
    NSString *accessID = view.accessibilityIdentifier ?: @"";
    NSString *accessLabel = view.accessibilityLabel ?: @"";
    
    // 类名包含 "Macro"
    if ([className localizedCaseInsensitiveContainsString:@"macro"]) return YES;
    
    // accessibilityIdentifier 包含 "macro"
    if ([accessID localizedCaseInsensitiveContainsString:@"macro"]) return YES;
    
    // accessibilityLabel 包含 "微距" 或 "macro"
    if ([accessLabel localizedCaseInsensitiveContainsString:@"微距"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"macro"]) return YES;
    
    return NO;
}

// 检查一个视图是否可能是文本识别按钮
static BOOL isTextRecognitionButton(UIView *view) {
    NSString *className = NSStringFromClass([view class]);
    NSString *accessID = view.accessibilityIdentifier ?: @"";
    NSString *accessLabel = view.accessibilityLabel ?: @"";
    
    // 类名包含 "TextRecognition" 或 "LiveText" 或 "ScanText"
    if ([className localizedCaseInsensitiveContainsString:@"textrecognition"]) return YES;
    if ([className localizedCaseInsensitiveContainsString:@"livetext"]) return YES;
    if ([className localizedCaseInsensitiveContainsString:@"scantext"]) return YES;
    
    // accessibilityIdentifier
    if ([accessID localizedCaseInsensitiveContainsString:@"textrecognition"]) return YES;
    if ([accessID localizedCaseInsensitiveContainsString:@"livetext"]) return YES;
    if ([accessID localizedCaseInsensitiveContainsString:@"scantext"]) return YES;
    
    // accessibilityLabel（中英文）
    if ([accessLabel localizedCaseInsensitiveContainsString:@"扫描文本"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"识别文字"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"实况文本"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"scan text"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"live text"]) return YES;
    if ([accessLabel localizedCaseInsensitiveContainsString:@"text recognition"]) return YES;
    
    return NO;
}

// 递归查找
static UIView *findView(UIView *root, BOOL(*checker)(UIView *)) {
    if (!root) return nil;
    if (checker(root)) return root;
    
    for (UIView *sub in root.subviews) {
        UIView *found = findView(sub, checker);
        if (found) return found;
    }
    return nil;
}

// ============================================================================
// 执行交换
// ============================================================================
static void performSwap(UIView *rootView) {
    if (!g_swapEnabled || g_isSwapping) return;
    g_isSwapping = YES;
    
    UIView *macroView = findView(rootView, isMacroControl);
    UIView *textView = findView(rootView, isTextRecognitionButton);
    
    if (macroView && textView && !macroView.hidden && !textView.hidden) {
        CBS_LOG(@"找到微距控件: %@ frame=%@", 
                NSStringFromClass([macroView class]), 
                NSStringFromCGRect(macroView.frame));
        CBS_LOG(@"找到文本按钮: %@ frame=%@", 
                NSStringFromClass([textView class]), 
                NSStringFromCGRect(textView.frame));
        
        if (macroView.superview == textView.superview) {
            // 同一父视图 → 直接交换 frame
            CGRect macroFrame = macroView.frame;
            CGRect textFrame = textView.frame;
            macroView.frame = textFrame;
            textView.frame = macroFrame;
        } else {
            // 不同父视图 → 通过 window 坐标系转换
            CGPoint macroCenter = [macroView.superview convertPoint:macroView.center toView:nil];
            CGPoint textCenter = [textView.superview convertPoint:textView.center toView:nil];
            
            macroView.center = [macroView.superview convertPoint:textCenter fromView:nil];
            textView.center = [textView.superview convertPoint:macroCenter fromView:nil];
        }
        
        CBS_LOG(@"✅ 位置交换完成！");
    }
    
    g_isSwapping = NO;
}

// ============================================================================
// Hook: 使用运行时查找目标类
// ============================================================================

// 我们 Hook 所有 UIViewController 的 viewDidLayoutSubviews
// 但只在相机 App 的主视图控制器中执行交换逻辑
%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    
    // 只处理名称中包含 "Camera" 或 "Viewfinder" 的视图控制器
    NSString *className = NSStringFromClass([self class]);
    if (![className containsString:@"CAM"] && 
        ![className containsString:@"Camera"] && 
        ![className containsString:@"Viewfinder"]) {
        return;
    }
    
    // 过滤：只处理根级别的相机控制器，避免子控制器重复处理
    if (![className containsString:@"Viewfinder"] && 
        ![className containsString:@"CameraView"]) {
        return;
    }
    
    // 异步执行交换，确保布局完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        performSwap(self.view);
    });
}

%end

// ============================================================================
// 通知中心：提供运行时开关能力
// ============================================================================
static void toggleSwap(CFNotificationCenterRef center, void *observer, 
                        CFStringRef name, const void *object, 
                        CFDictionaryRef userInfo) {
    g_swapEnabled = !g_swapEnabled;
    CBS_LOG(@"按钮交换已%@", g_swapEnabled ? @"启用" : @"禁用");
}

// ============================================================================
// 构造函数
// ============================================================================
%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.camera"]) {
            return;
        }
        
        CBS_LOG(@"✅ 运行时版本已加载");
        CBS_LOG(@"目标 App: %@", bundleID);
        CBS_LOG(@"功能: 交换微距开关和扫描文本按钮位置");
        
        // 注册通知 - 可通过发送通知来动态开关
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            toggleSwap,
            CFSTR("com.yourname.camerabuttonswap.toggle"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        %init;
    }
}
