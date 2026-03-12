/*
 *  DyldInfo.mm
 *  MachOView
 *
 *  Created by psaghelyi on 21/09/2010.
 *
 */

// 引入 C++ 标准库
#include <string>
#include <vector>
#include <set>
#include <map>

// 引入公共头文件
#import "Common.h"
// 引入 DyldInfo 头文件
#import "DyldInfo.h"
// 引入读写工具头文件
#import "ReadWrite.h"
// 引入数据控制器头文件
#import "DataController.h"
// 引入 Mach-O 加载器定义
#import <mach-o/loader.h>

// 使用标准命名空间
using namespace std;


//============================================================================
// DyldHelper 实现：辅助类，用于处理外部符号映射
//============================================================================
@implementation DyldHelper

//-----------------------------------------------------------------------------
// 初始化方法：根据符号表构建外部符号映射
- (instancetype) initWithSymbols:(NSDictionary *)symbolNames is64Bit:(bool)is64Bit
{
  // 调用父类初始化
  if (self = [super init])
  {
    // 初始化外部映射字典
    externalMap = [[NSMutableDictionary alloc] initWithCapacity:[symbolNames count]];
    
    // 遍历符号名字典
    NSEnumerator * enumerator = [symbolNames keyEnumerator];
    id key;
    while ((key = [enumerator nextObject]) != nil) 
    {
      // 获取符号索引
      NSNumber * symbolIndex = (NSNumber *)key;
      // 负数索引表示它是外部符号（External Symbol）
      // negative index indicates that it is external
      if ((is64Bit == NO && (int32_t)[symbolIndex unsignedLongValue] < 0) ||
          (int64_t)[symbolIndex unsignedLongLongValue] < 0)
      {
        // 将其加入映射表
        [externalMap setObject:key forKey:[symbolNames objectForKey:key]];
      }
    }
  }
  // 返回实例
  return self;
}

//-----------------------------------------------------------------------------
// 工厂方法：创建 DyldHelper 实例
+(DyldHelper *) dyldHelperWithSymbols:(NSDictionary *)symbolNames is64Bit:(bool)is64Bit
{
  // 分配并初始化
  return [[DyldHelper alloc] initWithSymbols:symbolNames is64Bit:is64Bit];
}

//-----------------------------------------------------------------------------
// 根据符号名查找索引
-(NSNumber *) indexForSymbol:(NSString *)symbolName
{
  // 从映射表中获取
  return [externalMap objectForKey:symbolName];
}

@end


//============================================================================
// MachOLayout (DyldInfo) 分类实现：扩展 MachOLayout 以解析 Dyld 信息
//============================================================================
@implementation MachOLayout (DyldInfo)


//-----------------------------------------------------------------------------
// 辅助方法：记录重定位地址信息到详情表
- (void)rebaseAddress:(uint64_t)address 
                 type:(uint32_t)type 
                 node:(MVNode *)node
             location:(uint64_t)location
{
  // 格式化描述字符串：包含段名、地址和类型
  NSString * descStr = [NSString stringWithFormat:@"%@ 0x%qX %@",
                        [self findSectionContainsRVA:address],
                        address,
                        type == REBASE_TYPE_POINTER ? @"Pointer" :
                        type == REBASE_TYPE_TEXT_ABSOLUTE32 ? @"Abs32  " :
                        type == REBASE_TYPE_TEXT_PCREL32 ? @"PCrel32" : @"???"];
  
  // 向详情表添加一行记录
  [node.details appendRow:[NSString stringWithFormat:@"%.8qX", location]
                         :@""
                         :descStr
                         :@""];
}

