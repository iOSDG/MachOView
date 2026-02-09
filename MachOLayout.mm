/*
 *  MachOLayout.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 公共宏与全局变量
#import "Common.h"
// Mach-O 布局头与类型定义
#import "MachOLayout.h"
// 数据控制器与 MVNode
#import "DataController.h"
// 按 NSRange 读写整数/字节
#import "ReadWrite.h"
// Load Command 解析与节点创建（Category）
#import "LoadCommands.h"
// 符号表、重定位等 LinkEdit 解析（Category）
#import "LinkEdit.h"
// Dyld 绑定/导出等解析（Category）
#import "DyldInfo.h"
// 异常 CFI/LSDA 解析（Category）
#import "Exceptions.h"
// 节内容（C 串、字面量、反汇编等）解析（Category）
#import "SectionContents.h"
// Objective-C 节解析（Category）
#import "ObjC.h"
// C++ 运行时足迹等（Category）
#import "CRTFootPrints.h"
// mach_header、load_command、segment_command 等
#import <mach-o/loader.h>
// nlist、nlist_64
#import <mach-o/nlist.h>
// relocation_info
#import <mach-o/reloc.h>

using namespace std;

//============================================================================
// MachOLayout 实现：Mach-O 头、Load Commands、段节、符号表、重定位、Dyld、节内容、异常、ObjC 等
//============================================================================
@implementation MachOLayout

//-----------------------------------------------------------------------------
// 指定初始化：先调父类，再初始化 RVA->符号名字典
- (instancetype)initWithDataController:(MVDataController *)dc rootNode:(MVNode *)node
{
  // 父类完成 dataController、rootNode、imageOffset、imageSize、backgroundThread、archiver
  if (self = [super initWithDataController:dc rootNode:node])
  {
    // 用于 findSymbolAtRVA，由 LinkEdit/Dyld 等解析时填充
    symbolNames = [[NSMutableDictionary alloc] init];
  }
  return self;
}

//-----------------------------------------------------------------------------
// 工厂方法：alloc + initWithDataController:rootNode:
+ (MachOLayout *)layoutWithDataController:(MVDataController *)dc rootNode:(MVNode *)node
{
  return [[MachOLayout alloc] initWithDataController:dc rootNode:node];
}

//-----------------------------------------------------------------------------
// 是否 64 位：根据 mach_header 的 cputype 是否带 CPU_ARCH_ABI64
- (BOOL)is64bit
{
  // 从镜像起始取 mach_header（32 位镜像）
  MATCH_STRUCT(mach_header,imageOffset);
  return ((mach_header->cputype & CPU_ARCH_ABI64) == CPU_ARCH_ABI64);
}

//-----------------------------------------------------------------------------
// 是否为 dylib stub：文件类型为 MH_DYLIB_STUB
- (BOOL)isDylibStub
{
  MATCH_STRUCT(mach_header,imageOffset);
  return (mach_header->filetype == MH_DYLIB_STUB);
}

//-----------------------------------------------------------------------------
// 按索引取 32 位 section，越界返回静态“未找到”结构
- (struct section const *)getSectionByIndex:(uint32_t)index
{
  // 占位用，索引 0 为 NULL，越界也返回类似占位
  static const struct section notfound = { "???", "?????", 0, 0, 0, 0, 0, 0, 0, 0, 0 };
  return (index < sections.size() ? sections.at(index) : &notfound);
}

//-----------------------------------------------------------------------------
// 按索引取 64 位 section
- (struct section_64 const *)getSection64ByIndex:(uint32_t)index
{
  static const struct section_64 notfound = { "???", "?????", 0, 0, 0, 0, 0, 0, 0, 0, 0 };
  return (index < sections_64.size() ? sections_64.at(index) : &notfound);
}

//-----------------------------------------------------------------------------
// 按索引取 32 位符号表条目
- (struct nlist const *)getSymbolByIndex:(uint32_t)index
{
  static const struct nlist notfound = { 0, 0, 0, 0, 0 }; 
  return (index < symbols.size() ? symbols.at(index) : &notfound);
}

//-----------------------------------------------------------------------------
// 按索引取 64 位符号表条目
- (struct nlist_64 const *)getSymbol64ByIndex:(uint32_t)index
{
  static const struct nlist_64 notfound = { 0, 0, 0, 0, 0 }; 
  return (index < symbols_64.size() ? symbols_64.at(index) : &notfound);
}

//-----------------------------------------------------------------------------
// 按索引取 dylib，越界返回静态占位
- (struct dylib const *)getDylibByIndex:(uint32_t)index
{
  static const struct dylib notfound = { 0, 0, 0, 0 }; 
  return (index < dylibs.size() ? dylibs.at(index) : &notfound);
}

//-----------------------------------------------------------------------------
// 根据 RVA 查符号名：先查 symbolNames 字典，无则返回十六进制地址字符串
- (NSString *)findSymbolAtRVA:(uint64_t)rva
{
  // 用 NSNumber 包装 rva 作为 key
  NSString * symbolName = [symbolNames objectForKey:[NSNumber numberWithUnsignedLongLong:rva]];
  return (symbolName != nil ? symbolName : [NSString stringWithFormat:@"0x%qX",rva]);
}

//-----------------------------------------------------------------------------
// 按节名与可选段名查找 32 位 section；从第二个元素开始（第一个为占位 NULL）
-(struct section const *)findSectionByName:(char const *)sectname 
                                andSegment:(char const *)segname
{
  // 跳过 sections[0] 占位
  for (SectionVector::const_iterator sectIter = ++sections.begin(); 
       sectIter != sections.end(); ++sectIter)
  {
    struct section const * section = *sectIter;
    // 段名可选；节名必须匹配，比较长度 16
    if ((segname == NULL || strncmp(section->segname,segname,16) == 0) && 
        strncmp(section->sectname,sectname,16) == 0)
    {
      return section;
    }
  }
  return NULL;
}

//-----------------------------------------------------------------------------
// 按节名与可选段名查找 64 位 section
-(struct section_64 const *)findSection64ByName:(char const *)sectname 
                                     andSegment:(char const *)segname
{
  for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); 
       sectIter != sections_64.end(); ++sectIter)
  {
    struct section_64 const * section_64 = *sectIter;
    if ((segname == NULL || strncmp(section_64->segname,segname,16) == 0) &&
        strncmp(section_64->sectname,sectname,16) == 0)
    {
      return section_64;
    }
  }
  return NULL;
}

//-----------------------------------------------------------------------------
// 将文件偏移转为虚拟地址：用 segmentInfo（fileOffset -> address,size）找到包含该偏移的段再换算
- (uint64_t)fileOffsetToRVA: (uint64_t)offset
{
    // upper_bound 找第一个 first > offset，前一个即为包含 offset 的段
    SegmentInfoMap::const_iterator segIter = segmentInfo.upper_bound(offset);
    if (segIter == segmentInfo.begin()) {
        [NSException raise:@"fileOffsetToRVA"
                    format:@"no segment found at offset 0x%llX", offset];
    }
    --segIter;
    uint64_t segOffset = segIter->first;
    uint64_t segAddr = segIter->second.first;
    // XXX: missing overflow checks
    return offset - segOffset + segAddr;
}

// ----------------------------------------------------------------------------
// 将虚拟地址转为文件偏移：用 sectionInfo（address -> fileOffset, userInfo）找到包含 rva 的节
- (uint64_t)RVAToFileOffset: (uint64_t)rva
{
    SectionInfoMap::const_iterator sectIter = sectionInfo.upper_bound(rva);
    if (sectIter == sectionInfo.begin()) {
        [NSException raise:@"RVAToFileOffset"
                    format:@"no section found at address 0x%llX", rva];
    }
    --sectIter;
    uint64_t sectOffset = sectIter->second.first;
    // 节内偏移 + 节文件偏移
    uint64_t fileOffset = sectOffset + (rva - [self fileOffsetToRVA:sectOffset]);
    NSAssert1(fileOffset < [dataController.fileData length], @"rva is out of range (0x%llX)", rva);
    return fileOffset;
}

// ----------------------------------------------------------------------------
// 在指定文件偏移处写入重定位值，直接修改 realData（用于 UI 重定位编辑等）
- (void)addRelocAtFileOffset:(uint64_t)offset withLength:(uint64_t)length andValue:(uint64_t)value
{
  [dataController.realData replaceBytesInRange:NSMakeRange(offset,length) withBytes:&value];
}

// ----------------------------------------------------------------------------

// 关闭“初始化覆盖”警告，因下面用 [0..255]=-1 再部分覆盖
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winitializer-overrides"
// 十六进制字符转数值表：非法字符为 -1，'0'-'9' 为 0-9，'A'-'F'/'a'-'f' 为 10-15
static const long hextable[] =
{
  [0 ... 255] = -1, // bit aligned access into this table is considerably
  ['0'] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, // faster for most modern processors,
  ['A'] = 10, 11, 12, 13, 14, 15,       // for the space conscious, reduce to
  ['a'] = 10, 11, 12, 13, 14, 15        // signed char.
};
#pragma clang diagnostic pop

/**
 * @brief convert a hexidecimal string to a signed long
 * will not produce or process negative numbers except
 * to signal error.
 *
 * @param hex without decoration, case insensitive.
 *
 * @return -1 on error, or result (max (sizeof(long)*8)-1 bits)
 */
static inline
long hexdec(const char *hex) {
    long ret = 0;
    while (*hex && ret >= 0) {
        ret = (ret << 4) | hextable[*hex++];
    }
    return ret;
}

// ----------------------------------------------------------------------------
// 数据源用：将界面中的“文件偏移”十六进制字符串转为 RVA 字符串显示
- (NSString *)convertToRVA: (NSString *)offsetStr
{
    // 先按十六进制解析为文件偏移
    uint64_t fileOffset = hexdec(CSTRING(offsetStr));
    NSParameterAssert((long)fileOffset != -1);
  
    // 若无段信息或偏移不在任意段内，返回空串
    if (segmentInfo.empty() ||
        fileOffset < segmentInfo.begin()->first ||
        fileOffset + 1 >= (--segmentInfo.end())->first + (--segmentInfo.end())->second.second)
    {
        return @"";
    }
  
    return [NSString stringWithFormat:@"%.8qX",[self fileOffsetToRVA:fileOffset]];
}

// ----------------------------------------------------------------------------
// 为 32 位 section 生成 userInfo：layout、segname、sectname、address，供 findNodeByUserInfo 查找节点
- (NSDictionary *)userInfoForSection:(struct section const *)section
{
  if (section == NULL) return nil;
  typeof(self) __weak weakSelf = self;
  return [NSDictionary dictionaryWithObjectsAndKeys:
          weakSelf,MVLayoutUserInfoKey,
          NSSTRING(string(section->segname,16).c_str()), @"segname",
          NSSTRING(string(section->sectname,16).c_str()), @"sectname",
          [NSNumber numberWithUnsignedLong:section->addr], @"address",
          nil];
}

//-----------------------------------------------------------------------------
// 为 64 位 section 生成 userInfo
- (NSDictionary *)userInfoForSection64:(struct section_64 const *)section_64
{
  if (section_64 == NULL) return nil;
  typeof(self) __weak weakSelf = self;
  return [NSDictionary dictionaryWithObjectsAndKeys:
          weakSelf,MVLayoutUserInfoKey,
          NSSTRING(string(section_64->segname,16).c_str()), @"segname",
          NSSTRING(string(section_64->sectname,16).c_str()), @"sectname",
          [NSNumber numberWithUnsignedLongLong:section_64->addr], @"address",
          nil];
}

//-----------------------------------------------------------------------------
// 重定位节点用 userInfo：layout + 固定 key "Relocations"
- (NSDictionary *)userInfoForRelocs
{
  typeof(self) __weak weakSelf = self;
  return [NSDictionary dictionaryWithObjectsAndKeys:
          weakSelf,MVLayoutUserInfoKey,
          @"Relocations", MVNodeUserInfoKey,
          nil];
}

