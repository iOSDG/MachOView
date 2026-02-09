/*
 *  LoadCommands.h
 *  MachOView
 *
 *  Created by psaghelyi on 20/07/2010.
 *
 */

// 引入 Mach-O 布局基类，本 Category 将扩展其 Load Command 解析能力
#import "MachOLayout.h"

// MachOLayout 的 LoadCommands 分类：负责根据 Load Command 类型创建对应详情节点并填充字段
@interface MachOLayout (LoadCommands)

// 根据 Load Command 类型码 cmd 返回可读名称（如 LC_SEGMENT、LC_SYMTAB 等），未识别则返回 @"???"
- (NSString *)getNameForCommand:(uint32_t)cmd;

// 根据 command 类型创建对应的 Load Command 详情节点：解析 cmd/cmdsize 并分发到具体 createLC* 方法，未支持的类型创建 "unsupported" 数据节点
-(MVNode *)createLoadCommandNode:(MVNode *)parent
                         caption:(NSString *)caption
                        location:(uint64_t)location
                          length:(uint64_t)length
                         command:(uint32_t)command;

@end
