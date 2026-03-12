/*
 *  MVDocument.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 *  文档与主窗口 UI 实现。包含：左侧 MVOutlineView、右侧 MVTableView、
 *  十六进制格式化器 MVRightFormatter、文档类 MVDocument。负责从 URL 读入二进制、
 *  创建临时拷贝、调用 DataController 创建布局、协调树/表与后台线程及搜索/停止/RVA 切换。
 */

#include <string>
#include <vector>
#include <set>
#include <map>
#include <cxxabi.h>

// 引入公共头文件
#import "Common.h"
// 引入文档头文件
#import "Document.h"
// 引入数据控制器头文件
#import "DataController.h"
// 引入布局头文件
#import "Layout.h"
#include <unistd.h>

//============================================================================
// MVOutlineView：左侧树形大纲视图
//============================================================================
@implementation MVOutlineView

/*
//----------------------------------------------------------------------------
- (void)mouseDown:(NSEvent *)theEvent
{
  // Control+Click invokes that the selected node will not be swapped out
  if ([theEvent modifierFlags] & NSControlKeyMask)
  {
    NSPoint event_location = [theEvent locationInWindow];
    NSPoint local_point = [self convertPoint:event_location fromView:nil];
    MVNode * node = [self itemAtRow:[self rowAtPoint:local_point]];
    
    // note: offset should not be zero for explicit change of dirty indicator
    if (node.details != nil)
    {
      node.dirty = !node.dirty;
      [self reloadItem:node];
      NSLog(@"%@: node: %@ becomes %@", self, node, node.dirty ? @"dirty" : @"clean");
    }
  }

  [super mouseDown:theEvent];
}
*/

@end


//============================================================================
// MVTableView：右侧详情/十六进制表视图，自定义网格线与行高亮
//============================================================================
@implementation MVTableView

//----------------------------------------------------------------------------
// 在裁剪区域内绘制网格：仅对带有 MVUnderlineAttributeName 的行绘制底部分隔线
//----------------------------------------------------------------------------
- (void)drawGridInClipRect:(NSRect)clipRect
{
  // 获取当前文档对象
  MVDocument * document = [[[self window] windowController] document];
  
  // 获取裁剪区域对应的行范围
  NSRange rowRange = [self rowsInRect:clipRect];
  
  // 设置灰色画笔
  // 从 0 开始遍历列，以便能绘制到可视区域左侧之外的列
  [[NSColor grayColor] set];
  // 遍历可见行
  for (NSUInteger rowIndex = rowRange.location ;
       rowIndex < NSMaxRange(rowRange) ;
       rowIndex++ )
  {
    // 获取当前行的 MVRow 对象
    MVRow * row = [document.dataController.selectedNode.details getRowToDisplay:rowIndex];
    // 如果行对象为空则跳过
    if (row == nil)
    {
      continue;
    }
    
    // 检查是否有下划线属性
    if ([[row.attributes objectForKey:MVUnderlineAttributeName] isEqualToString:@"YES"])
    {
      // 获取行的绘制矩形
      NSRect rowRect = [self rectOfRow:rowIndex];
      
      // 绘制底部分隔线
      [NSBezierPath strokeLineFromPoint:NSMakePoint(rowRect.origin.x,
                                                    -0.5+rowRect.origin.y+rowRect.size.height)
                                toPoint:NSMakePoint(rowRect.origin.x + rowRect.size.width,
                                                    -0.5+rowRect.origin.y+rowRect.size.height)];
    }
  }
  //[super drawGridInClipRect:clipRect];
}

//----------------------------------------------------------------------------
// 高亮选中区域：对带有 MVCellColorAttributeName 的行用指定颜色与交替行背景混合填充
//----------------------------------------------------------------------------
- (void)highlightSelectionInClipRect:(NSRect)clipRect
{
  // 获取当前文档对象
  MVDocument * document = [[[self window] windowController] document];
  
  // 获取可见行范围
  NSRange rowRange = [self rowsInRect:clipRect];
  
  // 遍历可见行
  for (NSUInteger rowIndex = rowRange.location ;
       rowIndex < NSMaxRange(rowRange) ;
       rowIndex++ )
  {
    // 获取行对象
    MVRow * row = [document.dataController.selectedNode.details getRowToDisplay:rowIndex];
    // 如果行对象为空则跳过
    if (row == nil)
    {
      continue;
    }
    
    // 获取单元格背景色属性
    NSColor * color = [row.attributes objectForKey:MVCellColorAttributeName];
    // 如果有自定义颜色
    if (color != nil)
    {      
      // 获取当前行的默认交替背景色
      NSColor * bgcolor = [[NSColor controlAlternatingRowBackgroundColors] objectAtIndex:rowIndex % 2];
      
      // 将自定义颜色与背景色混合（85% 自定义色）并设置为填充色
      [[color blendedColorWithFraction:0.85f ofColor:bgcolor] setFill];
      
      // 填充行矩形
      NSRect rowRect = [self rectOfRow:rowIndex];
      NSRectFill (rowRect);
    }
  }
  // 调用父类方法完成标准高亮绘制
  [super highlightSelectionInClipRect: clipRect];
}

