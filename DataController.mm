/*
 *  DataController.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 引入公共头文件，包含全局定义和宏
#import "Common.h"
// 引入数据控制器头文件
#import "DataController.h"
// 引入 Mach-O 布局头文件，用于处理 Mach-O 格式
#import "MachOLayout.h"
// 引入 Fat 布局头文件，用于处理多架构二进制
#import "FatLayout.h"
// 引入归档布局头文件，用于处理静态库
#import "ArchiveLayout.h"
// 引入 Mach-O 加载器定义
#import <mach-o/loader.h>
// 引入 Fat 二进制定义
#import <mach-o/fat.h>
// 引入字节序交换工具
#import <mach-o/swap.h>

// 定义属性在交换文件中的序数值枚举
enum {
  // 下划线属性序数
  MVUnderlineAttributeOrdinal = 1,
  // 单元格颜色属性序数
  MVCellColorAttributeOrdinal,
  // 文本颜色属性序数
  MVTextColorAttributeOrdinal,
  // 元数据属性序数
  MVMetaDataAttributeOrdinal
};

// 定义颜色在交换文件中的序数值枚举
enum {
  // 黑色序数
  MVBlackColorOrdinal = 1,
  // 深灰色序数
  MVDarkGrayColorOrdinal,
  // 浅灰色序数
  MVLightGrayColorOrdinal,
  // 白色序数
  MVWhiteColorOrdinal,
  // 灰色序数
  MVGrayColorOrdinal,
  // 红色序数
  MVRedColorOrdinal,
  // 绿色序数
  MVGreenColorOrdinal,
  // 蓝色序数
  MVBlueColorOrdinal,
  // 青色序数
  MVCyanColorOrdinal,
  // 黄色序数
  MVYellowColorOrdinal,
  // 洋红色序数
  MVMagentaColorOrdinal,
  // 橙色序数
  MVOrangeColorOrdinal,
  // 紫色序数
  MVPurpleColorOrdinal,
  // 棕色序数
  MVBrownColorOrdinal
};

// 定义下划线属性名称常量
NSString * const MVUnderlineAttributeName         = @"MVUnderlineAttribute";
// 定义单元格颜色属性名称常量
NSString * const MVCellColorAttributeName         = @"MVCellColorAttribute";
// 定义文本颜色属性名称常量
NSString * const MVTextColorAttributeName         = @"MVTextColorAttribute";
// 定义元数据属性名称常量
NSString * const MVMetaDataAttributeName          = @"MVMetaDataAttribute";

// 定义布局用户信息键名常量
NSString * const MVLayoutUserInfoKey              = @"MVLayoutUserInfoKey";
// 定义节点用户信息键名常量
NSString * const MVNodeUserInfoKey                = @"MVNodeUserInfoKey";
// 定义状态用户信息键名常量
NSString * const MVStatusUserInfoKey              = @"MVStatusUserInfoKey";

// 定义数据树即将变更通知名称
NSString * const MVDataTreeWillChangeNotification = @"MVDataTreeWillChangeNotification";
// 定义数据树已变更通知名称
NSString * const MVDataTreeDidChangeNotification  = @"MVDataTreeDidChangeNotification";
// 定义数据树变更通知名称（用于刷新视图）
NSString * const MVDataTreeChangedNotification    = @"MVDataTreeChanged";
// 定义数据表变更通知名称
NSString * const MVDataTableChangedNotification   = @"MVDataTableChanged";
// 定义线程状态变更通知名称
NSString * const MVThreadStateChangedNotification = @"MVThreadStateChanged";

// 定义任务开始状态字符串
NSString * const MVStatusTaskStarted              = @"MVStatusTaskStarted";
// 定义任务终止状态字符串
NSString * const MVStatusTaskTerminated           = @"MVStatusTaskTerminated";

//============================================================================
// MVColumns 实现：表示表格的一行数据（四列字符串）
//============================================================================
@implementation MVColumns

// 合成 offsetStr, dataStr, descriptionStr, valueStr 属性的存取方法
@synthesize offsetStr, dataStr, descriptionStr, valueStr;

//-----------------------------------------------------------------------------
// 默认初始化方法
- (instancetype)init
{
  // 调用父类的初始化方法
  self = [super init];
  // 如果初始化成功
  if (self)
  {
#ifdef MV_STATISTICS
    // 原子操作增加已加载行数计数
    OSAtomicIncrement64(&nrow_loaded);
#endif
  }
  // 返回初始化后的实例
  return self;
}

//-----------------------------------------------------------------------------
// 带数据的初始化方法，分别设置四列的内容
-(id)initWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3
{
  // 调用父类的初始化方法，并将结果赋值给 self
  if (self = [super init])
  {
    // 设置第一列（偏移量）字符串
    offsetStr = col0;
    // 设置第二列（数据）字符串
    dataStr = col1;
    // 设置第三列（描述）字符串
    descriptionStr = col2;
    // 设置第四列（值）字符串
    valueStr = col3;

#ifdef MV_STATISTICS
    // 原子操作增加已加载行数计数
    OSAtomicIncrement64(&nrow_loaded);
#endif
  }
  // 返回初始化后的实例
  return self;
}

//-----------------------------------------------------------------------------
// 类工厂方法：创建一个包含指定数据的 MVColumns 实例
+(MVColumns *) columnsWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3
{
  // 分配内存并初始化 MVColumns 对象
  return [[MVColumns alloc] initWithData:col0:col1:col2:col3];
}

//-----------------------------------------------------------------------------
// 析构方法
-(void)dealloc
{
#ifdef MV_STATISTICS
  // 原子操作减少已加载行数计数
  OSAtomicDecrement64(&nrow_loaded);
#endif
}

@end


//============================================================================
// MVRow 实现：表示表格中的一行，包含列数据和属性
//============================================================================
@implementation MVRow

// 合成 columns, attributes, offset, deleted, dirty 属性的存取方法
@synthesize columns, attributes, offset, deleted, dirty;

//-----------------------------------------------------------------------------
// 默认初始化方法
- (instancetype)init
{
  // 调用父类的初始化方法
  self = [super init];
  // 如果初始化成功
  if (self)
  {
#ifdef MV_STATISTICS
    // 原子操作增加总行数计数
    OSAtomicIncrement64(&nrow_total);
#endif
  }
  // 返回初始化后的实例
  return self;
}

//-----------------------------------------------------------------------------
// 析构方法
-(void)dealloc
{
#ifdef MV_STATISTICS
  // 原子操作减少总行数计数
  OSAtomicDecrement64(&nrow_total);
#endif
}

//-----------------------------------------------------------------------------
// 根据索引获取对应列的字符串内容
-(NSString *)columnAtIndex:(NSUInteger)index
{
  // 根据索引进行分支判断
  switch (index)
  {
    // 如果是偏移量列，返回 offsetStr
    case OFFSET_COLUMN:       return columns.offsetStr;
    // 如果是数据列，返回 dataStr
    case DATA_COLUMN:         return columns.dataStr;
    // 如果是描述列，返回 descriptionStr
    case DESCRIPTION_COLUMN:  return columns.descriptionStr;
    // 如果是值列，返回 valueStr
    case VALUE_COLUMN:        return columns.valueStr;
  }
  // 如果索引无效，返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 替换指定列的字符串内容
-(void)replaceColumnAtIndex:(NSUInteger)index withString:(NSString *)str
{
    // 将 columnsOffset 置为 0，标记列数据需要重新保存
    columnsOffset = 0;
    // 根据索引进行分支判断
    switch (index)
    {
        // 如果是偏移量列，更新 offsetStr
        case OFFSET_COLUMN:       columns.offsetStr = str; break;
        // 如果是数据列，更新 dataStr
        case DATA_COLUMN:         columns.dataStr = str;  break;
        // 如果是描述列，更新 descriptionStr
        case DESCRIPTION_COLUMN: columns.descriptionStr = str; break;
        // 如果是值列，更新 valueStr
        case VALUE_COLUMN:        columns.valueStr = str; break;
    }
}

//-----------------------------------------------------------------------------
// 辅助方法：将 NSString 写入文件
- (void)writeString:(NSString *)str toFile:(FILE *)pFile
{
    // 如果字符串不为空
    if (str) {
        // 将字符串转换为 C 字符串并写入文件（包含结尾的空字符）
        fwrite(CSTRING(str), [str length] + 1, 1, pFile);
    } else {
        // 如果字符串为空，写入一个空字符作为占位符
        fputc('\0', pFile);
    }
}

//-----------------------------------------------------------------------------
// 辅助方法：从文件读取字符串
- (NSString *)readStringFromFile:(FILE *)pFile
{
  // 定义一个 C++ 字符串用于缓存读取的内容
  std::string s;
  // 无限循环读取字符
  for(;;)
  {
    // 从文件中读取一个字符
    char c = fgetc(pFile);
    // 如果未到文件末尾且字符不为空
    if (!feof(pFile) && c)
      // 将字符追加到字符串中
      s += c;
    else
      // 否则跳出循环
      break;
  }
  // 将 C++ 字符串转换为 NSString 并返回
  return NSSTRING(s.c_str());
}

//-----------------------------------------------------------------------------
// 辅助方法：将 NSColor 写入文件
- (void)writeColor:(NSColor *)color toFile:(FILE *)pFile
{
  // 判断颜色是否为预定义颜色，并获取对应的序数值
  int colorOrdinal = [color isEqualTo:[NSColor blackColor]]     ? MVBlackColorOrdinal
                   : [color isEqualTo:[NSColor darkGrayColor]]  ? MVDarkGrayColorOrdinal
                   : [color isEqualTo:[NSColor lightGrayColor]] ? MVLightGrayColorOrdinal
                   : [color isEqualTo:[NSColor whiteColor]]     ? MVWhiteColorOrdinal
                   : [color isEqualTo:[NSColor grayColor]]      ? MVGrayColorOrdinal
                   : [color isEqualTo:[NSColor redColor]]       ? MVRedColorOrdinal
                   : [color isEqualTo:[NSColor greenColor]]     ? MVGreenColorOrdinal
                   : [color isEqualTo:[NSColor blueColor]]      ? MVBlueColorOrdinal
                   : [color isEqualTo:[NSColor cyanColor]]      ? MVCyanColorOrdinal
                   : [color isEqualTo:[NSColor yellowColor]]    ? MVYellowColorOrdinal
                   : [color isEqualTo:[NSColor magentaColor]]   ? MVMagentaColorOrdinal
                   : [color isEqualTo:[NSColor orangeColor]]    ? MVOrangeColorOrdinal
                   : [color isEqualTo:[NSColor purpleColor]]    ? MVPurpleColorOrdinal
                   : [color isEqualTo:[NSColor brownColor]]     ? MVBrownColorOrdinal
                   : 0;

  // 将颜色序数值写入文件
  putc(colorOrdinal, pFile);
  // 如果不是预定义颜色（序数为 0）
  if (colorOrdinal == 0) {
    // 定义红、绿、蓝、透明度分量变量
    CGFloat red, green, blue, alpha;
    // 获取颜色的各个分量值
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    // 转换为 float 类型
    float fred = red, fgreen = green, fblue = blue, falpha = alpha;
    // 写入红色分量
    fwrite(&fred, sizeof(float), 1, pFile);
    // 写入绿色分量
    fwrite(&fgreen, sizeof(float), 1, pFile);
    // 写入蓝色分量
    fwrite(&fblue, sizeof(float), 1, pFile);
    // 写入透明度分量
    fwrite(&falpha, sizeof(float), 1, pFile);
  }
}

//-----------------------------------------------------------------------------
// 辅助方法：从文件读取 NSColor
- (NSColor *)readColorFromFile:(FILE *)pFile
{
  // 从文件读取颜色序数值
  int colorOrdinal = getc(pFile);
  // 根据序数值返回对应的预定义颜色
  switch (colorOrdinal)
  {
    // 返回黑色
    case MVBlackColorOrdinal:     return [NSColor blackColor];
    // 返回深灰色
    case MVDarkGrayColorOrdinal:  return [NSColor darkGrayColor];
    // 返回浅灰色
    case MVLightGrayColorOrdinal: return [NSColor lightGrayColor];
    // 返回白色
    case MVWhiteColorOrdinal:     return [NSColor whiteColor];
    // 返回灰色
    case MVGrayColorOrdinal:      return [NSColor grayColor];
    // 返回红色
    case MVRedColorOrdinal:       return [NSColor redColor];
    // 返回绿色
    case MVGreenColorOrdinal:     return [NSColor greenColor];
    // 返回蓝色
    case MVBlueColorOrdinal:      return [NSColor blueColor];
    // 返回青色
    case MVCyanColorOrdinal:      return [NSColor cyanColor];
    // 返回黄色
    case MVYellowColorOrdinal:    return [NSColor yellowColor];
    // 返回洋红色
    case MVMagentaColorOrdinal:   return [NSColor magentaColor];
    // 返回橙色
    case MVOrangeColorOrdinal:    return [NSColor orangeColor];
    // 返回紫色
    case MVPurpleColorOrdinal:    return [NSColor purpleColor];
    // 返回棕色
    case MVBrownColorOrdinal:     return [NSColor brownColor];
  }

  // 如果不是预定义颜色，定义 float 类型的颜色分量
  float fred, fgreen, fblue, falpha;
  // 读取红色分量
  fread(&fred, sizeof(float), 1, pFile);
  // 读取绿色分量
  fread(&fgreen, sizeof(float), 1, pFile);
  // 读取蓝色分量
  fread(&fblue, sizeof(float), 1, pFile);
  // 读取透明度分量
  fread(&falpha, sizeof(float), 1, pFile);
  // 使用读取的分量创建并返回 NSColor 对象
  return [NSColor colorWithDeviceRed:fred green:fgreen blue:fblue alpha:falpha];
}

//----------------------------------------------------------------------------
// 将属性字典保存到文件
- (void)saveAttributestoFile:(FILE *)pFile
{
    // 获取属性的数量
    uint64_t numAttributes = [attributes count];
    // 写入属性数量到文件，如果写入失败则打印错误日志并返回
    if (fwrite (&numAttributes, sizeof(uint64_t), 1, pFile) < 1) {
        NSLog(@"fwrite failed in saveAttributestoFile:");
        return;
    }

  // 遍历属性字典的所有键
  for (NSString * key in [attributes allKeys]) {
    // 获取键对应的值
    id value = [attributes objectForKey:key];
    // 如果值为 nil，跳过该属性
    if (value == nil) {
      continue;
    }

    // 将键字符串转换为对应的序数值
    int keyOrdinal = [key isEqualToString:MVUnderlineAttributeName] ? MVUnderlineAttributeOrdinal
                   : [key isEqualToString:MVCellColorAttributeName] ? MVCellColorAttributeOrdinal
                   : [key isEqualToString:MVTextColorAttributeName] ? MVTextColorAttributeOrdinal
                   : [key isEqualToString:MVMetaDataAttributeName] ? MVMetaDataAttributeOrdinal
                   : 0;

    // 将键的序数值写入文件
    putc(keyOrdinal, pFile);
    // 根据键的序数值，分别处理不同类型的属性值写入
    switch (keyOrdinal)
    {
      // 写入下划线属性（字符串类型）
      case MVUnderlineAttributeOrdinal: [self writeString:value toFile:pFile]; break;
      // 写入单元格颜色属性（颜色类型）
      case MVCellColorAttributeOrdinal: [self writeColor:value toFile:pFile]; break;
      // 写入文本颜色属性（颜色类型）
      case MVTextColorAttributeOrdinal: [self writeColor:value toFile:pFile]; break;
      // 写入元数据属性（字符串类型）
      case MVMetaDataAttributeOrdinal:  [self writeString:value toFile:pFile]; break;
      // 处理未知属性键
      default: NSLog(@"warning: unknown attribute key");
    }
  }
}

//----------------------------------------------------------------------------
// 从文件加载属性字典
- (void)loadAttributesFromFile:(FILE *)pFile
{
  // 定义属性数量变量
  uint64_t numAttributes;
  // 从文件读取属性数量
  fread(&numAttributes, sizeof(uint64_t), 1, pFile);

  // 创建一个可变字典用于存储读取的属性
  NSMutableDictionary * _attributes = [[NSMutableDictionary alloc] initWithCapacity:numAttributes];
  // 循环读取每一个属性
  while (numAttributes-- > 0)
  {
    // 读取键的序数值
    int keyOrdinal = getc(pFile);
    // 根据键的序数值，分别读取对应类型的值并存入字典
    switch (keyOrdinal)
    {
      // 读取下划线属性
      case MVUnderlineAttributeOrdinal: [_attributes setObject:[self readStringFromFile:pFile] forKey:MVUnderlineAttributeName]; break;
      // 读取单元格颜色属性
      case MVCellColorAttributeOrdinal: [_attributes setObject:[self readColorFromFile:pFile] forKey:MVCellColorAttributeName]; break;
      // 读取文本颜色属性
      case MVTextColorAttributeOrdinal: [_attributes setObject:[self readColorFromFile:pFile] forKey:MVTextColorAttributeName]; break;
      // 读取元数据属性
      case MVMetaDataAttributeOrdinal:  [_attributes setObject:[self readStringFromFile:pFile] forKey:MVMetaDataAttributeName]; break;
      // 处理未知属性键
      default: NSLog(@"warning: unknown attribute key");
    }
  }

  // 将读取到的字典赋值给 attributes 属性
  attributes = _attributes;
}

//----------------------------------------------------------------------------
// 保存行数据到文件（实现了 MVSerializing 协议）
- (void)saveToFile:(FILE *)pFile
{
    // 如果列数据尚未保存（columnsOffset 为 0）
    if (columnsOffset == 0) { // isSaved == NO
        // 获取当前文件位置作为列数据的偏移量
        off_t filePos = ftello(pFile);
        // 如果获取文件位置失败
        if (filePos == -1) {
            // 打印错误日志
            NSLog(@"MVRow saveToFile: ftello failed: %s", strerror(errno));
        }
        // 写入偏移量列字符串
        [self writeString:columns.offsetStr toFile:(FILE *)pFile];
        // 写入数据列字符串
        [self writeString:columns.dataStr toFile:(FILE *)pFile];
        // 写入描述列字符串
        [self writeString:columns.descriptionStr toFile:(FILE *)pFile];
        // 写入值列字符串
        [self writeString:columns.valueStr toFile:(FILE *)pFile];
        // 更新列数据偏移量
        columnsOffset = filePos;
    }

    // 如果属性数据已修改（dirty 为 YES）
    if (dirty) {
        // 如果之前已经保存过属性（attributesOffset > 0），需要先合并旧属性
        if (attributesOffset > 0) {
            // 复制当前属性到临时字典
            NSMutableDictionary * _attributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
            // 定位到旧属性在文件中的位置
            if (fseeko(pFile, attributesOffset, SEEK_SET) == -1) {
                // 如果定位失败，打印错误日志
                NSLog(@"MVRow saveToFile: fseeko SEEK_SET failed: %s", strerror(errno));
            }
            // 从文件加载旧属性
            [self loadAttributesFromFile:pFile];
            // 定位到文件末尾，准备追加写入
            if (fseeko(pFile, 0, SEEK_END) == -1) {
                // 如果定位失败，打印错误日志
                NSLog(@"MVRow saveToFile: fseeko SEEK_END failed: %s", strerror(errno));
            }
            // 将当前属性合并到加载的属性字典中
            [_attributes addEntriesFromDictionary:attributes];
            // 更新属性字典
            attributes = _attributes;
        }

        // 获取当前文件位置作为新属性数据的偏移量
        off_t filePos = ftello(pFile);
        // 如果获取文件位置失败
        if (filePos == -1) {
            // 打印错误日志
            NSLog(@"MVRow saveToFile: ftello failed: %s", strerror(errno));
        }
        // 将属性数据写入文件
        [self saveAttributestoFile:(FILE *)pFile];
        // 重置 dirty 标志为 NO
        dirty = NO;
        // 更新属性数据偏移量
        attributesOffset = filePos;
    }
}

//----------------------------------------------------------------------------
// 从文件加载行数据（实现了 MVSerializing 协议）
- (void)loadFromFile:(FILE *)pFile
{
    // 如果 columns 对象为空，说明需要加载列数据
    if (columns == nil) {
        // 断言列数据偏移量不为 0
        NSParameterAssert(columnsOffset != 0);

    // 定位到列数据在文件中的位置
    if (fseeko(pFile, columnsOffset, SEEK_SET) == 0) {
            // 分配并初始化 columns 对象
            columns = [[MVColumns alloc] init];
            // 读取偏移量列字符串
            columns.offsetStr = [self readStringFromFile:pFile];
            // 读取数据列字符串
            columns.dataStr = [self readStringFromFile:pFile];
            // 读取描述列字符串
            columns.descriptionStr = [self readStringFromFile:pFile];
            // 读取值列字符串
            columns.valueStr = [self readStringFromFile:pFile];
        } else {
            // 如果定位失败，打印错误日志
            NSLog(@"*** reading error (columns) '%s'",strerror(errno));
            // 断言失败
            NSParameterAssert(0);
            // 返回
            return;
        }
    }

  // 如果 attributes 对象为空且存在属性数据（attributesOffset > 0）
  if (attributes == nil && attributesOffset > 0) {
        // 定位到属性数据在文件中的位置
        if (fseeko(pFile, attributesOffset, SEEK_SET) == 0) {
            // 从文件加载属性数据
            [self loadAttributesFromFile:pFile];
        } else {
            // 如果定位失败，打印错误日志
            NSLog(@"*** reading error (attributes) '%s'",strerror(errno));
            // 断言失败
            NSParameterAssert(0);
        }
    }
}

//----------------------------------------------------------------------------
// 保存行的索引信息到文件
- (void)saveIndexToFile:(FILE *)pFile
{
  // 写入偏移量
  fwrite(&offset, sizeof(uint32_t), 1, pFile);
  // 写入列数据偏移量
  fwrite(&columnsOffset, sizeof(uint32_t), 1, pFile);
  // 写入属性数据偏移量
  fwrite(&attributesOffset, sizeof(uint32_t), 1, pFile);
  // 写入删除标记
  fwrite(&deleted, sizeof(BOOL), 1, pFile);
}

//----------------------------------------------------------------------------
// 从文件加载行的索引信息
- (void)loadIndexFromFile:(FILE *)pFile
{
  // 读取偏移量
  fread(&offset, sizeof(uint32_t), 1, pFile);
  // 读取列数据偏移量
  fread(&columnsOffset, sizeof(uint32_t), 1, pFile);
  // 读取属性数据偏移量
  fread(&attributesOffset, sizeof(uint32_t), 1, pFile);
  // 读取删除标记
  fread(&deleted, sizeof(BOOL), 1, pFile);
}

//----------------------------------------------------------------------------
// 判断行数据是否已保存
-(BOOL) isSaved
{
  // 如果列数据偏移量大于 0，则认为已保存
  return (columnsOffset > 0);
}

//----------------------------------------------------------------------------
// 清理内存中的数据（实现了 MVSerializing 协议）
-(void) clear
{
  // 仅当 isSaved 为 YES 时才进行清理
  if (columnsOffset > 0) // isSaved == YES
  {
    // 将 columns 置为 nil，释放内存
    columns = nil;

    // 如果属性数据未修改（dirty 为 NO）
    if (dirty == NO)
    {
      // 将 attributes 置为 nil，释放内存
      attributes = nil;
    }
  }
}

@end

//============================================================================
// MVTable 实现：管理表格行数据和对应的交换文件
//============================================================================
@implementation MVTable

// 合成 swapFile 属性的存取方法
@synthesize swapFile;

//-----------------------------------------------------------------------------
// 默认初始化方法（被禁用）
- (instancetype)init
{
  // 断言失败，不允许直接使用 init
  NSAssert(NO, @"plain init is not allowed");
  // 返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 使用归档器初始化的方法
- (instancetype)initWithArchiver:(MVArchiver *)_archiver
{
  // 调用父类的初始化方法
  if (self = [super init])
  {
    // 初始化行数组
    rows = [[NSMutableArray alloc] init];
    // 保存归档器引用
    archiver = _archiver;
    // 初始化表格锁
    tableLock = [[NSLock alloc] init];
  }
  // 返回初始化后的实例
  return self;
}

//----------------------------------------------------------------------------
// 类工厂方法：使用归档器创建 MVTable 实例
+(MVTable *) tableWithArchiver:(MVArchiver *)_archiver
{
  // 分配内存并初始化 MVTable 对象
  return [[MVTable alloc] initWithArchiver:_archiver];
}

//----------------------------------------------------------------------------
// 获取需要显示的行数
- (NSUInteger)rowCountToDisplay
{
  // 返回 displayRows 数组的元素个数
  return [displayRows count];
}

//----------------------------------------------------------------------------
// 获取指定索引的显示行对象
- (MVRow *)getRowToDisplay: (NSUInteger)rowIndex
{
  // 定义行对象变量
  MVRow * row = nil;

  // 如果索引在 displayRows 范围内
  if (rowIndex < [displayRows count])
  {
    // 获取对应的行对象
    row = [displayRows objectAtIndex:rowIndex];
  }

  // 如果获取到了行对象
  if (row != nil)
  {
    // 如果该行已被标记删除
    if (row.deleted)
    {
      // 将 row 置为 nil
      row = nil;
    }
    // 否则，如果行内容尚未加载
    else if (row.columns == nil)
    {
      // 从交换文件加载行内容
      [row loadFromFile:swapFile];
    }
  }

  // 返回行对象
  return row;
}

//----------------------------------------------------------------------------
// 插入一行数据
- (void)insertRowWithOffset:(uint64_t)offset :(id)col0 :(id)col1 :(id)col2 :(id)col3
{
  // 创建新的 MVRow 对象
  MVRow * row = [[MVRow alloc] init];
  // 设置行的数据列
  row.columns = [MVColumns columnsWithData:col0:col1:col2:col3];
  // 设置行的偏移量
  row.offset = offset;

  // 获取表格锁
  [tableLock lock];
  // 将新行添加到 rows 数组
  [rows addObject:row];
  // 释放表格锁
  [tableLock unlock];

  // 将新行添加到归档器的保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 追加一行数据（偏移量默认为 0）
- (void)appendRow:(id)col0 :(id)col1 :(id)col2 :(id)col3
{
  // 调用 insertRowWithOffset 方法插入行
  [self insertRowWithOffset:0 :col0:col1:col2:col3];
}

//----------------------------------------------------------------------------
// 更新指定行列的单元格内容
- (void)updateCellContentTo:(id)object atRow:(NSUInteger)rowIndex andCol:(NSUInteger)colIndex
{
  // 获取指定行的对象
  MVRow * row = [rows objectAtIndex:rowIndex];
  // 替换指定列的内容
  [row replaceColumnAtIndex:colIndex withString:object];
  // 在 rows 数组中替换该行对象（可能是冗余操作，因为是对引用的修改）
  [rows replaceObjectAtIndex:rowIndex withObject:row];

  // 将该行添加到归档器的保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 弹出最后一行（标记为删除）
- (void)popRow
{
  // 获取最后一行对象
  MVRow * row = [rows lastObject];
  // 将该行标记为已删除
  row.deleted = YES;
}

//----------------------------------------------------------------------------
// 获取总行数
- (NSUInteger)rowCount
{
  // 返回 rows 数组的元素个数
  return [rows count];
}

//----------------------------------------------------------------------------
// 辅助方法：从可变参数列表创建属性字典
//----------------------------------------------------------------------------
-(NSMutableDictionary *)attributesWithPairs:(id)firstArg :(va_list)args
{
  // 初始化一个可变字典
  NSMutableDictionary * attributes = [[NSMutableDictionary alloc] init];

  // 定义属性名变量
  NSString * name = nil;
  // 遍历可变参数列表
  for (id arg = firstArg; arg != nil; arg = va_arg(args, id))
  {
    // 如果 name 为空，说明当前参数是键名
    if (name == nil)
    {
      // 保存键名
      name = arg;
      // 继续下一次循环
      continue;
    }

    // 如果 name 不为空，说明当前参数是值，将其存入字典
    [attributes setObject:arg forKey:name];
    // 重置 name 为 nil，准备读取下一个键值对
    name = nil;
  }

  // 返回生成的属性字典
  return attributes;
}

//----------------------------------------------------------------------------
// 为指定行设置属性
- (void)setAttributes:(NSMutableDictionary *)attributes forRow:(MVRow *)row
{
  // 断言行对象不为 nil
  NSParameterAssert(row != nil);

  // 如果该行已经有修改（dirty 为 YES）
  if (row.dirty)
  {
    // 将原有属性合并到新的属性字典中
    [attributes addEntriesFromDictionary:row.attributes];
  }

  // 设置行的属性字典
  row.attributes = attributes;
  // 标记该行已修改
  row.dirty = YES;
}

//----------------------------------------------------------------------------
// 为最后一行设置属性（可变参数）
- (void)setAttributes:(id)firstArg, ...
{
  // 定义参数列表变量
  va_list args;
  // 初始化参数列表
  va_start(args, firstArg);
  // 解析参数列表生成属性字典
  NSMutableDictionary * attributes = [self attributesWithPairs:firstArg:args];
  // 结束参数列表处理
  va_end(args);

  // 获取最后一行对象
  MVRow * row = [rows lastObject];
  // 为该行设置属性
  [self setAttributes:attributes forRow:row];

  // 将该行添加到归档器的保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 为指定索引的行设置属性（可变参数）
- (void)setAttributesForRowIndex:(NSUInteger)index :(id)firstArg, ...
{
  // 定义参数列表变量
  va_list args;
  // 初始化参数列表
  va_start(args, firstArg);
  // 解析参数列表生成属性字典
  NSMutableDictionary * attributes = [self attributesWithPairs:firstArg:args];
  // 结束参数列表处理
  va_end(args);

  // 获取指定索引的行对象
  MVRow * row = [rows objectAtIndex:index];
  // 为该行设置属性
  [self setAttributes:attributes forRow:row];

  // 将该行添加到归档器的保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 从指定索引开始为后续所有行设置属性
- (void)setAttributesFromRowIndex:(NSUInteger)index :(id)firstArg, ...
{
  // 定义参数列表变量
  va_list args;
  // 初始化参数列表
  va_start(args, firstArg);
  // 解析参数列表生成属性字典（不可变）
  NSDictionary * attributes = [self attributesWithPairs:firstArg:args];
  // 结束参数列表处理
  va_end(args);

  // 遍历从指定索引开始的所有行
  for (NSUInteger numRows = [rows count]; index < numRows; ++index)
  {
    // 获取当前行对象
    MVRow * row = [rows objectAtIndex:index];
    // 为该行设置属性（使用属性字典的副本）
    [self setAttributes:[NSMutableDictionary dictionaryWithDictionary:attributes] forRow:row];

    // 将该行添加到归档器的保存队列
    [archiver addObjectToSave:row];
  }
}

//----------------------------------------------------------------------------
// 应用过滤器
- (void) applyFilter: (NSString *)filter
{
  // 获取表格锁
  [tableLock lock];
  // 如果过滤器为空或长度为 0
  if (filter == nil || [filter length] == 0)
  {
    // 显示所有行
    displayRows = [NSMutableArray arrayWithArray:rows];

    /*
    displayRows = [[NSMutableArray alloc] init];
    for (MVRow * row in rows)
    {
      if (row.isSaved)
      {
        [displayRows addObject:row];
      }
    }
     */

  }
  // 如果有过滤器
  else
  {
    // 创建谓词，匹配包含过滤字符串的内容（不区分大小写和变音符号）
    NSPredicate *predicate = [NSPredicate
                              predicateWithFormat:@"self contains[cd] %@", filter];

    // 初始化 displayRows 数组
    displayRows = [[NSMutableArray alloc] init];
    // 遍历所有行
    for (MVRow * row in rows)
    {
      // 如果行内容未加载
      if (row.columns == nil)
      {
        // 从交换文件加载行内容
        [row loadFromFile:swapFile];
      }

      // 获取行的元数据属性
      NSString * metadata = [row.attributes objectForKey:MVMetaDataAttributeName];
      // 如果元数据为空，或者元数据匹配过滤器
      if (metadata == nil || [predicate evaluateWithObject:metadata] == YES)
      {
        // 将该行加入显示列表
        [displayRows addObject:row];
      }
    }
  }
  // 释放表格锁
  [tableLock unlock];
}

