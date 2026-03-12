/*
 *  Document.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 *  文档与主窗口 UI 头文件。声明 MVDocument（NSDocument 子类）及左侧大纲视图、
 *  右侧表视图、十六进制格式化器等，定义文档如何协调 DataController 与左右视图。
 */

#include <atomic>

// 前向声明 MVDataController 类
@class MVDataController;

/// 左侧大纲视图，用于展示 Mach-O 结构的树形节点（如 Segment、Section、Load Command 等）
@interface MVOutlineView : NSOutlineView
{
}
@end

/// 右侧表视图，用于展示当前选中节点的详情行（Offset/Data/Description/Value 或十六进制）
@interface MVTableView : NSTableView
{
}
@end

/// 右侧可编辑单元格的十六进制格式化器，支持纯十六进制或分组字节显示
@interface MVRightFormatter : NSFormatter
{
  BOOL        compound;   // NO: 纯十六进制; YES: 分组字节显示 (11 22 33 44 55)
  NSUInteger  length;     // 十六进制值的长度（字节数）
  BOOL        alignLeft;  // NO: 12 --> 0012 右对齐; YES: 12 --> 1200 左对齐
}
@end

/// MachOView 文档类，负责打开/保存二进制、创建布局、协调左侧树与右侧表及后台解析
@interface MVDocument : NSDocument
{
  IBOutlet MVOutlineView *        leftView;         ///< 左侧树形大纲视图
  IBOutlet MVTableView *          rightView;        ///< 右侧详情/十六进制表视图
  IBOutlet NSSearchField *        searchField;      ///< 搜索框，用于过滤右侧表内容
  IBOutlet NSTextField *          statusText;       ///< 状态栏文本（如 "Loading..."）
  IBOutlet NSProgressIndicator *  progressIndicator;///< 后台解析时的进度指示器
  IBOutlet NSSegmentedControl *   offsetModeSwitch; ///< 偏移/地址模式切换（文件偏移 vs RVA）
  IBOutlet NSButton *             stopButton;       ///< 停止后台解析按钮
  MVDataController *              dataController;   ///< 数据控制器，持有文件数据与布局树
  std::atomic<std::int32_t>       threadCount;     ///< 当前后台任务线程数，用于控制进度条显隐
}
@property (nonatomic,readonly) MVDataController * dataController;

/// 搜索框内容变化时更新右侧表的过滤条件
- (IBAction)updateSearchFilter:(id)sender;
/// 切换偏移/地址显示模式（文件偏移 vs 虚拟地址）并刷新视图
- (IBAction)updateAddressingMode:(id)sender;
/// 停止所有后台解析任务
- (IBAction)stopProcessing:(id)sender;
/// 当前是否按 RVA（相对虚拟地址）显示；否则为文件偏移
- (BOOL)isRVA;

/// 返回用于临时拷贝/补丁的目录模板（进程名_版本号.XXXXXXXXXXX），配合 mkstemp 使用
+ (NSString *)temporaryDirectory;

@end