//----------------------------------------------------------------------------
// 响应 Esc：取消当前单元格编辑并恢复表视图为第一响应者（系统默认未实现）
//----------------------------------------------------------------------------
- (void)cancelOperation:(id)sender
{
  // 如果当前正在编辑
  if ([self currentEditor] != nil)
  {
    // 中止编辑
    [self abortEditing];
    // 将焦点还给表视图
    [[self window] makeFirstResponder:self];
  }
}

@end

//============================================================================
// MVRightFormatter：右侧可编辑单元格的十六进制格式化与校验
//============================================================================
@implementation MVRightFormatter

//----------------------------------------------------------------------------
// 禁止默认 init，必须使用指定长度的初始化方法
//----------------------------------------------------------------------------
- (instancetype)init
{
  // 断言失败，不允许直接使用 init
  NSAssert(NO, @"plain init is not allowed");
  // 返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 纯十六进制、右对齐、指定字节长度
//-----------------------------------------------------------------------------
- (instancetype)initPlainWithLength:(NSUInteger)len
{
  // 调用父类 init
  if (self = [super init])
  {
    // 不使用分组显示
    compound = NO;
    // 设置长度
    length = len;
    // 设置右对齐
    alignLeft = NO;
  }
  // 返回实例
  return self;
}

//----------------------------------------------------------------------------
// 纯十六进制、左对齐、指定字节长度
//----------------------------------------------------------------------------
- (instancetype)initLeftAlignedWithLength:(NSUInteger)len
{
  // 调用父类 init
  if (self = [super init])
  {
    // 不使用分组显示
    compound = NO;
    // 设置长度
    length = len;
    // 设置左对齐
    alignLeft = YES;
  }
  // 返回实例
  return self;
}

//----------------------------------------------------------------------------
// 分组字节显示（如 11 22 33 44）、右对齐、指定字节数
//----------------------------------------------------------------------------
- (instancetype)initCompoundWithLength:(NSUInteger)len
{
  // 调用父类 init
  if (self = [super init])
  {
    // 使用分组显示
    compound = YES;
    // 设置长度
    length = len;
    // 设置右对齐（Compound 模式下该标志未实际使用）
    alignLeft = NO;
  }
  // 返回实例
  return self;
}

//----------------------------------------------------------------------------
// 工厂方法：创建纯十六进制格式化器
+ (MVRightFormatter *)plainFormatterWithLength:(NSUInteger)len
{
  // 分配并初始化
  return [[MVRightFormatter alloc] initPlainWithLength:len];
}

//----------------------------------------------------------------------------
// 工厂方法：创建左对齐格式化器
+ (MVRightFormatter *)leftAlignedFormatterWithLength:(NSUInteger)len
{
  // 分配并初始化
  return [[MVRightFormatter alloc] initLeftAlignedWithLength:len];
}

//----------------------------------------------------------------------------
// 工厂方法：创建分组格式化器
+ (MVRightFormatter *)compoundFormatterWithLength:(NSUInteger)len
{
  // 分配并初始化
  return [[MVRightFormatter alloc] initCompoundWithLength:len];
}

//----------------------------------------------------------------------------
// 对象转显示字符串：NSAttributedString 取 string，否则直接返回
//----------------------------------------------------------------------------
- (NSString *)stringForObjectValue:(id)anObject
{
  // 如果对象是属性字符串，提取其文本
  if ([anObject isKindOfClass:[NSAttributedString class]])
  {
    return [anObject string]; 
  }
  // 否则直接返回对象
  return anObject;
}

//----------------------------------------------------------------------------
// 编辑后字符串转对象：compound 时原样存；否则按 length 补前导/尾随零（左/右对齐）
//----------------------------------------------------------------------------
- (BOOL)getObjectValue:(id *)anObject 
             forString:(NSString *)string 
      errorDescription:(NSString **)error
{
  // 如果是分组模式
  if (compound)
  {
    // 直接使用原字符串
    (*anObject) = string;
  } 
  // 如果是纯十六进制模式
  else
  {
    // 计算需要补零的个数
    // 补零以保持原始字节长度
    NSUInteger numZeroes = length - [string length];
    // 创建补零字符串
    NSMutableString * zeroes = [[NSMutableString alloc] initWithCapacity:numZeroes];
    // 循环追加 '0'
    while (numZeroes-- > 0)
    {
      [zeroes appendString:@"0"];
    }
    // 根据对齐方式拼接字符串
    (*anObject) = [NSString  stringWithFormat:@"%@%@", 
                   alignLeft ? string : zeroes, 
                   alignLeft ? zeroes : string];
  }

  // 返回成功
  return YES;
}

//----------------------------------------------------------------------------
// 若对象已是 NSAttributedString 则直接返回，否则返回 nil
//----------------------------------------------------------------------------
- (NSAttributedString *)attributedStringForObjectValue:(id)anObject 
                                 withDefaultAttributes:(NSDictionary *)attributes
{
  // 检查类型是否为 NSAttributedString
  if ([anObject isKindOfClass:[NSAttributedString class]])
  {
    // 直接返回
    return anObject;
  }
  // 返回 nil
  return nil;
}

//----------------------------------------------------------------------------
// 校验输入：compound 时为分组十六进制（每字节 0–0xff）；否则为纯十六进制且长度不超过 length
//----------------------------------------------------------------------------
- (BOOL)isPartialStringValid:(NSString **)partialStringPtr 
       proposedSelectedRange:(NSRangePointer)proposedSelRangePtr 
              originalString:(NSString *)origString 
       originalSelectedRange:(NSRange)origSelRange 
            errorDescription:(NSString **)error
{
  // 创建扫描器
  NSScanner * scanner = [NSScanner scannerWithString:*partialStringPtr];

  // 如果是分组模式
  if (compound)
  // 分组十六进制格式 (11 22 33 44 55 66 77 88)
  {
    // 跳过空白字符
    [scanner setCharactersToBeSkipped:[NSCharacterSet whitespaceCharacterSet]];
    
    // 剩余字节数
    NSUInteger numBytes = length;
    // 循环扫描
    while ([scanner isAtEnd] == NO)
    {
      unsigned value;
      // 扫描十六进制整数，检查值是否越界或字节数超限
      if ([scanner scanHexInt:&value] == NO || value > 0xff || numBytes == 0)
      {
        // 校验失败
        return NO;
      }
      // 字节数减一
      --numBytes;
    }
  }
  // 如果是纯十六进制模式
  else
  // 纯十六进制
  {
    // 不跳过任何字符
    [scanner setCharactersToBeSkipped:nil];
    
    // 设置允许的字符集（十六进制数字）
    NSCharacterSet * characterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"];
    // 循环扫描
    while ([scanner isAtEnd] == NO)
    {
      // 扫描字符集内的字符
      if ([scanner scanCharactersFromSet:characterSet intoString:NULL] == NO)
      {
        // 如果包含非法字符，校验失败
        return NO;
      }
      // 如果长度超过限制，校验失败
      if ([*partialStringPtr length] > length)
      {
        return NO;
      }
    }
  }
  
  // 校验通过
  return YES;
}


@end

//============================================================================
// MVDocument：文档类，协调 DataController、左右视图与后台解析
//============================================================================
@implementation MVDocument

// 合成 dataController 属性
@synthesize dataController;

/// 右侧表视图的展示模式：详情 32/64 位、十六进制 32/64 位
enum ViewType
{    
  e_details,
  e_details64,
  e_hex,
  e_hex64,
};

//----------------------------------------------------------------------------
// 返回临时目录模板，供 mkstemp 创建可写拷贝（原文件只读打开，补丁写入临时文件）
//----------------------------------------------------------------------------
+ (NSString *)temporaryDirectory
{
  // 获取进程信息
  NSProcessInfo * procInfo = [NSProcessInfo processInfo];
  // 获取主 Bundle
  NSBundle * mainBundle = [NSBundle mainBundle];
  
  // 格式化临时目录路径：/tmp/进程名_版本号.XXXXXXXXXXX
  NSString * swapDir = [NSString stringWithFormat:@"%@%@_%@.XXXXXXXXXXX",
                        NSTemporaryDirectory(),
                        [procInfo processName],
                        [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  
  // 返回路径模板
  return swapDir;
}

//-----------------------------------------------------------------------------
// 初始化 DataController、threadCount，并注册数据树/表/线程状态通知
//-----------------------------------------------------------------------------
- (instancetype)init
{
  // 调用父类 init
  self = [super init];
  // 如果初始化成功
  if (self) 
  {
    // 创建数据控制器
    dataController = [[MVDataController alloc] init];
    // 初始化线程计数
    threadCount = 0;
    
    // 获取通知中心
    NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
    // 创建弱引用以避免循环引用（虽然在 dealloc 中会移除观察者）
    typeof(self) __weak weakSelf = self;
    
    // 注册数据树变更通知
    [nc addObserver:weakSelf
           selector:@selector(handleDataTreeChanged:) 
               name:MVDataTreeChangedNotification
             object:nil]; 
    
    // 注册数据表变更通知
    [nc addObserver:weakSelf
           selector:@selector(handleDataTableChanged:) 
               name:MVDataTableChangedNotification
             object:nil]; 

    // 注册线程状态变更通知
    [nc addObserver:weakSelf 
           selector:@selector(handleThreadStateChanged:) 
               name:MVThreadStateChangedNotification
             object:nil];
  }
  // 返回实例
  return self;
}

//----------------------------------------------------------------------------
// 文档窗口对应的 Nib 名称
//----------------------------------------------------------------------------
- (NSString *)windowNibName 
{
  // 返回 "Layout"
  return @"Layout";
}

//----------------------------------------------------------------------------
// 当前是否以 RVA（相对虚拟地址）显示：offsetModeSwitch 选第 2 段时为 YES
//----------------------------------------------------------------------------
- (BOOL)isRVA
{
  // 根据分段控件的选择判断
  return ([offsetModeSwitch selectedSegment] == 1 ? YES : NO);
}

//----------------------------------------------------------------------------
// 数据树即将变化（预留，当前未使用）
//----------------------------------------------------------------------------
- (void)handleDataTreeWillChange:(NSNotification *)notification
{
  // 检查发送者是否为当前数据控制器
  if ([notification object] == dataController)
  {
    // lock treeView
  }
}

//----------------------------------------------------------------------------
// 数据树已完成变化（预留，当前未使用）
//----------------------------------------------------------------------------
- (void)handleDataTreeDidChange:(NSNotification *)notification
{
  // 检查发送者是否为当前数据控制器
  if ([notification object] == dataController)
  {
    // unlock treeView
  }
}

//----------------------------------------------------------------------------
// 数据树变化：在主队列刷新左侧树（仅刷新变更节点或整棵根节点）
//----------------------------------------------------------------------------
- (void)handleDataTreeChanged:(NSNotification *)notification
{
  // 检查发送者
  if ([notification object] == dataController) {
    // 在主线程执行 UI 更新
    dispatch_async(dispatch_get_main_queue(), ^
    {
      // 获取用户信息字典
      NSDictionary * userInfo = [notification userInfo];
      // 如果有具体节点信息
      if (userInfo) {
        // 获取变更的节点
        MVNode * node = [userInfo objectForKey:MVNodeUserInfoKey];
        // 如果没有窗口控制器（窗口已关闭），则不更新
        if ([[self windowControllers] count] == 0) {
          return;
        }
        // 刷新父节点
        [self->leftView reloadItem:node.parent];
        // 如果父节点已展开，则刷新该节点
        if ([self->leftView isItemExpanded:node.parent]) {
          [self->leftView reloadItem:node];
        }
      } else {
          // 否则全量刷新根节点
          [self->leftView reloadItem:self->dataController.rootNode reloadChildren:YES];
      }
    });
  }
}

//----------------------------------------------------------------------------
// 右侧表数据变化：通知行数变化并重载表
//----------------------------------------------------------------------------
- (void)handleDataTableChanged:(NSNotification *)notification
{
  // 检查发送者
  if ([notification object] == dataController)
  {
    // 通知行数已变更
    [rightView noteNumberOfRowsChanged];
    // 重载数据
    [rightView reloadData];
  }
}

//----------------------------------------------------------------------------
// 后台线程状态变化：首个任务开始时显示进度条与停止按钮，全部结束时隐藏
//----------------------------------------------------------------------------
- (void)handleThreadStateChanged:(NSNotification *)notification
{
    // 检查发送者
    if ([notification object] == dataController) {
        // 获取线程状态字符串
        NSString * threadState = [[notification userInfo] objectForKey:MVStatusUserInfoKey];
        // 如果是任务开始
        if ([threadState isEqualToString:MVStatusTaskStarted] == YES) {
            // 线程计数加一，若是第一个任务
            if (++threadCount == 1) {
                // 在主线程显示进度条
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->progressIndicator setUsesThreadedAnimation:YES];
                    [self->progressIndicator startAnimation:nil];
                    [self->stopButton setHidden:NO];
                });
            }
        }
        // 如果是任务结束
        else if ([threadState isEqualToString:MVStatusTaskTerminated] == YES) {
            // 线程计数减一，若所有任务已结束
            if (--threadCount == 0) {
                // 在主线程隐藏进度条
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->progressIndicator stopAnimation:nil];
                    [self->statusText setStringValue:@""];
                    [self->stopButton setHidden:YES];
                });
            }
        }
    }
}