//-----------------------------------------------------------------------------
// 创建重定位（Rebase）信息节点，解析重定位操作码
- (MVNode *)createRebaseNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                 baseAddress:(uint64_t)baseAddress
{
  // 创建数据节点
  MVNode * dataNode = [self createDataNode:parent 
                                   caption:caption 
                                  location:location 
                                    length:length];

  // 插入 "Opcodes" 子节点用于显示操作码流
  MVNodeSaver nodeSaver;
  MVNode * node = [dataNode insertChildWithDetails:@"Opcodes" location:location length:length saver:nodeSaver];
  
  // 插入 "Actions" 子节点用于显示重定位结果
  MVNodeSaver actionNodeSaver;
  MVNode * actionNode = [dataNode insertChildWithDetails:@"Actions" location:location length:length saver:actionNodeSaver];
  
  // 初始化当前处理范围
  NSRange range = NSMakeRange(location,0);
  NSString * lastReadHex;  

  // 解析状态变量
  BOOL isDone = NO;
  
  // 获取指针大小（32位为4字节，64位为8字节）
  uint64_t ptrSize = ([self is64bit] == NO ? sizeof(uint32_t) : sizeof(uint64_t));
  // 当前重定位地址
  uint64_t address = baseAddress;
  // 当前重定位类型
  uint32_t type = 0;
  
  // 记录执行重定位操作的文件位置
  uint64_t doRebaseLocation = location;
  
  // 循环解析直到结束或超出范围
  while (NSMaxRange(range) < location + length && isDone == NO)
  {
    // 读取一个字节作为操作码
    uint8_t byte = [dataController read_int8:range lastReadHex:&lastReadHex];
    // 提取操作码（高4位）
    uint8_t opcode = byte & REBASE_OPCODE_MASK;
    // 提取立即数（低4位）
    uint8_t immediate = byte & REBASE_IMMEDIATE_MASK;
    
    // 根据操作码进行分发
    switch (opcode) 
    {
      // 结束标记
      case REBASE_OPCODE_DONE:
        isDone = YES;

        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_DONE"
                               :@""];
        break;
        
      // 设置重定位类型（立即数）
      case REBASE_OPCODE_SET_TYPE_IMM:
        {
            type = immediate;
            NSString *typeString = [NSString alloc];
            switch (type)
            {
                case REBASE_TYPE_POINTER:
                    typeString = [typeString initWithString:@"REBASE_TYPE_POINTER"];
                    break;
                case REBASE_TYPE_TEXT_ABSOLUTE32:
                    typeString  = [typeString initWithString:@"REBASE_TYPE_TEXT_ABSOLUTE32"];
                    break;
                case REBASE_TYPE_TEXT_PCREL32:
                    typeString = [typeString initWithString:@"REBASE_TYPE_TEXT_PCREL32"];
                    break;
                default:
                    typeString = [typeString initWithString:@"Unknown"];
            }
            
            [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                                   :lastReadHex
                                   :@"REBASE_OPCODE_SET_TYPE_IMM"
                                   :[NSString stringWithFormat:@"type (%i, %@)", type, typeString]];
            break;
        }
      // 设置段索引和偏移（ULEB128）
      case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: 
      {
        uint32_t segmentIndex = immediate;
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB"
                               :[NSString stringWithFormat:@"segment (%u)", segmentIndex]];
         
        // 读取偏移量
        uint64_t offset = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",offset]];
        
        // 检查段索引是否越界
        if (([self is64bit] == NO && segmentIndex >= segments.size()) || 
            ([self is64bit] == YES && segmentIndex >= segments_64.size())) 
        {
          [NSException raise:@"Segment"
                      format:@"index is out of range %u", segmentIndex];
        }
        
        // 计算新的基准地址：段起始地址 + 偏移量
        address = ([self is64bit] == NO ? segments.at(segmentIndex)->vmaddr 
                                        : segments_64.at(segmentIndex)->vmaddr) + offset;
      } break;
        
      // 增加地址（ULEB128）
      case REBASE_OPCODE_ADD_ADDR_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_ADD_ADDR_ULEB"
                               :@""];
         
        // 读取增加的偏移量
        uint64_t offset = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",offset]];
        
        // 更新地址
        address += offset;
      } break;
        
      // 增加地址（立即数 * 指针大小）
      case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
      {
        uint32_t scale = immediate;
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_ADD_ADDR_IMM_SCALED"
                               :[NSString stringWithFormat:@"scale (%u)",scale]];
        
        // 更新地址
        address += scale * ptrSize;
      } break;
        
      // 执行重定位（立即数次数）
      case REBASE_OPCODE_DO_REBASE_IMM_TIMES: 
      {
        uint32_t count = immediate;
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_DO_REBASE_IMM_TIMES"
                               :[NSString stringWithFormat:@"count (%u)",count]];

        // 设置下划线属性以分隔块
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        // 循环执行重定位
        for (uint32_t index = 0; index < count; index++) 
        {
          [self rebaseAddress:address type:type node:actionNode location:doRebaseLocation];
          address += ptrSize;
        }
        
        // 更新重定位位置标记
        doRebaseLocation = NSMaxRange(range);
        
      } break;
        
      // 执行重定位（ULEB128次数）
      case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_DO_REBASE_ULEB_TIMES"
                               :@""];
        
        uint64_t startNextRebase = NSMaxRange(range);
        
        // 读取次数
        uint64_t count = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"count (%qu)",count]];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        // 循环执行重定位
        for (uint64_t index = 0; index < count; index++) 
        {
          [self rebaseAddress:address type:type node:actionNode location:doRebaseLocation];
          address += ptrSize;
        }
        
        doRebaseLocation = startNextRebase;
        
      } break;
        
      // 执行重定位并增加地址（ULEB128）
      case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB"
                               :@""];
        
        uint64_t startNextRebase = NSMaxRange(range);
        
        // 读取增加的偏移量
        uint64_t offset = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",offset]];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        // 执行一次重定位
        [self rebaseAddress:address type:type node:actionNode location:doRebaseLocation];
        // 更新地址
        address += ptrSize + offset;
        
        doRebaseLocation = startNextRebase;
        
      } break;
        
      // 执行重定位（ULEB128次数），每次跳过指定字节数（ULEB128）
      case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB"
                               :@""];
        
        uint64_t startNextRebase = NSMaxRange(range);
        
        // 读取次数
        uint64_t count = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"count (%qu)",count]];

        // 读取跳过字节数
        uint64_t skip = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"skip (%qu)",skip]];

        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        // 循环执行重定位
        for (uint64_t index = 0; index < count; index++) 
        {
          [self rebaseAddress:address type:type node:actionNode location:doRebaseLocation];
          address += ptrSize + skip;
        }
        
        doRebaseLocation = startNextRebase;
        
      } break;
        
      // 未知操作码
      default:
        [NSException raise:@"Rebase info" format:@"Unknown opcode (%u %u)", 
         ((uint32_t)-1 & opcode), ((uint32_t)-1 & immediate)];
    }
  }
  
  return node;
}