//----------------------------------------------------------------------------
// 根据偏移量对行进行排序
- (void)sortByOffset
{
  // 获取表格锁
  [tableLock lock];
  // 使用稳定排序算法对 rows 数组进行排序
  [rows sortWithOptions:NSSortStable usingComparator:^(id obj1, id obj2)
   {
     // 转换对象为 MVRow 类型
     MVRow * row1 = obj1;
     // 转换对象为 MVRow 类型
     MVRow * row2 = obj2;
     // 如果 row1 偏移量小于 row2，返回升序
     if (row1.offset < row2.offset) return (NSComparisonResult)NSOrderedAscending;
     // 如果 row1 偏移量大于 row2，返回降序
     if (row1.offset > row2.offset) return (NSComparisonResult)NSOrderedDescending;
     // 否则返回相等
     return (NSComparisonResult)NSOrderedSame;
   }];
  // 释放表格锁
  [tableLock unlock];
}

//----------------------------------------------------------------------------
// 保存索引到文件
- (void)saveIndexes
{
    // 获取行数
    uint64_t rowCount = [rows count];
    // 写入行数到文件，如果失败则打印日志并返回
    if (fwrite(&rowCount, sizeof(uint64_t), 1, swapFile) < 1) {
        NSLog(@"saveIndexes write error");
        return;
    }

    // 遍历所有行
    for (MVRow * row in rows) {
        // 保存每行的索引信息到文件
        [row saveIndexToFile:swapFile];
    }
}