//----------------------------------------------------------------------------
// Nib 加载完成后：先执行各布局 doMainTasks，刷新左侧树并展开根节点，再启动后台线程执行 doBackgroundTasks
//----------------------------------------------------------------------------
- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
  // 调用父类方法
  [super windowControllerDidLoadNib:aController];
  
  // 设置状态文本
  [statusText setStringValue:@"Loading..."];
  // 执行主线程任务（如初始化树结构）
  for (MVLayout * layout in dataController.layouts)
  {
    [layout doMainTasks];
  }
  
  // 刷新左侧树
  [leftView reloadData];
  // 展开根节点
  [leftView expandItem:dataController.rootNode];
  
  // 设置后台处理状态文本
  [statusText setStringValue:@"Processing in background..."];
  // 执行后台任务（如详细解析）
  for (MVLayout * layout in dataController.layouts)
  {
#ifdef MV_NO_MULTITHREAD
    // 调试模式下可能同步执行
    [layout doBackgroundTasks];
#else
    // 启动后台线程
    [layout.backgroundThread start];
#endif
  }
}

//----------------------------------------------------------------------------
// 绑定右侧表双击动作为 rightViewDoubleAction:
//----------------------------------------------------------------------------
- (void)awakeFromNib
{
  // 设置双击动作选择器
  [rightView setDoubleAction:@selector(rightViewDoubleAction:)];
  // 设置目标为 self
  [rightView setTarget:self];
}