//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------



//-----------------------------------------------------------------------------
// 辅助方法：记录绑定信息到详情表，并可选地修补内存中的重定位值
- (void)bindAddress:(uint64_t)address 
               type:(uint32_t)type 
         symbolName:(NSString *)symbolName 
              flags:(uint32_t)flags
             addend:(int64_t)addend 
     libraryOrdinal:(int32_t)libOrdinal
               node:(MVNode *)node
           nodeType:(BindNodeType)nodeType
           location:(uint64_t)location
         dyldHelper:(DyldHelper *)helper
            ptrSize:(size_t)ptrSize
{
  // 格式化描述字符串：包含段名和地址
  NSString * descStr = [NSString stringWithFormat:@"%@ 0x%qX", 
                        [self findSectionContainsRVA:address],
                        address];
  
  // 如果不是延迟绑定，添加绑定类型和增量信息
  if (nodeType != NodeTypeLazyBind)
  {
    descStr = [descStr stringByAppendingFormat:@" %@ addend:%qi",
               type == BIND_TYPE_POINTER ? @"Pointer" :
               type == BIND_TYPE_TEXT_ABSOLUTE32 ? @"Abs32  " :
               type == BIND_TYPE_TEXT_PCREL32 ? @"PCrel32" : @"type:???",
               addend];
  }
  
  // 添加弱引用标志
  if ((flags & BIND_SYMBOL_FLAGS_WEAK_IMPORT) != 0)
  {
    descStr = [descStr stringByAppendingString:@"[weak-ref]"];
  }
  // 添加强定义标志
  if ((flags & BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION) != 0)
  {
    descStr = [descStr stringByAppendingString:@"[strong-def]"];
  }
   
  // 如果不是弱绑定，添加库信息
  if (nodeType != NodeTypeWeakBind)
  {
    struct dylib const * dylib = [self getDylibByIndex:libOrdinal];
    
    // 解析库序数
    descStr = [descStr stringByAppendingFormat:@" (%@)", 
               libOrdinal == BIND_SPECIAL_DYLIB_SELF ? @"BIND_SPECIAL_DYLIB_SELF" :
               libOrdinal == BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE ? @"BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE" :
               libOrdinal == BIND_SPECIAL_DYLIB_FLAT_LOOKUP ? @"BIND_SPECIAL_DYLIB_FLAT_LOOKUP" :
               (uint32_t)libOrdinal >= dylibs.size() ? @"???" :
                 [NSSTRING((uint8_t *)dylib + dylib->name.offset - sizeof(struct load_command)) lastPathComponent]];
  }
  
  // 添加详情行
  [node.details appendRow:[NSString stringWithFormat:@"%.8qX", location]
                         :@""
                         :descStr
                         :symbolName];

  // 设置元数据属性
  [node.details setAttributes:MVMetaDataAttributeName,symbolName,nil];
  
  // 为非 stub 的普通绑定保留绑定信息用于重定位修补
  // preserve binding info for reloc pathcing
  if ([self isDylibStub] == NO && nodeType == NodeTypeBind) // weak and lazy does not count
  {
    // 目前仅支持指针类型绑定
    NSParameterAssert(type == BIND_TYPE_POINTER); // only this one is supported so far
    
    // 查找符号索引
    NSNumber * symbolIndex = [helper indexForSymbol:symbolName];
    if (symbolIndex != nil)
    {
      uint64_t relocLocation;
      uint64_t relocValue;
      // 将 RVA 转换为文件偏移
      relocLocation = [self RVAToFileOffset:address];
      
      // 获取符号索引值（处理32/64位）
      if ([self is64bit] == NO) {
        relocValue = [symbolIndex longValue];
      }
      else {
        relocValue = [symbolIndex longLongValue];
      }
      
      // 更新实际数据：索引值 + 增量
      // update real data
      relocValue += addend;
      // 替换内存中的数据
      [dataController.realData replaceBytesInRange:NSMakeRange(relocLocation, ptrSize) withBytes:&relocValue];
      
      /*
        NSLog(@"%0xqX --> %0xqX", 
              ([self is64bit] == NO ? [self fileOffsetToRVA:relocLocation] : [self fileOffsetToRVA64:relocLocation]),
              relocValue);
       */
    }
  }
}
//-----------------------------------------------------------------------------
      
