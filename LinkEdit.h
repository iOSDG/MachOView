/*
 *  LinkEdit.h
 *  MachOView
 *
 *  Created by psaghelyi on 20/07/2010.
 *
 */

// 引入 Mach-O 布局基类，本 Category 负责 Link Edit 段内各类数据的解析与展示
#import "MachOLayout.h"

// MachOLayout 的 LinkEdit 分类：重定位、符号表、间接符号、TOC、模块表、两级 Hints、Split Segment、函数起始、Data In Code 等
@interface MachOLayout (LinkEdit)

// 创建 32 位重定位节点：解析 relocation_info（含 scattered），按 baseAddress 计算地址并更新 realData
- (MVNode *) createRelocNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                 baseAddress:(uint32_t)baseAddress;

// 创建 64 位重定位节点：解析 relocation_info（x86_64/arm64），处理 SUBTRACTOR/UNSIGNED 对及外部/本地符号
- (MVNode *) createReloc64Node:(MVNode *)parent
                       caption:(NSString *)caption
                      location:(uint64_t)location
                        length:(uint64_t)length
                   baseAddress:(uint64_t)baseAddress;

// 创建 32 位符号表节点：解析 nlist + strtab，展示符号名、类型、sect、value、desc 等
- (MVNode *) createSymbolsNode:parent
                       caption:(NSString *)caption
                      location:(uint64_t)location
                        length:(uint64_t)length;

// 创建 64 位符号表节点：解析 nlist_64 + strtab
- (MVNode *) createSymbols64Node:parent
                         caption:(NSString *)caption
                        location:(uint64_t)location
                          length:(uint64_t)length;

// 创建外部引用表节点：解析 LC_DYSYMTAB 的 extrefsymoff/nextrefsyms 指向的引用信息
- (MVNode *) createReferencesNode:parent
                          caption:(NSString *)caption
                         location:(uint64_t)location
                           length:(uint64_t)length;

// 创建 32 位间接符号表节点：解析 indirectsymoff/nindirectsyms 的 uint32_t 数组，用于懒加载/非懒加载符号指针
- (MVNode *) createISymbolsNode:parent
                        caption:(NSString *)caption
                       location:(uint64_t)location
                         length:(uint64_t)length;

// 创建 64 位间接符号表节点
- (MVNode *) createISymbols64Node:parent
                          caption:(NSString *)caption
                         location:(uint64_t)location
                           length:(uint64_t)length;

// 创建 32 位 TOC 表节点：解析 dysymtab 的 tocoff/ntoc（Table Of Contents 条目）
- (MVNode *) createTOCNode:parent
                   caption:(NSString *)caption
                  location:(uint64_t)location
                    length:(uint64_t)length;

// 创建 64 位 TOC 表节点
- (MVNode *) createTOC64Node:parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length;

// 创建 32 位模块表节点：解析 modtaboff/nmodtab 的 dylib_module
- (MVNode *) createModulesNode:parent
                       caption:(NSString *)caption
                      location:(uint64_t)location
                        length:(uint64_t)length;

// 创建 64 位模块表节点：dylib_module_64
- (MVNode *) createModules64Node:parent
                         caption:(NSString *)caption
                        location:(uint64_t)location
                          length:(uint64_t)length;

// 创建两级 Hints 表节点：解析 LC_TWOLEVEL_HINTS 指向的 twolevel_hint 数组，index 为 hints 在表中的起始索引
- (MVNode *) createTwoLevelHintsNode:parent
                             caption:(NSString *)caption
                            location:(uint64_t)location
                              length:(uint64_t)length
                               index:(uint32_t)index;

// 创建 Segment Split Info 节点：解析 LC_SEGMENT_SPLIT_INFO 指向的拆分信息，baseAddress 为段基址
- (MVNode *) createSplitSegmentNode:parent
                            caption:(NSString *)caption
                           location:(uint64_t)location
                             length:(uint64_t)length
                        baseAddress:(uint64_t)baseAddress;

// 创建函数起始地址节点：解析 LC_FUNCTION_STARTS 的 ULEB128 偏移序列，baseAddress 为 __TEXT 段基址
- (MVNode *) createFunctionStartsNode:parent
                              caption:(NSString *)caption
                             location:(uint64_t)location
                               length:(uint64_t)length
                          baseAddress:(uint64_t)baseAddress;

// 创建 Data In Code 条目节点：解析 LC_DATA_IN_CODE 的 data_in_code_entry 数组（offset/length/kind）
- (MVNode *) createDataInCodeEntriesNode:parent
                                 caption:(NSString *)caption
                                location:(uint64_t)location
                                  length:(uint64_t)length;


@end
