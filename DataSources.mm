/*
 *  DataSources.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 引入公共头文件
#import "Common.h"
// 引入数据源头文件
#import "DataSources.h"
// 引入数据控制器头文件
#import "DataController.h"
// 引入文档类头文件
#import "Document.h"
// 引入布局类头文件
#import "Layout.h"

// 定义扫描器错误消息常量
NSString * const MVScannerErrorMessage  = @"NSScanner error";

//============================================================================
// MVDataSourceTree 实现：为左侧树形大纲视图（NSOutlineView）提供数据
//============================================================================
@implementation MVDataSourceTree

#pragma mark NSOutlineView must-have delegates

// 获取节点的子节点数量
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item 
{
  // 如果 item 为空，表示根节点，只有1个（虚拟根）
  if (item == nil)
  {
    return 1;
  }
  
  // 转换为 MVNode 对象
  MVNode * node = item;
  // 返回该节点的子节点数量
  return node.numberOfChildren;
}
//----------------------------------------------------------------------------

// 判断节点是否可展开（有子节点即可展开）
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item 
{
  // 如果 item 为空，表示根节点，总是可展开
  if (item == nil)
  {
    return YES;
  }
  
  // 转换为 MVNode 对象
  MVNode * node = item;
  // 如果子节点数量大于0则可展开
  return (node.numberOfChildren > 0);
}
//----------------------------------------------------------------------------

// 获取指定节点在特定索引处的子节点
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item 
{
  // 获取当前文档对象
  MVDocument * document = [[[outlineView window] windowController] document];
  // 如果 item 为空，返回文档的根节点
  if (item == nil)
  {
    return document.dataController.rootNode;
  }
  
  // 转换为 MVNode 对象
  MVNode * node = item;
  // 返回指定索引的子节点
  return [node childAtIndex:index];
}
//----------------------------------------------------------------------------

// 获取节点在特定列的显示内容（通常是标题）
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item 
{
  // 如果 item 为空，显示占位符
  if (item == nil)
  {
    return @"-";
  }
  
  // 转换为 MVNode 对象
  MVNode * node = item;
  
  // 如果节点有详情表但偏移量为0（表示内容已修改但尚未保存到交换文件），在标题前加星号
  if (node.details != nil && node.detailsOffset == 0)
  {
    return [@"*" stringByAppendingString:node.caption];
  }
  
  // 返回节点标题
  return node.caption;
}
//----------------------------------------------------------------------------

@end


//============================================================================
// MVDataSourceDetails 实现：为右侧详情表格视图（NSTableView）提供数据
//============================================================================
@implementation MVDataSourceDetails

#pragma mark NSTableView must-have delegates

// 获取表格行数
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
  // 获取当前文档对象
  MVDocument * document = [[[aTableView window] windowController] document];
  // 获取当前选中的树节点
  MVNode * selectedNode = document.dataController.selectedNode;
  
  // 如果选中节点没有解析好的详情表（details 为 nil），则提供原始二进制数据的十六进制转储
  // if there is no details, then provide binary dump
  if (selectedNode.details == nil)
  {
    // 每行显示 16 字节，计算总行数
    NSInteger numRows = selectedNode.dataRange.length / 16;
    // 如果有余数，行数加 1
    if (selectedNode.dataRange.length % 16 != 0)
    {
      ++numRows;
    }
    // 返回计算出的行数
    return numRows;
  }

  // 如果有详情表，返回详情表的显示行数
  return selectedNode.details.rowCountToDisplay;
}
//----------------------------------------------------------------------------

// 获取表格单元格的显示内容
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
  // 获取当前文档对象
  MVDocument * document = [[[aTableView window] windowController] document];
  // 获取当前选中的树节点
  MVNode * selectedNode = document.dataController.selectedNode;
  
  // 如果文档为空（例如正在关闭），返回 nil
  // if it is closing...
  if (document == nil)
  {
    return nil;
  }
  
  // 获取当前列的索引
  NSUInteger colIndex = [[aTableView tableColumns] indexOfObject:aTableColumn];
  
  //NSLog (@"queried (%d, %d)", rowIndex, colIndex);
  
  // 如果节点没有详情表，则显示指定范围的二进制数据
  // if it has no details then show binary data at given range
  if (selectedNode.details == nil)
  {
    // 计算当前行对应的文件偏移量
    NSUInteger offset = selectedNode.dataRange.location + rowIndex * 16;
    
    // 如果是偏移量列
    // file offset
    if (colIndex == OFFSET_COLUMN)
    {
      // 格式化为 8 位十六进制字符串
      NSString * cellContent = [NSString stringWithFormat:@"%.8lX", offset];
      // 如果启用了 RVA 显示模式
      if ([document isRVA] == YES)
      {
        // 获取布局对象并将偏移量转换为 RVA
        MVLayout *layout = [selectedNode.userInfo objectForKey:MVLayoutUserInfoKey];
        return [layout convertToRVA:cellContent];
      }
      // 返回文件偏移量字符串
      return cellContent;
    }

    // 初始化 16 字节的缓冲区
    // binary data
    uint8_t buffer[17] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    
    // 计算需要读取的长度（最多 16 字节，防止越界）
    NSUInteger len = MIN(selectedNode.dataRange.length - rowIndex * 16, (NSUInteger)16);
    
    // 从文件数据中复制字节到缓冲区
    memcpy(buffer, (uint8_t *)[document.dataController.fileData bytes] + offset, len);
    
    // 如果是低 8 字节数据列
    if (colIndex == DATA_LO_COLUMN)
    {
      // 确定显示的字节数（最多 8 字节）
      NSUInteger index = (len > 8 ? 8 : len); 
            
      // 格式化为十六进制字符串并截取有效部分
      return [[NSString stringWithFormat:@"%.2X %.2X %.2X %.2X %.2X %.2X %.2X %.2X ", 
              buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7]]
              substringToIndex:index*3];
    }
    
    // 如果是高 8 字节数据列
    if (colIndex == DATA_HI_COLUMN)
    {
      // 确定显示的字节数（如果有超过 8 字节的部分）
      NSUInteger index = (len > 8 ? len - 8 : 0);
      
      // 格式化为十六进制字符串并截取有效部分
      return [[NSString stringWithFormat:@"%.2X %.2X %.2X %.2X %.2X %.2X %.2X %.2X ", 
              buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15]]
              substringToIndex:index*3];
    }
    
    // 文本数据列（尽可能显示 ASCII）
    // textual data (where possible)
    for (NSUInteger i = 0; i < len; ++i)
    {
      // 如果是非打印字符，替换为点号
      // keep the output in ASCII
      if (buffer[i] < 32 || buffer[i] > 126)
      {
        buffer[i] = '.';
      }
    }
    
    // 返回处理后的 ASCII 字符串
    return NSSTRING(buffer);
  }
  
  // 如果有详情表，则显示解析后的内容
  // if it has descripion then show it
  MVRow * row = [selectedNode.details getRowToDisplay:rowIndex];
  // 如果行存在
  if (row != nil)
  { 
    // 获取指定列的字符串内容
    NSString * cellContent = [row columnAtIndex:colIndex];
      
    // 特殊处理偏移量列：如果是 RVA 模式，动态转换内容
    // special column is the offset column:
    // if RVA is selected then subtitute the content on the fly
    if (colIndex == OFFSET_COLUMN && [cellContent length] > 0) 
    {
      // 如果启用了 RVA 显示
      if ([document isRVA] == YES)
      {
        // 获取布局对象并进行转换
        MVLayout *layout = [selectedNode.userInfo objectForKey:MVLayoutUserInfoKey];
        cellContent = [layout convertToRVA:cellContent];
      }
    }
      
    // 应用文本颜色属性
    // put formatting on display text
    NSColor * color = [row.attributes objectForKey:MVTextColorAttributeName];
    // 如果有颜色属性
    if (color != nil)
    {
      // 创建带有前景色的属性字典
      NSDictionary * attributes = [NSDictionary dictionaryWithObject:color forKey:NSForegroundColorAttributeName];
      // 返回带属性的字符串
      return [[NSAttributedString alloc] initWithString:cellContent
                                             attributes:attributes];
    }
    // 返回普通字符串
    return cellContent;
  }
  
  // 默认返回 nil
  return nil;
}
//----------------------------------------------------------------------------

// 设置表格单元格的值（用于编辑）
- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
  // 定义扫描结果和文件偏移变量
  BOOL scanResult;
  uint64_t fileOffset;

  // 获取列索引
  NSUInteger colIndex = [[aTableView tableColumns] indexOfObject:aTableColumn];
  // 获取文档对象
  MVDocument * document = [[[aTableView window] windowController] document];
  // 获取输入的新内容（若是 NSAttributedString 则取 string）
  NSString * cellContent = ([anObject isKindOfClass:[NSAttributedString class]] ? [anObject string] : anObject);
  // 创建扫描器
  NSScanner * scanner = [NSScanner scannerWithString:cellContent];
  // 获取选中节点
  MVNode * selectedNode = document.dataController.selectedNode;
  
  // 如果是解析后的详情模式（编辑解析后的字段）
  if (selectedNode.details != nil)
  // option1: plain hex value
  {
    // 获取对应行
    MVRow * row = [selectedNode.details getRowToDisplay:rowIndex];
    // 如果行不存在则返回
    if (row == nil)
    {
      return;
    }
    
    // 从偏移量列解析出文件偏移
    // find out file offset from the offset column
    scanResult = [[NSScanner scannerWithString:row.columns.offsetStr] scanHexLongLong:&fileOffset];
    // 如果解析失败则断言错误
    if (scanResult == NO)
    {
      NSAssert(NO, MVScannerErrorMessage);
      return;
    }
    
    // 计算数据范围，长度为输入字符串长度的一半（假设输入为十六进制字符串）
    NSRange dataRange = NSMakeRange(fileOffset, [cellContent length] / 2);
    
    // 如果数据长度小于等于 64 位整数
    if (dataRange.length <= sizeof(uint64_t))
    {
      // 扫描十六进制数值
      uint64_t value;
      scanResult = [scanner scanHexLongLong:&value];
      // 如果扫描失败
      if (scanResult == NO)
      {
        NSAssert(NO, MVScannerErrorMessage);
        return;
      }
      // 替换文件中的数据
      [document.dataController.fileData replaceBytesInRange:dataRange withBytes:&value];
    }
    // 如果数据长度较长
    else 
    {
      // 断言输入长度必须为偶数
      // create a place holder for new value
      NSAssert ([cellContent length] % 2 == 0, @"cell content length must be even");
      
      // 创建可变数据容器
      NSMutableData * mdata = [NSMutableData dataWithCapacity:dataRange.length];
      
      // 定义缓冲区和原始字符串指针
      static char buf[3];
      char const * orgstr = CSTRING(cellContent);
      // 每两个字符解析为一个字节
      for (NSUInteger s = 0; s < [cellContent length]; s += 2)
      {
        buf[0] = orgstr[s];
        buf[1] = orgstr[s+1];
        unsigned long value = strtoul (buf, NULL, 16);
        [mdata appendBytes:&value length:sizeof(uint8_t)];
      }
      
      // 用新数据替换文件中的内容
      // replace data with the new value
      [document.dataController.fileData replaceBytesInRange:dataRange withBytes:[mdata bytes]];
    }

    // 更新单元格内容以反映更改，并标记为红色
    // update the cell content to indicate changes
    //================================================
    // 重置详情表偏移量，标记未保存
    selectedNode.detailsOffset = 0;
    // 更新内存中的单元格内容
    [selectedNode.details updateCellContentTo:cellContent atRow:rowIndex andCol:colIndex];
    // 设置文本颜色为红色
    [selectedNode.details setAttributesForRowIndex:rowIndex:MVTextColorAttributeName,[NSColor redColor],nil];
  }
  // 如果是二进制转储模式（编辑原始字节）
  else
  // option2: group of bytes
  {
    // 根据行号和列索引计算文件偏移量
    // find out file offset from the row index
    fileOffset = selectedNode.dataRange.location + 16 * rowIndex + 8 * (colIndex == DATA_HI_COLUMN);

    // 创建数据容器，容量为字符串长度除以3（假设格式为 "XX XX "）
    // create a place holder for new value
    NSMutableData * mdata = [NSMutableData dataWithCapacity:[cellContent length] / 3]; // each element = one byte plus space
    
    // 循环扫描输入字符串
    // fill in placeholder
    while ([scanner isAtEnd] == NO)
    {
      unsigned value;
      
      // 扫描十六进制整数
      scanResult = [scanner scanHexInt:&value];
      // 如果失败
      if (scanResult == NO)
      {
        NSAssert(NO, MVScannerErrorMessage);
        return;
      }
      
      // 追加到数据容器
      [mdata appendBytes:&value length:sizeof(uint8_t)];
    }
    
    // 用新数据替换文件中的内容
    // replace data with the new value
    [document.dataController.fileData replaceBytesInRange:NSMakeRange(fileOffset, [mdata length]) 
                                                withBytes:[mdata bytes]];
    
    // 不需要更新单元格内容，因为视图会刷新
    // do not need to update cell content...
  }

  // 标记文档已更改
  // set document to dirty
  [document updateChangeCount:NSChangeDone];
}
//----------------------------------------------------------------------------



@end