// 创建绑定（Binding）信息节点，解析绑定操作码
- (MVNode *)createBindingNode:(MVNode *)parent
                      caption:(NSString *)caption
                     location:(uint64_t)location
                       length:(uint64_t)length
                  baseAddress:(uint64_t)baseAddress
                     nodeType:(BindNodeType)nodeType
                   dyldHelper:(DyldHelper *)helper
{
  // 创建数据节点
  MVNode * dataNode = [self createDataNode:parent 
                                   caption:caption 
                                  location:location 
                                    length:length];
  
  // 插入 "Opcodes" 子节点
  MVNodeSaver nodeSaver;
  MVNode * node = [dataNode insertChildWithDetails:@"Opcodes" location:location length:length saver:nodeSaver];
  
  // 插入 "Actions" 子节点
  MVNodeSaver actionNodeSaver;
  MVNode * actionNode = [dataNode insertChildWithDetails:@"Actions" location:location length:length saver:actionNodeSaver];
  
  // 初始化范围
  NSRange range = NSMakeRange(location,0);
  NSString * lastReadHex;

  //----------------------------
  
  // 状态变量
  BOOL isDone = NO;
  
  int32_t libOrdinal = 0;
  uint32_t type = 0;
  int64_t addend = 0;
  NSString * symbolName = nil;
  uint32_t symbolFlags = 0;
  
  uint64_t doBindLocation = location;
  
  size_t ptrSize = ([self is64bit] == NO ? sizeof(uint32_t) : sizeof(uint64_t));
  uint64_t address = baseAddress;
  
  // 循环解析
  while (NSMaxRange(range) < location + length && isDone == NO)
  {
    // 读取字节
    uint8_t byte = [dataController read_int8:range lastReadHex:&lastReadHex];
    uint8_t opcode = byte & BIND_OPCODE_MASK;
    uint8_t immediate = byte & BIND_IMMEDIATE_MASK;
    
    switch (opcode) 
    {
      // 结束标记
      case BIND_OPCODE_DONE:
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_DONE"
                               :@""];
        
        // 延迟绑定（Lazy Bind）在每次绑定结束时都有一个 DONE，但不代表整个流程结束
        // The lazy bindings have one of these at the end of each bind.
        if (nodeType != NodeTypeLazyBind)
        {
          isDone = YES;
        }
        
        doBindLocation = NSMaxRange(range);
        
        break;
        
      // 设置库序数（立即数）
      case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
        libOrdinal = immediate;
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_DYLIB_ORDINAL_IMM"
                               :[NSString stringWithFormat:@"dylib (%d)",libOrdinal]];
        break;
        
      // 设置库序数（ULEB128）
      case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB"
                               :@""];
        // XXX: is this correct?
        libOrdinal = (int32_t)[dataController read_uleb128:range lastReadHex:&lastReadHex];
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"dylib (%d)",libOrdinal]];
        break;
        
      // 设置特殊库序数（立即数）
      case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: 
      {
        // Special means negative
        if (immediate == 0)
        {
          libOrdinal = 0;
        }
        else 
        {
          // 符号扩展
          int8_t signExtended = immediate | BIND_OPCODE_MASK; // This sign extends the value
          
          libOrdinal = signExtended;
        }
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_DYLIB_SPECIAL_IMM"
                               :[NSString stringWithFormat:@"dylib (%d)",libOrdinal]];
      } break;
        
      // 设置符号及标志（立即数）
      case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
        symbolFlags = immediate;
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM"
                               :[NSString stringWithFormat:@"flags (%u)",((uint32_t)-1 & symbolFlags)]];
        
        // 读取符号名字符串
        symbolName = [dataController read_string:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"string"
                               :[NSString stringWithFormat:@"name (%@)",symbolName]];
        break;
        
      // 设置绑定类型（立即数）
      case BIND_OPCODE_SET_TYPE_IMM:
        type = immediate;
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_TYPE_IMM"
                               :[NSString stringWithFormat:@"type (%@)",
                                 type == BIND_TYPE_POINTER ? @"BIND_TYPE_POINTER" :
                                 type == BIND_TYPE_TEXT_ABSOLUTE32 ? @"BIND_TYPE_TEXT_ABSOLUTE32" :
                                 type == BIND_TYPE_TEXT_PCREL32 ? @"BIND_TYPE_TEXT_PCREL32" : @"???"]];
        break;
        
      // 设置增量（SLEB128）
      case BIND_OPCODE_SET_ADDEND_SLEB:
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_ADDEND_SLEB"
                               :@""];
        
        addend = [dataController read_sleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"sleb128"
                               :[NSString stringWithFormat:@"addend (%qi)",addend]];
        break;
        
      // 设置段索引和偏移（ULEB128）
      case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: 
      {
        uint32_t segmentIndex = immediate;
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB"
                               :[NSString stringWithFormat:@"segment (%u)",segmentIndex]];
        
        uint64_t val = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",val]];
        
        // 检查索引越界
        if (([self is64bit] == NO && segmentIndex >= segments.size()) || 
            ([self is64bit] == YES && segmentIndex >= segments_64.size())) 
        {
          [NSException raise:@"Segment"
                      format:@"index is out of range %u", segmentIndex];
        }
        
        // 计算地址
        address = ([self is64bit] == NO ? segments.at(segmentIndex)->vmaddr 
                                        : segments_64.at(segmentIndex)->vmaddr) + val;
      } break;
        
      // 增加地址（ULEB128）
      case BIND_OPCODE_ADD_ADDR_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_ADD_ADDR_ULEB"
                               :@""];
        
        uint64_t val = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",val]];

        address += val;
      } break;
        
      // 执行绑定
      case BIND_OPCODE_DO_BIND:
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_DO_BIND"
                               :@""];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        [self bindAddress:address 
                     type:type 
               symbolName:symbolName 
                    flags:symbolFlags 
                   addend:addend 
           libraryOrdinal:libOrdinal 
                     node:actionNode
                 nodeType:nodeType
                 location:doBindLocation
               dyldHelper:helper
                  ptrSize:ptrSize];
        
        doBindLocation = NSMaxRange(range);
        
        address += ptrSize;
      } break;
        
      // 执行绑定并增加地址（ULEB128）
      case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB"
                               :@""];

        uint64_t startNextBind = NSMaxRange(range);
        
        uint64_t val = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"offset (%qi)",val]];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        [self bindAddress:address 
                     type:type 
               symbolName:symbolName 
                    flags:symbolFlags 
                   addend:addend 
           libraryOrdinal:libOrdinal 
                     node:actionNode
                 nodeType:nodeType
                 location:doBindLocation
               dyldHelper:helper
                  ptrSize:ptrSize];
        
        doBindLocation = startNextBind;
        
        address += ptrSize + val;
      } break;
        
      // 执行绑定并增加地址（立即数 * 指针大小）
      case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
      {
        uint32_t scale = immediate;
        
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED"
                               :[NSString stringWithFormat:@"scale (%u)",scale]];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        [self bindAddress:address 
                     type:type 
               symbolName:symbolName 
                    flags:symbolFlags 
                   addend:addend 
           libraryOrdinal:libOrdinal 
                     node:actionNode
                 nodeType:nodeType
                 location:doBindLocation
               dyldHelper:helper
                  ptrSize:ptrSize];
        
        doBindLocation = NSMaxRange(range);
        
        address += ptrSize + scale * ptrSize;
      } break;
        
      // 执行绑定（ULEB128次数），每次跳过指定字节（ULEB128）
      case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: 
      {
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB"
                               :@""];
        
        uint64_t startNextBind = NSMaxRange(range);
        
        uint64_t count = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"count (%qu)",count]];
        
        uint64_t skip = [dataController read_uleb128:range lastReadHex:&lastReadHex];
        [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                               :lastReadHex
                               :@"uleb128"
                               :[NSString stringWithFormat:@"skip (%qu)",skip]];
        
        [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
        
        for (uint64_t index = 0; index < count; index++) 
        {
          [self bindAddress:address 
                       type:type 
                 symbolName:symbolName 
                      flags:symbolFlags 
                     addend:addend 
             libraryOrdinal:libOrdinal 
                       node:actionNode
                   nodeType:nodeType
                   location:doBindLocation
                 dyldHelper:helper
                    ptrSize:ptrSize];
          
          doBindLocation = startNextBind;
          
          address += ptrSize + skip;
        }
      } break;
        
      // 未知操作码
      default:
        [NSException raise:@"Bind info" format:@"Unknown opcode (%u %u)", 
         ((uint32_t)-1 & opcode), ((uint32_t)-1 & immediate)];
    }
  }

  return node;
}
//-----------------------------------------------------------------------------

