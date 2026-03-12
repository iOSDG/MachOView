/*
 *  CRTFootPrints.h
 *  MachOView
 *
 *  Created by psaghelyi on 25/11/2010.
 *
 */


// 引入MachOLayout头文件，因为本文件定义了MachOLayout的分类
#import "MachOLayout.h"

// 宏定义：机器码指纹的步长，每行指纹最多包含16字节的机器码
#define FOOTPRINT_STRIDE 16
// 宏定义：用于在指纹匹配中表示需要跳过的字节数（GAP），第一个元素00表示这是个占位符，第二个元素x表示跳过的字节数
#define GAP(x)  {00, x}  // fake entry with zero length, second element is the size of bytes to skip

// 类型定义：AsmFootPrint是一个二维数组类型，每一行包含FOOTPRINT_STRIDE字节，用于存储汇编指令的机器码模式
typedef uint8_t AsmFootPrint[][FOOTPRINT_STRIDE];

// MachOLayout的分类CRTFootPrints，用于扩展MachOLayout的功能，增加C运行时库（CRT）指纹识别能力
@interface MachOLayout (CRTFootPrints)

// 声明方法matchAsmAtOffset:asmFootPrint:lineCount:，用于在指定文件偏移处匹配给定的汇编机器码指纹
- (bool) matchAsmAtOffset:(uint64_t)offset 
             asmFootPrint:(const AsmFootPrint)footprint 
                lineCount:(NSUInteger)lineCount;
                
// 声明方法determineRuntimeVersion，用于根据特征指纹确定Mach-O文件使用的C运行时版本
- (void) determineRuntimeVersion;

@end