//----------------------------------------------------------------------------
// 从文件加载索引
- (void)loadIndexes
{
  // 定义行数变量
  uint64_t rowCount;
  // 从文件读取行数
  fread(&rowCount, sizeof(uint64_t), 1, swapFile);

  // 循环读取每一行的索引
  while (rowCount-- > 0) {
    // 创建新的 MVRow 对象
    MVRow * row = [[MVRow alloc] init];
    // 从文件加载索引信息
    [row loadIndexFromFile:swapFile];
    // 将行添加到 rows 数组
    [rows addObject:row];
  }
}

@end


//============================================================================
// MVNode 实现：树节点，包含子节点和详情表
//============================================================================
@implementation MVNode

// 合成 caption, parent, dataRange, details, userInfo, detailsOffset 属性的存取方法
@synthesize caption, parent, dataRange, details, userInfo, detailsOffset;

//-----------------------------------------------------------------------------
// 默认初始化方法
- (instancetype)init
{
  // 调用父类的初始化方法
  if (self = [super init])
  {
    // 初始化子节点数组
    children = [[NSMutableArray alloc] init];
    // 初始化用户信息字典
    userInfo = [[NSMutableDictionary alloc] init];
  }
  // 返回初始化后的实例
  return self;
}

//----------------------------------------------------------------------------
// 获取对象的描述信息
-(NSString *)description
{
  // 返回父类描述加上节点的标题
  return [[super description] stringByAppendingFormat:@" [%@]", caption];
}