//----------------------------------------------------------------------------
// 保存时写回的数据（当前为 fileData）
//----------------------------------------------------------------------------
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
  // 返回 fileData
  return dataController.fileData;
}

//----------------------------------------------------------------------------
// 从 URL 读取：创建临时可写拷贝、用 fileData 只读映射原文件、realData 映射临时文件用于补丁、再 createLayouts 解析
//----------------------------------------------------------------------------
- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    // 获取临时目录路径模板
    const char *tmp = [[MVDocument temporaryDirectory] UTF8String];
    // 复制字符串
    char *tmpFilePath = strdup(tmp);
    // 创建临时文件并获取文件描述符
    int fd = mkstemp(tmpFilePath);
    // 检查创建是否成功
    if (fd < 0) {
        NSLog(@"mktemp failed!");
        free(tmpFilePath);
        return NO;
    }
    
    // 创建临时文件的 URL
    NSURL * tmpURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:tmpFilePath]];
    // 释放路径字符串内存
    free(tmpFilePath);
    
    // 设置文件名
    dataController.fileName = [absoluteURL path];
    // 映射原始文件到内存（fileData）
    dataController.fileData = [NSMutableData dataWithContentsOfURL:absoluteURL
                                                           options:NSDataReadingMappedIfSafe
                                                             error:outError];
    // 如果映射失败
    if (*outError) return NO;
    
    // 将原始数据写入临时文件（用于后续的可写映射 realData）
    if (write(fd, [dataController.fileData bytes], [dataController.fileData length]) != (ssize_t)[dataController.fileData length]) {
        NSLog(@"Write failed: %s", strerror(errno));
        return NO;
    }
    // 关闭文件描述符
    close(fd);

    // 映射临时文件到内存（realData，可写，用于应用补丁或修改）
    dataController.realData = [NSMutableData dataWithContentsOfURL:tmpURL
                                                           options:NSDataReadingMappedAlways
                                                             error:outError];
    // 如果映射失败
    if (*outError) return NO;
  
    // 尝试创建布局
    @try
    {
        // 根据根节点和完整文件范围创建布局
        [dataController createLayouts:dataController.rootNode location:0 length:[dataController.fileData length]];
    }
    // 捕获异常
    @catch (NSException * exception)
    {
        // 设置错误信息
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadUnknownError
                                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                              [[self fileURL] path], NSFilePathErrorKey,
                                              [exception reason], NSLocalizedDescriptionKey,
                                              nil]];
        // 返回失败
        return NO;
    }
                             
    // 返回成功
    return YES;                             
}