//-----------------------------------------------------------------------------
// 根据 RVA 在 sectionInfo 中查 section 的 userInfo（segname、sectname、address 等）
- (NSDictionary *)sectionInfoForRVA:(uint64_t)rva
{
    SectionInfoMap::iterator iter = sectionInfo.upper_bound(rva);
    if (iter == sectionInfo.begin()) {
        NSLog(@"warning: no section info found for address 0x%.8qX",rva);
        return nil;
    }
    return (--iter)->second.second;
}

//-----------------------------------------------------------------------------
// 根据 RVA 返回 "segname sectname" 字符串，无节则返回 "NO SECTION..."
- (NSString *)findSectionContainsRVA:(uint64_t)rva
{
    NSDictionary * userInfo = [self sectionInfoForRVA:rva];
    return (userInfo ? [NSString stringWithFormat:@"%8s %-16s",
                        CSTRING([userInfo objectForKey:@"segname"]),
                        CSTRING([userInfo objectForKey:@"sectname"])] : @"NO SECTION               ");
}

//------------------------------------------------------------------------------
// 根据 RVA 找到包含该地址的 section 对应的树节点
- (MVNode *)sectionNodeContainsRVA:(uint64_t)rva
{
    NSDictionary * userInfo = [self sectionInfoForRVA:rva];
    return (userInfo ? [self findNodeByUserInfo:userInfo] : nil);
}

