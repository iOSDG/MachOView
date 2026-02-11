/*
 *  AppController.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 *  应用级委托：负责应用生命周期、菜单动作（打开、附加、偏好）、
 *  以及打开面板的文件类型过滤（仅允许 Mach-O / Fat / Archive）。
 */

// 引入 Cocoa 框架（含 NSApplication、NSObject、NSOpenSavePanelDelegate 等）
#import <Cocoa/Cocoa.h>

// 前向声明偏好设置窗口控制器，避免在头文件中 #import 其实现
@class MVPreferenceController;

// 应用委托类：实现 NSApplicationDelegate 与 NSOpenSavePanelDelegate（用于打开面板中过滤可选文件）
@interface MVAppController : NSObject <NSApplicationDelegate,NSOpenSavePanelDelegate>
{
  // 偏好设置窗口控制器，懒创建，用于显示偏好面板
  MVPreferenceController * preferenceController;
}

// 菜单动作：显示偏好设置面板（对应菜单项的 IBAction）
- (IBAction)showPreferencePanel:(id)sender;
// 菜单动作：附加到指定 PID 的进程并读取其主二进制 Mach-O 头，再以临时文件方式用文档打开
- (IBAction)attach:(id)sender;

@end