//----------------------------------------------------------------------------
// 保存文档：若有 delegate 则弹出“另存为”面板，否则走系统默认保存
//----------------------------------------------------------------------------
- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)didSaveSelector contextInfo:(void *)contextInfo
{
  // 如果有代理（通常意味着这是“另存为”操作）
  if (delegate != nil)
  {
    // 运行模态保存面板
    [self runModalSavePanelForSaveOperation:NSSaveAsOperation
                                   delegate:delegate 
                            didSaveSelector:didSaveSelector 
                                contextInfo:contextInfo];
  }
  // 否则
  else
  {
    // 调用父类默认保存
    [super saveDocumentWithDelegate:delegate 
                    didSaveSelector:didSaveSelector
                        contextInfo:contextInfo];
  }
}

//----------------------------------------------------------------------------
// 搜索框变化：对当前选中节点的 details 应用过滤并重载右侧表
//----------------------------------------------------------------------------
- (IBAction)updateSearchFilter:(id)sender
{
  // 获取搜索关键词
  NSString * filter = [searchField stringValue];
  // 如果选中节点有详情表
  if (dataController.selectedNode.details != nil)
  {
    // 应用过滤器
    [dataController.selectedNode filterDetails:filter];
    // 重载右侧表
    [rightView reloadData];
  }
}