//-----------------------------------------------------------------------------
// 32 位：解析 __LINKEDIT 相关 Load Command，创建符号表、字符串表、DYSYMTAB、Two Level Hints、Segment Split、Code Signature、Function Starts、Data in Code 等节点
-(void) processLinkEdit
{
  // 待识别的 Load Command 指针，遍历 commands 时赋值
  struct symtab_command const * symtab_command = NULL;
  struct dysymtab_command const * dysymtab_command = NULL;
  struct twolevel_hints_command const * twolevel_hints_command = NULL;
  struct linkedit_data_command const * segment_split_info = NULL;
  struct linkedit_data_command const * code_signature = NULL;
  struct linkedit_data_command const * function_starts = NULL;
  struct linkedit_data_command const * data_in_code_entries = NULL;
  
  MATCH_STRUCT(mach_header,imageOffset);
  
  // 第一个有文件内容的段的 vmaddr（用于 Split Segment / Function Starts 等）
  uint32_t base_addr;
  // 所有段中最小 vmaddr
  uint32_t seg1addr = (uint32_t)-1;
  // MH_SPLIT_SEGS 时第一个可写段的 vmaddr，用于重定位基址
  uint32_t segs_read_write_addr = (uint32_t)-1;

  for (CommandVector::const_iterator cmdIter = commands.begin(); cmdIter != commands.end(); ++cmdIter)
  {
    struct load_command const * load_command = *cmdIter;
    switch (load_command->cmd)
    {
      case LC_SEGMENT:        
      {
        struct segment_command const * segment_command = (struct segment_command const *)load_command;
        
        if (segment_command->fileoff == 0 && segment_command->filesize != 0)
        {
					base_addr = segment_command->vmaddr;
        }

        if(segment_command->vmaddr < seg1addr)
        {
          seg1addr = segment_command->vmaddr;
        }
        
        // Pickup the address of the first read-write segment for MH_SPLIT_SEGS images.
        if((segment_command->initprot & VM_PROT_WRITE) == VM_PROT_WRITE &&
           segment_command->vmaddr < segs_read_write_addr)
        {
          segs_read_write_addr = segment_command->vmaddr;
        }
      } break;        
      case LC_SYMTAB: symtab_command = (struct symtab_command const *)load_command; break;
      case LC_DYSYMTAB: dysymtab_command = (struct dysymtab_command const *)load_command; break;
      case LC_TWOLEVEL_HINTS: twolevel_hints_command = (struct twolevel_hints_command const *)load_command; break;
      case LC_SEGMENT_SPLIT_INFO: segment_split_info = (struct linkedit_data_command const *)load_command; break;
      case LC_CODE_SIGNATURE: code_signature = (struct linkedit_data_command const *)load_command; break;
      case LC_FUNCTION_STARTS: function_starts = (struct linkedit_data_command const *)load_command; break;
      case LC_DATA_IN_CODE: data_in_code_entries = (struct linkedit_data_command const *)load_command; break;
      default: ; // not interested
    }
  }
  
  MVNode * symtabNode = nil;
  MVNode * dysymtabNode = nil;
  MVNode * twoLevelHintsNode = nil;
  MVNode * segmentSplitInfoNode = nil;
  MVNode * functionStartsNode = nil;
  MVNode * dataInCodeEntriesNode = nil;
  
  NSString * lastNodeCaption;
  
  if (symtab_command)
  {
    symtabNode = [self createDataNode:rootNode
                              caption:@"Symbol Table"
                             location:symtab_command->symoff + imageOffset
                               length:symtab_command->nsyms * sizeof(struct nlist)];
    
    [self createDataNode:rootNode 
                 caption:@"String Table"
                location:symtab_command->stroff + imageOffset
                  length:symtab_command->strsize];
  }
  
  if (dysymtab_command)
  {
    NSRange dysymtabRange = NSMakeRange(0,0);
    if (dysymtab_command->tocoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->tocoff + imageOffset, dysymtab_command->ntoc * sizeof(struct dylib_table_of_contents));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->modtaboff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->modtaboff + imageOffset, dysymtab_command->nmodtab * sizeof(struct dylib_module));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->extrefsymoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->extrefsymoff + imageOffset, dysymtab_command->nextrefsyms * sizeof(struct dylib_reference));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->indirectsymoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->indirectsymoff + imageOffset, dysymtab_command->nindirectsyms * sizeof(uint32_t));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->extreloff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->extreloff + imageOffset, dysymtab_command->nextrel * sizeof(struct relocation_info));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->locreloff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->locreloff + imageOffset, dysymtab_command->nlocrel * sizeof(struct relocation_info));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtabRange.length > 0)
    {
      dysymtabNode = [self createDataNode:rootNode
                                  caption:@"Dynamic Symbol Table"
                                 location:dysymtabRange.location
                                   length:dysymtabRange.length];
    }
  }
  
  if (twolevel_hints_command)
  {
    twoLevelHintsNode = [self createDataNode:rootNode 
                                     caption:@"Two Level Hints Table"
                                    location:twolevel_hints_command->offset + imageOffset
                                      length:twolevel_hints_command->nhints * sizeof(struct twolevel_hint)];
  }

  if (segment_split_info)
  {
    segmentSplitInfoNode = [self createDataNode:rootNode 
                                        caption:@"Segment Split Info"
                                       location:segment_split_info->dataoff + imageOffset
                                         length:segment_split_info->datasize];
  }
  
  if (code_signature)
  {
    [self createDataNode:rootNode 
                 caption:@"Code Signature"
                location:code_signature->dataoff + imageOffset
                  length:code_signature->datasize];
  }
  
  if (function_starts)
  {
    functionStartsNode = [self createDataNode:rootNode 
                                      caption:@"Function Starts"
                                     location:function_starts->dataoff + imageOffset
                                       length:function_starts->datasize];
  }
  
  if (data_in_code_entries)
  {
    dataInCodeEntriesNode = [self createDataNode:rootNode
                                         caption:@"Data in Code Entries"
                                        location:data_in_code_entries->dataoff + imageOffset
                                          length:data_in_code_entries->datasize];
  }
  
  //============ Symbol Table ====================
  //==============================================
  if (symtabNode)
  {
    @try
    {
      [self createSymbolsNode:symtabNode
                      caption:(lastNodeCaption = @"Symbols")
                     location:symtabNode.dataRange.location
                       length:symtabNode.dataRange.length];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  
  //=========== Dynamic Symbol Table =============
  //==============================================
  if (dysymtabNode)
  {
    @try
    {
      //=============== Module Table =================
      //==============================================
      if (dysymtab_command->modtaboff * dysymtab_command->nmodtab > 0)
      {
        [self createModulesNode:dysymtabNode 
                        caption:(lastNodeCaption = @"Modules")
                       location:dysymtab_command->modtaboff + imageOffset
                         length:dysymtab_command->nmodtab * sizeof(struct dylib_module)];
      }

      //========== Table of Contents =================
      //==============================================
      if (dysymtab_command->tocoff * dysymtab_command->ntoc > 0)
      {
        [self createTOCNode:dysymtabNode 
                    caption:(lastNodeCaption = @"Table of Contents")
                   location:dysymtab_command->tocoff + imageOffset 
                     length:dysymtab_command->ntoc * sizeof(struct dylib_table_of_contents)];
      }

      //======= External Reference Table =============
      //==============================================
      if (dysymtab_command->extrefsymoff * dysymtab_command->nextrefsyms > 0)
      {
        [self createReferencesNode:dysymtabNode 
                           caption:(lastNodeCaption = @"External References")
                          location:dysymtab_command->extrefsymoff + imageOffset
                            length:dysymtab_command->nextrefsyms * sizeof(struct dylib_reference)];
      }

      //========== Indirect Symbol Table =============
      //==============================================
      if (dysymtab_command->indirectsymoff * dysymtab_command->nindirectsyms > 0)
      {
        [self createISymbolsNode:dysymtabNode
                         caption:(lastNodeCaption = @"Indirect Symbols")
                        location:dysymtab_command->indirectsymoff + imageOffset
                          length:dysymtab_command->nindirectsyms * sizeof(uint32_t)];
      }

      //========== External Reloc Table ==============
      //==============================================
      if (dysymtab_command->extreloff * dysymtab_command->nextrel > 0)
      {
        [self createRelocNode:dysymtabNode 
                      caption:(lastNodeCaption = @"External Relocations")
                     location:dysymtab_command->extreloff + imageOffset
                       length:dysymtab_command->nextrel * sizeof(struct relocation_info)
                  baseAddress:(mach_header->flags & MH_SPLIT_SEGS) == MH_SPLIT_SEGS ? segs_read_write_addr : seg1addr];
      }

      //=========== Local Reloc Table ================
      //==============================================
      if (dysymtab_command->locreloff * dysymtab_command->nlocrel > 0)
      {
        [self createRelocNode:dysymtabNode 
                      caption:(lastNodeCaption = @"Local Relocations")
                     location:dysymtab_command->locreloff + imageOffset
                       length:dysymtab_command->nlocrel * sizeof(struct relocation_info)
                  baseAddress:(mach_header->flags & MH_SPLIT_SEGS) == MH_SPLIT_SEGS ? segs_read_write_addr : seg1addr];
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (twoLevelHintsNode && twoLevelHintsNode.dataRange.length > 0)
  {
    @try
    {
      [self createTwoLevelHintsNode:twoLevelHintsNode 
                            caption:(lastNodeCaption = @"Hints") 
                           location:twoLevelHintsNode.dataRange.location
                             length:twoLevelHintsNode.dataRange.length
                              index:dysymtab_command->iundefsym];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }

  if (segmentSplitInfoNode && segmentSplitInfoNode.dataRange.length > 0)
  {
    @try
    {
      [self createSplitSegmentNode:segmentSplitInfoNode 
                           caption:(lastNodeCaption = @"Shared Region Info")
                          location:segmentSplitInfoNode.dataRange.location
                            length:segmentSplitInfoNode.dataRange.length
                       baseAddress:base_addr];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (functionStartsNode && functionStartsNode.dataRange.length > 0)
  {
    @try
    {
      [self createFunctionStartsNode:functionStartsNode 
                             caption:(lastNodeCaption = @"Functions")  
                            location:functionStartsNode.dataRange.location 
                              length:functionStartsNode.dataRange.length
                         baseAddress:base_addr];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (dataInCodeEntriesNode && dataInCodeEntriesNode.dataRange.length > 0)
  {
    @try
    {
      [self createDataInCodeEntriesNode:dataInCodeEntriesNode
                                caption:(lastNodeCaption = @"Dices")
                               location:dataInCodeEntriesNode.dataRange.location
                                 length:dataInCodeEntriesNode.dataRange.length];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 64 位：解析 __LINKEDIT，创建符号表、字符串表、DYSYMTAB、Two Level Hints、Segment Split、Code Signature、Function Starts、Data in Code 等节点（与 processLinkEdit 对称，使用 nlist_64/dylib_module_64）
-(void) processLinkEdit64
{
  struct symtab_command const * symtab_command = NULL;
  struct dysymtab_command const * dysymtab_command = NULL;
  struct twolevel_hints_command const * twolevel_hints_command = NULL;
  struct linkedit_data_command const * segment_split_info = NULL;
  struct linkedit_data_command const * code_signature = NULL;
  struct linkedit_data_command const * function_starts = NULL;
  struct linkedit_data_command const * data_in_code_entries = NULL;
  
  MATCH_STRUCT(mach_header_64,imageOffset);
  
  uint64_t base_addr;
  uint64_t seg1addr = (uint64_t)-1LL;
  uint64_t segs_read_write_addr = (uint64_t)-1LL;
  
  for (CommandVector::const_iterator cmdIter = commands.begin(); cmdIter != commands.end(); ++cmdIter)
  {
    struct load_command const * load_command = *cmdIter;
    switch (load_command->cmd)
    {
      case LC_SEGMENT_64:     
      {
        struct segment_command_64 const * segment_command_64 = (struct segment_command_64 const *)load_command;
        
        if (segment_command_64->fileoff == 0 && segment_command_64->filesize != 0)
        {
					base_addr = segment_command_64->vmaddr;
        }
        
        if(segment_command_64->vmaddr < seg1addr)
        {
          seg1addr = segment_command_64->vmaddr;
        }
        
        // Pickup the address of the first read-write segment for MH_SPLIT_SEGS images.
        if((segment_command_64->initprot & VM_PROT_WRITE) == VM_PROT_WRITE &&
           segment_command_64->vmaddr < segs_read_write_addr)
        {
          segs_read_write_addr = segment_command_64->vmaddr;
        }
      } break;
      case LC_SYMTAB: symtab_command = (struct symtab_command const *)load_command; break;
      case LC_DYSYMTAB: dysymtab_command = (struct dysymtab_command const *)load_command; break;
      case LC_TWOLEVEL_HINTS: twolevel_hints_command = (struct twolevel_hints_command const *)load_command; break;
      case LC_SEGMENT_SPLIT_INFO: segment_split_info = (struct linkedit_data_command const *)load_command; break;
      case LC_CODE_SIGNATURE: code_signature = (struct linkedit_data_command const *)load_command; break;
      case LC_FUNCTION_STARTS: function_starts = (struct linkedit_data_command const *)load_command; break;
      case LC_DATA_IN_CODE: data_in_code_entries = (struct linkedit_data_command const *)load_command; break;
      default: ; // not interested
    }
  }

  MVNode * symtabNode = nil;
  MVNode * dysymtabNode = nil;
  MVNode * twoLevelHintsNode = nil;
  MVNode * segmentSplitInfoNode = nil;
  MVNode * functionStartsNode = nil;
  MVNode * dataInCodeEntriesNode = nil;

  NSString * lastNodeCaption;
  
  if (symtab_command)
  {
    symtabNode = [self createDataNode:rootNode
                              caption:@"Symbol Table"
                             location:symtab_command->symoff + imageOffset
                               length:symtab_command->nsyms * sizeof(struct nlist_64)];
    
    [self createDataNode:rootNode 
                 caption:@"String Table"
                location:symtab_command->stroff + imageOffset
                  length:symtab_command->strsize];
  }
  
  if (dysymtab_command)
  {
    NSRange dysymtabRange = NSMakeRange(0,0);
    if (dysymtab_command->tocoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->tocoff + imageOffset, dysymtab_command->ntoc * sizeof(struct dylib_table_of_contents));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->modtaboff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->modtaboff + imageOffset, dysymtab_command->nmodtab * sizeof(struct dylib_module_64));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->extrefsymoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->extrefsymoff + imageOffset, dysymtab_command->nextrefsyms * sizeof(struct dylib_reference));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->indirectsymoff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->indirectsymoff + imageOffset, dysymtab_command->nindirectsyms * sizeof(uint32_t));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->extreloff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->extreloff + imageOffset, dysymtab_command->nextrel * sizeof(struct relocation_info));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtab_command->locreloff > 0)
    {
      NSRange range = NSMakeRange(dysymtab_command->locreloff + imageOffset, dysymtab_command->nlocrel * sizeof(struct relocation_info));
      dysymtabRange = NSMaxRange(dysymtabRange) > 0 ? NSUnionRange(dysymtabRange, range) : range;
    }
    if (dysymtabRange.length > 0)
    {
      dysymtabNode = [self createDataNode:rootNode
                                  caption:@"Dynamic Symbol Table"
                                 location:dysymtabRange.location
                                   length:dysymtabRange.length];
    }
  }
  
  if (twolevel_hints_command)
  {
    twoLevelHintsNode = [self createDataNode:rootNode 
                                     caption:@"Two Level Hints Table"
                                    location:twolevel_hints_command->offset + imageOffset
                                      length:twolevel_hints_command->nhints * sizeof(struct twolevel_hint)];
  }
  
  if (segment_split_info)
  {
    segmentSplitInfoNode = [self createDataNode:rootNode 
                                        caption:@"Segment Split Info"
                                       location:segment_split_info->dataoff + imageOffset
                                         length:segment_split_info->datasize];
  }

  if (code_signature)
  {
    [self createDataNode:rootNode 
                 caption:@"Code Signature"
                location:code_signature->dataoff + imageOffset
                  length:code_signature->datasize];
  }

  if (function_starts)
  {
    functionStartsNode = [self createDataNode:rootNode 
                                      caption:@"Function Starts"
                                     location:function_starts->dataoff + imageOffset
                                       length:function_starts->datasize];
  }

  if (data_in_code_entries)
  {
    dataInCodeEntriesNode = [self createDataNode:rootNode
                                         caption:@"Data in Code Entries"
                                        location:data_in_code_entries->dataoff + imageOffset
                                          length:data_in_code_entries->datasize];
  }
  
  //============ Symbol Table ====================
  //==============================================
  if (symtabNode)
  {
    @try
    {
      [self createSymbols64Node:symtabNode
                        caption:(lastNodeCaption = @"Symbols")
                       location:symtabNode.dataRange.location
                         length:symtabNode.dataRange.length];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  

  //=========== Dynamic Symbol Table =============
  //==============================================
  if (dysymtabNode)
  {
    @try
    {
      //=============== Module Table =================
      //==============================================
      if (dysymtab_command->modtaboff * dysymtab_command->nmodtab > 0)
      {
        [self createModules64Node:dysymtabNode 
                          caption:(lastNodeCaption = @"Modules64")
                         location:dysymtab_command->modtaboff + imageOffset
                           length:dysymtab_command->nmodtab * sizeof(struct dylib_module_64)];
      }  

      //========== Table of Contents =================
      //==============================================
      if (dysymtab_command->tocoff * dysymtab_command->ntoc > 0)
      {
        [self createTOC64Node:dysymtabNode 
                      caption:(lastNodeCaption = @"Table of Contents")
                     location:dysymtab_command->tocoff + imageOffset 
                       length:dysymtab_command->ntoc * sizeof(struct dylib_table_of_contents)];
      }

      //======= External Reference Table =============
      //==============================================
      if (dysymtab_command->extrefsymoff * dysymtab_command->nextrefsyms > 0)
      {
        [self createReferencesNode:dysymtabNode 
                           caption:(lastNodeCaption = @"External References")
                          location:dysymtab_command->extrefsymoff + imageOffset
                            length:dysymtab_command->nextrefsyms * sizeof(struct dylib_reference)];
      }

      //========== Indirect Symbol Table =============
      //==============================================
      if (dysymtab_command->indirectsymoff * dysymtab_command->nindirectsyms > 0)
      {
        [self createISymbols64Node:dysymtabNode
                           caption:(lastNodeCaption = @"Indirect Symbols")
                          location:dysymtab_command->indirectsymoff + imageOffset
                            length:dysymtab_command->nindirectsyms * sizeof(uint32_t)];
      }

      //========== External Reloc Table ==============
      //==============================================
      if (dysymtab_command->extreloff * dysymtab_command->nextrel > 0)
      {
        [self createReloc64Node:dysymtabNode 
                        caption:(lastNodeCaption = @"External Relocations")
                       location:dysymtab_command->extreloff + imageOffset
                         length:dysymtab_command->nextrel * sizeof(struct relocation_info)
                    baseAddress:(mach_header_64->flags & MH_SPLIT_SEGS) == MH_SPLIT_SEGS ? segs_read_write_addr : seg1addr];
      }

      //=========== Local Reloc Table ================
      //==============================================
      if (dysymtab_command->locreloff * dysymtab_command->nlocrel > 0)
      {
        [self createReloc64Node:dysymtabNode 
                        caption:(lastNodeCaption = @"Local Reloc Table")
                       location:dysymtab_command->locreloff + imageOffset
                         length:dysymtab_command->nlocrel * sizeof(struct relocation_info)
                    baseAddress:(mach_header_64->flags & MH_SPLIT_SEGS) == MH_SPLIT_SEGS ? segs_read_write_addr : seg1addr];
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (twoLevelHintsNode && twoLevelHintsNode.dataRange.length > 0)
  {
    @try
    {
      [self createTwoLevelHintsNode:twoLevelHintsNode 
                            caption:(lastNodeCaption = @"Hints") 
                           location:twoLevelHintsNode.dataRange.location
                             length:twoLevelHintsNode.dataRange.length
                              index:dysymtab_command->iundefsym];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (segmentSplitInfoNode && segmentSplitInfoNode.dataRange.length > 0)
  {
    @try
    {
      [self createSplitSegmentNode:segmentSplitInfoNode 
                           caption:(lastNodeCaption = @"Shared Region Info") 
                          location:segmentSplitInfoNode.dataRange.location
                            length:segmentSplitInfoNode.dataRange.length
                       baseAddress:base_addr];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }  
  
  if (functionStartsNode && functionStartsNode.dataRange.length > 0)
  {
    @try
    {
      [self createFunctionStartsNode:functionStartsNode 
                             caption:(lastNodeCaption = @"Functions")  
                            location:functionStartsNode.dataRange.location 
                              length:functionStartsNode.dataRange.length
                         baseAddress:base_addr];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  if (dataInCodeEntriesNode && dataInCodeEntriesNode.dataRange.length > 0)
  {
    @try
    {
      [self createDataInCodeEntriesNode:dataInCodeEntriesNode
                                caption:(lastNodeCaption = @"Dices")
                               location:dataInCodeEntriesNode.dataRange.location
                                 length:dataInCodeEntriesNode.dataRange.length];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 解析 LC_DYLD_INFO/LC_DYLD_INFO_ONLY：创建 Dynamic Loader Info 节点，并解析 Rebase、Binding、Weak Bind、Lazy Bind、Export 子节点
-(void)processDyldInfo
{
  uint64_t base_addr = 0;
  
  struct dyld_info_command const * dyld_info_command = NULL;
  
  for (CommandVector::const_iterator cmdIter = commands.begin(); cmdIter != commands.end(); ++cmdIter)
  {
    struct load_command const * load_command = *cmdIter;
    switch (load_command->cmd)
    {
      case LC_SEGMENT:     
      {
        struct segment_command const * segment_command = (struct segment_command const *)load_command;
        if (segment_command->fileoff == 0 && segment_command->filesize != 0)
        {
					base_addr = segment_command->vmaddr;
        }
      } break;

      case LC_SEGMENT_64:     
      {
        struct segment_command_64 const * segment_command_64 = (struct segment_command_64 const *)load_command;
        if (segment_command_64->fileoff == 0 && segment_command_64->filesize != 0)
        {
					base_addr = segment_command_64->vmaddr;
        }
      } break;
      case LC_DYLD_INFO:
      case LC_DYLD_INFO_ONLY: dyld_info_command = (struct dyld_info_command const *)load_command; break;
      default: ; // not interested
    }
  }
  
  if (dyld_info_command == NULL)
  {
    return;
  }
  
  NSRange dyldInfoRange = NSMakeRange(0,0);
  if (dyld_info_command->rebase_off > 0)
  {
    NSRange range = NSMakeRange(dyld_info_command->rebase_off + imageOffset, dyld_info_command->rebase_size);
    dyldInfoRange = NSMaxRange(dyldInfoRange) > 0 ? NSUnionRange(dyldInfoRange, range) : range;
  }
  if (dyld_info_command->bind_off > 0)
  {
    NSRange range = NSMakeRange(dyld_info_command->bind_off + imageOffset, dyld_info_command->bind_size);
    dyldInfoRange = NSMaxRange(dyldInfoRange) > 0 ? NSUnionRange(dyldInfoRange, range) : range;
  }
  if (dyld_info_command->weak_bind_off > 0)
  {
    NSRange range = NSMakeRange(dyld_info_command->weak_bind_off + imageOffset, dyld_info_command->weak_bind_size);
    dyldInfoRange = NSMaxRange(dyldInfoRange) > 0 ? NSUnionRange(dyldInfoRange, range) : range;
  }
  if (dyld_info_command->lazy_bind_off > 0)
  {
    NSRange range = NSMakeRange(dyld_info_command->lazy_bind_off + imageOffset, dyld_info_command->lazy_bind_size);
    dyldInfoRange = NSMaxRange(dyldInfoRange) > 0 ? NSUnionRange(dyldInfoRange, range) : range;
  }
  if (dyld_info_command->export_off > 0)
  {
    NSRange range = NSMakeRange(dyld_info_command->export_off + imageOffset, dyld_info_command->export_size);
    dyldInfoRange = NSMaxRange(dyldInfoRange) > 0 ? NSUnionRange(dyldInfoRange, range) : range;
  }
  MVNode * dyldInfoNode = [self createDataNode:rootNode
                                       caption:@"Dynamic Loader Info"
                                      location:dyldInfoRange.location
                                        length:dyldInfoRange.length];
  
  DyldHelper * dyldHelper = [DyldHelper dyldHelperWithSymbols:symbolNames is64Bit:[self is64bit]];
  
  NSString * lastNodeCaption;
  @try 
  {
    if (dyld_info_command->rebase_off * dyld_info_command->rebase_size > 0)
    {
      [self createRebaseNode:dyldInfoNode
                     caption:(lastNodeCaption = @"Rebase Info")
                    location:dyld_info_command->rebase_off + imageOffset
                      length:dyld_info_command->rebase_size
                 baseAddress:base_addr];
    }

    if (dyld_info_command->bind_off * dyld_info_command->bind_size > 0)
    {
      [self createBindingNode:dyldInfoNode
                      caption:(lastNodeCaption = @"Binding Info")
                     location:dyld_info_command->bind_off + imageOffset
                       length:dyld_info_command->bind_size
                  baseAddress:base_addr
                     nodeType:NodeTypeBind
                   dyldHelper:dyldHelper];
    }

    if (dyld_info_command->weak_bind_off * dyld_info_command->weak_bind_size > 0)
    {
      [self createBindingNode:dyldInfoNode
                      caption:(lastNodeCaption = @"Weak Binding Info")
                     location:dyld_info_command->weak_bind_off + imageOffset
                       length:dyld_info_command->weak_bind_size
                  baseAddress:base_addr
                     nodeType:NodeTypeWeakBind
                   dyldHelper:dyldHelper];
    }

    if (dyld_info_command->lazy_bind_off * dyld_info_command->lazy_bind_size > 0)
    {
      [self createBindingNode:dyldInfoNode
                      caption:(lastNodeCaption = @"Lazy Binding Info")
                     location:dyld_info_command->lazy_bind_off + imageOffset
                       length:dyld_info_command->lazy_bind_size
                  baseAddress:base_addr
                     nodeType:NodeTypeLazyBind
                   dyldHelper:dyldHelper];
    }
    
    if (dyld_info_command->export_off * dyld_info_command->export_size > 0)
    {
      [self createExportNode:dyldInfoNode
                     caption:(lastNodeCaption = @"Export Info")
                    location:dyld_info_command->export_off + imageOffset
                      length:dyld_info_command->export_size
                 baseAddress:base_addr];
    }
  }
  @catch(NSException * exception)
  {
    [self printException:exception caption:lastNodeCaption];
  }
  
}

//-----------------------------------------------------------------------------
// 节名/段名比较仿函数：用于 find_if 查找指定 segname+sectname 或仅 sectname 的 section
template <typename SectionT>
struct CompareSectionByName
{
  CompareSectionByName(char const * segname, char const * sectname) 
    : segname(segname)
    , sectname(sectname) 
  {
  }

  CompareSectionByName(char const * sectname) 
    : segname(NULL)
    , sectname(sectname) 
  {
  }
  
  bool operator() (SectionT const * section)
  {
    return ((segname == NULL || strncmp(segname,section->segname,16) == 0) && 
                                strncmp(sectname,section->sectname,16) == 0);
  }
  
  char const * segname;
  char const * sectname;
};

//-----------------------------------------------------------------------------
// 32 位：按 section 类型创建字面量节（C 串、4/8/16 字节浮点）与指针/桩节（Literal Pointers、Lazy/Non-Lazy Symbol Pointers、Symbol Stubs 等）子节点
-(void)processSections
{
  NSString * lastNodeCaption;
  
  for (SectionVector::const_iterator sectIter = ++sections.begin(); sectIter != sections.end(); ++sectIter)
  {
    struct section const * section = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try
    {
      switch (section->flags & SECTION_TYPE)
      {
        case S_CSTRING_LITERALS: 
          [self createCStringsNode:sectionNode 
                           caption:(lastNodeCaption = @"C String Literals")
                          location:section->offset + imageOffset
                            length:section->size]; break;
      
        case S_4BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section->offset + imageOffset
                            length:section->size
                            stride:4]; break;
          
        case S_8BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section->offset + imageOffset
                            length:section->size
                            stride:8]; break;

        case S_16BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section->offset + imageOffset
                            length:section->size
                            stride:16]; break;
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }

  //================ sections with pointer content ============================
  for (SectionVector::const_iterator sectIter = ++sections.begin(); sectIter != sections.end(); ++sectIter)
  {
    struct section const * section = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try 
    {
      switch (section->flags & SECTION_TYPE)
      {
        case S_LITERAL_POINTERS:
          [self createPointersNode:sectionNode 
                           caption:(lastNodeCaption = @"Literal Pointers")
                          location:section->offset + imageOffset
                            length:section->size]; break;

        case S_MOD_INIT_FUNC_POINTERS:
          [self createPointersNode:sectionNode 
                           caption:(lastNodeCaption = @"Module Init Func Pointers") 
                          location:section->offset + imageOffset
                            length:section->size]; break;

        case S_MOD_TERM_FUNC_POINTERS:
          [self createPointersNode:sectionNode 
                           caption:(lastNodeCaption = @"Module Term Func Pointers") 
                          location:section->offset + imageOffset
                            length:section->size]; break;

        case S_LAZY_SYMBOL_POINTERS:
          [self createIndPointersNode:sectionNode 
                              caption:(lastNodeCaption = @"Lazy Symbol Pointers")
                             location:section->offset + imageOffset
                               length:section->size]; break;

        case S_NON_LAZY_SYMBOL_POINTERS:
          [self createIndPointersNode:sectionNode 
                              caption:(lastNodeCaption = @"Non-Lazy Symbol Pointers")
                             location:section->offset + imageOffset
                               length:section->size]; break;

        case S_LAZY_DYLIB_SYMBOL_POINTERS:
          [self createIndPointersNode:sectionNode 
                              caption:(lastNodeCaption = @"Lazy Dylib Symbol Pointers")
                             location:section->offset + imageOffset
                               length:section->size]; break;

        case S_SYMBOL_STUBS:
          [self createIndStubsNode:sectionNode 
                           caption:(lastNodeCaption = @"Symbol Stubs")
                          location:section->offset + imageOffset
                            length:section->size
                            stride:section->reserved2]; break;
       
        default:;
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
}

//-----------------------------------------------------------------------------
// 64 位：与 processSections 对称，处理 sections_64 的字面量节与指针/桩节
-(void)processSections64
{
  NSString * lastNodeCaption;

  for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); sectIter != sections_64.end(); ++sectIter)
  {
    struct section_64 const * section_64 = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try
    {
      switch (section_64->flags & SECTION_TYPE)
      {
        case S_CSTRING_LITERALS: 
          [self createCStringsNode:sectionNode 
                           caption:(lastNodeCaption = @"C String Literals")
                          location:section_64->offset + imageOffset
                            length:section_64->size]; break;
          
        case S_4BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section_64->offset + imageOffset
                            length:section_64->size
                            stride:4]; break;
          
        case S_8BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section_64->offset + imageOffset
                            length:section_64->size
                            stride:8]; break;
          
        case S_16BYTE_LITERALS:
          [self createLiteralsNode:sectionNode 
                           caption:(lastNodeCaption = @"Floating Point Literals")
                          location:section_64->offset + imageOffset
                            length:section_64->size
                            stride:16]; break;
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
    
  //================ sections with pointer content ============================
  for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); sectIter != sections_64.end(); ++sectIter)
  {
    struct section_64 const * section_64 = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try 
    {
      switch (section_64->flags & SECTION_TYPE)
      {
        case S_LITERAL_POINTERS:
          [self createPointers64Node:sectionNode 
                             caption:(lastNodeCaption = @"Literal Pointers")
                            location:section_64->offset + imageOffset
                              length:section_64->size]; break;
          
        case S_MOD_INIT_FUNC_POINTERS:
          [self createPointers64Node:sectionNode 
                             caption:(lastNodeCaption = @"Module Init Func Pointers") 
                            location:section_64->offset + imageOffset
                              length:section_64->size]; break;
          
        case S_MOD_TERM_FUNC_POINTERS:
          [self createPointers64Node:sectionNode 
                             caption:(lastNodeCaption = @"Module Term Func Pointers") 
                            location:section_64->offset + imageOffset
                              length:section_64->size]; break;
          
        case S_LAZY_SYMBOL_POINTERS:
          [self createIndPointers64Node:sectionNode 
                                caption:(lastNodeCaption = @"Lazy Symbol Pointers")
                               location:section_64->offset + imageOffset
                                 length:section_64->size]; break;
          
        case S_NON_LAZY_SYMBOL_POINTERS:
          [self createIndPointers64Node:sectionNode 
                                caption:(lastNodeCaption = @"Non-Lazy Symbol Pointers")
                               location:section_64->offset + imageOffset
                                 length:section_64->size]; break;
          
        case S_LAZY_DYLIB_SYMBOL_POINTERS:
          [self createIndPointers64Node:sectionNode 
                                caption:(lastNodeCaption = @"Lazy Dylib Symbol Pointers")
                               location:section_64->offset + imageOffset
                                 length:section_64->size]; break;
          
        case S_SYMBOL_STUBS:
          [self createIndStubs64Node:sectionNode 
                             caption:(lastNodeCaption = @"Symbol Stubs")
                            location:section_64->offset + imageOffset
                              length:section_64->size
                              stride:section_64->reserved2]; break;
          
        default:;
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
}

//-----------------------------------------------------------------------------
// 32 位：解析 __eh_frame 节中的 CFI 记录，为每个 FDE 创建 Call Frame 子节点
-(void)processEHFrames
{
  if ([self isDylibStub] == YES)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  
  for (SectionVector::iterator sectIter = find_if(++sections.begin(), sections.end(), CompareSectionByName<struct section>("__eh_frame"));
       sectIter != sections.end();
       sectIter = find_if(++sectIter, sections.end(), CompareSectionByName<struct section>("__eh_frame")))
  {
    struct section const * section = *sectIter;
    
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]];
    // there is no valid exception data
    if (sectionNode == nil) 
    {
      return;
    }
    
    /* The .eh_frame section shall contain 1 or more Call Frame Information (CFI) records. 
     * The number of records present shall be determined by size of the section as contained in the section header.
     * Each CFI record contains a Common Information Entry (CIE) record followed by 1 or more Frame Description Entry (FDE) records. 
     * Both CIEs and FDEs shall be aligned to an addressing unit sized boundary.
     */
    
    @try
    {
      uint64_t location = section->offset + imageOffset;
      do
      {
        NSRange range = NSMakeRange(location,0);
        uint32_t length = [dataController read_uint32:range];
        uint32_t cieID = [dataController read_uint32:range];
        
        if (cieID == 0)
        {
          uint64_t CIE_addr = [self fileOffsetToRVA:location];
          [self createCFINode:sectionNode
                      caption:(lastNodeCaption = [NSString stringWithFormat:@"Call Frame %@", [self findSymbolAtRVA:CIE_addr]])
                     location:location
                       length:section->offset + imageOffset + section->size - location];  // upper bound
        }
        location += length + /*length itself */ sizeof(uint32_t);
      } while (location - section->offset - imageOffset < section->size);
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 64 位：解析 __eh_frame 节中的 CFI 记录
-(void)processEHFrames64
{
  if ([self isDylibStub] == YES)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  
  for (Section64Vector::iterator sectIter = find_if(++sections_64.begin(), sections_64.end(), CompareSectionByName<struct section_64>("__eh_frame"));
       sectIter != sections_64.end();
       sectIter = find_if(++sectIter, sections_64.end(), CompareSectionByName<struct section_64>("__eh_frame")))
  {
    struct section_64 const * section_64 = *sectIter;
    
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]];
    // there is no valid exception data
    if (sectionNode == nil) 
    {
      return;
    }
    
    /* The .eh_frame section shall contain 1 or more Call Frame Information (CFI) records. 
     * The number of records present shall be determined by size of the section as contained in the section header.
     * Each CFI record contains a Common Information Entry (CIE) record followed by 1 or more Frame Description Entry (FDE) records. 
     * Both CIEs and FDEs shall be aligned to an addressing unit sized boundary.
     */
    
    @try
    {
      uint64_t location = section_64->offset + imageOffset;
      do
      {
        NSRange range = NSMakeRange(location,0);
        uint32_t length = [dataController read_uint32:range];
        uint32_t cieID = [dataController read_uint32:range];
        
        if (cieID == 0)
        {
          uint64_t CIE_addr = [self fileOffsetToRVA:location];
          [self createCFINode:sectionNode
                      caption:(lastNodeCaption = [NSString stringWithFormat:@"Call Frame %@", [self findSymbolAtRVA:CIE_addr]])
                     location:location
                       length:section_64->offset + imageOffset + section_64->size - location]; // upper bound
        }
        location += length + /*length itself */ sizeof(uint32_t);
      } while (location - section_64->offset - imageOffset < section_64->size);
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 32 位：解析 __gcc_except_tab 节，根据 lsdaInfo（LSDA 地址 -> FDE 地址）为每个 LSDA 创建子节点
-(void)processLSDA
{
  if ([self isDylibStub] == YES)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  
  for (SectionVector::iterator sectIter = find_if(++sections.begin(), sections.end(), CompareSectionByName<struct section>("__gcc_except_tab"));
       sectIter != sections.end();
       sectIter = find_if(++sectIter, sections.end(), CompareSectionByName<struct section>("__gcc_except_tab")))
  {
    struct section const * section = *sectIter;
    
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]];
    NSParameterAssert(sectionNode != nil);
    if (sectionNode == nil)
    { 
      return;
    }
    
    @try 
    {
      for (ExceptionFrameMap::iterator ehFrameIter = lsdaInfo.begin(); ehFrameIter != lsdaInfo.end();)
      {
        uint64_t lsdaAddr = ehFrameIter->first;
        uint64_t frameAddr = ehFrameIter->second;
        
        uint64_t location = [self RVAToFileOffset:lsdaAddr];
        
        uint64_t length = (++ehFrameIter != lsdaInfo.end()
                           ? [self RVAToFileOffset:ehFrameIter->first]
                           : imageOffset + section->offset + section->size) - location;
        
        [self createLSDANode:sectionNode 
                     caption:(lastNodeCaption = [NSString stringWithFormat:@"LSDA %@",[self findSymbolAtRVA:lsdaAddr]])
                    location:location
                      length:length
              eh_frame_begin:frameAddr];
      }
    }      
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 64 位：解析 __gcc_except_tab 节中的 LSDA
-(void)processLSDA64
{
  if ([self isDylibStub] == YES)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  
  for (Section64Vector::iterator sectIter = find_if(++sections_64.begin(), sections_64.end(), CompareSectionByName<struct section_64>("__gcc_except_tab"));
       sectIter != sections_64.end();
       sectIter = find_if(++sectIter, sections_64.end(), CompareSectionByName<struct section_64>("__gcc_except_tab")))
  {
    struct section_64 const * section_64 = *sectIter;
    
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]];
    NSParameterAssert(sectionNode != nil);
    if (sectionNode == nil)
    {
      return;
    }
    
    @try 
    {
      for (ExceptionFrameMap::iterator ehFrameIter = lsdaInfo.begin(); ehFrameIter != lsdaInfo.end();)
      {
        uint64_t lsdaAddr = ehFrameIter->first;
        uint64_t frameAddr = ehFrameIter->second;
        
        uint64_t location = [self RVAToFileOffset:lsdaAddr];
        
        uint64_t length = (++ehFrameIter != lsdaInfo.end()
                           ? [self RVAToFileOffset:ehFrameIter->first]
                           : section_64->offset + section_64->size) - location;
        
        [self createLSDANode:sectionNode 
                     caption:(lastNodeCaption = [NSString stringWithFormat:@"LSDA %@",[self findSymbolAtRVA:lsdaAddr]])
                    location:location
                      length:length
              eh_frame_begin:frameAddr];
      }
    }      
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 32 位：解析 Objective-C 相关节（__OBJC/__OBJC2/__DATA：module_info、class_list、category_list、protocol、message_refs、image_info、cfstring 等），并解析类/分类/协议指针
-(void)processObjcSections
{
    PointerVector objcClassPointers;
    PointerVector objcClassReferences;
    PointerVector objcSuperReferences;
    PointerVector objcCategoryPointers;
    PointerVector objcProtocolPointers;
    
    NSString * lastNodeCaption;
    MVNode * sectionNode;
    struct section const * section;
    bool hasObjCModules = false; // objC version detector
    
    @try
    {
        section = [self findSectionByName:"__module_info" andSegment:"__OBJC"];
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
            hasObjCModules = true;
            [self createObjCModulesNode:sectionNode
                                caption:(lastNodeCaption = @"ObjC Modules")
                               location:section->offset + imageOffset
                                 length:section->size];
        }
        
        section = [self findSectionByName:"__class_ext" andSegment:"__OBJC"];
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
            [self createObjCClassExtNode:sectionNode
                                 caption:(lastNodeCaption = @"ObjC Class Extensions")
                                location:section->offset + imageOffset
                                  length:section->size];
        }
        
        section = [self findSectionByName:"__protocol_ext" andSegment:"__OBJC"];
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
            [self createObjCProtocolExtNode:sectionNode
                                    caption:(lastNodeCaption = @"ObjC Protocol Extensions")
                                   location:section->offset + imageOffset
                                     length:section->size];
        }
        
        // second Objective-C ABI
        if (hasObjCModules == false) {
            section = [self findSectionByName:"__category_list" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_catlist" andSegment:"__DATA_CONST"];
            }
            if (section == NULL) {
                section = [self findSectionByName:"__objc_catlist" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2PointerListNode:sectionNode
                                         caption:(lastNodeCaption = @"ObjC2 Category List")
                                        location:section->offset + imageOffset
                                          length:section->size
                                        pointers:objcCategoryPointers];
            }
            
            section = [self findSectionByName:"__class_list" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_classlist" andSegment:"__DATA_CONST"];
            }
            if (section == NULL) {
                section = [self findSectionByName:"__objc_classlist" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2PointerListNode:sectionNode
                                         caption:(lastNodeCaption = @"ObjC2 Class List")
                                        location:section->offset + imageOffset
                                          length:section->size
                                        pointers:objcClassPointers];
            }
            
            section = [self findSectionByName:"__class_refs" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_classrefs" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2PointerListNode:sectionNode
                                         caption:(lastNodeCaption = @"ObjC2 References")
                                        location:section->offset + imageOffset
                                          length:section->size
                                        pointers:objcClassReferences];
            }
            
            section = [self findSectionByName:"__super_refs" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_superrefs" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2PointerListNode:sectionNode
                                         caption:(lastNodeCaption = @"ObjC2 References")
                                        location:section->offset + imageOffset
                                          length:section->size
                                        pointers:objcSuperReferences];
            }
            
            section = [self findSectionByName:"__protocol_list" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_protolist" andSegment:"__DATA__CONST"];
            }
            if (section == NULL) {
                section = [self findSectionByName:"__objc_protolist" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2PointerListNode:sectionNode
                                         caption:(lastNodeCaption = @"ObjC2 Pointer List")
                                        location:section->offset + imageOffset
                                          length:section->size
                                        pointers:objcProtocolPointers];
            }
            
            section = [self findSectionByName:"__message_refs" andSegment:"__OBJC2"];
            if (section == NULL) {
                section = [self findSectionByName:"__objc_msgrefs" andSegment:"__DATA"];
            }
            if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
                [self createObjC2MsgRefsNode:sectionNode
                                     caption:(lastNodeCaption = @"ObjC2 Message References")
                                    location:section->offset + imageOffset
                                      length:section->size];
            }
        } // if (hasObjcModules == false)
        
        section = [self findSectionByName:"__image_info" andSegment:"__OBJC"];
        if (section == NULL) {
            section = [self findSectionByName:"__objc_imageinfo" andSegment:"__DATA__CONST"];
        }
        if (section == NULL) {
            section = [self findSectionByName:"__objc_imageinfo" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
            [self createObjCImageInfoNode:sectionNode
                                  caption:(lastNodeCaption = @"ObjC2 Image Info")
                                 location:section->offset + imageOffset
                                   length:section->size];
        }
        
        section = [self findSectionByName:"__cfstring" andSegment:NULL];
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]])) {
            [self createObjCCFStringsNode:sectionNode
                                  caption:(lastNodeCaption = @"ObjC CFStrings")
                                 location:section->offset + imageOffset
                                   length:section->size];
        }
    }
    @catch(NSException * exception)
    {
        [self printException:exception caption:lastNodeCaption];
    }
    
    @try
    {
        [self parseObjC2ClassPointers:&objcClassPointers
                     CategoryPointers:&objcCategoryPointers
                     ProtocolPointers:&objcProtocolPointers];
    }
    @catch(NSException * exception)
    {
        [self printException:exception caption:lastNodeCaption];
    }
}

//-----------------------------------------------------------------------------
// 64 位：解析 Objective-C 相关节（class_list、category_list、protocol、message_refs、image_info、cfstring 等）
-(void)processObjcSections64
{
    Pointer64Vector objcClassPointers;
    Pointer64Vector objcClassReferences;
    Pointer64Vector objcSuperReferences;
    Pointer64Vector objcCategoryPointers;
    Pointer64Vector objcProtocolPointers;
    
    NSString * lastNodeCaption;
    MVNode * sectionNode;
    struct section_64 const * section_64;
    
    @try
    {
        section_64 = [self findSection64ByName:"__class_list" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_classlist" andSegment:"__DATA_CONST"];
        }
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_classlist" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2Pointer64ListNode:sectionNode
                                       caption:(lastNodeCaption = @"ObjC2 Class List")
                                      location:section_64->offset + imageOffset
                                        length:section_64->size
                                      pointers:objcClassPointers];
        }
        
        section_64 = [self findSection64ByName:"__class_refs" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_classrefs" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2Pointer64ListNode:sectionNode
                                       caption:(lastNodeCaption = @"ObjC2 References")
                                      location:section_64->offset + imageOffset
                                        length:section_64->size
                                      pointers:objcClassReferences];
        }
        
        section_64 = [self findSection64ByName:"__super_refs" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_superrefs" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2Pointer64ListNode:sectionNode
                                       caption:(lastNodeCaption = @"ObjC2 References")
                                      location:section_64->offset + imageOffset
                                        length:section_64->size
                                      pointers:objcSuperReferences];
        }
        
        section_64 = [self findSection64ByName:"__category_list" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_catlist" andSegment:"__DATA_CONST"];
        }
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_catlist" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2Pointer64ListNode:sectionNode
                                       caption:(lastNodeCaption = @"ObjC2 Category List")
                                      location:section_64->offset + imageOffset
                                        length:section_64->size
                                      pointers:objcCategoryPointers];
        }
        
        section_64 = [self findSection64ByName:"__protocol_list" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_protolist" andSegment:"__DATA_CONST"];
        }
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_protolist" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2Pointer64ListNode:sectionNode
                                       caption:(lastNodeCaption = @"ObjC2 Pointer List")
                                      location:section_64->offset + imageOffset
                                        length:section_64->size
                                      pointers:objcProtocolPointers];
        }
        
        section_64 = [self findSection64ByName:"__message_refs" andSegment:"__OBJC2"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_msgrefs" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjC2MsgRefs64Node:sectionNode
                                   caption:(lastNodeCaption = @"ObjC2 Message References")
                                  location:section_64->offset + imageOffset
                                    length:section_64->size];
        }
        
        section_64 = [self findSection64ByName:"__image_info" andSegment:"__OBJC"];
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_imageinfo" andSegment:"__DATA_CONST"];
        }
        if (section_64 == NULL) {
            section_64 = [self findSection64ByName:"__objc_imageinfo" andSegment:"__DATA"];
        }
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjCImageInfoNode:sectionNode
                                  caption:(lastNodeCaption = @"ObjC2 Image Info")
                                 location:section_64->offset + imageOffset
                                   length:section_64->size];
        }
        
        section_64 = [self findSection64ByName:"__cfstring" andSegment:NULL];
        if ((sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]]))
        {
            [self createObjCCFStrings64Node:sectionNode
                                    caption:(lastNodeCaption = @"ObjC CFStrings")
                                   location:section_64->offset + imageOffset
                                     length:section_64->size];
        }
    }
    @catch(NSException * exception)
    {
        [self printException:exception caption:lastNodeCaption];
    }
    
    @try
    {
        [self parseObjC2Class64Pointers:&objcClassPointers
                     Category64Pointers:&objcCategoryPointers
                     Protocol64Pointers:&objcProtocolPointers];
    }
    @catch(NSException * exception)
    {
        [self printException:exception caption:lastNodeCaption];
    }
}

//-----------------------------------------------------------------------------
// 32 位：为标记为 S_ATTR_PURE_INSTRUCTIONS 且非 S_SYMBOL_STUBS 的 section 创建反汇编（Assembly）子节点
- (void)processCodeSections
{
  struct dysymtab_command const * dysymtab_command = NULL;
  for (CommandVector::const_iterator cmdIter = commands.begin(); cmdIter != commands.end(); ++cmdIter)
  {
    struct load_command const * load_command = *cmdIter;
    switch (load_command->cmd)
    {
      case LC_DYSYMTAB: dysymtab_command = (struct dysymtab_command const *)load_command; break;
      default: ; // not interested
    }
  }
  

  NSString * lastNodeCaption;
  
  for (SectionVector::const_iterator sectIter = ++sections.begin(); sectIter != sections.end(); ++sectIter)
  {
    struct section const * section = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection:section]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try 
    {
      if ((section->flags & S_ATTR_PURE_INSTRUCTIONS) && (section->flags & SECTION_TYPE) != S_SYMBOL_STUBS)
      {
        [self createTextNode:sectionNode 
                     caption:(lastNodeCaption = @"Assembly") 
                    location:section->offset + imageOffset 
                      length:section->size
                      reloff:section->reloff + imageOffset
                      nreloc:section->nreloc
                   extreloff:dysymtab_command ? dysymtab_command->extreloff : 0
                     nextrel:dysymtab_command ? dysymtab_command->nextrel : 0
                   locreloff:dysymtab_command ? dysymtab_command->locreloff : 0
                     nlocrel:dysymtab_command ? dysymtab_command->nlocrel : 0];
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 64 位：为纯指令节创建反汇编子节点
- (void)processCodeSections64
{
  struct dysymtab_command const * dysymtab_command = NULL;
  for (CommandVector::const_iterator cmdIter = commands.begin(); cmdIter != commands.end(); ++cmdIter)
  {
    struct load_command const * load_command = *cmdIter;
    switch (load_command->cmd)
    {
      case LC_DYSYMTAB: dysymtab_command = (struct dysymtab_command const *)load_command; break;
      default: ; // not interested
    }
  }
  
  
  NSString * lastNodeCaption;
  
  for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); sectIter != sections_64.end(); ++sectIter)
  {
    struct section_64 const * section_64 = *sectIter;
    MVNode * sectionNode = [self findNodeByUserInfo:[self userInfoForSection64:section_64]];
    if (sectionNode == nil)
    {
      continue;
    }
    
    @try 
    {
      if ((section_64->flags & S_ATTR_PURE_INSTRUCTIONS) && (section_64->flags & SECTION_TYPE) != S_SYMBOL_STUBS)
      {
        [self createTextNode:sectionNode 
                     caption:(lastNodeCaption = @"Assembly") 
                    location:section_64->offset + imageOffset 
                      length:section_64->size
                      reloff:section_64->reloff + imageOffset
                      nreloc:section_64->nreloc
                   extreloff:dysymtab_command ? dysymtab_command->extreloff : 0
                     nextrel:dysymtab_command ? dysymtab_command->nextrel : 0
                   locreloff:dysymtab_command ? dysymtab_command->locreloff : 0
                     nlocrel:dysymtab_command ? dysymtab_command->nlocrel : 0];
      }
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
}

//-----------------------------------------------------------------------------
// 32 位：在“Relocations”节点下为每个有 nreloc 的 section 创建 (segname,sectname) 重定位子节点
- (void)processSectionRelocs
{
  MVNode * relocsNode = [self findNodeByUserInfo:[self userInfoForRelocs]];
  if (relocsNode == nil)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  @try
  {
    for (SectionVector::const_iterator sectIter = ++sections.begin(); sectIter != sections.end(); ++sectIter)
    {
      struct section const * section = *sectIter;
      if (section->nreloc > 0)
      {
        [self createRelocNode:relocsNode 
                      caption:(lastNodeCaption = [NSString stringWithFormat:@"(%s,%s)",
                                                  string(section->segname,16).c_str(),
                                                  string(section->sectname,16).c_str()])
                     location:section->reloff + imageOffset
                       length:section->nreloc * sizeof(struct relocation_info)
                  baseAddress:section->addr];
      }
    }
  }
  @catch(NSException * exception)
  {
    [self printException:exception caption:lastNodeCaption];
  }
}

//-----------------------------------------------------------------------------
// 64 位：在 Relocations 节点下为每个 section_64 创建重定位子节点
- (void)processSectionRelocs64
{
  MVNode * relocsNode = [self findNodeByUserInfo:[self userInfoForRelocs]];
  if (relocsNode == nil)
  {
    return;
  }
  
  NSString * lastNodeCaption;
  @try
  {  
    for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); sectIter != sections_64.end(); ++sectIter)
    {
      struct section_64 const * section_64 = *sectIter;
      if (section_64->nreloc > 0)
      {
        [self createReloc64Node:relocsNode 
                        caption:(lastNodeCaption = [NSString stringWithFormat:@"(%s,%s)",
                                                    string(section_64->segname,16).c_str(),
                                                    string(section_64->sectname,16).c_str()])
                       location:section_64->reloff + imageOffset
                         length:section_64->nreloc * sizeof(struct relocation_info)
                    baseAddress:section_64->addr];
      }
    }
  }
  @catch(NSException * exception)
  {
    [self printException:exception caption:lastNodeCaption];
  }
}

//-----------------------------------------------------------------------------
// 创建 32 位 Mach-O 头节点：解析 magic、cputype、cpusubtype、filetype、ncmds、sizeofcmds、flags 并写入详情表
- (MVNode *)createMachONode:(MVNode *)parent
                    caption:(NSString *)caption
                   location:(uint64_t)location
                mach_header:(struct mach_header const *)mach_header
{
  MVNodeSaver nodeSaver;
  MVNode * node = [parent insertChildWithDetails:caption location:location length:sizeof(struct mach_header) saver:nodeSaver]; 
  
  // 从 location 起按字段顺序读取并追加详情行
  NSRange range = NSMakeRange(location,0);
  NSString * lastReadHex;
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Magic Number"
                         :mach_header->magic == MH_MAGIC ? @"MH_MAGIC" :
                          mach_header->magic == MH_CIGAM ? @"MH_CIGAM" : @"???"];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"CPU Type"
                         :mach_header->cputype == CPU_TYPE_ANY ? @"CPU_TYPE_ANY" :
                          mach_header->cputype == CPU_TYPE_I386 ? @"CPU_TYPE_I386" :
                          mach_header->cputype == CPU_TYPE_ARM ? @"CPU_TYPE_ARM" :
                          mach_header->cputype == CPU_TYPE_POWERPC ? @"CPU_TYPE_POWERPC" : @"???"];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"CPU SubType"
                         :@""];
   
  if ((mach_header->cpusubtype & CPU_SUBTYPE_LIB64) == CPU_SUBTYPE_LIB64) [node.details appendRow:@"":@"":@"80000000":@"CPU_SUBTYPE_LIB64"];
  
  if (mach_header->cputype == CPU_TYPE_ARM)
  {
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_ALL)   [node.details appendRow:@"":@"":@"00000000":@"CPU_SUBTYPE_ARM_ALL"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V4T)   [node.details appendRow:@"":@"":@"00000005":@"CPU_SUBTYPE_ARM_V4T"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V6)    [node.details appendRow:@"":@"":@"00000006":@"CPU_SUBTYPE_ARM_V6"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V5TEJ) [node.details appendRow:@"":@"":@"00000007":@"CPU_SUBTYPE_ARM_V5TEJ"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_XSCALE)[node.details appendRow:@"":@"":@"00000008":@"CPU_SUBTYPE_ARM_XSCALE"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7)    [node.details appendRow:@"":@"":@"00000009":@"CPU_SUBTYPE_ARM_V7"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7F)   [node.details appendRow:@"":@"":@"0000000A":@"CPU_SUBTYPE_ARM_V7F (Cortex A9)"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7S)   [node.details appendRow:@"":@"":@"0000000B":@"CPU_SUBTYPE_ARM_V7S (Swift)"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7K)   [node.details appendRow:@"":@"":@"0000000C":@"CPU_SUBTYPE_ARM_V7K (Kirkwood4)"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V8)    [node.details appendRow:@"":@"":@"0000000D":@"CPU_SUBTYPE_ARM_V8"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V6M)   [node.details appendRow:@"":@"":@"0000000E":@"CPU_SUBTYPE_ARM_V6M"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7M)   [node.details appendRow:@"":@"":@"0000000F":@"CPU_SUBTYPE_ARM_V7M"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V7EM)  [node.details appendRow:@"":@"":@"00000010":@"CPU_SUBTYPE_ARM_V7EM"];
      if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM_V8M)   [node.details appendRow:@"":@"":@"00000011":@"CPU_SUBTYPE_ARM_V8M"];
  }
  else if (mach_header->cputype == CPU_TYPE_I386)
  {
    if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_I386_ALL) [node.details appendRow:@"":@"":@"00000003":@"CPU_SUBTYPE_I386_ALL"];
  }
  else if (mach_header->cputype == CPU_TYPE_ANY)
  {
    if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_MULTIPLE) [node.details appendRow:@"":@"":@"FFFFFFFF":@"CPU_SUBTYPE_MULTIPLE"];
    if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_LITTLE_ENDIAN) [node.details appendRow:@"":@"":@"00000000":@"CPU_SUBTYPE_LITTLE_ENDIAN"];
    if ((mach_header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_BIG_ENDIAN) [node.details appendRow:@"":@"":@"00000001":@"CPU_SUBTYPE_BIG_ENDIAN"];
  }
   
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"File Type"
                         :mach_header->filetype == MH_OBJECT ? @"MH_OBJECT" :
                          mach_header->filetype == MH_EXECUTE ? @"MH_EXECUTE" :
                          mach_header->filetype == MH_FVMLIB ? @"MH_FVMLIB" :
                          mach_header->filetype == MH_CORE ? @"MH_CORE" :
                          mach_header->filetype == MH_PRELOAD ? @"MH_PRELOAD" :
                          mach_header->filetype == MH_DYLIB ? @"MH_DYLIB" :
                          mach_header->filetype == MH_DYLINKER ? @"MH_DYLINKER" :
                          mach_header->filetype == MH_BUNDLE ? @"MH_BUNDLE" :
                          mach_header->filetype == MH_DYLIB_STUB ? @"MH_DYLIB_STUB" :
                          mach_header->filetype == MH_DSYM ? @"MH_DSYM" : 
                          mach_header->filetype == MH_KEXT_BUNDLE ? @"MH_KEXT_BUNDLE" :
                          mach_header->filetype == MH_FILESET ? @"MH_FILESET" :
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
                          mach_header->filetype == MH_GPU_EXECUTE ? @"MH_GPU_EXECUTE" :
                          mach_header->filetype == MH_GPU_DYLIB ? @"MH_GPU_DYLIB" :
