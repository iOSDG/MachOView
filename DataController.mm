/*
 *  DataController.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 引入公共头（全局变量、宏）
#import "Common.h"
// 引入本类头文件
#import "DataController.h"
// 引入 Mach-O 单镜像布局，createLayouts 会创建此类
#import "MachOLayout.h"
// 引入 Fat 布局，用于通用二进制
#import "FatLayout.h"
// 引入静态库布局，用于 ar 格式
#import "ArchiveLayout.h"
// 引入 Mach-O 头结构（mach_header、load_command 等）
#import <mach-o/loader.h>
// 引入 Fat 头结构（fat_header、fat_arch）
#import <mach-o/fat.h>
// 引入字节序交换函数（swap_fat_header、swap_mach_header 等）
#import <mach-o/swap.h>

// 属性键在交换文件中的枚举值：紧凑存储，写文件时用序号代替字符串键
enum {
  MVUnderlineAttributeOrdinal = 1,
  MVCellColorAttributeOrdinal,
  MVTextColorAttributeOrdinal,
  MVMetaDataAttributeOrdinal
};

// 颜色在交换文件中的枚举值：常用系统色用序号，自定义色写 0 后跟四个 float RGBA
enum {
  MVBlackColorOrdinal = 1,
  MVDarkGrayColorOrdinal,
  MVLightGrayColorOrdinal,
  MVWhiteColorOrdinal,
  MVGrayColorOrdinal,
  MVRedColorOrdinal,
  MVGreenColorOrdinal,
  MVBlueColorOrdinal,
  MVCyanColorOrdinal,
  MVYellowColorOrdinal,
  MVMagentaColorOrdinal,
  MVOrangeColorOrdinal,
  MVPurpleColorOrdinal,
  MVBrownColorOrdinal
};

// 属性名常量：下划线，与 .h 中 extern 对应
NSString * const MVUnderlineAttributeName         = @"MVUnderlineAttribute";
// 属性名常量：单元格背景色
NSString * const MVCellColorAttributeName         = @"MVCellColorAttribute";
// 属性名常量：文字颜色
NSString * const MVTextColorAttributeName         = @"MVTextColorAttribute";
// 属性名常量：元数据，用于搜索
NSString * const MVMetaDataAttributeName          = @"MVMetaDataAttribute";

// userInfo 键：当前 Layout
NSString * const MVLayoutUserInfoKey              = @"MVLayoutUserInfoKey";
// userInfo 键：当前 Node
NSString * const MVNodeUserInfoKey                = @"MVNodeUserInfoKey";
// userInfo 键：状态文案
NSString * const MVStatusUserInfoKey              = @"MVStatusUserInfoKey";

// 通知名：树即将变化
NSString * const MVDataTreeWillChangeNotification = @"MVDataTreeWillChangeNotification";
// 通知名：树已完成变化
NSString * const MVDataTreeDidChangeNotification  = @"MVDataTreeDidChangeNotification";
// 通知名：树已更新
NSString * const MVDataTreeChangedNotification    = @"MVDataTreeChanged";
// 通知名：右侧表已更新
NSString * const MVDataTableChangedNotification   = @"MVDataTableChanged";
// 通知名：线程状态变化
NSString * const MVThreadStateChangedNotification = @"MVThreadStateChanged";

// 状态文案：任务开始
NSString * const MVStatusTaskStarted              = @"MVStatusTaskStarted";
// 状态文案：任务结束
NSString * const MVStatusTaskTerminated           = @"MVStatusTaskTerminated";

//============================================================================
// MVColumns：一行四列的字符串容器，对应详情表一行的四个单元格文本
//============================================================================
@implementation MVColumns

// 合成 offsetStr、dataStr、descriptionStr、valueStr 的存取器
@synthesize offsetStr, dataStr, descriptionStr, valueStr;

//-----------------------------------------------------------------------------
// 默认初始化
- (instancetype)init
{
  // 调用父类 NSObject 的 init
  self = [super init];
  // 初始化成功时
  if (self)
  {
#ifdef MV_STATISTICS
    // 统计：已加载行数 +1（MV_STATISTICS 开启时）
    OSAtomicIncrement64(&nrow_loaded);
#endif
  }
  // 返回 self
  return self;
}

//-----------------------------------------------------------------------------
// 用四列字符串初始化，col0~col3 对应 offset/data/description/value
-(id)initWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3
{
  // 先调用 [super init]，成功则继续
  if (self = [super init])
  {
    // 赋值偏移列
    offsetStr = col0;
    // 赋值数据列
    dataStr = col1;
    // 赋值描述列
    descriptionStr = col2;
    // 赋值值列
    valueStr = col3;

#ifdef MV_STATISTICS
    // 统计：已加载行数 +1
    OSAtomicIncrement64(&nrow_loaded);
#endif
  }
  // 返回 self
  return self;
}

//-----------------------------------------------------------------------------
// 类方法：用四列字符串创建并返回 MVColumns 实例
+(MVColumns *) columnsWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3
{
  // 分配并用 initWithData:::: 初始化后返回
  return [[MVColumns alloc] initWithData:col0:col1:col2:col3];
}

//-----------------------------------------------------------------------------
// 析构时若开启了统计则已加载行数 -1
-(void)dealloc
{
#ifdef MV_STATISTICS
  OSAtomicDecrement64(&nrow_loaded);
#endif
}

@end


//============================================================================
// MVRow：详情表一行，支持延迟从交换文件加载 columns/attributes 与按需写回
//============================================================================
@implementation MVRow

// 合成 columns、attributes、offset、deleted、dirty 的存取器
@synthesize columns, attributes, offset, deleted, dirty;

//-----------------------------------------------------------------------------
// 默认初始化
- (instancetype)init
{
  // 调用父类 init
  self = [super init];
  // 成功时
  if (self)
  {
#ifdef MV_STATISTICS
    // 统计：总行数 +1
    OSAtomicIncrement64(&nrow_total);
#endif
  }
  return self;
}

//-----------------------------------------------------------------------------
// 析构时若开启统计则总行数 -1
-(void)dealloc
{
#ifdef MV_STATISTICS
  OSAtomicDecrement64(&nrow_total);
#endif
}

//-----------------------------------------------------------------------------
// 按列索引返回对应字符串（OFFSET_COLUMN / DATA_COLUMN / DESCRIPTION_COLUMN / VALUE_COLUMN）
-(NSString *)columnAtIndex:(NSUInteger)index
{
  // 根据列索引返回对应列的字符串
  switch (index)
  {
    case OFFSET_COLUMN:       return columns.offsetStr;
    case DATA_COLUMN:         return columns.dataStr;
    case DESCRIPTION_COLUMN:  return columns.descriptionStr;
    case VALUE_COLUMN:        return columns.valueStr;
  }
  // 非法索引返回 nil
  return nil;
}

//-----------------------------------------------------------------------------
// 替换某一列内容并标记 columns 未写回（columnsOffset 清零，下次 saveToFile 会重写）
-(void)replaceColumnAtIndex:(NSUInteger)index withString:(NSString *)str
{
    // 标记 columns 尚未写回交换文件
    columnsOffset = 0;
    // 按列索引更新对应列字符串
    switch (index)
    {
        case OFFSET_COLUMN:       columns.offsetStr = str; break;
        case DATA_COLUMN:         columns.dataStr = str;  break;
        case DESCRIPTION_COLUMN: columns.descriptionStr = str; break;
        case VALUE_COLUMN:        columns.valueStr = str; break;
    }
}

//-----------------------------------------------------------------------------
// 将字符串以 C 字符串形式写入文件（含结尾 \0）
- (void)writeString:(NSString *)str toFile:(FILE *)pFile
{
    // 非空则写入整串加 \0
    if (str) {
        fwrite(CSTRING(str), [str length] + 1, 1, pFile);
    } else {
        // 空则只写一个 \0
        fputc('\0', pFile);
    }
}

//-----------------------------------------------------------------------------
// 从文件读取以 \0 结尾的 C 字符串并转为 NSString
- (NSString *)readStringFromFile:(FILE *)pFile
{
  // 用 std::string 累积字符
  std::string s;
  // 循环直到遇到 \0 或 EOF
  for(;;)
  {
    char c = fgetc(pFile);
    // 未到文件尾且非 \0 则追加
    if (!feof(pFile) && c)
      s += c;
    else
      break;
  }
  // 转为 NSString 返回
  return NSSTRING(s.c_str());
}

//-----------------------------------------------------------------------------
// 将颜色写入文件：系统预设色写枚举值，其它写 0 + 四个 float (RGBA)
- (void)writeColor:(NSColor *)color toFile:(FILE *)pFile
{
  // 与系统预设色逐一比较，匹配则用对应枚举值，否则为 0 表示后面跟 RGBA
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

  // 先写一个字节的枚举值
  putc(colorOrdinal, pFile);
  // 若为 0 则再写四个 float 表示 RGBA
  if (colorOrdinal == 0) {
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    float fred = red, fgreen = green, fblue = blue, falpha = alpha;
    fwrite(&fred, sizeof(float), 1, pFile);
    fwrite(&fgreen, sizeof(float), 1, pFile);
    fwrite(&fblue, sizeof(float), 1, pFile);
    fwrite(&falpha, sizeof(float), 1, pFile);
  }
}

//-----------------------------------------------------------------------------
// 从文件读取颜色：先读枚举值，若为 0 再读四个 float 构造 NSColor
- (NSColor *)readColorFromFile:(FILE *)pFile
{
  // 读一个字节的枚举值
  int colorOrdinal = getc(pFile);
  // 预设色直接返回对应 NSColor
  switch (colorOrdinal)
  {
    case MVBlackColorOrdinal:     return [NSColor blackColor];
    case MVDarkGrayColorOrdinal:  return [NSColor darkGrayColor];
    case MVLightGrayColorOrdinal: return [NSColor lightGrayColor];
    case MVWhiteColorOrdinal:     return [NSColor whiteColor];
    case MVGrayColorOrdinal:      return [NSColor grayColor];
    case MVRedColorOrdinal:       return [NSColor redColor];
    case MVGreenColorOrdinal:     return [NSColor greenColor];
    case MVBlueColorOrdinal:      return [NSColor blueColor];
    case MVCyanColorOrdinal:      return [NSColor cyanColor];
    case MVYellowColorOrdinal:    return [NSColor yellowColor];
    case MVMagentaColorOrdinal:   return [NSColor magentaColor];
    case MVOrangeColorOrdinal:    return [NSColor orangeColor];
    case MVPurpleColorOrdinal:    return [NSColor purpleColor];
    case MVBrownColorOrdinal:     return [NSColor brownColor];
  }

  // 枚举为 0 时读四个 float 并构造 NSColor
  float fred, fgreen, fblue, falpha;
  fread(&fred, sizeof(float), 1, pFile);
  fread(&fgreen, sizeof(float), 1, pFile);
  fread(&fblue, sizeof(float), 1, pFile);
  fread(&falpha, sizeof(float), 1, pFile);
  return [NSColor colorWithDeviceRed:fred green:fgreen blue:fblue alpha:falpha];
}

//----------------------------------------------------------------------------
// 将当前行的 attributes 字典序列化到文件（先写数量，再逐键值写 key 枚举 + value）
- (void)saveAttributestoFile:(FILE *)pFile
{
    // 属性个数
    uint64_t numAttributes = [attributes count];
    // 先写入属性个数，失败则返回
    if (fwrite (&numAttributes, sizeof(uint64_t), 1, pFile) < 1) {
        NSLog(@"fwrite failed in saveAttributestoFile:");
        return;
    }

  // 遍历每个键
  for (NSString * key in [attributes allKeys]) {
    id value = [attributes objectForKey:key];
    // 值为空则跳过
    if (value == nil) {
      continue;
    }

    // 将键名转为枚举值
    int keyOrdinal = [key isEqualToString:MVUnderlineAttributeName] ? MVUnderlineAttributeOrdinal
                   : [key isEqualToString:MVCellColorAttributeName] ? MVCellColorAttributeOrdinal
                   : [key isEqualToString:MVTextColorAttributeName] ? MVTextColorAttributeOrdinal
                   : [key isEqualToString:MVMetaDataAttributeName] ? MVMetaDataAttributeOrdinal
                   : 0;

    // 写入键枚举
    putc(keyOrdinal, pFile);
    // 根据键类型写入值（字符串或颜色）
    switch (keyOrdinal)
    {
      case MVUnderlineAttributeOrdinal: [self writeString:value toFile:pFile]; break;
      case MVCellColorAttributeOrdinal: [self writeColor:value toFile:pFile]; break;
      case MVTextColorAttributeOrdinal: [self writeColor:value toFile:pFile]; break;
      case MVMetaDataAttributeOrdinal:  [self writeString:value toFile:pFile]; break;
      default: NSLog(@"warning: unknown attribute key");
    }
  }
}

//----------------------------------------------------------------------------
// 从文件反序列化 attributes 字典（与 saveAttributestoFile 对应）
- (void)loadAttributesFromFile:(FILE *)pFile
{
  uint64_t numAttributes;
  // 先读属性个数
  fread(&numAttributes, sizeof(uint64_t), 1, pFile);

  // 创建字典并预分配容量
  NSMutableDictionary * _attributes = [[NSMutableDictionary alloc] initWithCapacity:numAttributes];
  // 按个数循环读取每个键值对
  while (numAttributes-- > 0)
  {
    // 读键枚举
    int keyOrdinal = getc(pFile);
    // 根据键类型读值并放入字典
    switch (keyOrdinal)
    {
      case MVUnderlineAttributeOrdinal: [_attributes setObject:[self readStringFromFile:pFile] forKey:MVUnderlineAttributeName]; break;
      case MVCellColorAttributeOrdinal: [_attributes setObject:[self readColorFromFile:pFile] forKey:MVCellColorAttributeName]; break;
      case MVTextColorAttributeOrdinal: [_attributes setObject:[self readColorFromFile:pFile] forKey:MVTextColorAttributeName]; break;
      case MVMetaDataAttributeOrdinal:  [_attributes setObject:[self readStringFromFile:pFile] forKey:MVMetaDataAttributeName]; break;
      default: NSLog(@"warning: unknown attribute key");
    }
  }

  // 赋给实例变量
  attributes = _attributes;
}

//----------------------------------------------------------------------------
// 将本行写入交换文件：若 columns 未写过则追加四列字符串并记下 columnsOffset；若 dirty 则追加/更新 attributes 并记 attributesOffset
- (void)saveToFile:(FILE *)pFile
{
    // 若 columns 尚未写入过（columnsOffset == 0）
    if (columnsOffset == 0) { // isSaved == NO
        // 记录当前文件位置作为 columns 的起始偏移
        off_t filePos = ftello(pFile);
        if (filePos == -1) {
            NSLog(@"MVRow saveToFile: ftello failed: %s", strerror(errno));
        }
        // 依次写入四列字符串
        [self writeString:columns.offsetStr toFile:(FILE *)pFile];
        [self writeString:columns.dataStr toFile:(FILE *)pFile];
        [self writeString:columns.descriptionStr toFile:(FILE *)pFile];
        [self writeString:columns.valueStr toFile:(FILE *)pFile];
        // 保存本次写入的起始位置，供后续按需读取
        columnsOffset = filePos;
    }

    // 若属性有修改未写回
    if (dirty) {
        // 若有旧属性在文件中，先读回再与当前内存属性合并，再整体写回
        if (attributesOffset > 0) {
            // 先复制当前内存属性
            NSMutableDictionary * _attributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
            // 定位到旧属性块并读入
            if (fseeko(pFile, attributesOffset, SEEK_SET) == -1) {
                NSLog(@"MVRow saveToFile: fseeko SEEK_SET failed: %s", strerror(errno));
            }
            [self loadAttributesFromFile:pFile];
            // 读完后回到文件末尾以便追加
            if (fseeko(pFile, 0, SEEK_END) == -1) {
                NSLog(@"MVRow saveToFile: fseeko SEEK_END failed: %s", strerror(errno));
            }
            // 将刚读入的旧属性合并进 _attributes（避免丢失之前写过的键）
            [_attributes addEntriesFromDictionary:attributes];
            // 用合并后的字典作为当前属性
            attributes = _attributes;
        }

        // 记录新属性块的起始位置
        off_t filePos = ftello(pFile);
        if (filePos == -1) {
            NSLog(@"MVRow saveToFile: ftello failed: %s", strerror(errno));
        }
        // 将属性写入文件
        [self saveAttributestoFile:(FILE *)pFile];
        // 清除脏标记
        dirty = NO;
        // 保存属性块偏移
        attributesOffset = filePos;
    }
}

//----------------------------------------------------------------------------
// 按需从交换文件加载：若 columns 未加载则按 columnsOffset 读四列；若 attributes 未加载且 attributesOffset>0 则读属性
- (void)loadFromFile:(FILE *)pFile
{
    // 若 columns 尚未加载
    if (columns == nil) {
        NSParameterAssert(columnsOffset != 0);

    // 定位到 columns 在文件中的位置
    if (fseeko(pFile, columnsOffset, SEEK_SET) == 0) {
            // 分配并依次读四列
            columns = [[MVColumns alloc] init];
            columns.offsetStr = [self readStringFromFile:pFile];
            columns.dataStr = [self readStringFromFile:pFile];
            columns.descriptionStr = [self readStringFromFile:pFile];
            columns.valueStr = [self readStringFromFile:pFile];
        } else {
            NSLog(@"*** reading error (columns) '%s'",strerror(errno));
            NSParameterAssert(0);
            return;
        }
    }

  // 若 attributes 未加载且文件中有属性块
  if (attributes == nil && attributesOffset > 0) {
        // 定位到属性块并读入
        if (fseeko(pFile, attributesOffset, SEEK_SET) == 0) {
            [self loadAttributesFromFile:pFile];
        } else {
            NSLog(@"*** reading error (attributes) '%s'",strerror(errno));
            NSParameterAssert(0);
        }
    }
}

//----------------------------------------------------------------------------
// 将本行在“索引区”中的条目写入（offset、columnsOffset、attributesOffset、deleted），供 MVTable 的索引区使用
- (void)saveIndexToFile:(FILE *)pFile
{
  fwrite(&offset, sizeof(uint32_t), 1, pFile);
  fwrite(&columnsOffset, sizeof(uint32_t), 1, pFile);
  fwrite(&attributesOffset, sizeof(uint32_t), 1, pFile);
  fwrite(&deleted, sizeof(BOOL), 1, pFile);
}

//----------------------------------------------------------------------------
// 从索引区读取本行元数据，行内容仍按需通过 loadFromFile 加载
- (void)loadIndexFromFile:(FILE *)pFile
{
  fread(&offset, sizeof(uint32_t), 1, pFile);
  fread(&columnsOffset, sizeof(uint32_t), 1, pFile);
  fread(&attributesOffset, sizeof(uint32_t), 1, pFile);
  fread(&deleted, sizeof(BOOL), 1, pFile);
}

//----------------------------------------------------------------------------
// 是否已把 columns 写入过交换文件（columnsOffset > 0）
-(BOOL) isSaved
{
  return (columnsOffset > 0);
}

//----------------------------------------------------------------------------
// MVSerializing 协议：释放已写入交换文件的内存（columns 必释，attributes 仅当未 dirty 时释）
-(void) clear
{
  // 仅当本行已写入过交换文件时才释放内存
  if (columnsOffset > 0) // isSaved == YES
  {
    // 释放四列内容
    columns = nil;

    // 若未脏则也可释放属性（避免覆盖未写回的新属性）
    if (dirty == NO)
    {
      attributes = nil;
    }
  }
}

@end

//============================================================================
// MVTable：某节点的详情表，管理 rows、过滤后的 displayRows、与 Archiver 的 swap 文件
//============================================================================
@implementation MVTable

// 合成 swapFile 的存取器
@synthesize swapFile;

//-----------------------------------------------------------------------------
// 禁止无参初始化，必须使用 tableWithArchiver:
- (instancetype)init
{
  NSAssert(NO, @"plain init is not allowed");
  return nil;
}

//-----------------------------------------------------------------------------
// 必须指定 archiver，用于把新行加入保存队列
- (instancetype)initWithArchiver:(MVArchiver *)_archiver
{
  if (self = [super init])
  {
    // 初始化行数组
    rows = [[NSMutableArray alloc] init];
    // 保存 archiver 弱引用
    archiver = _archiver;
    // 初始化表锁
    tableLock = [[NSLock alloc] init];
  }
  return self;
}

//----------------------------------------------------------------------------
// 类方法：用指定 archiver 创建 MVTable
+(MVTable *) tableWithArchiver:(MVArchiver *)_archiver
{
  return [[MVTable alloc] initWithArchiver:_archiver];
}

//----------------------------------------------------------------------------
// 返回当前应显示的行数（displayRows 的 count）
- (NSUInteger)rowCountToDisplay
{
  return [displayRows count];
}

//----------------------------------------------------------------------------
// 取当前过滤后的第 rowIndex 行；若该行尚未加载则从 swapFile 按需 loadFromFile
- (MVRow *)getRowToDisplay: (NSUInteger)rowIndex
{
  MVRow * row = nil;

  // 索引合法则取 displayRows 中对应行
  if (rowIndex < [displayRows count])
  {
    row = [displayRows objectAtIndex:rowIndex];
  }

  // 若取到行
  if (row != nil)
  {
    // 已逻辑删除则返回 nil
    if (row.deleted)
    {
      row = nil;
    }
    // 否则若该行内容尚未加载则从交换文件按需加载
    else if (row.columns == nil)
    {
      [row loadFromFile:swapFile];
    }
  }

  return row;
}

//----------------------------------------------------------------------------
// 插入一行（带 offset 用于排序），并加入 archiver 待保存队列
- (void)insertRowWithOffset:(uint64_t)offset :(id)col0 :(id)col1 :(id)col2 :(id)col3
{
  // 创建新行并设置四列与偏移
  MVRow * row = [[MVRow alloc] init];
  row.columns = [MVColumns columnsWithData:col0:col1:col2:col3];
  row.offset = offset;

  // 加锁后追加到 rows
  [tableLock lock];
  [rows addObject:row];
  [tableLock unlock];

  // 加入 archiver 待保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 在末尾追加一行（offset 传 0）
- (void)appendRow:(id)col0 :(id)col1 :(id)col2 :(id)col3
{
  [self insertRowWithOffset:0 :col0:col1:col2:col3];
}

//----------------------------------------------------------------------------
// 更新指定行列的单元格内容，并标记该行待写回
- (void)updateCellContentTo:(id)object atRow:(NSUInteger)rowIndex andCol:(NSUInteger)colIndex
{
  // 取出行并更新对应列
  MVRow * row = [rows objectAtIndex:rowIndex];
  [row replaceColumnAtIndex:colIndex withString:object];
  [rows replaceObjectAtIndex:rowIndex withObject:row];

  // 加入保存队列
  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 将最后一行标记为逻辑删除（deleted = YES）
- (void)popRow
{
  MVRow * row = [rows lastObject];
  row.deleted = YES;
}

//----------------------------------------------------------------------------
// 返回总行数（rows 的 count）
- (NSUInteger)rowCount
{
  return [rows count];
}

//----------------------------------------------------------------------------
// 将可变参数 name-value 对转为 NSMutableDictionary（用于 setAttributes 系列）
//----------------------------------------------------------------------------
-(NSMutableDictionary *)attributesWithPairs:(id)firstArg :(va_list)args
{
  NSMutableDictionary * attributes = [[NSMutableDictionary alloc] init];

  // 交替取 key 和 value，key 为 name，下一项为 value
  NSString * name = nil;
  for (id arg = firstArg; arg != nil; arg = va_arg(args, id))
  {
    if (name == nil)
    {
      name = arg;
      continue;
    }

    [attributes setObject:arg forKey:name];
    name = nil;
  }

  return attributes;
}

//----------------------------------------------------------------------------
// 为指定行设置属性字典并标记 dirty，若该行原本 dirty 则合并旧属性到新字典
- (void)setAttributes:(NSMutableDictionary *)attributes forRow:(MVRow *)row
{
  NSParameterAssert(row != nil);

  // 若该行原本脏，将旧属性合并进传入的 attributes，避免丢失
  if (row.dirty)
  {
    [attributes addEntriesFromDictionary:row.attributes];
  }

  row.attributes = attributes;
  row.dirty = YES;
}

//----------------------------------------------------------------------------
// 为最后一行设置属性（可变参数为 key1, value1, key2, value2, ..., nil）
- (void)setAttributes:(id)firstArg, ...
{
  va_list args;
  va_start(args, firstArg);
  NSMutableDictionary * attributes = [self attributesWithPairs:firstArg:args];
  va_end(args);

  MVRow * row = [rows lastObject];
  [self setAttributes:attributes forRow:row];

  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 为指定索引行设置属性
- (void)setAttributesForRowIndex:(NSUInteger)index :(id)firstArg, ...
{
  va_list args;
  va_start(args, firstArg);
  NSMutableDictionary * attributes = [self attributesWithPairs:firstArg:args];
  va_end(args);

  MVRow * row = [rows objectAtIndex:index];
  [self setAttributes:attributes forRow:row];

  [archiver addObjectToSave:row];
}

//----------------------------------------------------------------------------
// 从 index 行起至末尾，为每一行设置相同的属性字典（每行一份副本）
- (void)setAttributesFromRowIndex:(NSUInteger)index :(id)firstArg, ...
{
  va_list args;
  va_start(args, firstArg);
  NSDictionary * attributes = [self attributesWithPairs:firstArg:args];
  va_end(args);

  for (NSUInteger numRows = [rows count]; index < numRows; ++index)
  {
    MVRow * row = [rows objectAtIndex:index];
    [self setAttributes:[NSMutableDictionary dictionaryWithDictionary:attributes] forRow:row];

    [archiver addObjectToSave:row];
  }
}

//----------------------------------------------------------------------------
// 按搜索关键词过滤：空则显示全部；否则用 MVMetaDataAttributeName 做 contains 匹配，更新 displayRows
- (void) applyFilter: (NSString *)filter
{
  [tableLock lock];
  // 无过滤条件则显示全部行
  if (filter == nil || [filter length] == 0)
  {
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
  else
  {
    // 创建包含 filter 的谓词（不区分大小写）
    NSPredicate *predicate = [NSPredicate
                              predicateWithFormat:@"self contains[cd] %@", filter];

    displayRows = [[NSMutableArray alloc] init];
    for (MVRow * row in rows)
    {
      // 若行未加载则先从交换文件加载
      if (row.columns == nil)
      {
        [row loadFromFile:swapFile];
      }

      // 取该行元数据，无元数据或匹配则加入显示
      NSString * metadata = [row.attributes objectForKey:MVMetaDataAttributeName];
      if (metadata == nil || [predicate evaluateWithObject:metadata] == YES)
      {
        [displayRows addObject:row];
      }
    }
  }
  [tableLock unlock];
}

//----------------------------------------------------------------------------
// 按每行 offset 升序稳定排序 rows（displayRows 不重排，由 UI 按 displayRows 顺序显示）
- (void)sortByOffset
{
  [tableLock lock];
  [rows sortWithOptions:NSSortStable usingComparator:^(id obj1, id obj2)
   {
     MVRow * row1 = obj1;
     MVRow * row2 = obj2;
     if (row1.offset < row2.offset) return (NSComparisonResult)NSOrderedAscending;
     if (row1.offset > row2.offset) return (NSComparisonResult)NSOrderedDescending;
     return (NSComparisonResult)NSOrderedSame;
   }];
  [tableLock unlock];
}

//----------------------------------------------------------------------------
// 将本表索引写入 swapFile：先写行数，再逐行写每行的 saveIndexToFile（供 MVNode 保存 details 时用）
- (void)saveIndexes
{
    uint64_t rowCount = [rows count];
    if (fwrite(&rowCount, sizeof(uint64_t), 1, swapFile) < 1) {
        NSLog(@"saveIndexes write error");
        return;
    }

    for (MVRow * row in rows) {
        [row saveIndexToFile:swapFile];
    }
}

//----------------------------------------------------------------------------
// 从 swapFile 读取索引：行数 + 每行的 loadIndexFromFile，恢复 rows 元数据（行内容仍按需 loadFromFile）
- (void)loadIndexes
{
  uint64_t rowCount;
  fread(&rowCount, sizeof(uint64_t), 1, swapFile);

  while (rowCount-- > 0) {
    MVRow * row = [[MVRow alloc] init];
    [row loadIndexFromFile:swapFile];
    [rows addObject:row];
  }
}

@end


//============================================================================
// MVNode：左侧树节点，可带 details（MVTable），details 可交换到磁盘
//============================================================================
@implementation MVNode

@synthesize caption, parent, dataRange, details, userInfo, detailsOffset;

//-----------------------------------------------------------------------------
// 默认初始化：创建子节点数组与 userInfo 字典
- (instancetype)init
{
  if (self = [super init])
  {
    children = [[NSMutableArray alloc] init];
    userInfo = [[NSMutableDictionary alloc] init];
  }
  return self;
}

//----------------------------------------------------------------------------
// 调试描述：在父类描述后追加 [caption]
-(NSString *)description
{
  return [[super description] stringByAppendingFormat:@" [%@]", caption];
}

//----------------------------------------------------------------------------
// 返回第 n 个子节点
- (MVNode *)childAtIndex:(NSUInteger)n
{
  return [children objectAtIndex:n];
}

//----------------------------------------------------------------------------
// 返回子节点个数
- (NSUInteger)numberOfChildren
{
  return [children count];
}

//----------------------------------------------------------------------------
// 将子节点按 dataRange.location 有序插入 children，并发树变化通知、更新树视图
- (void)insertNode:(MVNode *)node
{
  // 从 userInfo 取当前 Layout
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];

  [layout.dataController.treeLock lock];

  // 找到第一个 dataRange.location 大于 node 的子节点索引，保证按 location 有序
  NSUInteger index = [children indexOfObjectPassingTest:
                      ^(id obj, NSUInteger idx, BOOL *stop)
                      {
                        if (node.dataRange.location < [obj dataRange].location)
                        {
                          *stop = YES;
                          return YES;
                        }
                        return NO;
                      }];

  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVDataTreeWillChangeNotification
                    object:layout.dataController];

  // 插入到找到的位置或末尾
  if (index == NSNotFound)
  {
    [children addObject:node];
  }
  else
  {
    [children insertObject:node atIndex:index];
  }

  [nc postNotificationName:MVDataTreeDidChangeNotification
                    object:layout.dataController];

  [layout.dataController updateTreeView:self];

  [layout.dataController.treeLock unlock];
}

//----------------------------------------------------------------------------
// 创建并插入一个无详情表的子节点（仅标题与 dataRange），userInfo 继承自父节点
- (MVNode *)insertChild:(NSString *)_caption
            location:(uint64_t)location
              length:(uint64_t)length
{
  MVNode * node = [[MVNode alloc] init];
  node.caption = _caption;
  node.dataRange = NSMakeRange(location,length);
  node.parent = self;
  [node.userInfo addEntriesFromDictionary:userInfo];
  [self insertNode:node];
  return node;
}

//----------------------------------------------------------------------------
// 创建带详情表的子节点；saver 在析构时会把该节点加入 layout.archiver 的保存队列
- (MVNode *)insertChildWithDetails:(NSString *)_caption
                       location:(uint64_t)location
                         length:(uint64_t)length
                          saver:(MVNodeSaver &)saver
{
  MVNode * node = [self insertChild:_caption location:location length:length];
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  node.details = [MVTable tableWithArchiver:layout.archiver];
  saver.setNode(node);
  return node;
}

//----------------------------------------------------------------------------
// 递归查找 userInfo 与给定字典相等的节点（用于从 userInfo 反查 MVNode）
- (MVNode *)findNodeByUserInfo:(NSDictionary *)uinfo
{
  // 当前节点匹配则返回 self
  if ([userInfo isEqualToDictionary:uinfo] == YES)
  {
    return self;
  }

  // 递归在子节点中查找
  for (MVNode * node in children)
  {
    MVNode * found = [node findNodeByUserInfo:uinfo];
    if (found != nil)
    {
      return found;
    }
  }

  return nil;
}

//-----------------------------------------------------------------------------
// 打开交换文件：若 details 正在写入则只把句柄赋给 details.swapFile；若已写入过则 loadFromFile 恢复 details
- (void)openDetails
{
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  FILE * pFile = fopen(CSTRING(layout.archiver.swapPath), "r");
  if (pFile != NULL)
  {
    if (details != nil) // saving in progress
    {
      details.swapFile = pFile;
    }
    else if (detailsOffset != 0) // saved and has content
    {
      [self loadFromFile:pFile];
    }
  }
}

//-----------------------------------------------------------------------------
// 关闭 details 的交换文件句柄
- (void)closeDetails
{
  if (details.swapFile != NULL)
  {
    fclose(details.swapFile);
    details.swapFile = NULL;
  }
}

//-----------------------------------------------------------------------------
// 对 details 表按 offset 排序，并更新状态条
- (void)sortDetails
{
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  [layout.dataController updateStatus:MVStatusTaskStarted];
  [details sortByOffset];
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//----------------------------------------------------------------------------
// 对 details 应用搜索过滤；过滤期间暂停 archiver 避免并发写
- (void)filterDetails: (NSString *)filter
{
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  [layout.dataController updateStatus:MVStatusTaskStarted];
  [layout.archiver suspend];
  [details applyFilter:filter];
  [layout.archiver resume];
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// MVSerializing：将本节点 details 的索引写入 pFile，记下 detailsOffset，并刷新树/表 UI
- (void)saveToFile:(FILE *)pFile
{
    MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
    [layout.dataController updateStatus:MVStatusTaskStarted];

    off_t filePos = ftello(pFile);
    if (filePos == -1) {
        NSLog(@"MVNode saveToFile: ftello failed: %s", strerror(errno));
    }
    details.swapFile = pFile;
    [details saveIndexes];
    detailsOffset = filePos;
    [layout.dataController updateTreeView:self];
    if (self == layout.dataController.selectedNode) {
        [self openDetails];
        [details applyFilter:nil];
    }

    [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// MVSerializing：从 pFile 的 detailsOffset 处恢复 details 表（loadIndexes）
- (void)loadFromFile:(FILE *)pFile
{
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  [layout.dataController updateStatus:MVStatusTaskStarted];
  details = [MVTable tableWithArchiver:layout.archiver];
  details.swapFile = pFile;
  NSParameterAssert(detailsOffset != 0);
  fseek (pFile, detailsOffset, SEEK_SET);
  [details loadIndexes];
  [layout.dataController updateStatus:MVStatusTaskTerminated];
}

//-----------------------------------------------------------------------------
// MVSerializing：若当前节点未被选中则释放 details 以省内存
-(void)clear
{
  MVLayout * layout = [userInfo objectForKey:MVLayoutUserInfoKey];
  if (layout.dataController.selectedNode != self)
  {
    details = nil;
  }
}

@end


//============================================================================
// MVDataController：根据文件头 magic 创建 Fat/Mach-O/Archive 布局，提供 CPU 与文件类型描述
//============================================================================
@implementation MVDataController

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
// 初始化：创建布局数组、根节点与树锁
- (instancetype)init
{
  if (self = [super init])
  {
    layouts = [[NSMutableArray alloc] init];
    rootNode = [[MVNode alloc] init];
    treeLock = [[NSLock alloc] init];
  }
  return self;
}

//----------------------------------------------------------------------------
// 将 cpu_type_t 转为可读架构名（X86、ARM64 等）
-(NSString *)getMachine:(cpu_type_t)cputype
{
    switch (cputype)
    {
        default:                  return @"???";
        case CPU_TYPE_I386:       return @"X86";
        case CPU_TYPE_POWERPC:    return @"PPC";
        case CPU_TYPE_X86_64:     return @"X86_64";
        case CPU_TYPE_POWERPC64:  return @"PPC64";
        case CPU_TYPE_ARM:        return @"ARM";
        case CPU_TYPE_ARM64:      return @"ARM64";
        case CPU_TYPE_ARM64_32:   return @"ARM64_32";
    }
}

//----------------------------------------------------------------------------
// 32 位 ARM 的 subtype 描述
-(NSString *)getARMCpu:(cpu_subtype_t)cpusubtype
{
    switch (cpusubtype & ~CPU_SUBTYPE_MASK)
    {
        default:                      return @"???";
        case CPU_SUBTYPE_ARM_ALL:     return @"ARM_ALL";
        case CPU_SUBTYPE_ARM_V4T:     return @"ARM_V4T";
        case CPU_SUBTYPE_ARM_V6:      return @"ARM_V6";
        case CPU_SUBTYPE_ARM_V5TEJ:   return @"ARM_V5TEJ";
        case CPU_SUBTYPE_ARM_XSCALE:  return @"ARM_XSCALE";
        case CPU_SUBTYPE_ARM_V7:      return @"ARM_V7";
        case CPU_SUBTYPE_ARM_V7F:     return @"ARM_V7F";
        case CPU_SUBTYPE_ARM_V7S:     return @"ARM_V7S";
        case CPU_SUBTYPE_ARM_V7K:     return @"ARM_V7K";
        case CPU_SUBTYPE_ARM_V8:      return @"ARM_V8";
        case CPU_SUBTYPE_ARM_V6M:     return @"ARM_V6M";
        case CPU_SUBTYPE_ARM_V7M:     return @"ARM_V7M";
        case CPU_SUBTYPE_ARM_V7EM:    return @"ARM_V7EM";
        case CPU_SUBTYPE_ARM_V8M:     return @"ARM_V8M";
    }
}

//----------------------------------------------------------------------------
// 64 位 ARM 的 subtype 描述
-(NSString *)getARM64Cpu:(cpu_subtype_t)cpusubtype
{
    switch (cpusubtype & ~CPU_SUBTYPE_MASK)
    {
        default:                      return @"???";
        case CPU_SUBTYPE_ARM64_ALL:   return @"ARM64_ALL";
        case CPU_SUBTYPE_ARM64_V8:    return @"ARM64_V8";
        case CPU_SUBTYPE_ARM64E:      return @"ARM64E";
    }
}

//----------------------------------------------------------------------------
// 当前是否支持该架构的解析与展示（支持则加入 layouts 并解析，否则仅显示标题）
-(BOOL)isSupportedMachine:(NSString *)machine
{
    return ([machine isEqualToString:@"X86"] == YES ||
            [machine isEqualToString:@"X86_64"] == YES ||
            [machine isEqualToString:@"ARM"] == YES ||
            [machine isEqualToString:@"ARM64"] == YES ||
            [machine isEqualToString:@"ARM64_32"] == YES);
}

//----------------------------------------------------------------------------
// Mach-O 文件类型对应的可读字符串（MH_OBJECT、MH_EXECUTE 等）
-(NSString *)getFileType:(uint32_t)filetype
{
    switch (filetype) {
        case MH_OBJECT:
            return @"Object ";
        case MH_EXECUTE:
            return @"Executable ";
        case MH_FVMLIB:
            return @"Fixed VM Shared Library";
        case MH_CORE:
            return @"Core";
        case MH_PRELOAD:
            return @"Preloaded Executable";
        case MH_DYLIB:
            return @"Shared Library ";
        case MH_DYLINKER:
            return @"Dynamic Link Editor";
        case MH_BUNDLE:
            return @"Bundle";
        case MH_DYLIB_STUB:
            return @"Shared Library Stub";
        case MH_DSYM:
            return @"Debug Symbols";
        case MH_KEXT_BUNDLE:
            return @"Kernel Extension";
        case MH_FILESET:
            return @"File Set";
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
        case MH_GPU_EXECUTE:
            return @"GPU Program";
        case MH_GPU_DYLIB:
            return @"GPU Support Functions";
#endif
        default:
            return @"?????";
    }
}

//----------------------------------------------------------------------------
// 为 32 位 Mach-O 创建 MachOLayout，设置节点标题并加入 layouts（若架构支持）
-(void)createMachOLayout:(MVNode *)node
             mach_header:(struct mach_header const *)mach_header
{
    NSString * machine = [self getMachine:mach_header->cputype];

  node.caption = [NSString stringWithFormat:@"%@ (%@)",
                    [self getFileType:mach_header->filetype],
                    [machine isEqualToString:@"ARM"] == YES ? [self getARMCpu:mach_header->cpusubtype] : machine];
  
    MachOLayout * layout = [MachOLayout layoutWithDataController:self rootNode:node];
                          
    [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];
  
    if ([self isSupportedMachine:machine]) {
        [layouts addObject:layout];
    }
    else {
        // there is no detail to extract
        [layout.archiver halt];
    }
}

//----------------------------------------------------------------------------
// 为 64 位 Mach-O 创建 MachOLayout
-(void)createMachO64Layout:(MVNode *)node
            mach_header_64:(struct mach_header_64 const *)mach_header_64
{
    NSString * machine = [self getMachine:mach_header_64->cputype];
        
    node.caption = [NSString stringWithFormat:@"%@ (%@)",
                    [self getFileType:mach_header_64->filetype],
                    [machine isEqualToString:@"ARM64"] == YES ? [self getARM64Cpu:mach_header_64->cpusubtype] : machine];
  
    MachOLayout * layout = [MachOLayout layoutWithDataController:self rootNode:node];

    [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];

    if ([self isSupportedMachine:machine]) {
        [layouts addObject:layout];
    }
    else {
        // there is no detail to extract
        [layout.archiver halt];
    }
}

//----------------------------------------------------------------------------
// 为静态库（ar）创建 ArchiveLayout；machine 可为 nil 或架构名
-(void)createArchiveLayout:(MVNode *)node machine:(NSString *)machine
{
  node.caption = machine ? [NSString stringWithFormat:@"Static Library (%@)", machine] : @"Static Library";
  
  ArchiveLayout * layout = [ArchiveLayout layoutWithDataController:self rootNode:node];
  
  [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];
    
  if (machine == nil || [self isSupportedMachine:machine])
    {
    [layouts addObject:layout];
    }
    else
    {
    // there is no detail to extract
    [layout.archiver halt];
  }
}

//----------------------------------------------------------------------------
// 根据 parent 在 location 处的 magic 创建对应布局：Fat / 32位 Mach-O / 64位 Mach-O / Archive
- (void)createLayouts:(MVNode *)parent
             location:(uint64_t)location
               length:(uint64_t)length
{
  // 读取文件头魔数（四字节）
  uint32_t magic = *(uint32_t*)((uint8_t *)[fileData bytes] + location);

  switch (magic)
  {
    case FAT_MAGIC:
    case FAT_CIGAM:
    {
      struct fat_header fat_header;
      [fileData getBytes:&fat_header range:NSMakeRange(location, sizeof(struct fat_header))];
      if (magic == FAT_CIGAM)
        swap_fat_header(&fat_header, NX_LittleEndian);
      [self createFatLayout:parent fat_header:&fat_header];
    } break;

    case MH_MAGIC:
    case MH_CIGAM:
    {
      struct mach_header mach_header;
      [fileData getBytes:&mach_header range:NSMakeRange(location, sizeof(struct mach_header))];
      if (magic == MH_CIGAM)
        swap_mach_header(&mach_header, NX_LittleEndian);
      [self createMachOLayout:parent mach_header:&mach_header];
    } break;

    case MH_MAGIC_64:
    case MH_CIGAM_64:
    {
      struct mach_header_64 mach_header_64;
      [fileData getBytes:&mach_header_64 range:NSMakeRange(location, sizeof(struct mach_header_64))];
      if (magic == MH_CIGAM_64)
        swap_mach_header_64(&mach_header_64, NX_LittleEndian);
      [self createMachO64Layout:parent mach_header_64:&mach_header_64];
    } break;

    default:
      [self createArchiveLayout:parent machine:nil];
  }

  parent.dataRange = NSMakeRange(location, length);
}

//----------------------------------------------------------------------------
// 创建 Fat 布局并递归为每个 slice 创建子布局（可能为 Archive 或单 Mach-O）
-(void)createFatLayout:(MVNode *)node
            fat_header:(struct fat_header const *)fat_header
{
  node.caption = @"Fat Binary";
  FatLayout * layout = [FatLayout layoutWithDataController:self rootNode:node];

  [node.userInfo setObject:layout forKey:MVLayoutUserInfoKey];

  [layouts addObject:layout];
  for (uint32_t nimg = 0; nimg < fat_header->nfat_arch; ++nimg)
  {
    struct fat_arch fat_arch;
    [fileData getBytes:&fat_arch range:NSMakeRange(sizeof(struct fat_header) + nimg * sizeof(struct fat_arch), sizeof(struct fat_arch))];
    swap_fat_arch(&fat_arch, 1, NX_LittleEndian);

    MVNode * archNode = [node insertChild:nil location:fat_arch.offset length:fat_arch.size];

    if (*(uint64_t*)((uint8_t *)[fileData bytes] + fat_arch.offset) == *(uint64_t*)"!<arch>\n")
    {
      [self createArchiveLayout:archNode machine:[self getMachine:fat_arch.cputype]];
    }
    else
    {
      [self createLayouts:archNode location:fat_arch.offset length:fat_arch.size];
    }
  }
}

//----------------------------------------------------------------------------
// 发送“树即将变化”通知（由 Layout 在插入节点前调用）
- (void)treeViewWillChange
{
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVDataTreeWillChangeNotification 
                    object:self];
}

//----------------------------------------------------------------------------
// 发送“树已完成变化”通知
- (void)treeViewDidChange
{
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVDataTreeDidChangeNotification
                    object:self];
}

//----------------------------------------------------------------------------
// 通知 UI 刷新树，可选携带本次变更相关的 node（MVNodeUserInfoKey）
- (void)updateTreeView: (MVNode *)node
{
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVDataTreeChangedNotification
                    object:self
                  userInfo:node ? [NSDictionary dictionaryWithObject:node forKey:MVNodeUserInfoKey] : nil];
}

//-----------------------------------------------------------------------------
// 通知 UI 刷新右侧详情表
- (void)updateTableView
{
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVDataTableChangedNotification
                    object:self];
}

//-----------------------------------------------------------------------------
// 更新状态条文案（通过 MVThreadStateChangedNotification + MVStatusUserInfoKey）
- (void)updateStatus: (NSString *)status
{
  NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:MVThreadStateChangedNotification
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:status forKey:MVStatusUserInfoKey]];
}

@end

#pragma mark -

//============================================================================
// MVArchiver：交换文件与后台保存线程，将 MVRow/MVNode 等延迟写入磁盘
//============================================================================
@implementation MVArchiver

@synthesize swapPath;

//-----------------------------------------------------------------------------
- (instancetype)init
{
  NSAssert(NO, @"plain init is not allowed");
  return nil;
}

//-----------------------------------------------------------------------------
// 创建交换文件（写版本头 "!<MachoViewSwapFile 1.0>\n"）并启动后台保存线程（除非 MV_NO_ARCHIVER）
- (instancetype)initWithPath:(NSString *)path
{
  if (self = [super init])
  {
    objectsToSave = [[NSMutableArray alloc] init];

    swapPath = path;

    NSLog(@"%@: swap file is being created:%@", self, swapPath);
    FILE * pFile = fopen(CSTRING(swapPath), "w");
    if (pFile == NULL)
    {
      NSLog(@"*** file cannot be created: %@ '%s'", swapPath,strerror(errno));
      return nil;
    }
    fputs("!<MachoViewSwapFile 1.0>\n", pFile);
    fclose(pFile);

    saverLock = [[NSLock alloc] init];

#ifndef MV_NO_ARCHIVER
    saverThread = [[NSThread alloc] initWithTarget:self selector:@selector(doSave) object:nil];
    [saverThread start];
    NSLog(@"********MVArchiver started: %@", self);
#endif
  }
  return self;
}

//-----------------------------------------------------------------------------
+(MVArchiver *) archiverWithPath:(NSString *)path
{
  return [[MVArchiver alloc] initWithPath:path];
}

//-----------------------------------------------------------------------------
// 暂停保存（持锁，doSave 中会因无法持锁而等待）
-(void) suspend
{
  [saverLock lock];
}

//-----------------------------------------------------------------------------
-(void) resume
{
  [saverLock unlock];
}

//-----------------------------------------------------------------------------
// 取消保存线程（析构或不需要再写时调用）
-(void) halt
{
  [saverThread cancel];
  NSLog(@"********MVArchiver halted: %@", self);
}

//-----------------------------------------------------------------------------
// 将实现了 MVSerializing 的对象加入待保存队列；若线程已取消则同步执行一次 doSave
-(void) addObjectToSave:(id)object;
{
  NSParameterAssert([object conformsToProtocol:@protocol(MVSerializing)] == YES);

  [saverLock lock];
  [objectsToSave addObject:object];
  [saverLock unlock];

  // if the background saver thread has been cancelled, then do do one cycle manually
  if ([saverThread isCancelled])
  {
    [self doSave];
  }
}

//-----------------------------------------------------------------------------
// 后台保存循环：有待保存对象时持 pipeCondition 增加 numIOThread、追加写入 swap 文件、clear 对象、释放锁并 signal；线程被取消时在队列空后退出
-(void) doSave
{
  for (;;)
  {
    if ([objectsToSave count] > 0)
    {
      [pipeCondition lock];
      ++numIOThread;
      [pipeCondition unlock];

      FILE * pFile = fopen(CSTRING(swapPath), "a+");
      if (pFile != NULL)
      {
        [saverLock lock];

#if DEBUG
        NSLog(@"%@: saving %lu rows",[NSThread currentThread],(unsigned long)[objectsToSave count]);
#endif
        for (id <MVSerializing> serializable in objectsToSave)
        {
          [serializable saveToFile:pFile];
        }
        fclose(pFile);

        for (id <MVSerializing> serializable in objectsToSave)
        {
          [serializable clear];
        }

        // reset buffer
        objectsToSave = [[NSMutableArray alloc] init];

        [saverLock unlock];
      }

      [pipeCondition lock];
      --numIOThread;
      [pipeCondition signal];
      [pipeCondition unlock];
    }

    if ([saverThread isCancelled])
    {
    // only exit if buffer is surely empty
      if ([objectsToSave count] == 0)
    {
      break; // the nicest way
      //return;
      //[NSThread exit];
    }
      // do not wait for new rows if the saver has been cancelled
      // just flush out the existing ones
      continue;
    }

    // let's wait for some objects to collect for saving
    double rnd = 1. + rand()/((double)RAND_MAX+1); // between 1 and 2
    [NSThread sleepForTimeInterval:rnd];
  }
}

@end

//-----------------------------------------------------------------------------
// MVNodeSaver：构造时记录节点，析构时将该节点加入对应 Layout 的 archiver 保存队列（供 insertChildWithDetails: 使用）
MVNodeSaver::MVNodeSaver()
  : m_node(nil)
{
}

//-----------------------------------------------------------------------------
// 析构：将登记的节点加入其 Layout 的 archiver 保存队列
MVNodeSaver::~MVNodeSaver()
{
  MVLayout * layout = [m_node.userInfo objectForKey:MVLayoutUserInfoKey];
  [layout.archiver addObjectToSave:m_node];
}