// 辅助方法：记录导出符号到详情表
- (void)exportSymbol:(uint64_t)address 
          symbolName:(NSString *)symbolName
               flags:(uint64_t)flags 
                node:(MVNode *)node
            location:(uint64_t)location
{
  //uint64_t address = [self is64bit] == NO ? [self fileOffsetToRVA:offset] : [self fileOffsetToRVA64:offset];
  
  // 格式化描述字符串
  NSString * descStr = [NSString stringWithFormat:@"%@ 0x%qX",
                        [self findSectionContainsRVA:address],
                        address];
  
  // 处理导出符号标志
  if ((flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) == EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL)
  {
    descStr = [descStr stringByAppendingString:@" [thread-local]"];
  }

  if (flags & EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION)
  {
    descStr = [descStr stringByAppendingString:@" [weak-def]"];
  }

  if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT)
  {
    descStr = [descStr stringByAppendingString:@" [reexport]"];
  }

  if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER)
  {
    descStr = [descStr stringByAppendingString:@" [stub & resolver]"];
  }
  
  // 插入详情行
  [node.details insertRowWithOffset:location
                                   :[NSString stringWithFormat:@"%.8qX", location]
                                   :@""
                                   :descStr
                                   :symbolName];
  
  // 设置元数据属性
  [node.details setAttributes:MVMetaDataAttributeName,symbolName,nil];
}
//-----------------------------------------------------------------------------