//----------------------------------------------------------------------------
// 切换偏移/地址模式：通过发送大纲选择变化通知触发表头与列更新
//----------------------------------------------------------------------------
- (IBAction)updateAddressingMode:(id)sender
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送大纲视图选择变更通知，触发视图更新逻辑
  [nc postNotificationName:NSOutlineViewSelectionDidChangeNotification
                    object:leftView];
}

//----------------------------------------------------------------------------
// 停止后台解析：先禁用停止按钮防止重复点击，再取消所有 layout 的后台线程
//----------------------------------------------------------------------------
- (IBAction)stopProcessing:(id)sender
{
  // 禁用停止按钮
  [stopButton setEnabled:NO];
  // 遍历所有布局
  for (MVLayout * layout in dataController.layouts)
  {
    // 取消后台线程
    [layout.backgroundThread cancel];
  }
}

//----------------------------------------------------------------------------
// 右侧表双击：可编辑列则进入编辑；否则（如 Value 列）可扩展为跳转到符号定义
//----------------------------------------------------------------------------
- (IBAction)rightViewDoubleAction:(id)sender 
{
  // 断言发送者是右侧表
  NSParameterAssert(sender == rightView);
           
  // 获取点击的列和行
  NSInteger colIndex = [sender clickedColumn];
  NSInteger rowIndex = [sender clickedRow];
  
  // 如果该列可编辑
  if ([[[rightView tableColumns] objectAtIndex:colIndex] isEditable])
  {
    // 检查选中节点是否有详情表
    if (dataController.selectedNode.details != nil)
    {
      // 获取对应的行
      MVRow * row = [dataController.selectedNode.details getRowToDisplay:rowIndex];
      // 如果行不存在
      if (row == nil)
      {
        return;
      }
      
      // 获取单元格内容
      NSString * cellContent = [row columnAtIndex:colIndex];
      // 如果内容为空
      if ([cellContent length] == 0)
      {
        return;
      }
    }
    // 进入编辑模式
    [rightView editColumn:colIndex row:rowIndex withEvent:nil select:YES];
    return;
  }
  
  
  // 如果是 Value 列
  if (colIndex == VALUE_COLUMN)
  {
    // 可扩展：根据符号类型（local/public/external）跳转到符号定义
    //NSIndexSet * indexes;
    //[leftView selectRowIndexes:indexes byExtendingSelection:NO];
  }
}

