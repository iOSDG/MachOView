/*
 *  Exceptions.h
 *  MachOView
 *
 *  Created by psaghelyi on 20/07/2010.
 *
 */

// 引入 MachOLayout 头文件，MachOLayout (Exceptions) 将作为其 Category
#import "MachOLayout.h"

// MachOLayout 的分类 (Exceptions)：扩展 MachOLayout 以支持异常处理信息的解析
@interface MachOLayout (Exceptions)

// 创建调用帧信息（CFI）节点，解析 .eh_frame 段
- (MVNode *)createCFINode:(MVNode *)parent
                  caption:(NSString *)caption
                 location:(uint64_t)location
                   length:(uint64_t)length;


// 创建语言特定数据区域（LSDA）节点，解析 GCC/LLVM 异常表
- (MVNode *)createLSDANode:(MVNode *)parent
                 caption:(NSString *)caption
                location:(uint64_t)location
                  length:(uint64_t)length
          eh_frame_begin:(uint64_t)eh_frame_begin;

// 创建 Unwind Info Header 节点，解析 Compact Unwind Info（已废弃/非强制）
- (MVNode *)createUnwindInfoHeaderNode:(MVNode *)parent
                               caption:(NSString *)caption
                              location:(uint64_t)location
                                header:(struct unwind_info_section_header const *)unwind_info_section_header;


@end