#endif
                          @"???"];

  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Number of Load Commands"
                         :[NSString stringWithFormat:@"%u", mach_header->ncmds]];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Size of Load Commands"
                         :[NSString stringWithFormat:@"%u", mach_header->sizeofcmds]];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Flags"
                         :@""];
  
    if (mach_header->flags & MH_NOUNDEFS)                [node.details appendRow:@"":@"":@"00000001":@"MH_NOUNDEFS"];
    if (mach_header->flags & MH_INCRLINK)                [node.details appendRow:@"":@"":@"00000002":@"MH_INCRLINK"];
    if (mach_header->flags & MH_DYLDLINK)                [node.details appendRow:@"":@"":@"00000004":@"MH_DYLDLINK"];
    if (mach_header->flags & MH_BINDATLOAD)              [node.details appendRow:@"":@"":@"00000008":@"MH_BINDATLOAD"];
    if (mach_header->flags & MH_PREBOUND)                [node.details appendRow:@"":@"":@"00000010":@"MH_PREBOUND"];
    if (mach_header->flags & MH_SPLIT_SEGS)              [node.details appendRow:@"":@"":@"00000020":@"MH_SPLIT_SEGS"];
    if (mach_header->flags & MH_LAZY_INIT)               [node.details appendRow:@"":@"":@"00000040":@"MH_LAZY_INIT"];
    if (mach_header->flags & MH_TWOLEVEL)                [node.details appendRow:@"":@"":@"00000080":@"MH_TWOLEVEL"];
    if (mach_header->flags & MH_FORCE_FLAT)              [node.details appendRow:@"":@"":@"00000100":@"MH_FORCE_FLAT"];
    if (mach_header->flags & MH_NOMULTIDEFS)             [node.details appendRow:@"":@"":@"00000200":@"MH_NOMULTIDEFS"];
    if (mach_header->flags & MH_NOFIXPREBINDING)         [node.details appendRow:@"":@"":@"00000400":@"MH_NOFIXPREBINDING"];
    if (mach_header->flags & MH_PREBINDABLE)             [node.details appendRow:@"":@"":@"00000800":@"MH_PREBINDABLE"];
    if (mach_header->flags & MH_ALLMODSBOUND)            [node.details appendRow:@"":@"":@"00001000":@"MH_ALLMODSBOUND"];
    if (mach_header->flags & MH_SUBSECTIONS_VIA_SYMBOLS) [node.details appendRow:@"":@"":@"00002000":@"MH_SUBSECTIONS_VIA_SYMBOLS"];
    if (mach_header->flags & MH_CANONICAL)               [node.details appendRow:@"":@"":@"00004000":@"MH_CANONICAL"];
    if (mach_header->flags & MH_WEAK_DEFINES)            [node.details appendRow:@"":@"":@"00008000":@"MH_WEAK_DEFINES"];
    if (mach_header->flags & MH_BINDS_TO_WEAK)           [node.details appendRow:@"":@"":@"00010000":@"MH_BINDS_TO_WEAK"];
    if (mach_header->flags & MH_ALLOW_STACK_EXECUTION)   [node.details appendRow:@"":@"":@"00020000":@"MH_ALLOW_STACK_EXECUTION"];
    if (mach_header->flags & MH_ROOT_SAFE)               [node.details appendRow:@"":@"":@"00040000":@"MH_ROOT_SAFE"];
    if (mach_header->flags & MH_SETUID_SAFE)             [node.details appendRow:@"":@"":@"00080000":@"MH_SETUID_SAFE"];
    if (mach_header->flags & MH_NO_REEXPORTED_DYLIBS)    [node.details appendRow:@"":@"":@"00100000":@"MH_NO_REEXPORTED_DYLIBS"];
    if (mach_header->flags & MH_PIE)                     [node.details appendRow:@"":@"":@"00200000":@"MH_PIE"];
    if (mach_header->flags & MH_DEAD_STRIPPABLE_DYLIB)   [node.details appendRow:@"":@"":@"00400000":@"MH_DEAD_STRIPPABLE_DYLIB"];
    if (mach_header->flags & MH_HAS_TLV_DESCRIPTORS)     [node.details appendRow:@"":@"":@"00800000":@"MH_HAS_TLV_DESCRIPTORS"];
    if (mach_header->flags & MH_NO_HEAP_EXECUTION)       [node.details appendRow:@"":@"":@"01000000":@"MH_NO_HEAP_EXECUTION"];
    if (mach_header->flags & MH_APP_EXTENSION_SAFE)      [node.details appendRow:@"":@"":@"02000000":@"MH_APP_EXTENSION_SAFE"];
    if (mach_header->flags & MH_NLIST_OUTOFSYNC_WITH_DYLDINFO)      [node.details appendRow:@"":@"":@"04000000":@"MH_NLIST_OUTOFSYNC_WITH_DYLDINFO"];
    if (mach_header->flags & MH_SIM_SUPPORT)             [node.details appendRow:@"":@"":@"08000000":@"MH_SIM_SUPPORT"];
    if (mach_header->flags & MH_DYLIB_IN_CACHE)          [node.details appendRow:@"":@"":@"80000000":@"MH_DYLIB_IN_CACHE"];

  return node;
}
//-----------------------------------------------------------------------------
// 创建 64 位 Mach-O 头节点：解析 magic、cputype、cpusubtype、filetype、ncmds、sizeofcmds、flags、reserved
- (MVNode *)createMachO64Node:(MVNode *)parent
                      caption:(NSString *)caption
                     location:(uint64_t)location
               mach_header_64:(struct mach_header_64 const *)mach_header_64
{
  MVNodeSaver nodeSaver;
  MVNode * node = [parent insertChildWithDetails:caption location:location length:sizeof(struct mach_header_64) saver:nodeSaver]; 
  
  NSRange range = NSMakeRange(location,0);
  NSString * lastReadHex;
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Magic Number"
                         :mach_header_64->magic == MH_MAGIC_64 ? @"MH_MAGIC_64" :
                          mach_header_64->magic == MH_CIGAM_64 ? @"MH_CIGAM_64" : @"???"];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"CPU Type"
                         :mach_header_64->cputype == CPU_TYPE_ANY ? @"CPU_TYPE_ANY" :
                          mach_header_64->cputype == CPU_TYPE_POWERPC64 ? @"CPU_TYPE_POWERPC64" :
                          mach_header_64->cputype == CPU_TYPE_X86_64 ? @"CPU_TYPE_X86_64" :
                          mach_header_64->cputype == CPU_TYPE_ARM64 ? @"CPU_TYPE_ARM64" :
                          mach_header_64->cputype == CPU_TYPE_ARM64_32 ? @"CPU_TYPE_ARM64_32" : @"???"];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"CPU SubType"
                         :@""];

  if ((mach_header_64->cpusubtype & CPU_SUBTYPE_LIB64) == CPU_SUBTYPE_LIB64) [node.details appendRow:@"":@"":@"80000000":@"CPU_SUBTYPE_LIB64"];

  if (mach_header_64->cputype == CPU_TYPE_X86_64)
  {
    if ((mach_header_64->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_X86_64_ALL) [node.details appendRow:@"":@"":@"00000003":@"CPU_SUBTYPE_X86_64_ALL"]; 
  }
  else if (mach_header_64->cputype == CPU_TYPE_ARM64)
  {
      if ((mach_header_64->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64_ALL) {
          [node.details appendRow:@"":@"":@"00000000":@"CPU_SUBTYPE_ARM64_ALL"];
      }
      else if ((mach_header_64->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64_V8) {
          [node.details appendRow:@"":@"":@"00000001":@"CPU_SUBTYPE_ARM64_V8"];
      }
      else if ((mach_header_64->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E) {
          [node.details appendRow:@"":@"":@"00000002":@"CPU_SUBTYPE_ARM64E"];
      }
  }

  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"File Type"
                         :mach_header_64->filetype == MH_OBJECT ? @"MH_OBJECT" :
                          mach_header_64->filetype == MH_EXECUTE ? @"MH_EXECUTE" :
                          mach_header_64->filetype == MH_FVMLIB ? @"MH_FVMLIB" :
                          mach_header_64->filetype == MH_CORE ? @"MH_CORE" :
                          mach_header_64->filetype == MH_PRELOAD ? @"MH_PRELOAD" :
                          mach_header_64->filetype == MH_DYLIB ? @"MH_DYLIB" :
                          mach_header_64->filetype == MH_DYLINKER ? @"MH_DYLINKER" :
                          mach_header_64->filetype == MH_BUNDLE ? @"MH_BUNDLE" :
                          mach_header_64->filetype == MH_DYLIB_STUB ? @"MH_DYLIB_STUB" :
                          mach_header_64->filetype == MH_DSYM ? @"MH_DSYM" : 
                          mach_header_64->filetype == MH_KEXT_BUNDLE ? @"MH_KEXT_BUNDLE" :
                          mach_header_64->filetype == MH_FILESET ? @"MH_FILESET" :
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
                          mach_header_64->filetype == MH_GPU_EXECUTE ? @"MH_GPU_EXECUTE" :
                          mach_header_64->filetype == MH_GPU_DYLIB ? @"MH_GPU_DYLIB" :
#endif
                          @"???"];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Number of Load Commands"
                         :[NSString stringWithFormat:@"%u", mach_header_64->ncmds]];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Size of Load Commands"
                         :[NSString stringWithFormat:@"%u", mach_header_64->sizeofcmds]];
  
  [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Flags"
                         :@""];
  
    if (mach_header_64->flags & MH_NOUNDEFS)               [node.details appendRow:@"":@"":@"00000001":@"MH_NOUNDEFS"];
    if (mach_header_64->flags & MH_INCRLINK)               [node.details appendRow:@"":@"":@"00000002":@"MH_INCRLINK"];
    if (mach_header_64->flags & MH_DYLDLINK)               [node.details appendRow:@"":@"":@"00000004":@"MH_DYLDLINK"];
    if (mach_header_64->flags & MH_BINDATLOAD)             [node.details appendRow:@"":@"":@"00000008":@"MH_BINDATLOAD"];
    if (mach_header_64->flags & MH_PREBOUND)               [node.details appendRow:@"":@"":@"00000010":@"MH_PREBOUND"];
    if (mach_header_64->flags & MH_SPLIT_SEGS)             [node.details appendRow:@"":@"":@"00000020":@"MH_SPLIT_SEGS"];
    if (mach_header_64->flags & MH_LAZY_INIT)              [node.details appendRow:@"":@"":@"00000040":@"MH_LAZY_INIT"];
    if (mach_header_64->flags & MH_TWOLEVEL)               [node.details appendRow:@"":@"":@"00000080":@"MH_TWOLEVEL"];
    if (mach_header_64->flags & MH_FORCE_FLAT)             [node.details appendRow:@"":@"":@"00000100":@"MH_FORCE_FLAT"];
    if (mach_header_64->flags & MH_NOMULTIDEFS)            [node.details appendRow:@"":@"":@"00000200":@"MH_NOMULTIDEFS"];
    if (mach_header_64->flags & MH_NOFIXPREBINDING)        [node.details appendRow:@"":@"":@"00000400":@"MH_NOFIXPREBINDING"];
    if (mach_header_64->flags & MH_PREBINDABLE)            [node.details appendRow:@"":@"":@"00000800":@"MH_PREBINDABLE"];
    if (mach_header_64->flags & MH_ALLMODSBOUND)           [node.details appendRow:@"":@"":@"00001000":@"MH_ALLMODSBOUND"];
    if (mach_header_64->flags & MH_SUBSECTIONS_VIA_SYMBOLS)[node.details appendRow:@"":@"":@"00002000":@"MH_SUBSECTIONS_VIA_SYMBOLS"];
    if (mach_header_64->flags & MH_CANONICAL)              [node.details appendRow:@"":@"":@"00004000":@"MH_CANONICAL"];
    if (mach_header_64->flags & MH_WEAK_DEFINES)           [node.details appendRow:@"":@"":@"00008000":@"MH_WEAK_DEFINES"];
    if (mach_header_64->flags & MH_BINDS_TO_WEAK)          [node.details appendRow:@"":@"":@"00010000":@"MH_BINDS_TO_WEAK"];
    if (mach_header_64->flags & MH_ALLOW_STACK_EXECUTION)  [node.details appendRow:@"":@"":@"00020000":@"MH_ALLOW_STACK_EXECUTION"];
    if (mach_header_64->flags & MH_ROOT_SAFE)              [node.details appendRow:@"":@"":@"00040000":@"MH_ROOT_SAFE"];
    if (mach_header_64->flags & MH_SETUID_SAFE)            [node.details appendRow:@"":@"":@"00080000":@"MH_SETUID_SAFE"];
    if (mach_header_64->flags & MH_NO_REEXPORTED_DYLIBS)   [node.details appendRow:@"":@"":@"00100000":@"MH_NO_REEXPORTED_DYLIBS"];
    if (mach_header_64->flags & MH_PIE)                    [node.details appendRow:@"":@"":@"00200000":@"MH_PIE"];
    if (mach_header_64->flags & MH_DEAD_STRIPPABLE_DYLIB)  [node.details appendRow:@"":@"":@"00400000":@"MH_DEAD_STRIPPABLE_DYLIB"];
    if (mach_header_64->flags & MH_HAS_TLV_DESCRIPTORS)    [node.details appendRow:@"":@"":@"00800000":@"MH_HAS_TLV_DESCRIPTORS"];
    if (mach_header_64->flags & MH_NO_HEAP_EXECUTION)      [node.details appendRow:@"":@"":@"01000000":@"MH_NO_HEAP_EXECUTION"];
    if (mach_header_64->flags & MH_APP_EXTENSION_SAFE)     [node.details appendRow:@"":@"":@"02000000":@"MH_APP_EXTENSION_SAFE"];
    if (mach_header_64->flags & MH_NLIST_OUTOFSYNC_WITH_DYLDINFO)      [node.details appendRow:@"":@"":@"04000000":@"MH_NLIST_OUTOFSYNC_WITH_DYLDINFO"];
    if (mach_header_64->flags & MH_SIM_SUPPORT)            [node.details appendRow:@"":@"":@"08000000":@"MH_SIM_SUPPORT"];
    if (mach_header_64->flags & MH_DYLIB_IN_CACHE)         [node.details appendRow:@"":@"":@"80000000":@"MH_DYLIB_IN_CACHE"];
    
  uint32_t reserved = [dataController read_uint32:range lastReadHex:&lastReadHex];
  [node.details appendRow:[NSString stringWithFormat:@"%.8lX", range.location]
                         :lastReadHex
                         :@"Reserved"
                         :[NSString stringWithFormat:@"%u", reserved]];
  return node;
}