//----------------------------------------------------------------------------
// 根据 viewType 切换右侧表列标题与可编辑性（详情模式 vs 十六进制模式，32/64 位）
//----------------------------------------------------------------------------
- (void)changeView:(ViewType)viewType
{
  // 获取四列对象
  NSTableColumn * column0 = [[rightView tableColumns] objectAtIndex:0];
  NSTableColumn * column1 = [[rightView tableColumns] objectAtIndex:1];
  NSTableColumn * column2 = [[rightView tableColumns] objectAtIndex:2];
  NSTableColumn * column3 = [[rightView tableColumns] objectAtIndex:3];
  
  // 根据视图类型设置
  switch (viewType)
  {
    // 详情模式（32/64位）
    case e_details:       
    case e_details64:
      // 设置第一列标题（偏移量或地址）
      [[column0 headerCell] setStringValue:[self isRVA] == NO ? @"Offset" : @"Address"];
      // 设置第二列标题
      [[column1 headerCell] setStringValue:@"Data"];
      // 设置第三列标题
      [[column2 headerCell] setStringValue:@"Description"];
      // 设置第四列标题
      [[column3 headerCell] setStringValue:@"Value"]; 
      
      // 设置可编辑性
      [column0 setEditable:NO];
      [column1 setEditable:YES]; // Data 列可编辑
      [column2 setEditable:NO];
      [column3 setEditable:NO];
      break;
      
    // 十六进制模式（32/64位）
    case e_hex:
    case e_hex64:
      // 设置第一列标题
      [[column0 headerCell] setStringValue:[self isRVA] == NO ? @"pFile" : @"Address"];
      // 设置第二列标题（低位数据）
      [[column1 headerCell] setStringValue:@"Data LO"];
      // 设置第三列标题（高位数据）
      [[column2 headerCell] setStringValue:@"Data HI"];
      // 设置第四列标题（ASCII 值）
      [[column3 headerCell] setStringValue:@"Value"];
      
      // 设置可编辑性
      [column0 setEditable:NO];
      [column1 setEditable:YES]; // Data LO 可编辑
      [column2 setEditable:YES]; // Data HI 可编辑
      [column3 setEditable:NO];      
      break;
      
    default:;
  }
}

//----------------------------------------------------------------------------
// 关闭文档前：移除所有通知观察者并取消所有后台线程，再交给系统关闭
//----------------------------------------------------------------------------
- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo
{
  // 移除所有观察者
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  // 取消所有布局的后台线程
  for (MVLayout * layout in dataController.layouts)
  {
    [layout.backgroundThread cancel];
  }
   
  // 调用父类方法
  [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
}


#pragma mark responders for UI events

//----------------------------------------------------------------------------
// 左侧树选中项变化：关闭旧节点 details、打开新节点 details、按 32/64 位切换右侧表模式并重载
//----------------------------------------------------------------------------
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  // 检查发送者是否为左侧树
  if ([notification object] == leftView)
  {
    // 获取选中行索引
    NSInteger rowIndex = [leftView selectedRow];
    // 获取选中节点
    MVNode * nodeToSelect = [leftView itemAtRow:rowIndex];
    
    // 如果选中的节点发生变化
    if (dataController.selectedNode != nodeToSelect)
    {
      // 如果旧节点有已保存的详情表
      if (dataController.selectedNode.detailsOffset != 0)
      {
        // 关闭旧节点的详情表
        [dataController.selectedNode closeDetails];
        // 释放内存
        dataController.selectedNode.details = nil;
      }
      
      // 打开新节点的详情表
      [nodeToSelect openDetails];
      // 清除过滤器
      [nodeToSelect filterDetails:nil];
      // 更新当前选中节点
      dataController.selectedNode = nodeToSelect;
    }
  
    // 获取节点所属布局
    MVLayout * layout = [nodeToSelect.userInfo objectForKey:MVLayoutUserInfoKey];
    // 判断是否为 64 位
    BOOL is64bit = [layout is64bit];
  
    // 如果节点有详情表
    if (nodeToSelect.details != nil)
    {
      // 切换为详情视图
      [self changeView:is64bit == NO ? e_details : e_details64];
    }
    // 否则（如原始数据节点）
    else 
    {
      // 切换为十六进制视图
      [self changeView:is64bit == NO ? e_hex : e_hex64];
    }
    
    // 重载右侧表
    [rightView reloadData];
  }
}

