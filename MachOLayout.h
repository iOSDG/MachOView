/*
 *  MachOLayout.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// C++ 标准库：字符串，用于 segname/sectname 等
#include <string>
// C++ 标准库：动态数组，用于 commands、sections、symbols 等
#include <vector>
// C++ 标准库：集合
#include <set>
// C++ 标准库：映射，用于 segmentInfo、sectionInfo、lsdaInfo
#include <map>
// C++ ABI：用于 C++ 符号 demangle
#include <cxxabi.h>

#import "Layout.h"

// Load Command 指针数组，解析时按顺序保存
typedef std::vector<struct load_command const *>          CommandVector;
// 32 位 LC_SEGMENT 的 segment 指针数组
typedef std::vector<struct segment_command const *>       SegmentVector;
// 64 位 LC_SEGMENT_64 的 segment 指针数组
typedef std::vector<struct segment_command_64 const *>    Segment64Vector;
// 32 位 section 指针数组，与 segments 对应
typedef std::vector<struct section const *>               SectionVector;
// 64 位 section 指针数组
typedef std::vector<struct section_64 const *>            Section64Vector;
// 32 位符号表 nlist 指针数组
typedef std::vector<struct nlist const *>                 NListVector;
// 64 位符号表 nlist_64 指针数组
typedef std::vector<struct nlist_64 const *>              NList64Vector;
// 依赖的 dylib 指针数组（LC_LOAD_DYLIB 等）
typedef std::vector<struct dylib const *>                 DylibVector;
// 32 位 dylib_module 指针数组（动态库模块表）
typedef std::vector<struct dylib_module const *>          ModuleVector;
// 64 位 dylib_module_64 指针数组
typedef std::vector<struct dylib_module_64 const *>       Module64Vector;
// LC_DATA_IN_CODE 条目指针数组
typedef std::vector<struct data_in_code_entry const *>    DataInCodeEntryVector;
// 间接符号表：uint32_t 指针数组
typedef std::vector<uint32_t const *>                     IndirectSymbolVector;

// 重定位映射：文件偏移 -> (长度, 值)；当前未使用（已注释）
typedef std::map<uint32_t,std::pair<uint64_t,uint64_t> >        RelocMap;           // fileOffset --> <length,value>
// 段信息：文件偏移 -> (虚拟地址, 段大小)，用于 fileOffsetToRVA
typedef std::map<uint64_t,std::pair<uint64_t,uint64_t> >        SegmentInfoMap;     // fileOffset --> <address,size>
// 节信息：虚拟地址 -> (文件偏移, sectionUserInfo)，用于 RVAToFileOffset、findSection 等
typedef std::map<uint64_t,std::pair<uint64_t,NSDictionary *> >  SectionInfoMap;     // address --> <fileOffset,sectionUserInfo>
// 异常帧：LSDA 地址 -> 对应 FDE 的 PCBegin 地址
typedef std::map<uint64_t,uint64_t>                             ExceptionFrameMap;  // LSDA_addr  --> PCBegin_addr

// Mach-O 布局类：解析单架构 Mach-O，继承 MVLayout，提供段/节/符号/重定位等容器与查询 API
@interface MachOLayout : MVLayout 
{
  // 入口点地址（来自 LC_THREAD 等），用于 UI 跳转
  uint64_t                entryPoint;       // instruction pointer in thread command
  
  // 所有 Load Command 指针，按文件顺序
  CommandVector           commands;         // load commands
  // 32 位 segment 指针
  SegmentVector           segments;         // segment entries for 32-bit architectures
  // 64 位 segment 指针
  Segment64Vector         segments_64;      // segment entries for 64-bit architectures
  // 32 位 section 指针（含占位 NULL）
  SectionVector           sections;         // section entries for 32-bit architectures
  // 64 位 section 指针
  Section64Vector         sections_64;      // section entries for 64-bit architectures
  // 32 位符号表条目指针
  NListVector             symbols;          // symbol entries in the symbol table for 32-bit architectures
  // 64 位符号表条目指针
  NList64Vector           symbols_64;       // symbol entries in the symbol table for 64-bit architectures
  // 间接符号表条目
  IndirectSymbolVector    isymbols;         // indirect symbols
  
  // 依赖库 dylib 指针
  DylibVector             dylibs;           // imported dynamic libraries
  // 32 位模块表
  ModuleVector            modules;          // module table entries in a dynamic shared library for 32-bit architectures
  // 64 位模块表
  Module64Vector          modules_64;       // module table entries in a dynamic shared library for 64-bit architectures
  // Data in Code 条目
  DataInCodeEntryVector   dices;            // data in code entries
  // 字符串表基址（指向 __LINKEDIT 内）
  char const *            strtab;           // pointer to the string table
  
  //RelocMap                relocMap;         // section relocations
  // 按文件偏移查段：用于 fileOffsetToRVA
  SegmentInfoMap          segmentInfo;      // segment info lookup table by offset
  // 按虚拟地址查节：用于 RVAToFileOffset、sectionNodeContainsRVA
  SectionInfoMap          sectionInfo;      // section info lookup table by address
  // LSDA 地址到 FDE 起始地址的映射，用于异常解析
  ExceptionFrameMap       lsdaInfo;         // LSDA info lookup table by address
  
  // 虚拟地址 -> 符号名，用于 findSymbolAtRVA、Dyld 解析填充
  NSMutableDictionary *   symbolNames;      // symbol names by address
}

// 工厂方法：创建并返回 MachOLayout 实例
+ (MachOLayout *)layoutWithDataController:(MVDataController *)dc rootNode:(MVNode *)node;

// 按索引取 32 位 section，越界返回静态“未找到”结构
- (struct section const *)getSectionByIndex:(uint32_t)index;
// 按索引取 64 位 section
- (struct section_64 const *)getSection64ByIndex:(uint32_t)index;

// 按索引取 32 位符号
- (struct nlist const *)getSymbolByIndex:(uint32_t)index;
// 按索引取 64 位符号
- (struct nlist_64 const *)getSymbol64ByIndex:(uint32_t)index;

// 按索引取 dylib
- (struct dylib const *)getDylibByIndex:(uint32_t)index;

// 为 32 位 section 生成 userInfo（layout、segname、sectname、address），供 findNodeByUserInfo
- (NSDictionary *)userInfoForSection:(struct section const *)section;
// 为 64 位 section 生成 userInfo
- (NSDictionary *)userInfoForSection64:(struct section_64 const *)section_64;

// 根据 RVA 查包含该地址的 section 对应树节点
- (MVNode *)sectionNodeContainsRVA:(uint64_t)rva;

// 根据 RVA 返回 "segname sectname" 字符串，无节则返回 "NO SECTION..."
- (NSString *)findSectionContainsRVA:(uint64_t)rva;

// 根据 RVA 查符号名，无则返回十六进制地址字符串
- (NSString *)findSymbolAtRVA:(uint64_t)rva;

// 文件偏移转虚拟地址（RVA）
- (uint64_t)fileOffsetToRVA:(uint64_t)offset;

// 虚拟地址转文件偏移
- (uint64_t)RVAToFileOffset:(uint64_t)rva;

// 在指定文件偏移处写入重定位值（修改 realData）
- (void)addRelocAtFileOffset:(uint64_t)offset withLength:(uint64_t)length andValue:(uint64_t)value;

// 是否为 MH_DYLIB_STUB（桩 dylib，无实际段节）
- (BOOL)isDylibStub;

@end
