/*
 * view_hierarchy_dump.cy - Cycript 脚本
 * 
 * 用法：
 *   1. SSH 到越狱设备
 *   2. cycript -p Camera
 *   3. 复制粘贴以下代码执行
 * 
 * 功能：
 *   - 打印相机 App 的完整视图层次结构
 *   - 标记出微距控件和文本识别按钮
 *   - 帮助确认实际的类名和 accessibilityIdentifier
 */

// 打印完整视图层次
function printHierarchy() {
    var w = UIApp.keyWindow;
    return w.recursiveDescription().toString();
}

// 查找包含特定关键词的类
function findClasses(keyword) {
    var classes = [];
    var count = objc_getClassList(NULL, 0);
    var buffer = new (interp.modules['<CydiaSubstrate>'].resolve('class_t').arrayType(count))();
    objc_getClassList(buffer, count);
    
    for (var i = 0; i < count; i++) {
        var name = class_getName(buffer[i]);
        if (name && name.toString().toLowerCase().indexOf(keyword.toLowerCase()) !== -1) {
            classes.push(name.toString());
        }
    }
    return classes;
}

// 查找所有 CAM 开头的类
function findCAMClasses() {
    return findClasses("CAM");
}

// 查找微距相关的类
function findMacroClasses() {
    return findClasses("Macro");
}

// 查找文本识别相关的类
function findTextClasses() {
    var results = findClasses("TextRecognition");
    results = results.concat(findClasses("LiveText"));
    results = results.concat(findClasses("ScanText"));
    return results;
}

// 递归搜索视图并返回信息
function searchViews(view, depth) {
    if (!view) return "";
    depth = depth || 0;
    var indent = "";
    for (var i = 0; i < depth; i++) indent += "  ";
    
    var className = view.class().toString();
    var frame = view.frame();
    var accessID = view.accessibilityIdentifier() || "(null)";
    var accessLabel = view.accessibilityLabel() || "(null)";
    var hidden = view.isHidden();
    
    var result = indent + className + " | frame=" + frame + " | id=" + accessID + " | label=" + accessLabel + " | hidden=" + hidden;
    
    // 标记可能的目标
    if (className.toLowerCase().indexOf("macro") !== -1) {
        result += " ★★★ [微距控件] ★★★";
    }
    if (className.toLowerCase().indexOf("textrecognition") !== -1 || 
        className.toLowerCase().indexOf("livetext") !== -1) {
        result += " ★★★ [文本识别] ★★★";
    }
    
    result += "\n";
    
    var subviews = view.subviews();
    for (var i = 0; i < subviews.count(); i++) {
        result += searchViews(subviews[i], depth + 1);
    }
    
    return result;
}

// 主入口函数
function dumpCameraUI() {
    var w = UIApp.keyWindow;
    var root = w.rootViewController().view();
    NSLog(@"[CameraButtonSwap Debug] === 相机视图层次 ===\n" + searchViews(root, 0));
    return "已输出到 syslog，使用 `cat /var/log/syslog | grep CameraButtonSwap` 查看";
}

// 直接输出到控制台
function dumpCameraUIToConsole() {
    var w = UIApp.keyWindow;
    var root = w.rootViewController().view();
    return searchViews(root, 0);
}