//----------------------------------------------------------------------------
// 获取指定索引的子节点
- (MVNode *)childAtIndex:(NSUInteger)n
{
  // 从 children 数组中返回对应元素
  return [children objectAtIndex:n];
}

//----------------------------------------------------------------------------
// 获取子节点数量
- (NSUInteger)numberOfChildren
{
  // 返回 children 数组的元素个数
  return [children count];
}

//----------------------------------------------------------------------------
// 插入一个子节点（保持有序）
- (void)insertNode:(MVNode *)node
{
  // 从 userInfo 中获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];

  // 获取树锁
  [layout.dataController.treeLock lock];

  // 查找插入位置，保持 dataRange.location 有序
  NSUInteger index = [children indexOfObjectPassingTest:
                      ^(id obj, NSUInteger idx, BOOL *stop)
                      {
                        // 如果待插入节点的位置小于当前遍历节点的位置
                        if (node.dataRange.location < [obj dataRange].location)
                        {
                          // 停止遍历
                          *stop = YES;
                          // 返回匹配成功
                          return YES;
                        }
                        // 返回不匹配
                        return NO;
                      }];

  // 获取通知中心单例
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送数据树即将变更的通知
  [nc postNotificationName:MVDataTreeWillChangeNotification
                    object:layout.dataController];

  // 如果未找到插入位置（即所有现有节点位置都小于等于待插入节点）
  if (index == NSNotFound)
  {
    // 将节点添加到数组末尾
    [children addObject:node];
  }
  else
  {
    // 在找到的位置插入节点
    [children insertObject:node atIndex:index];
  }

  // 发送数据树已变更的通知
  [nc postNotificationName:MVDataTreeDidChangeNotification
                    object:layout.dataController];

  // 通知数据控制器更新树视图
  [layout.dataController updateTreeView:self];

  // 释放树锁
  [layout.dataController.treeLock unlock];
}