// 递归遍历导出符号 Trie 树
- (void)printSymbols:(NSString *)prefix                    
            location:(uint64_t)location
           skipBytes:(uint64_t)skip
                node:(MVNode *)node
          actionNode:(MVNode *)actionNode
         baseAddress:(uint64_t)baseAddress
      exportLocation:(uint64_t &)exportLocation
{
  // 计算当前读取范围
  NSRange range = NSMakeRange(location + skip,0);
  NSString * lastReadHex;

  // 读取终端节点大小
  uint8_t terminalSize = [dataController read_uint8:range lastReadHex:&lastReadHex];
  [node.details insertRowWithOffset:range.location
                                   :[NSString stringWithFormat:@"%.8lX", range.location]
                                   :lastReadHex
                                   :@"Terminal Size"
                                   :[NSString stringWithFormat:@"%u",((uint32_t)-1 & terminalSize)]];
  
  // 如果终端大小不为 0，说明当前节点对应一个导出符号
  if (terminalSize != 0) 
  {
    uint64_t terminalLocation = NSMaxRange(range);
    
    // 读取标志
    uint64_t flags = [dataController read_uleb128:range lastReadHex:&lastReadHex];
    [node.details insertRowWithOffset:range.location
                                     :[NSString stringWithFormat:@"%.8lX", range.location]
                                     :lastReadHex
                                     :@"Flags"
                                     :@""];

    // 解析标志位并添加到详情
    if ((flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) == EXPORT_SYMBOL_FLAGS_KIND_REGULAR)      [node.details insertRowWithOffset:range.location:@"":@"":@"00":@"EXPORT_SYMBOL_FLAGS_KIND_REGULAR"];
    if ((flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) == EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL) [node.details insertRowWithOffset:range.location:@"":@"":@"01":@"EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL"];
    if (flags & EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION)                                      [node.details insertRowWithOffset:range.location:@"":@"":@"04":@"EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION"];
    if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT)                                             [node.details insertRowWithOffset:range.location:@"":@"":@"08":@"EXPORT_SYMBOL_FLAGS_REEXPORT"];
    if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER)                                    [node.details insertRowWithOffset:range.location:@"":@"":@"10":@"EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER"];
    
    // 读取符号偏移
    uint64_t offset = [dataController read_uleb128:range lastReadHex:&lastReadHex];
    [node.details insertRowWithOffset:range.location
                                     :[NSString stringWithFormat:@"%.8lX", range.location]
                                     :lastReadHex
                                     :@"Symbol Offset"
                                     :[NSString stringWithFormat:@"0x%qX",offset]];
    
    //=================================================================
    // 记录导出符号信息
    [self exportSymbol:baseAddress + offset
            symbolName:prefix
                 flags:flags 
                  node:actionNode
              location:exportLocation];
    //=================================================================
    
    range = NSMakeRange(terminalLocation, terminalSize);
  }
  
  // 读取子节点数量
  uint8_t childCount = [dataController read_uint8:range lastReadHex:&lastReadHex];
  [node.details insertRowWithOffset:range.location
                                   :[NSString stringWithFormat:@"%.8lX", range.location]
                                   :lastReadHex
                                   :@"Child Count"
                                   :[NSString stringWithFormat:@"%u",((uint32_t)-1 & childCount)]];
  
  // 如果没有子节点，添加分隔线
  if (childCount == 0)
  {
    // separate export nodes
    [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
  }
  
  // 遍历子节点
  while (childCount-- > 0)
  {
    exportLocation = NSMaxRange(range);
    
    // 读取边上的标签字符串（Trie 树的边）
    NSString * label = [dataController read_string:range lastReadHex:&lastReadHex];
    [node.details insertRowWithOffset:range.location
                                     :[NSString stringWithFormat:@"%.8lX", range.location]
                                     :lastReadHex
                                     :@"Node Label"
                                     :[NSString stringWithFormat:@"\"%@\"",label]];
     
    // 读取下一节点的跳过字节数
    uint64_t skip = [dataController read_uleb128:range lastReadHex:&lastReadHex];
    [node.details insertRowWithOffset:range.location
                                     :[NSString stringWithFormat:@"%.8lX", range.location]
                                     :lastReadHex
                                     :@"Next Node"
                                     :[NSString stringWithFormat:@"0x%qX",[self fileOffsetToRVA:location + skip]]];
    
    if (childCount == 0)
    {
      // separate export nodes
      [node.details setAttributes:MVUnderlineAttributeName,@"YES",nil];
    }
    
    // 递归打印子树，累加前缀
    [self printSymbols:[NSString stringWithFormat:@"%@%@", prefix, label]
              location:location
             skipBytes:skip
                  node:node 
            actionNode:actionNode
           baseAddress:baseAddress
        exportLocation:exportLocation];
  }
}
//-----------------------------------------------------------------------------

