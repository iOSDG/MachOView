/*
 *  ArchiveLayout.mm
 *  MachOView
 *
 *  Created by psaghelyi on 18/03/2011.
 *
 */

// 引入C++标准库string，用于字符串处理
#include <string>
// 引入C++标准库vector，用于动态数组管理
#include <vector>
// 引入C++标准库set，用于集合操作
#include <set>
// 引入C++标准库map，用于键值对映射
#include <map>
// 引入C++ ABI头文件，用于运行时类型信息处理
#include <cxxabi.h>

// 引入项目公共头文件
#import "Common.h"
// 引入ArchiveLayout类定义
#import "ArchiveLayout.h"
// 引入数据控制器，用于文件数据读取
#import "DataController.h"
// 引入Mach-O布局类，用于解析Archive中的Mach-O对象
#import "MachOLayout.h"
// 引入读写工具类
#import "ReadWrite.h"
// 引入ranlib结构定义，用于处理静态库符号表
#import <mach-o/ranlib.h>

//============================================================================
// MVObjectInfo类的实现，用于存储Archive成员对象的信息
@implementation MVObjectInfo

// 自动合成属性name, length, layout的存取方法
@synthesize name, length, layout;

//-----------------------------------------------------------------------------
// 初始化方法，设置对象名称和长度
- (instancetype)initWithName:(NSString *)_name Length:(uint32_t)_length
{
  // 调用父类初始化方法
  if (self = [super init])
  {
    // 设置对象名称
    name = _name;
    // 设置对象长度
    length = _length;
  }
  // 返回初始化后的对象实例
  return self;
}

//-----------------------------------------------------------------------------
// 类工厂方法，快速创建MVObjectInfo实例
+(MVObjectInfo *)objectInfoWithName:(NSString *)name Length:(uint32_t)length
{
  // 分配并初始化MVObjectInfo对象
  return [[MVObjectInfo alloc] initWithName:name Length:length];
}

@end

//============================================================================
// ArchiveLayout类的实现，负责静态库（Archive）的布局解析
@implementation ArchiveLayout

// 初始化方法，关联数据控制器和根节点，并初始化对象信息映射表
- (instancetype)initWithDataController:(MVDataController *)dc rootNode:(MVNode *)node
{
  // 调用父类初始化方法
  if (self = [super initWithDataController:dc rootNode:node])
  {
    // 初始化objectInfoMap字典，用于存储文件偏移到对象信息的映射
    objectInfoMap = [[NSMutableDictionary alloc] init];
  }
  // 返回初始化后的ArchiveLayout实例
  return self;
}
//-----------------------------------------------------------------------------

// 类工厂方法，创建ArchiveLayout实例
+ (ArchiveLayout *)layoutWithDataController:(MVDataController *)dc rootNode:(MVNode *)node
{
  // 分配并初始化ArchiveLayout对象
  return [[ArchiveLayout alloc] initWithDataController:dc rootNode:node];
}
//-----------------------------------------------------------------------------

// 创建签名节点，用于显示Archive文件的起始签名（"!<arch>\n"）
- (MVNode *)createSignatureNode:(MVNode *)parent
                        caption:(NSString *)caption
                       location:(uint64_t)location
                         length:(uint64_t)length
{
  // 创建节点保存器，用于后台线程数据加载
  MVNodeSaver nodeSaver;
  // 在父节点下插入新节点，包含详细信息
  MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver]; 
  
  // 创建读取范围，长度初始为0（由读取函数决定）
  NSRange range = NSMakeRange(location,0);
  // 用于存储读取到的十六进制字符串
  NSString * lastReadHex;
  
  // 读取8字节的固定长度字符串作为签名
  NSString * signature = [dataController read_string:range fixlen:8 lastReadHex:&lastReadHex];
  // 将签名信息添加到节点详情表中：偏移量、十六进制值、字段名、签名内容
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Signature"
                         :signature];
  // 返回创建的节点
  return node;
}
//----------------------------------------------------------------------------