//----------------------------------------------------------------------------
// 为可编辑单元格设置格式化器：详情模式按数据长度选左对齐/纯十六进制；十六进制模式按列选 compound/长度
//----------------------------------------------------------------------------
- (void)tableView:(NSTableView *)aTableView 
  willDisplayCell:(id)aCell 
   forTableColumn:(NSTableColumn *)aTableColumn 
              row:(NSInteger)rowIndex
{
  // 仅处理右侧表
  if (aTableView == rightView)
  {
    // 如果是详情模式
    if (dataController.selectedNode.details != nil)
    {
      // 获取对应行
      MVRow * row = [dataController.selectedNode.details getRowToDisplay:rowIndex];
      if (row == nil)
      {
        return;
      }
      
      // 获取数据字符串长度
      NSUInteger len = [row.columns.dataStr length];
      
      // 设置格式化器：超过 16 字节用左对齐，否则用纯十六进制
      [aCell setFormatter:len > 16
       ? [MVRightFormatter leftAlignedFormatterWithLength:len] 
       : [MVRightFormatter plainFormatterWithLength:len]];
    }
    // 如果是十六进制模式
    else
    {
      // 获取列索引
      NSUInteger colIndex = [[aTableView tableColumns] indexOfObject:aTableColumn];
      // 计算数据长度
      NSUInteger len = MIN(dataController.selectedNode.dataRange.length - rowIndex * 16, (NSUInteger)16);
      
      // 设置 Data LO 列格式化器（分组显示）
      if (colIndex == DATA_LO_COLUMN)
      {
        [aCell setFormatter:[MVRightFormatter compoundFormatterWithLength:len > 8 ? 8 : len]];
      }
      // 设置 Data HI 列格式化器（分组显示）
      else if (colIndex == DATA_HI_COLUMN)
      {
        [aCell setFormatter:[MVRightFormatter compoundFormatterWithLength:len > 8 ? len - 8 : 0]];
      }
    }
  }
}

//----------------------------------------------------------------------------
// 悬停提示：若单元格含 C++ 修饰名（_Z 开头），则 demangle 后作为 tooltip 显示（多符号时 TODO：分别提示）
//----------------------------------------------------------------------------
- (NSString *)tableView:(NSTableView *)aTableView 
         toolTipForCell:(NSCell *)aCell 
                   rect:(NSRectPointer)rect 
            tableColumn:(NSTableColumn *)aTableColumn 
                    row:(NSInteger)rowIndex 
          mouseLocation:(NSPoint)mouseLocation
{
  // 仅处理右侧表
  if (aTableView == rightView)
  {
    // 获取对应行
    MVRow * row = [dataController.selectedNode.details getRowToDisplay:rowIndex];
    if (row == nil)
    {
      return nil;
    }
      
    // 获取单元格内容
    NSUInteger colIndex = [[aTableView tableColumns] indexOfObject:aTableColumn];
    NSString * cellContent = [row columnAtIndex:colIndex];
    
    // 查找 C++ 修饰名起始标记 "_Z"
    NSUInteger start = [cellContent rangeOfString:@"_Z"].location;

    // 如果未找到
    if (start == NSNotFound)
    {
      return nil;
    }

    // 查找结束标记（括号或方括号）
    NSUInteger stop = [cellContent rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@")]"]
                                                   options:NSLiteralSearch
                                                     range:NSMakeRange(start, [cellContent length] - start)].location;
    // 如果未找到结束标记，则直到字符串末尾
    if (stop == NSNotFound)
    {
      stop = [cellContent length];
    }
    
    // 截取修饰名
    char const * cell_str = CSTRING([cellContent substringWithRange:NSMakeRange(start, stop - start)]);

    // 调用 ABI 函数进行 demangle
    int status;
    char * sym_str = abi::__cxa_demangle (cell_str, NULL, NULL, &status);
    // 如果成功
    if (status == 0)
    {
      // 转换为 NSString
      NSString * toolTip= NSSTRING(sym_str);
      // 释放 C 字符串
      free(sym_str);
      // 返回作为 tooltip
      return toolTip;
    }
  }
  
  // 返回 nil
  return nil;
}


@end