// 创建导出（Export）符号信息节点
- (MVNode *)createExportNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                 baseAddress:(uint64_t)baseAddress
{
  // 创建数据节点
  MVNode * dataNode = [self createDataNode:parent 
                                   caption:caption 
                                  location:location 
                                    length:length];
  
  // 插入 "Opcodes" 子节点（此处实际显示 Trie 树结构）
  MVNodeSaver nodeSaver;
  MVNode * node = [dataNode insertChildWithDetails:@"Opcodes" location:location length:length saver:nodeSaver];
  
  // 插入 "Actions" 子节点（显示最终导出符号列表）
  MVNodeSaver actionNodeSaver;
  MVNode * actionNode = [dataNode insertChildWithDetails:@"Actions" location:location length:length saver:actionNodeSaver];
  
  uint64_t exportLocation = location;
  
  // 从根节点开始遍历 Trie 树
  // start to traverse with initial values
  [self printSymbols:@"" 
            location:location 
           skipBytes:0 
                node:node
          actionNode:actionNode
         baseAddress:baseAddress
      exportLocation:exportLocation];
  
  // 对详情表进行排序
  // line up the details of traversal
  [node sortDetails];
  [actionNode sortDetails];
  
  return node;
}
//-----------------------------------------------------------------------------

@end