// 创建头部节点，解析Archive成员的头部信息（ar_hdr）
- (MVNode *)createHeaderNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
{
  // 创建节点保存器
  MVNodeSaver nodeSaver;
  // 插入新节点
  MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver]; 
  
  // 初始化读取范围
  NSRange range = NSMakeRange(location,0);
  // 用于存储十六进制字符串
  NSString * lastReadHex;
  
  // 读取16字节的文件名
  NSString * name = [dataController read_string:range fixlen:16 lastReadHex:&lastReadHex];
  // 添加文件名信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Name"
                         :name];
  
  // 读取12字节的时间戳字符串
  NSString * time_str = [dataController read_string:range fixlen:12 lastReadHex:&lastReadHex];
  // 将时间戳字符串转换为长整型时间值
  time_t time = (time_t)[time_str longLongValue];
  // 添加格式化后的时间戳信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Time Stamp"
                         :[NSString stringWithFormat:@"%s", ctime(&time)]];

  // 读取6字节的用户ID字符串
  NSString * user_id_str = [dataController read_string:range fixlen:6 lastReadHex:&lastReadHex];
  // 添加用户ID信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"UserID"
                         :[NSString stringWithFormat:@"%u",[user_id_str intValue]]];

  // 读取6字节的组ID字符串
  NSString * group_id_str = [dataController read_string:range fixlen:6 lastReadHex:&lastReadHex];
  // 添加组ID信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"GroupID"
                         :[NSString stringWithFormat:@"%u",[group_id_str intValue]]];

  // 读取8字节的文件模式字符串
  NSString * mode_str = [dataController read_string:range fixlen:8 lastReadHex:&lastReadHex];
  // 添加文件模式信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Mode"
                         :[NSString stringWithFormat:@"%u",[mode_str intValue]]];

  // 读取8字节的文件大小字符串
  NSString * size_str = [dataController read_string:range fixlen:8 lastReadHex:&lastReadHex];
  // 添加文件大小信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Size"
                         :[NSString stringWithFormat:@"%u",[size_str intValue]]];
  
  // read spaces until end-of-header (0x60 0x0A)
  // 初始化可变字符串，用于存储最后读取的十六进制值
  NSMutableString * mutableLastReadHex = [[NSMutableString alloc] initWithCapacity:2];
  // 初始化可变字符串，用于存储填充字符（Archive头结束标记）
  NSMutableString * padding = [[NSMutableString alloc] initWithCapacity:2];
  // 循环读取直到遇到非空格字符（通常是结束标记）
  for(;;) 
  {
    // 读取1字节并追加到padding
    [padding appendString:[dataController read_string:range fixlen:1 lastReadHex:&lastReadHex]];
    // 追加十六进制值
    [mutableLastReadHex appendString:lastReadHex];
    // 检查倒数第1个字符是否不是空格
    if (*(CSTRING(padding) + [padding length] - 1) != ' ')
    {
      // 如果不是空格，再读取1字节（确保读取完整的结束序列 "`\n"）
      [padding appendString:[dataController read_string:range fixlen:1 lastReadHex:&lastReadHex]];
      // 追加十六进制值
      [mutableLastReadHex appendString:lastReadHex];
      // 跳出循环
      break;
    }
  }
  // 添加头部结束标记信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location - [padding length] + 2]
                         :mutableLastReadHex
                         :@"End Header"
                         :padding];
  
  // 声明MVObjectInfo对象指针
  MVObjectInfo * objectInfo;
  // 检查文件名是否以 "#1/" 开头（BSD风格长文件名扩展）
  if (NSEqualRanges([name rangeOfString:@"#1/"], NSMakeRange(0,3)))
  {
    // 解析文件名长度
    uint32_t len = [[name substringFromIndex:3] intValue];
    // 读取实际的长文件名
    NSString * long_name = [dataController read_string:range fixlen:len lastReadHex:&lastReadHex];
    // 添加长文件名信息到详情表
    [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                           :lastReadHex
                           :@"Long Name"
                           :long_name];
    
    // 创建对象信息，修正实际内容长度（减去文件名的长度）
    objectInfo = [MVObjectInfo objectInfoWithName:long_name Length:[size_str intValue] - len];
  }
  else 
  {
    // 使用普通文件名创建对象信息
    objectInfo = [MVObjectInfo objectInfoWithName:name Length:[size_str intValue]];
  }
  // 将对象信息存入映射表，Key为文件偏移量
  [objectInfoMap setObject:objectInfo forKey:[NSNumber numberWithUnsignedLong:location]];
  
  // 设置节点的数据范围，包含头部和可能的长文件名
  node.dataRange = NSMakeRange(location, NSMaxRange(range) - location);
  
  // 返回头部节点
  return node;
}
//----------------------------------------------------------------------------