//----------------------------------------------------------------------------
// 插入一个简单的子节点（无详情表）
- (MVNode *)insertChild:(NSString *)_caption
            location:(uint64_t)location
              length:(uint64_t)length
{
  // 创建新的 MVNode 对象
  MVNode * node = [[MVNode alloc] init];
  // 设置标题
  node.caption = _caption;
  // 设置数据范围
  node.dataRange = NSMakeRange(location,length);
  // 设置父节点
  node.parent = self;
  // 继承父节点的用户信息
  [node.userInfo addEntriesFromDictionary:userInfo];
  // 插入该子节点
  [self insertNode:node];
  // 返回新创建的节点
  return node;
}

//----------------------------------------------------------------------------
// 插入一个带有详情表的子节点
- (MVNode *)insertChildWithDetails:(NSString *)_caption
                       location:(uint64_t)location
                         length:(uint64_t)length
                          saver:(MVNodeSaver &)saver
{
  // 首先插入一个普通子节点
  MVNode * node = [self insertChild:_caption location:location length:length];
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 为节点创建详情表，并关联归档器
  node.details = [MVTable tableWithArchiver:layout.archiver];
  // 设置保存器关联的节点
  saver.setNode(node);
  // 返回新创建的节点
  return node;
}

//----------------------------------------------------------------------------
// 根据用户信息查找节点
- (MVNode *)findNodeByUserInfo:(NSDictionary *)uinfo
{
  // 如果当前节点的用户信息与目标一致
  if ([userInfo isEqualToDictionary:uinfo] == YES)
  {
    // 返回当前节点
    return self;
  }

  // 遍历所有子节点
  for (MVNode * node in children)
  {
    // 递归在子节点中查找
    MVNode * found = [node findNodeByUserInfo:uinfo];
    // 如果找到了节点
    if (found != nil)
    {
      // 返回找到的节点
      return found;
    }
  }

  // 如果未找到，返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 打开详情表的交换文件
- (void)openDetails
{
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 以只读模式打开交换文件
  FILE * pFile = fopen(CSTRING(layout.archiver.swapPath), "r");
  // 如果文件打开成功
  if (pFile != NULL)
  {
    // 如果详情表不为空（表示正在保存中）
    if (details != nil) // saving in progress
    {
      // 设置详情表的交换文件句柄
      details.swapFile = pFile;
    }
    // 否则，如果详情表偏移量不为 0（表示已保存且有内容）
    else if (detailsOffset != 0) // saved and has content
    {
      // 从文件加载节点数据
      [self loadFromFile:pFile];
    }
  }
}

//-----------------------------------------------------------------------------
// 关闭详情表的交换文件
- (void)closeDetails
{
  // 如果详情表的交换文件句柄有效
  if (details.swapFile != NULL)
  {
    // 关闭文件
    fclose(details.swapFile);
    // 将句柄置为 NULL
    details.swapFile = NULL;
  }
}

//-----------------------------------------------------------------------------
// 对详情表进行排序
- (void)sortDetails
{
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 更新状态为任务开始
  [layout.dataController updateStatus:MVStatusTaskStarted];
  // 对详情表进行排序
  [details sortByOffset];
  // 更新状态为任务终止
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//----------------------------------------------------------------------------
// 过滤详情表
- (void)filterDetails: (NSString *)filter
{
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 更新状态为任务开始
  [layout.dataController updateStatus:MVStatusTaskStarted];
  // 挂起归档器
  [layout.archiver suspend];
  // 对详情表应用过滤器
  [details applyFilter:filter];
  // 恢复归档器
  [layout.archiver resume];
  // 更新状态为任务终止
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// 保存节点数据到文件（实现了 MVSerializing 协议）
- (void)saveToFile:(FILE *)pFile
{
    // 获取布局对象
    MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
    // 更新状态为任务开始
    [layout.dataController updateStatus:MVStatusTaskStarted];

    // 获取当前文件位置
    off_t filePos = ftello(pFile);
    // 如果获取位置失败
    if (filePos == -1) {
        // 打印错误日志
        NSLog(@"MVNode saveToFile: ftello failed: %s", strerror(errno));
    }
    // 设置详情表的交换文件句柄
    details.swapFile = pFile;
    // 保存详情表的索引
    [details saveIndexes];
    // 更新详情表偏移量
    detailsOffset = filePos;
    // 通知数据控制器更新树视图
    [layout.dataController updateTreeView:self];
    // 如果当前节点是选中节点
    if (self == layout.dataController.selectedNode) {
        // 打开详情表
        [self openDetails];
        // 应用空过滤器（即显示所有内容）
        [details applyFilter:nil];
    }

    // 更新状态为任务终止
    [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// 从文件加载节点数据（实现了 MVSerializing 协议）
- (void)loadFromFile:(FILE *)pFile
{
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 更新状态为任务开始
  [layout.dataController updateStatus:MVStatusTaskStarted];
  // 创建新的详情表
  details = [MVTable tableWithArchiver:layout.archiver];
  // 设置交换文件句柄
  details.swapFile = pFile;
  // 断言详情表偏移量不为 0
  NSParameterAssert(detailsOffset != 0);
  // 定位到详情表数据位置
  fseek (pFile, detailsOffset, SEEK_SET);
  // 加载详情表索引
  [details loadIndexes];
  // 更新状态为任务终止
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// 清理节点数据（实现了 MVSerializing 协议）
-(void)clear
{
  // 获取布局对象
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  // 如果当前节点不是选中节点
  if (layout.dataController.selectedNode != self)
  {
    // 释放详情表内存
    details = nil;
  }
}

@end


//============================================================================
// MVDataController 实现：数据控制器，负责管理布局和文件解析
//============================================================================
@implementation MVDataController

// 合成 fileName, fileData, realData, layouts, rootNode, selectedNode, treeLock 属性的存取方法
@synthesize fileName, fileData, realData, layouts, rootNode, selectedNode, treeLock;

//-----------------------------------------------------------------------------
/*
- (void)dealloc
{
  NSLog(@"********MVDataController deallocated: %@", self);
  for (MVLayout * layout in layouts)
  {
    NSLog(@"%@ Retain count is %ld", layout, CFGetRetainCount((__bridge CFTypeRef)layout));
  }
}
*/

//-----------------------------------------------------------------------------
// 初始化方法
- (instancetype)init
{
  // 调用父类的初始化方法
  if (self = [super init])
  {
    // 初始化布局数组
    layouts = [[NSMutableArray alloc] init];
    // 初始化根节点
    rootNode = [[MVNode alloc] init];
    // 初始化树锁
    treeLock = [[NSLock alloc] init];
  }
  // 返回初始化后的实例
  return self;
}

//----------------------------------------------------------------------------
// 获取 CPU 类型对应的字符串描述
-(NSString *)getMachine:(cpu_type_t)cputype
{
    // 根据 CPU 类型进行分支判断
    switch (cputype)
    {
        // 默认情况返回未知
        default:                  return @"???";
        // I386 架构返回 X86
        case CPU_TYPE_I386:       return @"X86";
        // PowerPC 架构返回 PPC
        case CPU_TYPE_POWERPC:    return @"PPC";
        // X86_64 架构返回 X86_64
        case CPU_TYPE_X86_64:     return @"X86_64";
        // PowerPC64 架构返回 PPC64
        case CPU_TYPE_POWERPC64:  return @"PPC64";
        // ARM 架构返回 ARM
        case CPU_TYPE_ARM:        return @"ARM";
        // ARM64 架构返回 ARM64
        case CPU_TYPE_ARM64:      return @"ARM64";
        // ARM64_32 架构返回 ARM64_32
        case CPU_TYPE_ARM64_32:   return @"ARM64_32";
    }
}

//----------------------------------------------------------------------------
// 获取 ARM CPU 子类型对应的字符串描述
-(NSString *)getARMCpu:(cpu_subtype_t)cpusubtype
{
    // 根据 CPU 子类型（去除掩码）进行分支判断
    switch (cpusubtype & ~CPU_SUBTYPE_MASK)
    {
        // 默认情况返回未知
        default:                      return @"???";
        // ARM 所有类型返回 ARM_ALL
        case CPU_SUBTYPE_ARM_ALL:     return @"ARM_ALL";
        // ARM V4T 返回 ARM_V4T
        case CPU_SUBTYPE_ARM_V4T:     return @"ARM_V4T";
        // ARM V6 返回 ARM_V6
        case CPU_SUBTYPE_ARM_V6:      return @"ARM_V6";
        // ARM V5TEJ 返回 ARM_V5TEJ
        case CPU_SUBTYPE_ARM_V5TEJ:   return @"ARM_V5TEJ";
        // ARM XSCALE 返回 ARM_XSCALE
        case CPU_SUBTYPE_ARM_XSCALE:  return @"ARM_XSCALE";
        // ARM V7 返回 ARM_V7
        case CPU_SUBTYPE_ARM_V7:      return @"ARM_V7";
        // ARM V7F 返回 ARM_V7F
        case CPU_SUBTYPE_ARM_V7F:     return @"ARM_V7F";
        // ARM V7S 返回 ARM_V7S
        case CPU_SUBTYPE_ARM_V7S:     return @"ARM_V7S";
        // ARM V7K 返回 ARM_V7K
        case CPU_SUBTYPE_ARM_V7K:     return @"ARM_V7K";
        // ARM V8 返回 ARM_V8
        case CPU_SUBTYPE_ARM_V8:      return @"ARM_V8";
        // ARM V6M 返回 ARM_V6M
        case CPU_SUBTYPE_ARM_V6M:     return @"ARM_V6M";
        // ARM V7M 返回 ARM_V7M
        case CPU_SUBTYPE_ARM_V7M:     return @"ARM_V7M";
        // ARM V7EM 返回 ARM_V7EM
        case CPU_SUBTYPE_ARM_V7EM:    return @"ARM_V7EM";
        // ARM V8M 返回 ARM_V8M
        case CPU_SUBTYPE_ARM_V8M:     return @"ARM_V8M";
    }
}

//----------------------------------------------------------------------------
// 获取 ARM64 CPU 子类型对应的字符串描述
-(NSString *)getARM64Cpu:(cpu_subtype_t)cpusubtype
{
    // 根据 CPU 子类型（去除掩码）进行分支判断
    switch (cpusubtype & ~CPU_SUBTYPE_MASK)
    {
        // 默认情况返回未知
        default:                      return @"???";
        // ARM64 所有类型返回 ARM64_ALL
        case CPU_SUBTYPE_ARM64_ALL:   return @"ARM64_ALL";
        // ARM64 V8 返回 ARM64_V8
        case CPU_SUBTYPE_ARM64_V8:    return @"ARM64_V8";
        // ARM64E 返回 ARM64E
        case CPU_SUBTYPE_ARM64E:      return @"ARM64E";
    }
}

//----------------------------------------------------------------------------
// 判断是否为支持的机器架构
-(BOOL)isSupportedMachine:(NSString *)machine
{
    // 判断是否为 X86
    return ([machine isEqualToString:@"X86"] == YES ||
            // 判断是否为 X86_64
            [machine isEqualToString:@"X86_64"] == YES ||
            // 判断是否为 ARM
            [machine isEqualToString:@"ARM"] == YES ||
            // 判断是否为 ARM64
            [machine isEqualToString:@"ARM64"] == YES ||
            // 判断是否为 ARM64_32
            [machine isEqualToString:@"ARM64_32"] == YES);
}

//----------------------------------------------------------------------------
// 获取文件类型的字符串描述
-(NSString *)getFileType:(uint32_t)filetype
{
    // 根据文件类型进行分支判断
    switch (filetype) {
        // 目标文件
        case MH_OBJECT:
            return @"Object ";
        // 可执行文件
        case MH_EXECUTE:
            return @"Executable ";
        // 固定 VM 共享库
        case MH_FVMLIB:
            return @"Fixed VM Shared Library";
        // 核心文件
        case MH_CORE:
            return @"Core";
        // 预加载可执行文件
        case MH_PRELOAD:
            return @"Preloaded Executable";
        // 动态共享库
        case MH_DYLIB:
            return @"Shared Library ";
        // 动态链接编辑器
        case MH_DYLINKER:
            return @"Dynamic Link Editor";
        // Bundle
        case MH_BUNDLE:
            return @"Bundle";
        // 动态库存根
        case MH_DYLIB_STUB:
            return @"Shared Library Stub";
        // 调试符号文件
        case MH_DSYM:
            return @"Debug Symbols";
        // 内核扩展 Bundle
        case MH_KEXT_BUNDLE:
            return @"Kernel Extension";
        // 文件集
        case MH_FILESET:
            return @"File Set";
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
        // GPU 程序
        case MH_GPU_EXECUTE:
            return @"GPU Program";
        // GPU 支持函数
        case MH_GPU_DYLIB:
            return @"GPU Support Functions";
#endif
        // 默认未知类型
        default:
            return @"?????";
    }
}

//----------------------------------------------------------------------------
// 创建 Mach-O 布局（32位）
-(void)createMachOLayout:(MVNode *)node
             mach_header:(struct mach_header const *)mach_header
{
    // 获取机器架构字符串
    NSString * machine = [self getMachine:mach_header->cputype];

  // 设置节点标题，格式为“文件类型 (CPU架构)”
  node.caption = [NSString stringWithFormat:@"%@ (%@)",
                    [self getFileType:mach_header->filetype],
                    [machine isEqualToString:@"ARM"] == YES ? [self getARMCpu:mach_header->cpusubtype] : machine];
  
    // 创建 MachOLayout 对象
    MachOLayout * layout = [MachOLayout layoutWithDataController:self rootNode:node];
                          
    // 将布局对象保存到节点用户信息中
    [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];
  
    // 如果是支持的机器架构
    if ([self isSupportedMachine:machine]) {
        // 将布局添加到 layouts 数组
        [layouts addObject:layout];
    }
    // 如果不支持
    else {
        // 停止归档器，因为没有细节需要提取
        // there is no detail to extract
        [layout.archiver halt];
    }
}

//----------------------------------------------------------------------------
// 创建 Mach-O 布局（64位）
-(void)createMachO64Layout:(MVNode *)node
            mach_header_64:(struct mach_header_64 const *)mach_header_64
{
    // 获取机器架构字符串
    NSString * machine = [self getMachine:mach_header_64->cputype];
        
    // 设置节点标题
    node.caption = [NSString stringWithFormat:@"%@ (%@)",
                    [self getFileType:mach_header_64->filetype],
                    [machine isEqualToString:@"ARM64"] == YES ? [self getARM64Cpu:mach_header_64->cpusubtype] : machine];
  
    // 创建 MachOLayout 对象
    MachOLayout * layout = [MachOLayout layoutWithDataController:self rootNode:node];

    // 将布局对象保存到节点用户信息中
    [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];

    // 如果是支持的机器架构
    if ([self isSupportedMachine:machine]) {
        // 将布局添加到 layouts 数组
        [layouts addObject:layout];
    }
    // 如果不支持
    else {
        // 停止归档器
        // there is no detail to extract
        [layout.archiver halt];
    }
}

//----------------------------------------------------------------------------
// 创建归档布局（静态库）
-(void)createArchiveLayout:(MVNode *)node machine:(NSString *)machine
{
  // 设置节点标题，如果有指定机器架构则显示，否则仅显示 Static Library
  node.caption = machine ? [NSString stringWithFormat:@"Static Library (%@)", machine] : @"Static Library";
  
  // 创建 ArchiveLayout 对象
  ArchiveLayout * layout = [ArchiveLayout layoutWithDataController:self rootNode:node];
  
  // 将布局对象保存到节点用户信息中
  [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];
    
  // 如果机器架构为空或者支持该架构
  if (machine == nil || [self isSupportedMachine:machine])
    {
    // 将布局添加到 layouts 数组
    [layouts addObject:layout];
    }
    // 否则
    else
    {
    // 停止归档器
    // there is no detail to extract
    [layout.archiver halt];
  }
}

//----------------------------------------------------------------------------
// 根据位置创建布局（识别文件类型）
- (void)createLayouts:(MVNode *)parent
             location:(uint64_t)location
               length:(uint64_t)length
{
  // 读取文件头部的魔数
  uint32_t magic = *(uint32_t*)((uint8_t *)[fileData bytes] + location);

  // 根据魔数进行分支处理
  switch (magic)
  {
    // Fat 二进制魔数
    case FAT_MAGIC:
    // Fat 二进制魔数（CIGAM，即反序）
    case FAT_CIGAM:
    {
      // 定义 fat_header 结构体
      struct fat_header fat_header;
      // 读取 fat_header 数据
      [fileData getBytes:&fat_header range:NSMakeRange(location, sizeof(struct fat_header))];
      // 如果是 CIGAM，需要进行字节序交换
      if (magic == FAT_CIGAM)
        swap_fat_header(&fat_header, NX_LittleEndian);
      // 创建 Fat 布局
      [self createFatLayout:parent fat_header:&fat_header];
    } break;

    // 32位 Mach-O 魔数
    case MH_MAGIC:
    // 32位 Mach-O 魔数（CIGAM）
    case MH_CIGAM:
    {
      // 定义 mach_header 结构体
      struct mach_header mach_header;
      // 读取 mach_header 数据
      [fileData getBytes:&mach_header range:NSMakeRange(location, sizeof(struct mach_header))];
      // 如果是 CIGAM，进行字节序交换
      if (magic == MH_CIGAM)
        swap_mach_header(&mach_header, NX_LittleEndian);
      // 创建 32位 Mach-O 布局
      [self createMachOLayout:parent mach_header:&mach_header];
    } break;

    // 64位 Mach-O 魔数
    case MH_MAGIC_64:
    // 64位 Mach-O 魔数（CIGAM）
    case MH_CIGAM_64:
    {
      // 定义 mach_header_64 结构体
      struct mach_header_64 mach_header_64;
      // 读取 mach_header_64 数据
      [fileData getBytes:&mach_header_64 range:NSMakeRange(location, sizeof(struct mach_header_64))];
      // 如果是 CIGAM，进行字节序交换
      if (magic == MH_CIGAM_64)
        swap_mach_header_64(&mach_header_64, NX_LittleEndian);
      // 创建 64位 Mach-O 布局
      [self createMachO64Layout:parent mach_header_64:&mach_header_64];
    } break;

    // 默认情况，视为归档文件
    default:
      [self createArchiveLayout:parent machine:nil];
  }

  // 设置父节点的数据范围
  parent.dataRange = NSMakeRange(location, length);
}

//----------------------------------------------------------------------------
// 创建 Fat 布局
-(void)createFatLayout:(MVNode *)node
            fat_header:(struct fat_header const *)fat_header
{
  // 设置节点标题
  node.caption = @"Fat Binary";
  // 创建 FatLayout 对象
  FatLayout * layout = [FatLayout layoutWithDataController:self rootNode:node];

  // 将布局对象保存到节点用户信息中
  [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];

  // 将布局添加到 layouts 数组
  [layouts addObject:layout];
  // 遍历所有架构
  for (uint32_t nimg = 0; nimg < fat_header->nfat_arch; ++nimg)
  {
    // 定义 fat_arch 结构体
    struct fat_arch fat_arch;
    // 读取 fat_arch 数据
    [fileData getBytes:&fat_arch range:NSMakeRange(sizeof(struct fat_header) + nimg * sizeof(struct fat_arch), sizeof(struct fat_arch))];
    // 进行字节序交换
    swap_fat_arch(&fat_arch, 1, NX_LittleEndian);

    // 插入子节点
    MVNode * archNode = [node insertChild:nil location:fat_arch.offset length:fat_arch.size];

    // 检查是否为归档文件（以 !<arch> 开头）
    if (*(uint64_t*)((uint8_t *)[fileData bytes] + fat_arch.offset) == *(uint64_t*)"!<arch>\n")
    {
      // 创建归档布局
      [self createArchiveLayout:archNode machine:[self getMachine:fat_arch.cputype]];
    }
    // 否则
    else
    {
      // 递归创建布局
      [self createLayouts:archNode location:fat_arch.offset length:fat_arch.size];
    }
  }
}

//----------------------------------------------------------------------------
// 树视图即将变更
- (void)treeViewWillChange
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送 MVDataTreeWillChangeNotification 通知
  [nc postNotificationName:MVDataTreeWillChangeNotification 
                    object:self];
}

//----------------------------------------------------------------------------
// 树视图已变更
- (void)treeViewDidChange
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送 MVDataTreeDidChangeNotification 通知
  [nc postNotificationName:MVDataTreeDidChangeNotification
                    object:self];
}

//----------------------------------------------------------------------------
// 更新树视图
- (void)updateTreeView: (MVNode *)node
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送 MVDataTreeChangedNotification 通知，并携带节点信息
  [nc postNotificationName:MVDataTreeChangedNotification
                    object:self
                  userInfo:node ? [NSDictionary dictionaryWithObject:node forKey:MVNodeUserInfoKey] : nil];
}

//-----------------------------------------------------------------------------
// 更新表格视图
- (void)updateTableView
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送 MVDataTableChangedNotification 通知
  [nc postNotificationName:MVDataTableChangedNotification
                    object:self];
}

//-----------------------------------------------------------------------------
// 更新状态
- (void)updateStatus: (NSString *)status
{
  // 获取通知中心
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  // 发送 MVThreadStateChangedNotification 通知，并携带状态信息
  [nc postNotificationName:MVThreadStateChangedNotification
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:status forKey:MVStatusUserInfoKey]];
}

@end

#pragma mark -

//============================================================================
// MVArchiver 实现：归档器，负责后台保存数据
//============================================================================
@implementation MVArchiver

// 合成 swapPath 属性的存取方法
@synthesize swapPath;

//-----------------------------------------------------------------------------
// 默认初始化方法（被禁用）
- (instancetype)init
{
  // 断言失败，不允许直接使用 init
  NSAssert(NO, @"plain init is not allowed");
  // 返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 使用路径初始化归档器
- (instancetype)initWithPath:(NSString *)path
{
  // 调用父类的初始化方法
  if (self = [super init])
  {
    // 初始化待保存对象数组
    objectsToSave = [[NSMutableArray alloc] init];

    // 保存交换文件路径
    swapPath = path;

    // 打印创建交换文件的日志
    NSLog(@"%@: swap file is being created:%@", self, swapPath);
    // 以写模式打开交换文件
    FILE * pFile = fopen(CSTRING(swapPath), "w");
    // 如果文件打开失败
    if (pFile == NULL)
    {
      // 打印错误日志
      NSLog(@"*** file cannot be created: %@ '%s'", swapPath,strerror(errno));
      // 返回 nil
      return nil;
    }
    // 写入交换文件头部标识
    fputs("!<MachoViewSwapFile 1.0>\n", pFile);
    // 关闭文件
    fclose(pFile);

    // 初始化保存器锁
    saverLock = [[NSLock alloc] init];

#ifndef MV_NO_ARCHIVER
    // 创建后台保存线程
    saverThread = [[NSThread alloc] initWithTarget:self selector:@selector(doSave) object:nil];
    // 启动线程
    [saverThread start];
    // 打印归档器启动日志
    NSLog(@"********MVArchiver started: %@", self);
#endif
  }
  // 返回初始化后的实例
  return self;
}

//-----------------------------------------------------------------------------
// 类工厂方法：使用路径创建归档器
+(MVArchiver *) archiverWithPath:(NSString *)path
{
  // 分配内存并初始化 MVArchiver 对象
  return [[MVArchiver alloc] initWithPath:path];
}

//-----------------------------------------------------------------------------
// 挂起归档器
-(void) suspend
{
  // 获取保存器锁
  [saverLock lock];
}

//-----------------------------------------------------------------------------
// 恢复归档器
-(void) resume
{
  // 释放保存器锁
  [saverLock unlock];
}

//-----------------------------------------------------------------------------
// 停止归档器
-(void) halt
{
  // 取消保存线程
  [saverThread cancel];
  // 打印归档器停止日志
  NSLog(@"********MVArchiver halted: %@", self);
}

//-----------------------------------------------------------------------------
// 添加对象到保存队列
-(void) addObjectToSave:(id)object;
{
  // 断言对象实现了 MVSerializing 协议
  NSParameterAssert([object conformsToProtocol:@protocol(MVSerializing)] == YES);

  // 获取保存器锁
  [saverLock lock];
  // 将对象添加到数组
  [objectsToSave addObject:object];
  // 释放保存器锁
  [saverLock unlock];

  // 如果后台保存线程已被取消，则手动执行一次保存循环
  // if the background saver thread has been cancelled, then do do one cycle manually
  if ([saverThread isCancelled])
  {
    // 执行保存操作
    [self doSave];
  }
}

//-----------------------------------------------------------------------------
// 执行保存操作（后台线程运行）
-(void) doSave
{
  // 无限循环
  for (;;)
  {
    // 如果有待保存的对象
    if ([objectsToSave count] > 0)
    {
      // 获取管道条件锁
      [pipeCondition lock];
      // 增加 IO 线程计数
      ++numIOThread;
      // 释放管道条件锁
      [pipeCondition unlock];

      // 以追加模式打开交换文件
      FILE * pFile = fopen(CSTRING(swapPath), "a+");
      // 如果文件打开成功
      if (pFile != NULL)
      {
        // 获取保存器锁
        [saverLock lock];

#if DEBUG
        // 打印保存行数的调试日志
        NSLog(@"%@: saving %lu rows",[NSThread currentThread],(unsigned long)[objectsToSave count]);
#endif
        // 遍历待保存的对象
        for (id <MVSerializing> serializable in objectsToSave)
        {
          // 保存对象到文件
          [serializable saveToFile:pFile];
        }
        // 关闭文件
        fclose(pFile);

        // 遍历已保存的对象
        for (id <MVSerializing> serializable in objectsToSave)
        {
          // 清理对象内存
          [serializable clear];
        }

        // 重置待保存数组
        // reset buffer
        objectsToSave = [[NSMutableArray alloc] init];

        // 释放保存器锁
        [saverLock unlock];
      }

      // 获取管道条件锁
      [pipeCondition lock];
      // 减少 IO 线程计数
      --numIOThread;
      // 发送信号唤醒等待线程
      [pipeCondition signal];
      // 释放管道条件锁
      [pipeCondition unlock];
    }

    // 如果保存线程已被取消
    if ([saverThread isCancelled])
    {
    // 仅当缓冲区为空时才退出
    // only exit if buffer is surely empty
      if ([objectsToSave count] == 0)
    {
      // 跳出循环，结束线程
      break; // the nicest way
      //return;
      //[NSThread exit];
    }
      // 如果保存器已被取消，不再等待新行，只是将现有行刷新出去
      // do not wait for new rows if the saver has been cancelled
      // just flush out the existing ones
      continue;
    }

    // 等待一段时间，让对象积攒一些再保存
    // let's wait for some objects to collect for saving
    double rnd = 1. + rand()/((double)RAND_MAX+1); // between 1 and 2
    // 线程休眠
    [NSThread sleepForTimeInterval:rnd];
  }
}

@end

//-----------------------------------------------------------------------------
// MVNodeSaver 构造函数
MVNodeSaver::MVNodeSaver()
  : m_node(nil)
{
}

//-----------------------------------------------------------------------------
// MVNodeSaver 析构函数
MVNodeSaver::~MVNodeSaver()
{
  // 获取节点所属的布局
  MVLayout * layout = [m_node.userInfo objectForKey:MVLayoutUserInfoKey];
  // 将节点添加到归档器的保存队列
  [layout.archiver addObjectToSave:m_node];
}
