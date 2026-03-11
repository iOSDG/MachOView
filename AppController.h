/*
 *  AppController.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 *  应用级委托：负责应用生命周期、菜单动作（打开、附加、偏好）、
 *  以及打开面板的文件类型过滤（仅允许 Mach-O / Fat / Archive）。
 */

// 导入Cocoa框架头文件，提供MacOS应用开发核心类库支持
#import <Cocoa/Cocoa.h>

// 前向声明MVPreferenceController类，避免在头文件中引入实现细节，减少编译依赖
@class MVPreferenceController;

// 定义MVAppController类接口，继承NSObject，遵循NSApplicationDelegate和NSOpenSavePanelDelegate协议，负责应用生命周期管理和文件打开面板逻辑
@interface MVAppController : NSObject <NSApplicationDelegate,NSOpenSavePanelDelegate>
{
  // 声明实例变量preferenceController，用于懒加载和管理偏好设置窗口的显示与交互
  MVPreferenceController * preferenceController;
}


// 声明IBAction方法showPreferencePanel，响应菜单点击事件以显示偏好设置面板
- (IBAction)showPreferencePanel:(id)sender;

// 声明IBAction方法attach，响应菜单点击事件以附加到外部进程进行Mach-O动态分析
- (IBAction)attach:(id)sender;

@end