// 创建成员节点（符号表），解析Archive的符号表部分
- (MVNode *)createMemberNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                      strtab:(char const *)strtab
{
  // 创建节点保存器
  MVNodeSaver nodeSaver;
  // 插入新节点
  MVNode * node = [parent insertChildWithDetails:caption location:location length:length saver:nodeSaver]; 
  
  // 初始化读取范围
  NSRange range = NSMakeRange(location,0);
  // 用于存储十六进制字符串
  NSString * lastReadHex;
  
  // 读取4字节的符号表大小
  uint32_t size = [dataController read_uint32:range lastReadHex:&lastReadHex];
  // 添加大小信息到详情表
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Size"
                         :[NSString stringWithFormat:@"%u",size]];
  
  // 设置详情表的属性，高亮显示
  [node.details setAttributes:MVCellColorAttributeName,[NSColor greenColor],
                              MVUnderlineAttributeName,@"YES",nil];
  
  // 设置节点的数据范围
  node.dataRange = NSMakeRange(location, size);
  
  // 遍历符号表条目（ranlib结构数组）
  while (size > 0)
  {
    // 读取4字节的字符串表索引
    uint32_t strx = [dataController read_uint32:range lastReadHex:&lastReadHex];
    
    // accumulate search info
    // 记录当前行号作为书签，用于后续设置属性
    NSUInteger bookmark = node.details.rowCount;
    // 从字符串表中获取符号名称
    NSString * symbolName = [NSString stringWithFormat:@"%s",strtab + strx];
    
    // 添加符号名称到详情表
    [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                           :lastReadHex
                           :@"Symbol"
                           :symbolName];

    // 读取4字节的对象文件偏移量
    uint32_t off = [dataController read_uint32:range lastReadHex:&lastReadHex];
    
    // 根据偏移量从映射表中查找对应的对象信息（需要加上基址imageOffset）
    MVObjectInfo * objectInfo = [objectInfoMap objectForKey:[NSNumber numberWithUnsignedLong:off + imageOffset]];
    
    // 添加所属对象名称到详情表
    [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                           :lastReadHex
                           :@"Object"
                           :objectInfo.name];
    
    // 为书签行设置元数据属性，便于搜索
    [node.details setAttributesFromRowIndex:bookmark:MVMetaDataAttributeName,symbolName,nil];
    // 设置下划线属性
    [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
    
    // 减少剩余大小，每次处理一个ranlib结构
    size -= sizeof(struct ranlib);
  }
  
  // 返回符号表节点
  return node;
}


//----------------------------------------------------------------------------