//-----------------------------------------------------------------------------
// 主线程任务：创建 Mach Header、Load Commands、Sections、Relocations 节点，填充 segmentInfo/sectionInfo，并确定运行时版本
- (void)doMainTasks
{
  uint32_t      ncmds;        // number of load commands
  uint32_t      sizeofcmds;   // the size of all the load commands
  
  sections.push_back(NULL); 
  sections_64.push_back(NULL); 
  
  dylibs.push_back((struct dylib *)NULL);
  
  NSString * lastNodeCaption; // for error message
  
  if ([self is64bit] == NO)
  {
    MATCH_STRUCT(mach_header,imageOffset)
    ncmds = mach_header->ncmds;
    sizeofcmds = mach_header->sizeofcmds;

    @try
    {
      [self createMachONode:rootNode
                    caption:(lastNodeCaption = @"Mach Header")
                   location:imageOffset
                mach_header:mach_header];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  else //64bit
  {
    MATCH_STRUCT(mach_header_64,imageOffset)
    ncmds = mach_header_64->ncmds;
    sizeofcmds = mach_header_64->sizeofcmds;

    @try
    {
      [self createMachO64Node:rootNode
                      caption:(lastNodeCaption = @"Mach64 Header")
                     location:imageOffset
               mach_header_64:mach_header_64];
    }
    @catch(NSException * exception)
    {
      [self printException:exception caption:lastNodeCaption];
    }
  }
  
  
  {
    uint64_t fileOffset = imageOffset + ([self is64bit] == NO
                                         ? sizeof(struct mach_header) 
                                         : sizeof(struct mach_header_64));
    
    MVNode * commandsNode = [self createDataNode:rootNode 
                                         caption:@"Load Commands"
                                        location:fileOffset
                                          length:sizeofcmds];
    
    for (uint32_t ncmd = 0; ncmd < ncmds; ++ncmd)
    {
      MATCH_STRUCT(load_command,fileOffset)
      
      commands.push_back(load_command);
      
      @try
      {
        [self createLoadCommandNode:commandsNode
                            caption:(lastNodeCaption = [self getNameForCommand:load_command->cmd])
                           location:fileOffset
                             length:load_command->cmdsize
                            command:load_command->cmd];
      }
      @catch(NSException * exception)
      {
        [self printException:exception caption:lastNodeCaption];
      }
      
      fileOffset += load_command->cmdsize;
    }
  }
  
  
  //=========================== Sections =========================
  NSRange relocsRange = NSMakeRange(0,0);
  
  if ([self is64bit] == NO)
  {
    for (SectionVector::const_iterator sectIter = ++sections.begin(); sectIter != sections.end(); ++sectIter)
    {
      struct section const * section = *sectIter;
      if (section->offset == 0)
      {
        continue;
      }
      
      MVNode * sectionNode = [self createDataNode:rootNode 
                                          caption:[NSString stringWithFormat:@"Section (%s,%s)", 
                                                   string(section->segname,16).c_str(),
                                                   string(section->sectname,16).c_str()]
                                         location:section->offset + imageOffset
                                           length:(section->flags & SECTION_TYPE) == S_ZEROFILL ||
                                                  (section->flags & SECTION_TYPE) == S_GB_ZEROFILL ? 0 : section->size];
      
      [sectionNode.userInfo addEntriesFromDictionary:[self userInfoForSection:section]];
      
      NSRange range = NSMakeRange(section->reloff + imageOffset, section->nreloc * sizeof(struct relocation_info));
      if (range.length > 0)
      {
        relocsRange = NSMaxRange(relocsRange) > 0 ? NSUnionRange(relocsRange,range) : range;
      }
    }
  }
  else //64bit
  {
    for (Section64Vector::const_iterator sectIter = ++sections_64.begin(); sectIter != sections_64.end(); ++sectIter)
    {
      struct section_64 const * section_64 = *sectIter;
      if (section_64->offset == 0)
      {
        continue;
      }
      
      MVNode * sectionNode = [self createDataNode:rootNode 
                                          caption:[NSString stringWithFormat:@"Section64 (%s,%s)", 
                                                   string(section_64->segname,16).c_str(),
                                                   string(section_64->sectname,16).c_str()]
                                         location:section_64->offset + imageOffset
                                           length:(section_64->flags & SECTION_TYPE) == S_ZEROFILL ||
                                                  (section_64->flags & SECTION_TYPE) == S_GB_ZEROFILL ? 0 : section_64->size];
      
      [sectionNode.userInfo addEntriesFromDictionary:[self userInfoForSection64:section_64]];
      
      NSRange range = NSMakeRange(section_64->reloff + imageOffset, section_64->nreloc * sizeof(struct relocation_info));
      if (range.length > 0)
      {
        relocsRange = NSMaxRange(relocsRange) > 0 ? NSUnionRange(relocsRange,range) : range;
      }
    }
  }
  
  
  //======================== Relocations ============================
  if (NSMaxRange(relocsRange) > 0)
  {
    MVNode * relocsNode = [self createDataNode:rootNode
                                       caption:@"Relocations"
                                      location:relocsRange.location
                                        length:relocsRange.length];
    
    [relocsNode.userInfo addEntriesFromDictionary:[self userInfoForRelocs]];
  }
 
  //======================== determine SDK ============================
  @try 
  {
    [self determineRuntimeVersion];
  }
  @catch(NSException * exception)
  {
    [self printException:exception caption:rootNode.caption];
  }
  
  [super doMainTasks];
}

//-----------------------------------------------------------------------------
// 后台任务：用 NSOperation 队列按依赖顺序执行 LinkEdit、Sections、SectionRelocs、DyldInfo、EHFrames、LSDA、ObjC、CodeSections，最后调用父类并更新状态
- (void)doBackgroundTasks
{
  NSBlockOperation * linkEditOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processLinkEdit]; else [self processLinkEdit64];
    }
    NSLog(@"%@: LinkEdit finished parsing. (%lu symbols found)", self, 
    [self is64bit] == NO ? self->symbols.size() : self->symbols_64.size());
  }];
  
  NSBlockOperation * sectionRelocsOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processSectionRelocs]; else [self processSectionRelocs64];
    }
    NSLog(@"%@: Section relocations finished parsing.", self);
  }];
  
  NSBlockOperation * dyldInfoOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      [self processDyldInfo];
    }
    NSLog(@"%@: Dyld info finished parsing.", self);
  }];
  
  NSBlockOperation * sectionOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processSections]; else [self processSections64];
    }
    NSLog(@"%@: Section contents finished parsing.", self);
  }];
  
  NSBlockOperation * EHFramesOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processEHFrames]; else [self processEHFrames64];
    }
    NSLog(@"%@: Exception Frames finished parsing.", self);
  }];
  
  NSBlockOperation * LSDAsOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processLSDA]; else [self processLSDA64];
    }
    NSLog(@"%@: Lang Spec Data Areas finished parsing. (%lu LSDAs found)", self, self->lsdaInfo.size());
  }];
  
  NSBlockOperation * objcSectionOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processObjcSections]; else [self processObjcSections64];
    }
    NSLog(@"%@: ObjC Section contents finished parsing.", self);
  }];
  
  NSBlockOperation * codeSectionsOperation = [NSBlockOperation blockOperationWithBlock:^
  {
    if ([self->backgroundThread isCancelled]) return;
    @autoreleasepool {
      if ([self is64bit] == NO) [self processCodeSections]; else [self processCodeSections64];
    }
    NSLog(@"%@: Code sections finished parsing.", self);
  }];
  
  [sectionOperation       addDependency:linkEditOperation];
  [sectionRelocsOperation addDependency:sectionOperation];
  [dyldInfoOperation      addDependency:sectionRelocsOperation];
  [objcSectionOperation   addDependency:dyldInfoOperation];
  [codeSectionsOperation  addDependency:objcSectionOperation];
  [EHFramesOperation      addDependency:dyldInfoOperation];
  [LSDAsOperation         addDependency:EHFramesOperation];
    
  [codeSectionsOperation  setQueuePriority:NSOperationQueuePriorityLow];
  
  NSOperationQueue * oq = [[NSOperationQueue alloc] init];

  [dataController updateStatus:MVStatusTaskStarted];
  
  [oq   addOperations:[NSArray arrayWithObjects:linkEditOperation,
                                                sectionOperation,
                                                sectionRelocsOperation,
                                                dyldInfoOperation,
                                                EHFramesOperation,
                                                LSDAsOperation,
                                                objcSectionOperation,
                                                codeSectionsOperation,nil] 
    waitUntilFinished:YES];
  
  [super doBackgroundTasks];
  
  [dataController updateStatus:MVStatusTaskTerminated];
}

@end