// 执行主要任务，构建Archive的整体结构树
- (void)doMainTasks
{
  // 用于存储十六进制字符串
  NSString * lastReadHex;
  
  // archive start signature
  // 创建Archive起始签名节点（8字节）
  [self createSignatureNode:rootNode 
                    caption:@"Start" 
                   location:imageOffset 
                     length:8];
  

  // read symbol table (ranlibs)
  // 创建符号表头部节点（长度暂定0，内部解析）
  MVNode * symtabHeaderNode = [self createHeaderNode:rootNode 
                                             caption:@"Symtab Header"
                                            location:imageOffset + 8 
                                              length:0]; // length will be determined in function
  
  // skip symbol and string table for now
  // 获取符号表头部之后的数据偏移量（即符号表数据开始处）
  uint64_t symtabOffset = NSMaxRange(symtabHeaderNode.dataRange);
  // 初始化读取范围
  NSRange range = NSMakeRange(symtabOffset,0);
  // 读取符号表大小（包含自身的4字节长度）
  uint32_t symtabSize = [dataController read_uint32:range lastReadHex:&lastReadHex] + sizeof(uint32_t);
  // 计算字符串表偏移量（紧随符号表之后）
  uint64_t strtabOffset = symtabOffset + symtabSize;
  // 更新读取范围到字符串表
  range = NSMakeRange(strtabOffset,0);  
  // 读取字符串表大小（包含自身的4字节长度）
  uint32_t strtabSize = [dataController read_uint32:range lastReadHex:&lastReadHex] + sizeof(uint32_t);
  
  // read headers

  // 遍历所有成员对象头部，从字符串表之后开始，直到文件末尾
  for (uint64_t location = strtabOffset + strtabSize; location < NSMaxRange(rootNode.dataRange); )
  {
    // 创建对象头部节点
    MVNode * headerNode = [self createHeaderNode:rootNode 
                                         caption:@"Object Header"
                                        location:location 
                                          length:0]; // length will be determined in function
    
    // 获取刚解析的对象信息
    MVObjectInfo * objectInfo = [objectInfoMap objectForKey:[NSNumber numberWithUnsignedLong:location]];
    
    // 计算对象数据内容的偏移量（紧随头部之后）
    uint64_t objectOffset = NSMaxRange(headerNode.dataRange); // starts right after the header
    // 获取对象数据大小
    uint64_t objectSize = objectInfo.length;
    
    // create Mach-O object layout
    // 创建数据节点，用于容纳Mach-O对象内容
    MVNode * objectNode = [self createDataNode:rootNode 
                                       caption:objectInfo.name
                                      location:objectOffset 
                                        length:objectSize];
    
    // 为该对象创建MachOLayout子布局处理器
    objectInfo.layout = [MachOLayout layoutWithDataController:dataController rootNode:objectNode];
    
    // 将子布局对象保存到节点的userInfo中
    [objectNode.userInfo setObject:objectInfo.layout forKey:MVLayoutUserInfoKey];
    // 递归执行子布局的主任务（解析Mach-O）
    [objectInfo.layout doMainTasks];
    
    // move to the next header
    // 更新位置到下一个对象头部
    location = objectOffset + objectSize;
  }

  // finish symbol table based on the information about processed objects
  // 填充符号表节点内容（此时已解析所有对象，可关联名称）
  [self createMemberNode:rootNode 
                 caption:@"Symbol Table"
                location:symtabOffset
                  length:symtabSize
                  strtab:(char *)((uint8_t *)[dataController.fileData bytes] + strtabOffset + sizeof(uint32_t))]; 
  
  // 创建字符串表节点
  [self createDataNode:rootNode caption:@"String Table" 
              location:strtabOffset 
                length:strtabSize];
  

  // 调用父类的主任务
  [super doMainTasks];
}
//----------------------------------------------------------------------------

// 执行后台任务，如加载详细数据
- (void)doBackgroundTasks
{
  // 更新状态为任务开始
  [dataController updateStatus:MVStatusTaskStarted];
  
  // 遍历所有已解析的成员对象信息
  for (MVObjectInfo * objectInfo in [objectInfoMap allValues])
  {
    // 获取对象的布局处理器
    MVLayout * layout = objectInfo.layout;
    
    // if the thread is cancelled, then the MVLayout::doBackgroundTasks will not been called
    // so, here is the only chance to stop the saver thread for the particular layout
    // 检查后台线程是否已取消
    if ([backgroundThread isCancelled])
    {
      // 如果取消，停止该布局的归档保存器
      [layout.archiver halt];
      // 跳过后续处理
      continue;
    }

    // the MVLayout::doBackgroundTasks is called before this returns
    // 递归执行子布局的后台任务
    [layout doBackgroundTasks];
  }
  
  // 调用父类的后台任务
  [super doBackgroundTasks];
  
  // 更新状态为任务终止
  [dataController updateStatus:MVStatusTaskTerminated];
}
//----------------------------------------------------------------------------

@end
